"""Behavioral tests for selective archive installation (no network)."""
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import struct
import sys
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
                ('bin/clang-apply-replacements', b'#!/bin/sh\nexit 0\n', None),
                ('share/clang/clang-format-diff.py', b'# helper fixture', None),
                ('bin/git-clang-format', b'# helper fixture', None),
                ('share/clang/clang-tidy-diff.py', b'# helper fixture', None),
                ('bin/run-clang-tidy', b'# helper fixture', None),
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

    def test_catalog_tools_helpers_and_completions_stay_in_sync(self):
        components = [name for name in selection.CATALOG['components'] if name != 'libc++']
        spec = selection.selection('custom', components)
        names = {tool for name in components for tool in selection.CATALOG['components'][name]['tools']}
        for name in components:
            self.assertIn(name + '\tcomponent\t', (ROOT/'llvmup-completion-common.sh').read_text())
            self.assertIn("'" + name + "'", (ROOT/'Llvm-Completion.psm1').read_text())
        existing = {'clang', 'clang++', 'lld', 'ld.lld', 'clang-apply-replacements'}
        archive = self.archive([('bin/'+name, b'#!/bin/sh\nexit 0\n', None) for name in sorted(names-existing)])
        destination = self.root/'catalog'
        selection.extract(archive, destination, spec)
        selection.finalize(destination, spec)
        selection.check(destination, spec)
        self.assertTrue((destination/'share/clang/clang-format-diff.py').is_file())
        self.assertTrue((destination/'bin/git-clang-format').is_file())
        self.assertIn('llvm-objcopy', selection.selection(components=['llvm-strip'])['targets'])
        self.assertIn('llvm-readobj', selection.selection(components=['llvm-readelf'])['targets'])
        self.assertIn('llvm-symbolizer', selection.selection(components=['llvm-addr2line'])['targets'])

    def test_xray_and_tidy_helpers_in_custom_selection(self):
        spec = selection.selection('custom', ['llvm-xray', 'clang-tidy'])
        self.assertNotIn('lld', spec['components'])
        self.assertIn('llvm-xray', spec['targets'])
        self.assertIn('clang-apply-replacements', spec['targets'])
        self.assertIn('clang-tools-extra', spec['checkout'])
        old_identity = {k: spec[k] for k in ('schema', 'components', 'strip', 'legacy')}
        import hashlib
        old_key = hashlib.sha256(json.dumps(old_identity, sort_keys=True).encode()).hexdigest()[:24]
        self.assertNotEqual(old_key, spec['key'])
        archive = self.archive([(name, b'#!/bin/sh\nexit 0\n', None) for name in ('bin/llvm-xray', 'bin/clang-tidy')])
        destination = self.root/'custom'
        selection.extract(archive, destination, spec)
        selection.finalize(destination, spec)
        for name in ('bin/llvm-xray', 'share/clang/clang-tidy-diff.py', 'bin/run-clang-tidy'):
            self.assertTrue((destination/name).is_file())
        self.assertFalse((destination/'bin/lld').exists())
        (destination/'share/clang/clang-tidy-diff.py').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing selected helper'): selection.validate(destination, spec)
        minimal = self.root/'minimal'
        selection.extract(archive, minimal, selection.selection('minimal'))
        self.assertFalse((minimal/'bin/llvm-xray').exists())
        self.assertFalse((minimal/'share/clang/clang-tidy-diff.py').exists())

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

    def stream_archive(self, entries):
        archive = self.root/'stream.tar.xz'
        with tarfile.open(archive, 'w:xz') as tar:
            for name, kind, value in entries:
                member = tarfile.TarInfo(name)
                member.type = kind
                member.mode = 0o755
                if kind == tarfile.REGTYPE:
                    member.size = len(value)
                elif kind in (tarfile.SYMTYPE, tarfile.LNKTYPE):
                    member.linkname = value
                tar.addfile(member, io.BytesIO(value) if kind == tarfile.REGTYPE else None)
        return archive

    def test_stream_writes_before_end_without_index_or_backward_seek(self):
        destination = self.root/'streamed'
        archive = self.archive()
        original_entries = selection.StreamingArchive.entries
        original_seek = tarfile._Stream.seek
        def entries(reader):
            for name, member in original_entries(reader):
                if name == 'bin/mlir-opt':
                    self.assertTrue((destination/'bin/clang-23').is_file())
                    self.assertFalse((destination/'bin/clang').is_symlink())
                yield name, member
        def seek(stream, position):
            self.assertGreaterEqual(position, stream.tell())
            return original_seek(stream, position)
        with mock.patch.object(tarfile.TarFile, 'getmembers', side_effect=AssertionError('full index')), \
             mock.patch.object(tarfile._Stream, 'seek', seek), \
             mock.patch.object(selection.StreamingArchive, 'entries', entries), \
             mock.patch.object(tarfile, 'open', wraps=tarfile.open) as opened:
            selection.extract(archive, destination, selection.selection('minimal'))
        self.assertEqual(opened.call_count, 1)
        self.assertEqual(os.readlink(destination/'bin/clang'), 'clang-23')

    def test_stream_forward_and_backward_link_chains(self):
        archive = self.stream_archive([
            ('LLVM/bin/clang', tarfile.SYMTYPE, 'clang-alias'),
            ('LLVM/bin/clang++', tarfile.LNKTYPE, 'LLVM/bin/clang-alias'),
            ('LLVM/bin/clang-alias', tarfile.LNKTYPE, 'LLVM/bin/private-driver'),
            ('LLVM/bin/private-driver', tarfile.REGTYPE, b'driver'),
            ('LLVM/bin/clang-cpp', tarfile.SYMTYPE, 'clang'),
        ])
        destination = self.root/'links'
        with mock.patch.object(tarfile, 'open', wraps=tarfile.open) as opened:
            selection.extract(archive, destination, selection.selection('minimal'))
        self.assertEqual(opened.call_count, 1)
        self.assertEqual((destination/'bin/clang-cpp').read_bytes(), b'driver')
        self.assertEqual((destination/'bin/clang++').stat().st_ino,
                         (destination/'bin/private-driver').stat().st_ino)
        self.assertEqual(os.readlink(destination/'bin/clang'), 'clang-alias')

    def test_stream_batches_earlier_dependencies_and_keeps_all_variants(self):
        archive = self.stream_archive([
            ('LLVM/lib/one/libearly.so', tarfile.REGTYPE, b'early'),
            ('LLVM/lib/two/libearly.so', tarfile.REGTYPE, b'early'),
            ('LLVM/lib/libunused.so', tarfile.REGTYPE, b'unused'),
            ('LLVM/lib/target', tarfile.REGTYPE, b'target'),
            ('LLVM/bin/clang', tarfile.REGTYPE, b'clang'),
            ('LLVM/lib/libalias.so', tarfile.SYMTYPE, 'target'),
            ('LLVM/lib/libforward.so', tarfile.REGTYPE, b'forward'),
        ])
        destination = self.root/'dependencies'
        def dependencies(path):
            return {'clang': ['libearly.so', 'libalias.so', 'libforward.so', 'system.so'],
                    'early': ['libforward.so']}.get(path.read_text(), [])
        with mock.patch.object(selection, 'binary_dependencies', dependencies), \
             mock.patch.object(tarfile, 'open', wraps=tarfile.open) as opened:
            selection.extract(archive, destination, selection.selection('minimal'))
        self.assertEqual(opened.call_count, 2)
        self.assertTrue((destination/'lib/one/libearly.so').is_file())
        self.assertTrue((destination/'lib/two/libearly.so').is_file())
        self.assertEqual((destination/'lib/libalias.so').read_bytes(), b'target')
        self.assertTrue((destination/'lib/libforward.so').is_file())
        self.assertFalse((destination/'lib/libunused.so').exists())

    def test_stream_rejects_late_invalid_headers_and_link_cycles(self):
        cases = [
            [('LLVM/bin/clang', tarfile.REGTYPE, b'first'),
             ('LLVM/bin/clang', tarfile.REGTYPE, b'duplicate')],
            [('LLVM/bin/clang', tarfile.REGTYPE, b'first'),
             ('LLVM/bin', tarfile.SYMTYPE, '../outside')],
            [('LLVM/bin/clang', tarfile.REGTYPE, b'first'),
             ('other/bin/ignored', tarfile.REGTYPE, b'other root')],
            [('LLVM/bin/clang', tarfile.SYMTYPE, 'alias'),
             ('LLVM/bin/alias', tarfile.SYMTYPE, 'clang')],
            [('LLVM/bin/clang', tarfile.LNKTYPE, '../outside')],
            [('LLVM/bin/clang', tarfile.SYMTYPE, '../lib'),
             ('LLVM/lib', tarfile.DIRTYPE, None)],
            [('LLVM/bin/clang', tarfile.REGTYPE, b'first'),
             ('LLVM/ignored', tarfile.FIFOTYPE, None)],
        ]
        for index, entries in enumerate(cases):
            with self.subTest(index=index), self.assertRaises(ValueError):
                selection.extract(self.stream_archive(entries), self.root/str(index), selection.selection('minimal'))

    def test_stream_flat_tar_with_leading_dot_directory(self):
        archive = self.stream_archive([
            ('.', tarfile.DIRTYPE, None),
            ('./bin', tarfile.DIRTYPE, None),
            ('./bin/clang', tarfile.REGTYPE, b'driver'),
            ('./bin/clang++', tarfile.SYMTYPE, 'clang'),
        ])
        destination = self.root/'flat'
        selection.extract(archive, destination, selection.selection('minimal'))
        self.assertEqual((destination/'bin/clang++').read_bytes(), b'driver')

    def test_tar_backend_selection_and_fallback(self):
        archive = self.archive()
        with mock.patch.dict(os.environ, {'LLVMUP_EXTRACTOR': 'auto'}), \
             mock.patch.object(shutil, 'which', return_value=None):
            self.assertIs(selection.tar_reader(archive)[0], selection.open_python_tar)
        for result in (subprocess.CompletedProcess([], 1), subprocess.TimeoutExpired('xz', 5)):
            with self.subTest(result=result), \
                 mock.patch.dict(os.environ, {'LLVMUP_EXTRACTOR': 'auto'}), \
                 mock.patch.object(shutil, 'which', return_value='/xz'), \
                 mock.patch.object(subprocess, 'run', **({'side_effect': result} if isinstance(result, Exception) else {'return_value': result})):
                self.assertIs(selection.tar_reader(archive)[0], selection.open_python_tar)
        with mock.patch.dict(os.environ, {'LLVMUP_EXTRACTOR': 'python'}), \
             mock.patch.object(subprocess, 'Popen', side_effect=AssertionError('Python must not spawn xz')):
            selection.extract(archive, self.root/'python-only', selection.selection('minimal'))
        with mock.patch.dict(os.environ, {'LLVMUP_EXTRACTOR': 'xz'}), \
             mock.patch.object(shutil, 'which', return_value=None), self.assertRaises(ValueError):
            selection.tar_reader(archive)
        for env in ({'LLVMUP_EXTRACTOR': 'invalid'},
                    {'LLVMUP_EXTRACTOR': 'auto', 'LLVMUP_EXTRACT_THREADS': '0'},
                    {'LLVMUP_EXTRACTOR': 'auto', 'LLVMUP_EXTRACT_THREADS': 'invalid'}):
            with self.subTest(env=env), mock.patch.dict(os.environ, env), self.assertRaises(ValueError):
                selection.tar_reader(archive)

    def fake_xz(self, after):
        executable = self.root/'fake-xz'
        executable.write_text('#!'+sys.executable+'\nimport lzma, sys, time\n'
                              'sys.stdout.buffer.write(lzma.decompress(open(sys.argv[-1], "rb").read()))\n'
                              'sys.stdout.buffer.flush()\n'+after+'\n')
        executable.chmod(0o755)
        return str(executable)

    @unittest.skipIf(os.name == 'nt', 'executable fixture uses a shebang')
    def test_parallel_reader_drains_trailer_and_checks_exit_status(self):
        archive = self.archive()
        executable = self.fake_xz('sys.stdout.buffer.write(b"\\0" * (4*1024*1024))\nsys.stdout.buffer.flush()\nsys.exit(7)')
        with self.assertRaises(subprocess.CalledProcessError) as failure:
            with selection.open_parallel_tar(archive, executable, 2) as tar:
                list(tar)
        self.assertEqual(failure.exception.returncode, 7)

    @unittest.skipIf(os.name == 'nt', 'executable fixture uses a shebang')
    def test_parallel_producer_is_reaped_when_selection_fails(self):
        archive = self.stream_archive([('LLVM/../outside', tarfile.REGTYPE, b'unsafe')])
        executable = self.fake_xz('sys.stdout.buffer.write(b"\\0" * (4*1024*1024))\nsys.stdout.buffer.flush()\ntime.sleep(60)')
        processes = []
        original = subprocess.Popen
        def spawn(*args, **kwargs):
            process = original(*args, **kwargs)
            processes.append(process)
            return process
        reader = lambda path: selection.open_parallel_tar(path, executable, 2)
        with mock.patch.object(selection, 'tar_reader', return_value=(reader, 'test xz')), \
             mock.patch.object(subprocess, 'Popen', spawn), self.assertRaises(ValueError):
            selection.extract(archive, self.root/'invalid', selection.selection('minimal'))
        self.assertEqual(len(processes), 1)
        self.assertIsNotNone(processes[0].poll())
        self.assertTrue(processes[0].stdout.closed)
        self.assertFalse((self.root/'outside').exists())

    @unittest.skipUnless(shutil.which('xz'), 'requires native xz')
    def test_native_xz_matches_python_and_ignores_xz_presets(self):
        archive = self.archive()
        with mock.patch.dict(os.environ, {'LLVMUP_EXTRACTOR': 'auto'}):
            if selection.tar_reader(archive)[0] is selection.open_python_tar:
                self.skipTest('requires xz with threaded decompression')
        installed = []
        for backend in ('python', 'xz'):
            destination = self.root/backend
            with mock.patch.dict(os.environ, {'LLVMUP_EXTRACTOR': backend, 'LLVMUP_EXTRACT_THREADS': '2',
                                              'XZ_OPT': '--invalid-preset', 'XZ_DEFAULTS': '--invalid-preset'}):
                installed.append(selection.extract(archive, destination, selection.selection('minimal')))
        self.assertEqual(installed[0], installed[1])
        for name in installed[0]:
            first, second = self.root/'python'/name, self.root/'xz'/name
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(first.lstat().st_mode, second.lstat().st_mode)
            if first.is_symlink(): self.assertEqual(os.readlink(first), os.readlink(second))
        damaged = bytearray(archive.read_bytes())
        damaged[-12] ^= 1  # Corrupt the XZ footer after the valid TAR payload.
        archive.write_bytes(damaged)
        with mock.patch.dict(os.environ, {'LLVMUP_EXTRACTOR': 'xz'}), \
             self.assertRaises((subprocess.CalledProcessError, tarfile.TarError)):
            selection.extract(archive, self.root/'corrupt', selection.selection('minimal'))

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
