"""Behavioral tests for selective archive installation (no network)."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import struct
import tarfile
import tempfile
import unittest
from unittest import mock
import zipfile

ROOT = Path(__file__).resolve().parents[2]
loader = importlib.util.spec_from_file_location('selection', ROOT/'libexec/llvmup-selection.py')
selection = importlib.util.module_from_spec(loader)
loader.loader.exec_module(selection)


class SelectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='llvmup-selection-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def archive(self, extra=(), compression='xz'):
        archive = self.root / ('release.tar.'+compression if compression else 'release.tar')
        with tarfile.open(archive, 'w:'+compression) as tar:
            entries = [
                ('bin/clang-23', b'#!/bin/sh\nexit 0\n', None),
                ('bin/clang', None, 'clang-23'),
                ('bin/clang++', None, 'clang'),
                ('bin/lld', b'#!/bin/sh\nexit 0\n', None),
                ('bin/ld.lld', None, 'lld'),
                ('lib/clang/23/include/stddef.h', b'/* fixture */', None),
                ('lib/clang/23/lib/linux/libclang_rt.profile.a', b'fixture runtime', None),
                ('bin/mlir-opt', b'excluded tool', None),
                ('lib/libLLVM.a', b'excluded static library', None),
            ] + list(extra)
            for name, data, link in entries:
                member = tarfile.TarInfo('LLVM/'+name)
                member.mode = 0o755 if name.startswith('bin/') else 0o644
                if link:
                    member.type, member.linkname = tarfile.SYMTYPE, link
                else:
                    member.size = len(data)
                tar.addfile(member, io.BytesIO(data) if data is not None else None)
        return archive

    def test_normalized_selection_and_defaults(self):
        self.assertEqual(selection.selection()['components'], ['*'])
        a = selection.selection('compiler')
        self.assertIn('llvm-ranlib', a['targets'])
        b = selection.selection('custom', ['llvm-ranlib,clang,lld', 'llvm-profdata llvm-cov llvm-ar libc++', 'clang'])
        self.assertEqual(a['key'], b['key'])
        self.assertIn('clang', selection.selection(components=['llvm-cov'])['components'])
        self.assertEqual(selection.selection('minimal', ['llvm-cov'])['components'], ['clang', 'lld', 'llvm-cov'])
        self.assertTrue(selection.selection(components=['lldb', 'clang'], source=True)['legacy'])
        for args in [('custom', []), ('invalid', []), ('custom', ['lldb'])]:
            with self.assertRaises(ValueError): selection.selection(*args)
        with self.assertRaises(ValueError): selection.selection(components=['lldb', 'llvm-cov'], source=True)

    def test_libcxx_selection_and_platform_defaults(self):
        spec = selection.selection('compiler')
        self.assertIn('libc++', spec['components'])
        self.assertTrue({'libcxx', 'libcxxabi', 'libunwind'} <= set(spec['runtimes']))
        self.assertIn('libcxx', spec['checkout'])
        with mock.patch.object(selection.platform, 'system', return_value='Windows'):
            self.assertNotIn('libc++', selection.selection('compiler')['components'])
            with self.assertRaises(ValueError): selection.selection(components=['libc++'])
        entries = [(name, b'fixture', None) for name in (
            'include/c++/v1/vector', 'include/c++/v1/__config',
            'include/x86_64-linux-gnu/c++/v1/__config_site',
            'lib/x86_64-linux-gnu/libc++.so.1', 'lib/x86_64-linux-gnu/libc++abi.so.1',
            'lib/x86_64-linux-gnu/libunwind.so.1', 'lib/libc++experimental.a')]
        entries.append(('lib/x86_64-linux-gnu/libc++.so', None, 'libc++.so.1'))
        archive = self.archive(entries)
        destination = self.root/'cxx'
        selected = selection.selection(components=['libc++'])
        selection.extract(archive, destination, selected)
        selection.finalize(destination, selected)
        self.assertTrue((destination/'include/x86_64-linux-gnu/c++/v1/__config_site').is_file())
        self.assertTrue((destination/'lib/x86_64-linux-gnu/libc++.so').is_symlink())
        self.assertFalse((destination/'lib/libLLVM.a').exists())
        minimal = self.root/'minimal'
        selection.extract(archive, minimal, selection.selection('minimal'))
        self.assertFalse((minimal/'include/c++').exists())
        (destination/'include/c++/v1/vector').unlink()
        with self.assertRaisesRegex(ValueError, 'headers'): selection.validate(destination, selected)

    def test_only_selected_files_and_transitive_aliases_are_written(self):
        destination = self.root/'installed'
        spec = selection.selection('minimal')
        original_open = selection.Archive.open
        opened = []
        def selected_only(archive, member):
            name = archive.names[id(member)]
            self.assertNotIn('mlir-opt', name)
            self.assertNotIn('libLLVM.a', name)
            opened.append(name)
            return original_open(archive, member)
        with mock.patch.object(selection.Archive, 'open', selected_only):
            selection.extract(self.archive(), destination, spec)
        self.assertTrue(opened)
        self.assertEqual(os.readlink(destination/'bin/clang++'), 'clang')
        self.assertEqual(os.readlink(destination/'bin/clang'), 'clang-23')
        self.assertFalse((destination/'bin/mlir-opt').exists())
        self.assertFalse((destination/'lib/libLLVM.a').exists())
        selection.finalize(destination, spec)
        selection.check(destination, spec)
        with self.assertRaises(ValueError): selection.check(destination, selection.selection('compiler'))
        (destination/'bin/clang-23').unlink()
        with self.assertRaises(ValueError): selection.check(destination, spec)

    def test_unsafe_unselected_member_is_rejected(self):
        for name, target in [('../outside', None), ('bin/bad-link', '../../../outside')]:
            with self.subTest(name=name):
                archive = self.archive([(name, b'bad' if not target else None, target)])
                if target:
                    # Unsafe unselected links need not be followed, but selected links must fail.
                    archive = self.archive([('bin/clang-cpp', None, target)])
                with self.assertRaises(ValueError): selection.extract(archive, self.root/name.replace('/', '_'), selection.selection('minimal'))
        self.assertFalse((self.root/'outside').exists())

    def test_cyclic_and_missing_links_are_rejected(self):
        for target in ('clang-cpp', 'missing'):
            archive = self.archive([('bin/clang-cpp', None, target)])
            with self.assertRaises(ValueError): selection.extract(archive, self.root/target, selection.selection('minimal'))

    def test_zip_and_tar_gzip(self):
        source = self.archive(compression='gz')
        selection.extract(source, self.root/'gz', selection.selection('minimal'))
        archive = self.root/'release.zip'
        with zipfile.ZipFile(archive, 'w') as zip:
            for path in (self.root/'gz').rglob('*'):
                if path.is_file(): zip.write(path, path.relative_to(self.root/'gz').as_posix())
        selection.extract(archive, self.root/'zip', selection.selection('minimal'))
        selection.validate(self.root/'zip', selection.selection('minimal'))

    def test_pe_imports_delay_imports_and_bundled_dll_closure(self):
        def pe(imported, delayed=None):
            data = bytearray(0x600)
            data[:2] = b'MZ'
            struct.pack_into('<I', data, 60, 0x80)
            data[0x80:0x84] = b'PE\0\0'
            struct.pack_into('<HHIIIHH', data, 0x84, 0x8664, 1, 0, 0, 0, 240, 2)
            optional = 0x98
            struct.pack_into('<H', data, optional, 0x20b)
            struct.pack_into('<II', data, optional+112+8, 0x1000, 40)
            struct.pack_into('<8sIIIIIIHHI', data, optional+240, b'.rdata', 0x400, 0x1000, 0x400, 0x200, 0, 0, 0, 0, 0)
            struct.pack_into('<IIIII', data, 0x200, 0, 0, 0, 0x1080, 0)
            data[0x280:0x280+len(imported)+1] = imported.encode()+b'\0'
            if delayed:
                struct.pack_into('<II', data, optional+112+13*8, 0x1100, 64)
                struct.pack_into('<IIIIIIII', data, 0x300, 1, 0x1180, 0, 0, 0, 0, 0, 0)
                data[0x380:0x380+len(delayed)+1] = delayed.encode()+b'\0'
            return data
        executable = self.root/'sample.exe'
        executable.write_bytes(pe('fixture.dll', 'DELAY.dll'))
        self.assertEqual(selection.binary_dependencies(executable), ['fixture.dll', 'DELAY.dll'])
        archive = self.root/'windows.zip'
        with zipfile.ZipFile(archive, 'w') as zip:
            zip.writestr('LLVM/bin/clang.exe', executable.read_bytes())
            zip.writestr('LLVM/bin/fixture.dll', pe('helper.dll'))
            zip.writestr('LLVM/bin/helper.dll', b'leaf')
            zip.writestr('LLVM/bin/delay.dll', b'leaf')
            zip.writestr('LLVM/bin/unused.dll', b'unrelated')
        destination = self.root/'windows'
        selection.extract(archive, destination, selection.selection(components=['clang']))
        self.assertTrue((destination/'bin/helper.dll').is_file())
        self.assertTrue((destination/'bin/delay.dll').is_file())
        self.assertFalse((destination/'bin/unused.dll').exists())

    @unittest.skipUnless(shutil.which('cc') and os.name != 'nt', 'requires native C compiler')
    def test_elf_dependency_closure_and_strip_preserve_hardlinks(self):
        source = self.root/'fixture.c'
        source.write_text('int fixture(void) { return 23; }\n')
        library = self.root/'libfixture.so'
        subprocess.run(['cc', '-shared', '-fPIC', str(source), '-o', str(library)], check=True)
        source.write_text('extern int fixture(void); int main(void) { return fixture() == 23 ? 0 : 1; }\n')
        binary = self.root/'fixture'
        subprocess.run(['cc', '-g', str(source), '-L'+str(self.root), '-lfixture', '-Wl,-rpath,$ORIGIN/../lib', '-o', str(binary)], check=True)
        self.assertIn('libfixture.so', selection.binary_dependencies(binary))
        self.assertTrue(selection.elf_executable(binary))
        self.assertFalse(selection.elf_executable(library))
        archive = self.archive([('bin/clang-tidy', binary.read_bytes(), None), ('lib/libfixture.so', library.read_bytes(), None)], compression='')
        with tarfile.open(archive, 'a') as tar:
            member = tarfile.TarInfo('LLVM/bin/clang-format')
            member.type, member.linkname = tarfile.LNKTYPE, 'LLVM/bin/clang-tidy'
            tar.addfile(member)
        destination = self.root/'native'
        spec = selection.selection('minimal', ['clang-tidy', 'clang-format'], strip=True)
        selection.extract(archive, destination, spec)
        original_size = (destination/'bin/clang-tidy').stat().st_size
        selection.finalize(destination, spec)
        self.assertEqual((destination/'bin/clang-tidy').stat().st_ino, (destination/'bin/clang-format').stat().st_ino)
        self.assertLess((destination/'bin/clang-tidy').stat().st_size, original_size)
        subprocess.run([str(destination/'bin/clang-format')], check=True)
        self.assertEqual((destination/'lib/libfixture.so').read_bytes(), library.read_bytes())

    def test_installer_failure_never_publishes_toolchain(self):
        # Real Bash orchestration with an offline release and mocked curl.
        archive = self.archive([('bin/clang-cpp', None, 'missing')])
        bindir = self.root/'commands'
        bindir.mkdir()
        curl = bindir/'curl'
        curl.write_text('#!/bin/bash\nfor ((i=1;i<=$#;i++)); do if [ "${!i}" = -o ]; then j=$((i+1)); cp "$FIXTURE_ARCHIVE" "${!j}"; exit; fi; done\nexit 0\n')
        curl.chmod(0o755)
        releases = self.root/'releases.json'
        releases.write_text(json.dumps([{'tag_name':'llvmorg-23.1.2', 'draft':False, 'prerelease':False, 'assets':[{'id':23, 'name':'LLVM-23.1.2-Linux-X64.tar.xz', 'state':'uploaded', 'browser_download_url':'https://example.invalid/llvm.tar.xz'}]}]))
        env = dict(os.environ, PATH=str(bindir)+os.pathsep+os.environ['PATH'], FIXTURE_ARCHIVE=str(archive), LLVMUP_RELEASES_FILE=str(releases), LLVM_TOOLCHAINS_DIR=str(self.root/'toolchains'), RUNNER_TEMP=str(self.root/'tmp'), LLVMUP_DISABLE_AUTOACTIVATE='1')
        result = subprocess.run([str(ROOT/'llvm-prebuilt'), '--profile', 'minimal', '--verify', 'skip', '--verbose', '23.1.2'], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing link target', result.stderr)
        self.assertIn('before cleanup', result.stderr)
        self.assertFalse((self.root/'toolchains/llvmorg-23.1.2').exists())
        self.assertEqual(list((self.root/'toolchains').iterdir()), [])


if __name__ == '__main__':
    unittest.main(verbosity=2)
