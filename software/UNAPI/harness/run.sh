#!/usr/bin/env bash
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
TIMEOUT="${TIMEOUT:-120}"
# Ubuntu has no bare `python`; Git Bash on Windows has no `python3`.
PYTHON="${PYTHON:-python}"

MACHINE="Canon_V-25"

# Hardware profile.  HW=msxpi (default) serves the disk over MSXPi, which is the
# existing working setup and what every phase before InterNestor Lite needs.
# HW=mfr is the Option D target from UNAPI/PHASE1_DESIGN.md 2.2 - disk and memory
# mapper on the MegaFlashROM, MSXPi for network only.  It is NOT usable yet: the
# openMSX MegaFlashROM auto-creates blank SDcard1.sdc / SDcard2.sdc, so Nextor
# 2.10 loads, finds no filesystem, and the machine ends up in SCREEN 8.  Building
# a formatted SD image is a tracked follow-up.
HW="${HW:-msxpi}"
case "$HW" in
    msxpi) EXTS=(-ext MSXPi -ext ram2mb) ;;
    mfr)   EXTS=(-ext "MegaFlashROM_SCC+_SD" -ext MSXPi) ;;
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
    rm -f "$result"

    # A fresh server per test: the protocol is stateful and a test that dies
    # mid-block would otherwise leave the next one reading someone else's bytes.
    start_server

    MSXPI_HARNESS_OUT="$result" \
    timeout "$TIMEOUT" "$OPENMSX" \
        -machine "$MACHINE" "${EXTS[@]}" "${RENDER_ARGS[@]}" \
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
