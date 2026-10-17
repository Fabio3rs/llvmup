"""Compile, link, run, and report coverage using an installed toolchain."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def smoke(root):
    root = Path(root).resolve()
    suffix = '.exe' if os.name == 'nt' else ''
    def tool(name): return str(root/'bin'/(name+suffix))
    with tempfile.TemporaryDirectory(prefix='llvmup-smoke-') as directory:
        work = Path(directory)
        def run(args, **kwargs):
            return subprocess.run(args, cwd=work, check=True, text=True, **kwargs)
        (work/'test.c').write_text('#include <stddef.h>\nint main(void) { return sizeof(size_t) > 0 ? 0 : 1; }\n')
        (work/'test.cpp').write_text('#include <vector>\nint main() { std::vector<int> v{1,2}; return v.size() == 2 ? 0 : 1; }\n')
        linker = [] if sys.platform == 'darwin' else ['-fuse-ld=lld']
        run([tool('clang'), 'test.c', *linker, '-o', 'test'+suffix])
        run([str(work/('test'+suffix))])
        run([tool('clang++'), 'test.cpp', *linker, '-o', 'test-cxx'+suffix])
        run([str(work/('test-cxx'+suffix))])
        if sys.platform == 'linux':
            (work/'cpp23.cpp').write_text('#include <print>\n#include <version>\n#ifndef _LIBCPP_VERSION\n#error Expected bundled libc++\n#endif\nint main() { std::println("libc++ C++23: {}", 23); }\n')
            library_dirs = sorted({p.parent for p in root.glob('lib*/**/libc++.*') if p.is_file()})
            flags = [flag for directory in library_dirs for flag in ('-L'+str(directory), '-Wl,-rpath,'+str(directory))]
            run([tool('clang++'), '-std=c++23', '-stdlib=libc++', 'cpp23.cpp', *flags, '-o', 'cpp23'])
            result = run([str(work/'cpp23')], capture_output=True)
            if 'libc++ C++23: 23' not in result.stdout: raise RuntimeError(result.stdout)

        run([tool('clang'), 'test.c', '-fprofile-instr-generate', '-fcoverage-mapping', '-o', 'coverage'+suffix])
        run([str(work/('coverage'+suffix))], env=dict(os.environ, LLVM_PROFILE_FILE=str(work/'test.profraw')))
        run([tool('llvm-profdata'), 'merge', '-sparse', 'test.profraw', '-o', 'test.profdata'])
        report = run([tool('llvm-cov'), 'report', 'coverage'+suffix, '-instr-profile=test.profdata'], capture_output=True)
        if '100.00%' not in report.stdout: raise RuntimeError(report.stdout)
        print(report.stdout)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('toolchain')
    smoke(parser.parse_args().toolchain)
