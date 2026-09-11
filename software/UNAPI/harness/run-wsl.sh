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
# TIMEOUT is forwarded because they are set outside WSL: a long
# transfer needs more than the default 300s, and without this the run was
# killed at 300s and reported as NORESULT rather than as a slow pass.
# For openmsx, pkill -x matches the PROCESS NAME exactly.  Do NOT use `pkill -f`
# for it: this very command line contains "openMSX/bin/openmsx" in the OPENMSX=
# assignment below, so a full-command-line match would kill its own shell and
# the run would silently produce nothing.
#
# The SERVER is the opposite case and needs -f.  It runs as `python3 -u
# msxpi-server.py`, so its process NAME is "python3" and `pkill -x
# msxpi-server.py` never matched anything - a stale server survived every run,
# the new one lost the bind with "Address already in use", and every test then
# failed as a machine that would not boot.  "msxpi-server.py" does not appear
# in this command line, so -f is safe here.
exec wsl.exe -d "$DISTRO" -- bash -lc \
  "pkill -x openmsx 2>/dev/null; pkill -f 'msxpi-server\.py' 2>/dev/null; \
   cd '$HERE_WSL' && OPENMSX=/opt/openMSX/bin/openmsx PYTHON=python3 INCLUDE_WSL=1 TIMEOUT=${TIMEOUT:-300} ./run.sh $*"
