# LLVMUP Maintenance Roadmap

LLVMUP is in maintenance-first mode. The current command set is broad enough;
the priority is to make it predictable before considering additional features.

## Current priorities

1. Fix reproducible bugs in installation, activation, version selection, removal,
   and project configuration.
2. Add a regression test for each confirmed bug when practical.
3. Keep Bash and PowerShell behavior aligned for commands that already exist.
4. Preserve download integrity checks and fail safely on partial operations.
5. Remove stale claims and examples when documentation differs from the code.

Work should be driven by a failing test or a minimal reproducer. Broad rewrites,
new abstraction layers, and speculative performance work are out of scope unless
they are required to correct a confirmed defect.

## Feature requests

There is no feature backlog at this time. New feature proposals should remain in
the issue tracker until there is evidence of recurring user need, a small design,
and a clear long-term maintenance cost. Acceptance is exceptional while known
reliability issues remain.
