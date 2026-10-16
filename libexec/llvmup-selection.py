#!/usr/bin/env python3
"""Shared, standard-library-only selective installation engine.

Archive verification belongs to the caller and must precede extraction. This
module never downloads or executes archive members while resolving dependencies.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import stat
import struct
import subprocess
import sys
import tarfile
import zipfile

CATALOG = json.loads(Path(__file__).with_name('llvmup-components.json').read_text())
MARKER = '.llvmup-installation.json'
LEGACY_PROJECTS = {'bolt', 'clang', 'clang-tools-extra', 'compiler-rt', 'cross-project-tests',
                   'flang', 'libc', 'libclc', 'lld', 'lldb', 'mlir', 'openmp', 'polly', 'pstl'}


def selection(profile='', components=(), strip=False, source=False):
    components = sorted(set(c for item in components for c in re.split(r'[,\s]+', item) if c))
    profile = profile or ('custom' if components else 'full')
    if profile not in ('full', *CATALOG['profiles']):
        raise ValueError('Invalid profile: ' + profile)
    unknown = set(components) - CATALOG['components'].keys()
    legacy = bool(unknown) and source and set(components) <= LEGACY_PROJECTS
    if unknown and not legacy:
        raise ValueError('Unsupported components: ' + ', '.join(sorted(unknown)))
    if profile == 'custom' and not components:
        raise ValueError('The custom profile requires components')
    if strip and platform.system() != 'Linux':
        raise ValueError('--strip is supported only for Linux ELF executables')
    if profile == 'full':
        chosen, projects, targets = ['*'], ['all'], []
        legacy = False
    elif legacy:
        chosen = sorted(set(components) | set(CATALOG['profiles'][profile]))
        projects = sorted({CATALOG['components'][c]['project'] if c in CATALOG['components'] else c for c in chosen} - {''})
        targets = []
    else:
        chosen = sorted(set(CATALOG['profiles'][profile]) | set(components))
        pending = list(chosen)
        while pending:
            for required in CATALOG['components'][pending.pop()].get('requires', []):
                if required not in chosen:
                    chosen.append(required)
                    pending.append(required)
        chosen.sort()
        projects = sorted({CATALOG['components'][c]['project'] for c in chosen} - {''})
        targets = sorted({t for c in chosen for t in CATALOG['components'][c]['targets']})
    if platform.system() == 'Windows' and 'libc++' in chosen:
        if 'libc++' in components:
            raise ValueError('libc++ selection is not supported for Windows MSVC; use the Visual Studio standard library')
        chosen.remove('libc++')
    runtimes = sorted({'compiler-rt'} | {r for c in chosen if c in CATALOG['components'] for r in CATALOG['components'][c].get('runtimes', [])})
    identity = {'schema': CATALOG['schema'], 'components': chosen, 'strip': bool(strip), 'legacy': legacy}
    revisions = {c: CATALOG['components'][c]['revision'] for c in chosen if c in CATALOG['components'] and 'revision' in CATALOG['components'][c]}
    if revisions: identity['component_revisions'] = revisions
    key = hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()[:24]
    if chosen == ['*'] and not strip and not legacy:
        key = 'full'
    return dict(identity, profile=profile, key=key, projects=projects, targets=targets,
                runtimes=runtimes, selective=profile != 'full' and not legacy,
                checkout=sorted({'llvm', 'cmake', 'third-party', 'runtimes', 'compiler-rt'} | set(projects) | set(runtimes)))


def safe_path(name):
    if '\\' in name or ':' in name or '\x00' in name:
        raise ValueError('Unsafe archive path: ' + repr(name))
    p = PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts:
        raise ValueError('Unsafe archive path: ' + repr(name))
    return p.as_posix().rstrip('/')


class Archive:
    def __init__(self, path):
        self.zip = zipfile.is_zipfile(path)
        self.handle = zipfile.ZipFile(path) if self.zip else tarfile.open(path, 'r:*')
        members = self.handle.infolist() if self.zip else self.handle.getmembers()
        self.raw = {}
        for member in members:
            name = safe_path(member.filename if self.zip else member.name)
            if name in ('', '.'):
                continue
            if name in self.raw:
                raise ValueError('Duplicate archive member: ' + name)
            self.raw[name] = member
        # Official releases have one enclosing directory; ZIPs may be flat.
        roots = {p.split('/')[0] for p in self.raw}
        self.prefix = next(iter(roots)) + '/' if len(roots) == 1 and next(iter(roots)) not in ('bin', 'lib') else ''
        self.members = {p[len(self.prefix):]: m for p, m in self.raw.items()
                        if p.startswith(self.prefix) and p != self.prefix.rstrip('/')}
        self.names = {id(m): p for p, m in self.raw.items()}

    def close(self):
        self.handle.close()

    def kind(self, m):
        if self.zip:
            mode = m.external_attr >> 16
            return 'dir' if m.is_dir() else ('symlink' if stat.S_ISLNK(mode) else 'file')
        if m.isdir(): return 'dir'
        if m.issym(): return 'symlink'
        if m.islnk(): return 'hardlink'
        if m.isfile(): return 'file'
        raise ValueError('Unsupported special archive member: ' + m.name)

    def open(self, m):
        return self.handle.open(m) if self.zip else self.handle.extractfile(m)

    def link(self, name):
        m = self.members[name]
        kind = self.kind(m)
        if kind not in ('symlink', 'hardlink'): return None
        if self.zip:
            with self.open(m) as f: target = f.read(4097).decode('utf-8')
            if len(target) > 4096: raise ValueError('Oversized link target')
        else:
            target = m.linkname
        if target.startswith('/') or '\\' in target or ':' in target:
            raise ValueError('Unsafe link target: ' + target)
        raw = target if kind == 'hardlink' else str(PurePosixPath(self.names[id(m)]).parent / target)
        parts = []
        for part in raw.split('/'):
            if part in ('', '.'): continue
            if part == '..':
                if not parts: raise ValueError('Link escapes archive')
                parts.pop()
            else: parts.append(part)
        normalized = '/'.join(parts)
        if not normalized.startswith(self.prefix): raise ValueError('Link escapes toolchain')
        resolved = normalized[len(self.prefix):]
        if resolved not in self.members: raise ValueError('Missing link target: ' + resolved)
        return resolved


def binary_dependencies(path):
    """Read ELF DT_NEEDED / PE imports and delay imports without loading code."""
    with open(path, 'rb') as f:
        def read(offset, size):
            f.seek(offset)
            data = f.read(size)
            if len(data) != size: raise ValueError('Truncated binary: ' + str(path))
            return data
        def string(offset):
            f.seek(offset)
            data = f.read(4096).split(b'\0', 1)[0]
            return data.decode('utf-8', errors='strict')
        magic = f.read(64)
        if magic.startswith(b'\x7fELF'):
            endian = '<' if magic[5] == 1 else '>'
            wide = magic[4] == 2
            header = struct.unpack(endian + ('HHIQQQIHHHHHH' if wide else 'HHIIIIIHHHHHH'), magic[16:64 if wide else 52])
            phoff, phsize, phnum = header[4], header[8], header[9]
            loads, dynamic = [], None
            for i in range(phnum):
                values = struct.unpack(endian + ('IIQQQQQQ' if wide else 'IIIIIIII'), read(phoff+i*phsize, 56 if wide else 32))
                typ = values[0]
                offset, addr, size = (values[2], values[3], values[5]) if wide else (values[1], values[2], values[4])
                if typ == 1: loads.append((addr, offset, size))
                if typ == 2: dynamic = (offset, size)
            if not dynamic: return []
            needed, strtab = [], None
            width = 16 if wide else 8
            for off in range(dynamic[0], sum(dynamic), width):
                tag, value = struct.unpack(endian + ('qQ' if wide else 'iI'), read(off, width))
                if tag == 0: break
                if tag == 1: needed.append(value)
                if tag == 5: strtab = value
            if not needed: return []
            for addr, offset, size in loads:
                if strtab is not None and addr <= strtab < addr+size:
                    return [string(offset+strtab-addr+n) for n in needed]
            raise ValueError('Missing ELF string table: ' + str(path))
        if magic[:2] != b'MZ': return []
        peoff = struct.unpack_from('<I', magic, 60)[0]
        head = read(peoff, 24)
        if head[:4] != b'PE\0\0': raise ValueError('Invalid PE header')
        count, optsize = struct.unpack_from('<H', head, 6)[0], struct.unpack_from('<H', head, 20)[0]
        opt = read(peoff+24, optsize)
        wide = struct.unpack_from('<H', opt)[0] == 0x20b
        directory = 112 if wide else 96
        imagebase = struct.unpack_from('<Q' if wide else '<I', opt, 24 if wide else 28)[0]
        sections = [struct.unpack('<8sIIIIIIHHI', read(peoff+24+optsize+i*40, 40)) for i in range(count)]
        def rva(value):
            for s in sections:
                if s[2] <= value < s[2]+max(s[1], s[3]): return s[4]+value-s[2]
            raise ValueError('Invalid PE RVA')
        result = []
        for index, width in ((1, 20), (13, 32)):
            if len(opt) < directory+(index+1)*8: continue
            address, size = struct.unpack_from('<II', opt, directory+index*8)
            if not address: continue
            for offset in range(rva(address), rva(address)+size, width):
                row = struct.unpack('<'+'I'*(width//4), read(offset, width))
                if not any(row): break
                name = row[3] if index == 1 else row[1] - (0 if row[0] & 1 else imagebase)
                result.append(string(rva(name)))
        return result


def libcxx_member(name):
    p = PurePosixPath(name)
    return (name.startswith('include/') and '/c++/v1/' in name) or (
        p.parts[0] in ('lib', 'lib64') and re.fullmatch(r'lib(?:c\+\+(?:abi|experimental)?|unwind)(?:\.a|\.so(?:\.[0-9.]+)?|(?:\.[0-9.]+)?\.dylib)', p.name) is not None)


def extract(archive_path, root, spec):
    archive = Archive(archive_path)
    root.mkdir(parents=True, exist_ok=True)
    if any(root.iterdir()): raise ValueError('Extraction destination must be empty')
    try:
        tools = {t for c in spec['components'] for t in CATALOG['components'][c]['tools']}
        helpers = {path for c in spec['components'] for group in CATALOG['components'][c].get('helpers', []) for path in group}
        helpers.update(path for c in spec['components'] for path in CATALOG['components'][c].get('optional_files', []))
        selected = set()
        for name, member in archive.members.items():
            kind = archive.kind(member)
            if kind == 'dir': continue
            p = PurePosixPath(name)
            stem = re.sub(r'(?:-\d+(?:\.\d+)*)?(?:\.exe)?$', '', p.name)
            if (p.parent == PurePosixPath('bin') and stem in tools) or name in helpers or name.startswith('lib/clang/') or ('libc++' in spec['components'] and libcxx_member(name)) or p.name.upper().startswith(('LICENSE', 'NOTICE')):
                selected.add(name)
        installed = set()
        def materialize(name, chain=()):
            if name in installed: return
            if name in chain: raise ValueError('Cyclic archive link: ' + name)
            member = archive.members[name]
            for parent in PurePosixPath(name).parents:
                if str(parent) in archive.members and archive.kind(archive.members[str(parent)]) != 'dir':
                    raise ValueError('Archive member has a non-directory parent: ' + name)
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            link = archive.link(name)
            if link is not None:
                materialize(link, (*chain, name))
                if archive.kind(member) == 'hardlink': os.link(root/link, target)
                elif os.name == 'nt': shutil.copy2(root/link, target)
                else: target.symlink_to(os.path.relpath(root/link, target.parent))
            else:
                with archive.open(member) as src, open(target, 'xb') as dst: shutil.copyfileobj(src, dst, 1024*1024)
                mode = member.external_attr >> 16 if archive.zip else member.mode
                target.chmod((mode & 0o777) or 0o644)
            installed.add(name)
        by_basename = {}
        for name in archive.members:
            if name.startswith(('lib/', 'bin/')):
                by_basename.setdefault(PurePosixPath(name).name.lower(), []).append(name)
        scanned = set()
        while selected:
            for name in sorted(selected, key=lambda n: archive.members[n].header_offset if archive.zip else archive.members[n].offset):
                materialize(name)
            selected = set()
            for name in sorted(installed - scanned):
                scanned.add(name)
                for dependency in binary_dependencies(root/name):
                    matches = by_basename.get(dependency.lower(), [])
                    # Preserve all bundled variants when an archive provides
                    # multiple target-specific copies of the same SONAME.
                    selected.update(n for n in matches if n not in installed)
        return installed
    finally:
        archive.close()


def validate(root, spec):
    if not spec['selective']: return
    if 'libc++' in spec['components']:
        if not list(root.glob('include/**/c++/v1/vector')) or not list(root.glob('include/**/c++/v1/__config')):
            raise ValueError('Selected libc++ headers are missing')
        for library in ('libc++', 'libc++abi', 'libunwind'):
            if not any(p.is_file() and libcxx_member(p.relative_to(root).as_posix()) for p in root.glob('lib*/**/' + library + '.*')):
                raise ValueError('Selected library is missing: ' + library)
    for component in spec['components']:
        for group in CATALOG['components'][component].get('helpers', []):
            if not any((root/path).is_file() for path in group):
                raise ValueError('Missing selected helper: ' + group[0])
        if component == 'libc++': continue
        names = ['clang', 'clang++'] if component == 'clang' else (['lld-link' if os.name == 'nt' else 'ld.lld'] if component == 'lld' else [component])
        for name in names:
            path = root / 'bin' / (name + ('.exe' if os.name == 'nt' else ''))
            if not path.is_file(): raise ValueError('Missing selected tool: ' + str(path))
            if os.name != 'nt' and not os.access(path, os.X_OK): raise ValueError('Tool is not executable: ' + str(path))
            subprocess.run([str(path), '--version'], check=True, stdout=subprocess.DEVNULL, timeout=30)
    if not list(root.glob('lib/clang/*/include')):
        raise ValueError('Clang resource headers are missing')
    if not list(root.glob('lib/clang/*/lib')):
        raise ValueError('Clang runtimes are missing')


def elf_executable(path):
    """Distinguish PIE executables from shared libraries before stripping."""
    with path.open('rb') as f:
        header = f.read(64)
        if len(header) < 64 or header[:4] != b'\x7fELF': return False
        endian = '<' if header[5] == 1 else '>'
        wide = header[4] == 2
        fields = struct.unpack(endian + ('HHIQQQIHHHHHH' if wide else 'HHIIIIIHHHHHH'), header[16:64 if wide else 52])
        if fields[0] == 2: return True
        if fields[0] != 3: return False
        for index in range(fields[9]):
            f.seek(fields[4] + index * fields[8])
            if f.read(4) == struct.pack(endian + 'I', 3): return True  # PT_INTERP
    return False


def finalize(root, spec):
    validate(root, spec)
    if spec['strip']:
        strip = shutil.which('llvm-strip') or shutil.which('strip')
        if not strip: raise ValueError('--strip requires llvm-strip or strip on PATH')
        seen, before, after = set(), 0, 0
        for path in sorted((root/'bin').iterdir()):
            if not path.is_file() or path.is_symlink(): continue
            info = path.stat()
            inode = (info.st_dev, info.st_ino)
            if inode in seen: continue
            seen.add(inode)
            if not elf_executable(path): continue
            before += info.st_size
            # Tools may replace the inode. Copy the result back through the
            # original inode so archive hardlinks remain aliases.
            temporary = path.with_name(path.name+'.llvmup-stripped')
            try:
                shutil.copy2(path, temporary)
                subprocess.run([strip, '--strip-unneeded', str(temporary)], check=True)
                with temporary.open('rb') as src, path.open('wb') as dst: shutil.copyfileobj(src, dst)
            finally:
                temporary.unlink(missing_ok=True)
            after += path.stat().st_size
        print(f'Strip: before={before} after={after} saved={before-after} bytes', file=sys.stderr)
        validate(root, spec)
        for name in ('clang', 'clang++'):
            subprocess.run([str(root/'bin'/name), '--version'], check=True, stdout=subprocess.DEVNULL, timeout=30)
    files = []
    for path in sorted(root.rglob('*')):
        if path.name == MARKER or path.is_dir(): continue
        files.append({'path': path.relative_to(root).as_posix(), 'size': path.lstat().st_size,
                      'link': os.readlink(path) if path.is_symlink() else None})
    (root/MARKER).write_text(json.dumps(dict(spec, files=files), indent=2)+'\n')


def check(root, spec):
    marker = root/MARKER
    if not marker.exists():
        if spec['components'] == ['*'] and not spec['strip']: return
        raise ValueError('Installation has no selection manifest; use another --name or remove it explicitly')
    recorded = json.loads(marker.read_text(encoding='utf-8-sig'))
    if recorded.get('schema') != spec['schema'] or recorded.get('key') != spec['key']:
        raise ValueError('Installed components/strip differ; use another --name or remove it explicitly')
    for item in recorded.get('files', []):
        path = root/safe_path(item['path'])
        if not path.is_file(): raise ValueError('Missing installed file: ' + str(path))
        if path.lstat().st_size != item['size']: raise ValueError('Changed installed file size: ' + str(path))
        if item.get('link') is not None and (not path.is_symlink() or os.readlink(path) != item['link']):
            raise ValueError('Changed installed link: ' + str(path))
    validate(root, spec)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['selection', 'extract', 'finalize', 'check'])
    parser.add_argument('--profile', default='')
    parser.add_argument('--component', action='append', default=[])
    parser.add_argument('--strip', action='store_true')
    parser.add_argument('--source', action='store_true')
    parser.add_argument('--root', type=Path)
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    spec = selection(args.profile, args.component, args.strip, args.source)
    if args.command == 'selection': print(json.dumps(spec)); return
    if args.root is None: parser.error('--root is required')
    if args.command == 'extract':
        if not args.archive: parser.error('--archive is required')
        extract(args.archive, args.root, spec)
    elif args.command == 'finalize': finalize(args.root, spec)
    else: check(args.root, spec)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, struct.error, tarfile.TarError, zipfile.BadZipFile, subprocess.SubprocessError) as exc:
        print('Selection error: ' + str(exc), file=sys.stderr)
        sys.exit(1)
