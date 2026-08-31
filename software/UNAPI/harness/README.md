# MSXPi UNAPI test harness

Automated openMSX loop for the UNAPI work: **build → boot → run → scrape the
screen → assert**, with no hardware and no human in the loop.

```bash
./run.sh                    # run every test in tests/
./run.sh smoke              # run one
./run.sh smoke dos_dir      # run several
```

Exit status is 0 only if every test passed, so this drops straight into CI or a
pre-commit hook.

## What a test looks like

```tcl
harness::init "dos_dir"

harness::at_dos_prompt {
    harness::run_command "DIR" 12 {
        harness::assert_screen_contains "sees-msxpi-rom" "MSXPIBIO ROM"
        harness::done
    }
}
```

Tests are openMSX TCL scripts in `tests/`. `lib/harness.tcl` is sourced first
and provides:

| proc | purpose |
|---|---|
| `harness::init name` | name the test; result file comes from `MSXPI_HARNESS_OUT` |
| `harness::at_dos_prompt body ?timeout?` | run `body` once `A:` appears |
| `harness::run_command cmd settle body` | type `cmd`, wait, then run `body` |
| `harness::wait_for pattern timeout body ?onfail?` | poll the screen for text |
| `harness::wait seconds body` | plain delay |
| `harness::screen_lines` / `screen_text` | current screen as lines / one string |
| `harness::assert_screen_contains name pat` | assertion |
| `harness::assert_screen_lacks name pat` | negative assertion |
| `harness::assert_eq name expected actual` | value assertion |
| `harness::done` | write results and quit openMSX |

**All waiting is on emulated time**, never wall-clock, so tests behave the same
on a loaded host and cannot flake.

### Server-side assertions

Some things are only visible on the Pi side — that a command actually arrived,
that the checksums matched. A test may have a `tests/<name>.expect` file with
one `grep` pattern per line; each must appear in that test's `server.log`.
Without this, a test that never really talked to the server could still pass.

See `tests/msxpi_roundtrip.expect`.

## Screen scraping

Text is read out of VRAM via the `VRAM` and `VDP regs` debuggables rather than
openMSX's optional `save_msx_screen` script — those debuggables are always
present and need no auto-loading.

Geometry is **decoded from the VDP mode bits**, not assumed:

```
M1 = R1 bit4   M2 = R1 bit3   M3 = R0 bit1   M4 = R0 bit2   M5 = R0 bit3
  M1 only  -> TEXT1    (SCREEN 0, 40 col)
  M1 + M4  -> TEXT2    (SCREEN 0 width 80)
  none     -> GRAPHIC1 (SCREEN 1, 32 col)   <- what MSX-DOS uses here
```

This matters: the machine boots into **SCREEN 1, 32 columns, name table
0x1800**. An early version of this harness assumed 40 columns and still
"passed" — the substrings it matched happened to survive the smeared read. If
you add a mode, verify it by dumping the same screen at two candidate widths
and seeing which one produces clean text, rather than trusting the register
decode alone.

## Hardware profiles

```bash
HW=msxpi ./run.sh      # default
HW=mfr   ./run.sh
```

- **`msxpi`** (default) — `Canon_V-25` + `MSXPi` + `Ram2Mb`. Disk served over
  MSXPi. This is the existing working setup and boots to `A:` at about
  16 emulated seconds. Everything before InterNestor Lite uses this.
- **`mfr`** — `Canon_V-25` + `MegaFlashROM_SCC+_SD` + `MSXPi`. The Option D
  target from `../PHASE1_DESIGN.md` §2.2: disk and memory mapper on the
  MegaFlashROM, MSXPi for network only.

  **`mfr` does not work yet.** openMSX auto-creates blank `SDcard1.sdc` /
  `SDcard2.sdc`, so Nextor 2.10 loads, finds no filesystem, and the machine
  ends up in SCREEN 8 showing garbage. Both extensions *do* coexist correctly
  (MegaFlashROM in slot 1, MSXPi in slot 2, `hasmemorymapper` true) — the only
  missing piece is a formatted SD image. Tracked as a follow-up.

## Environment

| var | default | meaning |
|---|---|---|
| `OPENMSX` | the tree this project uses | path to `openmsx.exe` |
| `MSXPI_SERVER` | `../../Server/Python/src/msxpi-server.py` | set to `""` to skip starting a server |
| `TIMEOUT` | 120 | wall-clock seconds before a hung openMSX is killed |
| `HW` | `msxpi` | hardware profile, above |

A fresh server is started per test: the protocol is stateful, and a test that
died mid-block would otherwise leave the next one reading someone else's bytes.

## Output

`out/` holds, per test: `<name>.result` (assertions plus a dump of the final
screen), `<name>.server.log`, `<name>.openmsx.log`. All are overwritten each
run and none are worth committing.
