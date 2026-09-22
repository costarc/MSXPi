#!/bin/bash
# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License - Copyright (c) 2015-2026 Ronivon Costa
# The full licence text is in the LICENSE file of this repository.
# ------------------------------------------------------------------------------
#
# Compatibility stub. The setup scripts moved from software/Server/Shell to
# software/Server/Setup, but the short link https://tinyurl.com/MSXPi-Setup (and
# every guide that quotes it) still points at this path. This fetches the real
# script and runs it with the same options, so the old command keeps working:
#
#   wget https://tinyurl.com/MSXPi-Setup && bash ./MSXPi-Setup
#
# New guides should link to software/Server/Setup/msxpi-setup.sh directly.

URL="https://raw.githubusercontent.com/${MSXPI_REPO:-costarc/MSXPi}/${MSXPI_BRANCH:-master}/software/Server/Setup/msxpi-setup.sh"
tmp="$(mktemp)" || exit 1
if ! wget -q --tries=3 --timeout=30 -O "$tmp" "$URL" || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    echo "msxpi-setup: cannot download $URL - is the Pi online?" >&2
    exit 1
fi
exec bash "$tmp" "$@"
