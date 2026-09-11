#!/usr/bin/env bash
# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

# =============================================================================
# MSXPi UNAPI test harness - runner
# =============================================================================
#   ./run.sh                 run every test in tests/
#   ./run.sh smoke           run tests/smoke.tcl
#   ./run.sh smoke eth_info  run several by name
#
# Environment:
#   OPENMSX      path to the openmsx binary (default: the Windows build)
#   PYTHON       python interpreter (default: python; use python3 on Linux)
#   MSXPI_SERVER path to msxpi-server.py; set to "" to skip starting a server
#   TIMEOUT      wall-clock seconds before a hung openMSX is killed (default 120)
#
# Exit status is 0 only if every test reported RESULT PASS.
# =============================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="$HERE/out"

OPENMSX="${OPENMSX:-C:/Users/roniv/Dev/MSX/MSXPi/openMSX/openmsx.exe}"
MSXPI_SERVER="${MSXPI_SERVER-$HERE/../../Server/Python/src/msxpi-server.py}"
TIMEOUT="${TIMEOUT:-300}"
# Ubuntu has no bare `python`; Git Bash on Windows has no `python3`.
PYTHON="${PYTHON:-python}"

# Canon_V-25 has only a 64K mapper, so the harness adds ram2mb - which lands the
# mapper in a DIFFERENT SLOT from page-1 RAM.
#
# That used to be the standing explanation for "INL S" reporting "not
# installed": InterNestor Lite's residency check looks at RAMAD1 (F344h).  It
# is NOT the explanation - MACHINE=Philips_NMS_8245 HW=msxpi128 has 128K in the
# main slot, needs no ram2mb, and puts the mapper and page-1 RAM in the same
# slot, and INL S still says not installed there.  Use that combination when
# something genuinely looks slot-dependent; do not re-run it for INL S.
MACHINE="${MACHINE:-Canon_V-25}"

# Hardware profile.  HW=msxpi (default) serves the disk over MSXPi, which is the
# existing working setup and what every phase before InterNestor Lite needs.
# HW=mfr is the Option D target from UNAPI/PHASE1_DESIGN.md 2.2 - disk and memory
# mapper on the MegaFlashROM, MSXPi for network only.  It is NOT usable yet: the
# openMSX MegaFlashROM auto-creates blank SDcard1.sdc / SDcard2.sdc, so Nextor
# 2.10 loads, finds no filesystem, and the machine ends up in SCREEN 8.  Building
# a formatted SD image is a tracked follow-up.
HW="${HW:-msxpi}"
# Extra -command arguments a profile needs (inserting media, say).  Kept
# separate from RENDER_ARGS, which is rebuilt from scratch further down.
MEDIA_ARGS=()
case "$HW" in
    # DOS1 target: MSXPi in SLOT 2, booting MSX-DOS 1 from the Pi-served
    # msxpiboot.dsk.  Extension order is slot order, so ram2mb goes first to
    # take slot 1 and leave MSXPi in slot 2, matching the hardware - the
    # driver then reports slot 2 as it does there.  ram2mb is also what
    # supplies the memory mapper INL needs, which a bare V-25 does not have.
    msxpi) EXTS=(-ext ram2mb -ext MSXPi) ;;
    msxpi128) EXTS=(-ext MSXPi) ;;   # machine already has >=128K in the RAM slot
    # The real target: MegaFlashROM SCC+SD in slot 1 running Nextor, MSXPi in
    # slot 2 for the network only.  Extension order is slot order, so MFR must
    # come first to land in slot 1 and match the hardware - the driver then
    # reports slot 2, as it does on the real machine.
    #
    # Needs a FORMATTED Nextor SD image in SDIMG.  Without one openMSX
    # auto-creates a blank SDcard1.sdc, Nextor finds no filesystem, and the
    # machine ends up in SCREEN 8 garbage - which looks like a harness bug and
    # is not one.
    # DOS2 target: Canon V-25, MegaFlashROM SCC+SD in slot 1, MSXPi in slot 2,
    # booting Nextor.  The Nextor tree lives as a host FOLDER and is baked into
    # a hard-disk image by ./mknextorhd.sh - openMSX only does folder-as-disk
    # for floppies, not for hd/SD devices.  Re-run that script whenever the
    # tools in the folder change; nothing here detects staleness.
    nextor)
        EXTS=(-ext "MegaFlashROM_SCC+_SD" -ext MSXPi)
        NEXTORHD="${NEXTORHD:-C:/Users/roniv/Dev/MSX/NextorHD.dsk}"
        [ -f "$NEXTORHD" ] || {
            echo "no Nextor HD image at $NEXTORHD - run ./mknextorhd.sh first"
            exit 1
        }
        MEDIA_ARGS=(-command "hdb {$NEXTORHD}")
        ;;
    mfr)
        EXTS=(-ext "MegaFlashROM_SCC+_SD" -ext MSXPi)
        if [ -n "${SDIMG:-}" ]; then
            # Either a real .sdc image or a DIRECTORY - openMSX mounts a
            # folder as the card's filesystem, which is how the Nextor boot
            # tree is kept editable from the host side.
            [ -e "$SDIMG" ] || { echo "SDIMG not found: $SDIMG"; exit 1; }
            MEDIA_ARGS=(-command "sdcard1 insert {$SDIMG}")
        else
            echo "!! HW=mfr with no SDIMG set - Nextor will find no filesystem."
            echo "   Set SDIMG=/path/to/nextor.sdc"
        fi
        ;;
    *)     echo "unknown HW='$HW' (want msxpi or mfr)"; exit 1 ;;
