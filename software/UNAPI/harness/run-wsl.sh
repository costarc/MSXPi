#!/usr/bin/env bash
# =============================================================================
# Run the harness inside Ubuntu WSL against the natively-built openMSX.
# =============================================================================
#   ./run-wsl.sh                  all tests, including the wsl_* ones
#   ./run-wsl.sh wsl_waitmode     just one
#
# Why this exists: the Windows openmsx.exe cannot emulate hardware /WAIT until
# it is rebuilt, whereas /opt/openMSX in WSL is built from
# Dev/github/openMSX/openMSX and does.  Same tests, same server, same disk
# image (the server's /home/pi/msxpi default is symlinked to /mnt/c/home/pi/msxpi
# inside WSL) - only the emulator binary differs.
# =============================================================================
set -eu

DISTRO="${DISTRO:-Ubuntu-24.04}"

# `pwd -W` gives the Windows form (C:/...) under Git Bash; plain `pwd` there
# gives the MSYS form (/c/...).  Accept either and normalise to /mnt/c/...
HERE_WIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && { pwd -W 2>/dev/null || pwd; })"
HERE_WSL="$(printf '%s' "$HERE_WIN" \
    | sed -E 's#^([A-Za-z]):#/mnt/\L\1#' \
    | sed -E 's#^/([A-Za-z])/#/mnt/\1/#')"

# Clear anything a previously interrupted run left behind.  A surviving openmsx
# keeps /opt/openMSX/bin/openmsx open, and the next `make install` then fails
# with "Text file busy"; a surviving server holds port 5000.
# pkill -x matches the PROCESS NAME exactly.  Do not use `pkill -f` with a path
# here: this very command line contains "openMSX/bin/openmsx" in the OPENMSX=
# assignment below, so a full-command-line match kills its own shell and the
# run silently produces nothing.
exec wsl.exe -d "$DISTRO" -- bash -lc \
  "pkill -x openmsx 2>/dev/null; pkill -x msxpi-server.py 2>/dev/null; \
   cd '$HERE_WSL' && OPENMSX=/opt/openMSX/bin/openmsx PYTHON=python3 INCLUDE_WSL=1 ./run.sh $*"
