"""Compile an instrumented program and analyze its FDR log with the same LLVM."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def smoke(root):
    root = Path(root).resolve()
    with tempfile.TemporaryDirectory(prefix='llvmup-xray-') as directory:
        work = Path(directory)
        source = work / 'probe.cpp'
        source.write_text('''#include <xray/xray_interface.h>
#include <xray/xray_log_interface.h>
[[clang::xray_always_instrument]] __attribute__((noinline))
int probe(int value) { return value + 1; }
[[clang::xray_never_instrument]] int main() {
  if (__xray_log_select_mode("xray-fdr") != XRAY_REGISTRATION_OK) return 5;
  if (__xray_log_init_mode("xray-fdr", "func_duration_threshold_us=0") !=
      XRAY_LOG_INITIALIZED) return 1;
  __xray_patch();
  volatile int result = probe(41);
  __xray_unpatch();
  if (__xray_log_finalize() != XRAY_LOG_FINALIZED) return 2;
  if (__xray_log_flushLog() != XRAY_LOG_FLUSHED) return 3;
  return result == 42 ? 0 : 4;
}
''')
        binary = work / 'probe'
        subprocess.run([str(root/'bin/clang++'), '-fuse-ld=bfd', '-fxray-instrument',
                        str(source), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True, env=dict(os.environ,
                       XRAY_OPTIONS='xray_logfile_base=' + str(work/'xray-log-')))
        xray = str(root/'bin/llvm-xray')
        subprocess.run([xray, 'extract', str(binary)], check=True, stdout=subprocess.DEVNULL)
        logs = list(work.glob('xray-log-*'))
        if not logs:
            raise RuntimeError('XRay did not produce an FDR log')
        for log in logs:
            subprocess.run([xray, 'account', '-instr_map='+str(binary), str(log)], check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('toolchain', help='Linux toolchain with clang and llvm-xray')
    smoke(parser.parse_args().toolchain)