esac

# Headless by default.  Tests read the screen out of VRAM through the debugger,
# which the VDP keeps updating whether or not anything is drawn, so a window
# buys nothing - and under WSL there is no X server at all, so openMSX would
# abort with "SDL init failed: x11 not available".
# Set HEADLESS=0 to watch a test run.
if [ "${HEADLESS:-1}" = "1" ]; then
    RENDER_ARGS=(-command "set renderer none")
else
    RENDER_ARGS=()
fi

mkdir -p "$OUTDIR"

# --- pick the tests ---------------------------------------------------------
if [ $# -gt 0 ]; then
    TESTS=("$@")
else
    TESTS=()
    for f in "$HERE"/tests/*.tcl; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .tcl)"
        # wsl_* tests need the natively-built openMSX in WSL (hardware /WAIT
        # emulation); they would always fail against the Windows binary until
        # it is rebuilt, so the default suite leaves them out.  run-wsl.sh
        # sets INCLUDE_WSL=1.
        case "$name" in
            wsl_*) [ "${INCLUDE_WSL:-0}" = "1" ] || continue ;;
            # nextor_* model the DOS2 target and need HW=nextor plus the hard
            # disk image ./mknextorhd.sh builds; they would fail on any other
            # profile for reasons that have nothing to do with the driver.
            nextor_*) [ "$HW" = "nextor" ] || continue ;;
        esac
        TESTS+=("$name")
    done
fi

if [ ${#TESTS[@]} -eq 0 ]; then
    echo "no tests found in $HERE/tests"
    exit 1
fi

# --- server -----------------------------------------------------------------
# The openMSX MSXPi device is a TCP client to 127.0.0.1:5000 (MSXPiDevice.cc),
# so a server has to be listening or every MSXPi access reads stale bytes.
# Refuse to start if something is ALREADY serving port 5000.  Three separate
# debugging sessions were lost to this: a leftover msxpi-server or a stray
# openMSX keeps the port, the harness's own server either loses the bind or is
# bypassed entirely, and every test then fails looking like a machine that will
# not boot - blank screen, no banner, nothing in the log to suggest a stale
# process.  Cheap to detect, very expensive to diagnose.
if "$PYTHON" -c "import socket,sys; sys.exit(0 if socket.socket().connect_ex(('127.0.0.1',5000))==0 else 1)" 2>/dev/null; then
    echo "!! something is already listening on 127.0.0.1:5000"
    echo "   stop it first - a leftover msxpi-server.py, or an openMSX still running"
    exit 1
fi

SERVER_PID=""
start_server() {
    [ -n "$MSXPI_SERVER" ] || return 0
    if [ ! -f "$MSXPI_SERVER" ]; then
        echo "!! server not found at $MSXPI_SERVER - continuing without it"
        return 0
    fi
    # -u: without it Python block-buffers stdout when redirected and the log
    # stays empty until exit, which is useless while diagnosing a failed test.
    # Run from the server's own directory: it resolves its .ini and disk images
    # relative to itself.
    ( cd "$(dirname "$MSXPI_SERVER")" && exec "$PYTHON" -u "$(basename "$MSXPI_SERVER")" ) \
        >"$OUTDIR/$t.server.log" 2>&1 &
    SERVER_PID=$!
    # Give it a moment to bind before openMSX tries to connect.
    sleep 2
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "!! server exited immediately - see $OUTDIR/$t.server.log"
        SERVER_PID=""
    fi
}

stop_server() {
    [ -n "$SERVER_PID" ] || return 0
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    SERVER_PID=""
}

cleanup() { stop_server; }
trap cleanup EXIT INT TERM

# --- run --------------------------------------------------------------------
pass=0
fail=0
failed_names=()

for t in "${TESTS[@]}"; do
    script="$HERE/tests/$t.tcl"
    if [ ! -f "$script" ]; then
        echo "SKIP $t (no $script)"
        continue
    fi

    result="$OUTDIR/$t.result"
    # Remove every artefact for this test, not just the result: a stale
    # .screen from a previous run looks exactly like a fresh one and will
    # happily send you diagnosing output that no longer exists.
    rm -f "$result" "$result".* "$OUTDIR/$t.openmsx.log"

    # A fresh server per test: the protocol is stateful and a test that dies
    # mid-block would otherwise leave the next one reading someone else's bytes.
    start_server

    MSXPI_HARNESS_OUT="$result" \
    timeout "$TIMEOUT" "$OPENMSX" \
        -machine "$MACHINE" "${EXTS[@]}" "${MEDIA_ARGS[@]}" "${RENDER_ARGS[@]}" \
        -script "$HERE/lib/harness.tcl" \
        -script "$script" \
        >"$OUTDIR/$t.openmsx.log" 2>&1
    rc=$?

    stop_server

    if [ ! -f "$result" ]; then
        echo "NORESULT $t (openmsx rc=$rc, see $OUTDIR/$t.openmsx.log)"
        fail=$((fail + 1)); failed_names+=("$t")
        continue
    fi

    # Optional server-side expectations.  Some things are only observable on the
    # Pi side - that a command actually arrived, that the checksums matched -
    # and asserting them on the MSX screen alone would pass a test that never
    # really talked to the server.  tests/<name>.expect holds one grep pattern
    # per line; blank lines and # comments are ignored.
    expect="$HERE/tests/$t.expect"
    expect_fail=0
    if [ -f "$expect" ]; then
        while IFS= read -r pat; do
            case "$pat" in ""|\#*) continue ;; esac
            if ! grep -q "$pat" "$OUTDIR/$t.server.log" 2>/dev/null; then
                echo "       server.log missing: $pat"
                expect_fail=1
            fi
        done < "$expect"
    fi

    if grep -q "^RESULT PASS" "$result" && [ $expect_fail -eq 0 ]; then
        echo "PASS $t"
        pass=$((pass + 1))
    else
        echo "FAIL $t"
        sed -n '/^FAIL /p' "$result" | sed 's/^/       /'
        fail=$((fail + 1)); failed_names+=("$t")
    fi
done

echo "-----------------------------------------"
echo "passed $pass, failed $fail"
if [ $fail -gt 0 ]; then
    echo "failing: ${failed_names[*]}"
    echo "details in $OUTDIR/"
    exit 1
fi
exit 0
