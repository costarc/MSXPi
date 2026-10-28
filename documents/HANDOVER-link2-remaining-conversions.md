# LINK2 - the three tools that were still on the legacy protocol: DONE

Status (2026-10-26): all three conversions are finished on `feature/link2`. This handover is kept only as a pointer.

- `playnet`: converted (38441d2b, shipped in e586169d). `playnet save` goes as two transfers that the server joins.
- `msxarch.asm`: deleted (6f4ca3da); the C `msxarch.c` is the only msxarch.
- `ROM-Patcher` runtimes arctic, goonies, nemesis, vampire: converted (a6e8c348), assets rebuilt (fca766d6).

What was done, what it found and what is left is in `LINK2-IMPLEMENTATION-PLAN.md`, "Phase 7 results" ("The three remaining
tools"). Open: nothing has run on the hardware; the checklist is `LINK2-TEST-PLAN.md` T6.7. Retiring the legacy protocol
from the server and from `msxpi_bios.asm` (`IFNDEF MSXPI_LINK2`) is a separate decision, to be taken after the hardware
tests: older EEPROMs and installs would stop working.
