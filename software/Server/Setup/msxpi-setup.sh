#!/bin/bash
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
#
# MSXPi Raspberry Pi setup: a freshly installed Raspberry Pi OS (Lite) to a
# working msxpi-server, in one run.
#
#   wget https://tinyurl.com/MSXPi-Setup && bash ./MSXPi-Setup
#
# Safe to run again: it updates the server, keeps msxpi.ini, and repairs
# whatever is missing. Run as the user "pi" (it uses sudo) or as root.
#
# File history :
# 0.1    : Initial version.
# 1.6    : Rewritten to be self-contained and repeatable.
#          - checks the Pi, the network and the clock before changing anything
#          - packages are installed so that one a newer OS no longer ships
#            (libcurl4-nss-dev and pigpio are gone from Debian 13) cannot
#            abort the whole install
#          - installs RPi.GPIO, iptables and procps, and a setuptools that still
#            has pkg_resources (needed by "fs")
#          - installs msxpi-tcpip-setup.sh, which the old script never did
#          - msxpi.ini follows the board (--board) and is never overwritten
#          - verifies the result and only then reboots

set -u
set -o pipefail

MSXPI_USER=pi
MSXPIHOME=/home/pi/msxpi
MSXPI_REPO="${MSXPI_REPO:-costarc/MSXPi}"
BRANCH="${MSXPI_BRANCH:-master}"

BOARD="${MSXPI_BOARD:-}"
WIFI_SSID="${MSXPI_WIFI_SSID:-}"
WIFI_PSK="${MSXPI_WIFI_PSK:-}"
WIFI_COUNTRY="${MSXPI_WIFI_COUNTRY:-}"
SOURCE=""
FORCE_DOWNLOAD=0
RESET_INI=0
DO_REBOOT=1
DO_SSH=1
DO_SWAP=1
DO_AUDIO=1
ALLOW_NON_PI="${MSXPI_ALLOW_NON_PI:-0}"

WARNINGS=0
FAILURES=0
WORK=""

usage() {
    cat <<EOF
Usage: msxpi-setup.sh [options]

  --board v1.3|v1.1|old   which MSXPi board you have; picks the msxpi.ini template
                          (default old, or asked when run from a terminal).
                          Only used when msxpi.ini does not exist yet.
  --reset-ini             replace msxpi.ini with the template (the old one is kept
                          as msxpi.ini.bak-<date>)
  --wifi-ssid NAME        join this WiFi network at the end of the setup
  --wifi-psk PASSWORD       (or set MSXPI_WIFI_SSID / MSXPI_WIFI_PSK)
  --wifi-country CC       two-letter regulatory country, e.g. GB, BR, ES
  --no-ssh                do not enable the SSH server
  --no-swap               leave the swap file alone (default: switch it off, so the
                          SD card is not worn out)
  --no-audio              do not configure a USB sound card
  --no-reboot             do not reboot at the end
  --branch NAME           take the files from this branch of ${MSXPI_REPO} (default master)
  --source DIR            take the files from a local checkout of the repository
                          (used automatically when this script runs from one)
  --download              ignore a local checkout, take the files from GitHub
  --force-non-pi          go ahead on a machine that is not a Raspberry Pi
  -h, --help              this text

To keep a copy of what a run printed:
  bash msxpi-setup.sh 2>&1 | tee msxpi-setup.log
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --board)         BOARD="${2:-}"; shift ;;
        --reset-ini)     RESET_INI=1 ;;
        --wifi-ssid)     WIFI_SSID="${2:-}"; shift ;;
        --wifi-psk)      WIFI_PSK="${2:-}"; shift ;;
        --wifi-country)  WIFI_COUNTRY="${2:-}"; shift ;;
        --no-ssh)        DO_SSH=0 ;;
        --no-swap)       DO_SWAP=0 ;;
        --no-audio)      DO_AUDIO=0 ;;
        --no-reboot)     DO_REBOOT=0 ;;
        --branch)        BRANCH="${2:-}"; shift ;;
        --source)        SOURCE="${2:-}"; shift ;;
        --download)      FORCE_DOWNLOAD=1 ;;
        --force-non-pi)  ALLOW_NON_PI=1 ;;
        -h|--help)       usage; exit 0 ;;
        *)               echo "msxpi-setup: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ok   %s\n' "$*"; }
note() { printf '         %s\n' "$*"; }
warn() { printf '    WARN %s\n' "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
err()  { printf '    FAIL %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }
die()  { printf 'msxpi-setup: %s\n' "$*" >&2; exit 1; }

cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT

# Run as root: directly when we are root, through sudo otherwise.
as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

# Run as the MSXPi user, whoever started the script.
as_pi() {
    if [ "$(id -un)" = "$MSXPI_USER" ]; then
        "$@"
    elif [ "$(id -u)" -eq 0 ]; then
        runuser -u "$MSXPI_USER" -- "$@"
    else
        sudo -u "$MSXPI_USER" "$@"
    fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# True when python3 can run the given code. Output is discarded.
pyok() { python3 -c "$1" >/dev/null 2>&1; }

# The module is installed. Not the same as importable: RPi.GPIO refuses to import
# on anything but a Raspberry Pi, which matters for --force-non-pi.
pypresent() {
    pyok "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('$1') else 1)"
}

has_systemd() { [ -d /run/systemd/system ]; }

is_pi() { [ -r /proc/device-tree/model ] && tr -d '\0' </proc/device-tree/model | grep -q "Raspberry Pi"; }

# DPkg::Lock::Timeout: right after the first boot the system updates itself and
# holds the apt lock for minutes. Wait for it (up to 10 minutes) instead of failing.
apt_get() {
    as_root env DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
        -o Dpkg::Options::=--force-confold -o DPkg::Lock::Timeout=600 "$@"
}

# The package exists in the configured repositories.
apt_has() {
    local cand
    cand="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')"
    [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

# Install packages that are not optional. One that is missing is a failed setup.
apt_required() {
    apt_get install --no-install-recommends "$@" >/dev/null
}

# Install packages one at a time, so a package this OS release no longer ships
# cannot take the others down with it. Says which ones it had to leave out.
apt_optional() {
    local p missing=""
    for p in "$@"; do
        dpkg -s "$p" >/dev/null 2>&1 && continue
        if apt_has "$p" && apt_get install --no-install-recommends "$p" >/dev/null 2>&1; then
            :
        else
            missing="$missing $p"
        fi
    done
    [ -z "$missing" ] || warn "not installed (not available, or failed):$missing"
}

# Best effort and silent: the caller checks whether it worked.
apt_try() { apt_has "$1" && apt_get install --no-install-recommends "$1" >/dev/null 2>&1; }

# PIP_BREAK_SYSTEM_PACKAGES is the environment form of --break-system-packages:
# Debian 12+ needs it to install into the system Python, and an older pip that
# does not know the option ignores the variable instead of failing.
pip_install() {
    as_root env PIP_BREAK_SYSTEM_PACKAGES=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
        python3 -m pip install -q "$@" >/dev/null 2>&1
}

# fetch <base> <name> <dest> [mode]
# <base> is a URL or a local directory. The file lands on <dest> owned by the
# MSXPi user, or not at all: a failed download never replaces a good file.
fetch() {
    local base="$1" name="$2" dest="$3" mode="${4:-0644}" tmp
    tmp="$WORK/$(basename "$dest").$$"
    case "$base" in
        http://*|https://*) wget -q --tries=3 --timeout=30 -O "$tmp" "$base/$name" ;;
        *)                  cp "$base/$name" "$tmp" ;;
    esac || { rm -f "$tmp"; return 1; }
    [ -s "$tmp" ] || { rm -f "$tmp"; return 1; }
    as_root install -o "$MSXPI_USER" -g "$MSXPI_USER" -m "$mode" "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
}

fetch_required() {
    fetch "$@" || die "cannot get $2 from $1 - check the network, or --branch / --source"
}

# ------------------------------------------------------------------------------
# 0. Preflight
# ------------------------------------------------------------------------------
preflight() {
    step "Checking this machine"

    [ -r /etc/os-release ] && have apt-get || die "this needs Raspberry Pi OS (or another Debian-based system)"
    # shellcheck disable=SC1091
    ok "$(. /etc/os-release; echo "${PRETTY_NAME:-Linux}"), $(uname -m)"

    if is_pi; then
        ok "$(tr -d '\0' </proc/device-tree/model)"
    elif [ "$ALLOW_NON_PI" = 1 ]; then
        warn "this is not a Raspberry Pi - the server will not reach the MSXPi hardware here"
    else
        die "this is not a Raspberry Pi (use --force-non-pi to install anyway)"
    fi

    if [ "$(id -u)" -ne 0 ]; then
        have sudo || die "sudo is needed when not running as root"
        sudo -v || die "cannot get administrator rights with sudo"
    fi
    # A fresh image can lack wget, and its package lists may be empty.
    if ! have wget; then
        apt_get update >/dev/null 2>&1
        apt_get install wget ca-certificates >/dev/null 2>&1 || die "wget is missing and could not be installed"
    fi

    local free_kb
    free_kb="$(df -Pk / | awk 'NR==2 {print $4}')"
    [ "${free_kb:-0}" -ge 400000 ] || die "less than 400 MB free on / - free some space first"
    ok "$((free_kb / 1024)) MB free"

    # A Pi has no clock of its own: right after the first boot the date can be years
    # off until NTP has run, and then every HTTPS download fails with a
    # certificate error. Wait for the clock rather than turn certificate checks off.
    if [ "$(date +%Y)" -lt 2025 ]; then
        note "the clock says $(date +%F); waiting for network time"
        have timedatectl && as_root timedatectl set-ntp true >/dev/null 2>&1
        # (no loop variable needed)
        for _ in $(seq 1 60); do
            [ "$(date +%Y)" -ge 2025 ] && break
            sleep 2
        done
        [ "$(date +%Y)" -ge 2025 ] || die "the clock is wrong ($(date)) and network time is not working. Set it with: sudo date -s 'YYYY-MM-DD HH:MM:SS'"
    fi
    ok "clock $(date '+%F %H:%M')"

    if [ -z "$SOURCE" ]; then
        # The file itself, not just the host: this is also what a mistyped --branch hits.
        wget -q --spider --timeout=20 --tries=2 "$SW/Server/Setup/update.sh" \
            || die "cannot fetch $SW/Server/Setup/update.sh - is the Pi online, and does the branch exist? (with a local checkout use --source)"
        ok "files reachable"
    fi
}

# ------------------------------------------------------------------------------
# 1. Packages
# ------------------------------------------------------------------------------
install_packages() {
    step "System packages"
    apt_get update >/dev/null 2>&1 || warn "apt-get update failed - using the package lists already here"

    # Everything the server, msxpi-monitor and msxpi-tcpip-setup.sh call:
    #   python3, pip, setuptools  the server and its libraries
    #   gcc, libc6-dev            native GPIO engine (built on the Pi, for the Pi)
    #   iptables, iproute2        the NAT that gives the MSX a network
    #   procps                    ps and pgrep, used by msxpi-monitor
    #   unzip, unar, lhasa        archives (zip, lzh, everything else)
    #   sudo, ca-certificates     as the name says
    apt_required sudo ca-certificates wget procps iproute2 iptables gcc libc6-dev \
        python3 python3-pip python3-setuptools unzip unar lhasa \
        || die "installing the required packages failed (see the apt messages above)"
    ok "required packages"

    # Optional: a feature is lost, not the server, if one is missing. Installed one
    # by one for that reason: the old script listed libcurl4-nss-dev and pigpio in a
    # single command, and on Debian 13 neither exists, so nothing at all was installed.
    # network-manager is deliberately not here: the WiFi commands use it where the
    # image already has it, and adding it to an image without it would change how
    # the Pi connects to the network under the running SSH session.
    apt_optional alsa-utils music123 mplayer smbclient html2text logrotate
}

# ------------------------------------------------------------------------------
# 2. The pi user
# ------------------------------------------------------------------------------
# The server has /home/pi/msxpi built in and runs as "pi". Raspberry Pi Imager lets
# you choose another user name; then this creates a "pi" service account next to it.
setup_user() {
    step "User $MSXPI_USER"
    if id "$MSXPI_USER" >/dev/null 2>&1; then
        ok "exists"
    else
        as_root useradd -m -s /bin/bash "$MSXPI_USER" || die "cannot create user $MSXPI_USER"
        as_root passwd -l "$MSXPI_USER" >/dev/null 2>&1
        ok "created (no password: log in with your own user)"
    fi

    local g
    for g in gpio spi i2c audio video netdev plugdev input; do
        if getent group "$g" >/dev/null 2>&1; then as_root usermod -aG "$g" "$MSXPI_USER"; fi
    done

    # The server reboots, shuts down, rebuilds the network and resets WiFi through
    # sudo, and msxpi-monitor does the same: none of it can ask for a password.
    if as_root sh -c "sudo -l -U $MSXPI_USER 2>/dev/null" | grep -q 'NOPASSWD: *ALL'; then
        ok "passwordless sudo already set"
    else
        local sf=/etc/sudoers.d/010_msxpi
        printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$MSXPI_USER" | as_root tee "$sf" >/dev/null
        as_root chmod 440 "$sf"
        if as_root visudo -cf "$sf" >/dev/null 2>&1; then
            ok "passwordless sudo for $MSXPI_USER ($sf)"
        else
            as_root rm -f "$sf"
            err "could not write a valid sudoers file"
        fi
    fi
}

# ------------------------------------------------------------------------------
# 3. Python libraries
# ------------------------------------------------------------------------------
# The server imports three modules that are not in the standard library:
#   requests   HTTP for the network commands
#   fs         imported at start-up (nothing calls it any more) - and "fs" needs
#              pkg_resources, which setuptools 81 and later no longer contains
#   RPi.GPIO   the Pi's GPIO pins
# (pyfatfs and its signature patch, installed by the old script, are not used.)
setup_python() {
    step "Python libraries"
    ok "Python $(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"

    pyok "import requests" || apt_try python3-requests || true
    pyok "import requests" || pip_install requests || true
    if pyok "import requests"; then ok "requests"; else err "requests cannot be imported"; fi

    pyok "import fs" || apt_try python3-fs || true
    pyok "import fs" || pip_install fs "setuptools<81" || true
    # An "fs" that installed but cannot import is nearly always the missing
    # pkg_resources: put back a setuptools that still has it.
    pyok "import fs" || pip_install "setuptools<81" || true
    if pyok "import fs"; then
        ok "fs $(python3 -c 'import fs; print(fs.__version__)')"
    else
        err "fs cannot be imported: $(python3 -c 'import fs' 2>&1 | tail -1)"
    fi

    if ! pypresent RPi; then
        if grep -q "Raspberry Pi 5" /proc/device-tree/model 2>/dev/null; then
            apt_try python3-rpi-lgpio || apt_try python3-rpi.gpio || true
        else
            apt_try python3-rpi.gpio || apt_try python3-rpi-lgpio || true
        fi
        if ! pypresent RPi; then
            # Not in this OS's repositories: the PyPI package compiles a C extension.
            apt_try python3-dev || true
            pip_install RPi.GPIO || true
        fi
    fi
    if pypresent RPi; then
        ok "RPi.GPIO"
    elif is_pi; then
        err "RPi.GPIO is not installed"
    else
        warn "RPi.GPIO is not installed (not a Pi, so not needed here)"
    fi
}

# ------------------------------------------------------------------------------
# 4. MSXPi files
# ------------------------------------------------------------------------------
choose_board() {
    [ -n "$BOARD" ] && return 0
    # Matches the old script, which always installed msxpi-JumperLeft.ini: when
    # nobody says otherwise, assume the older board rather than guess newer.
    if [ -t 0 ] && [ -t 1 ]; then
        echo "Which MSXPi board do you have?"
        echo "  1) older boards (default)"
        echo "  2) V1.1 Rev.0"
        echo "  3) V1.3 or later"
        local ans=""
        read -r -t 60 -p "Choice [1]: " ans || ans=""
        case "$ans" in
            2) BOARD=v1.1 ;;
            3) BOARD=v1.3 ;;
            *) BOARD=old ;;
        esac
    else
        BOARD=old
        note "no --board given: using the older-board pin layout (pass --board v1.3 or --board v1.1 if that is yours)"
    fi
}

install_msxpi() {
    step "MSXPi files in $MSXPIHOME"
    as_root install -d -o "$MSXPI_USER" -g "$MSXPI_USER" -m 0755 \
        "$MSXPIHOME" "$MSXPIHOME/disks" "$MSXPIHOME/native"
    # Old installs linked /home/msxpi to the same place; kept for scripts that use it.
    [ -e /home/msxpi ] || as_root ln -s "$MSXPIHOME" /home/msxpi 2>/dev/null

    # The server and its modules, the native GPIO engine source, msxpi-tcpip-setup.sh:
    # update.sh knows the list, and it is also what the MSX runs to update the server.
    fetch_required "$SRC_SETUP" update.sh "$MSXPIHOME/update.sh" 0755
    if ! as_root env MSXPI_UPDATE_BASE="$SRC_PY" MSXPI_UPDATE_SETUP_BASE="$SRC_SETUP" \
            sh "$MSXPIHOME/update.sh" 2>&1 | sed 's/^/    /'; then
        err "update.sh reported a problem (see above)"
    fi

    local f
    for f in msxpi-server.py mapper_detect.py msxpi_eth.py msxpi_gpio_native.py msxpi-tcpip-setup.sh; do
        [ -s "$MSXPIHOME/$f" ] || err "$f is missing"
    done

    fetch_required "$SRC_SETUP" msxpi-monitor "$MSXPIHOME/msxpi-monitor" 0755
    fetch_required "$SRC_SETUP" kill.sh "$MSXPIHOME/kill.sh" 0755
    fetch_required "$SRC_SETUP" pplay.sh "$MSXPIHOME/pplay.sh" 0755
    ok "server, helpers, monitor"

    # Boot and tools disks for the Pi-served drives A: and B:. Kept as .bak when replaced.
    for f in msxpiboot.dsk tools.dsk; do
        [ -f "$MSXPIHOME/disks/$f" ] && as_pi cp -p "$MSXPIHOME/disks/$f" "$MSXPIHOME/disks/$f.bak"
        fetch "$SRC_DISKS" "$f" "$MSXPIHOME/disks/$f" 0644 || warn "could not get disks/$f"
    done
    ok "disks"

    # Template per board. All three are kept next to msxpi.ini for reference.
    local t
    for t in msxpi-JumperLeft.ini msxpi-JumperRight.ini msxpi-JumperRight_PCBV1.1Rev.0.ini; do
        fetch "$SRC_PY" "$t" "$MSXPIHOME/$t" 0644 || warn "could not get $t"
    done

    if [ -f "$MSXPIHOME/msxpi.ini" ] && [ "$RESET_INI" -eq 0 ]; then
        ok "msxpi.ini kept (your settings and keys are not touched; --reset-ini replaces it)"
    else
        choose_board
        local tmpl
        case "$BOARD" in
            v1.3|1.3|v1.3+) tmpl=msxpi-JumperRight.ini ;;
            v1.1|1.1)       tmpl=msxpi-JumperRight_PCBV1.1Rev.0.ini ;;
            old|older)      tmpl=msxpi-JumperLeft.ini ;;
            *)              die "unknown board '$BOARD' (use v1.3, v1.1 or old)" ;;
        esac
        [ -s "$MSXPIHOME/$tmpl" ] || die "$tmpl is missing"
        if [ -f "$MSXPIHOME/msxpi.ini" ]; then
            as_pi cp -p "$MSXPIHOME/msxpi.ini" "$MSXPIHOME/msxpi.ini.bak-$(date +%Y%m%d)"
        fi
        as_pi cp "$MSXPIHOME/$tmpl" "$MSXPIHOME/msxpi.ini"
        ok "msxpi.ini from $tmpl"
        note "a board without the shutdown button needs the line: var RPI_SHUTDOWN=none"
    fi

    # Older setups ran the server, or this script, as root.
    as_root chown -R "$MSXPI_USER:$MSXPI_USER" "$MSXPIHOME"

    if [ -f "$MSXPIHOME/native/libmsxpi_gpio.so" ]; then
        ok "native GPIO engine built for $(uname -m)"
    else
        warn "native GPIO engine not built: the server will use the slower Python GPIO"
    fi
}

# ------------------------------------------------------------------------------
# 5. System integration
# ------------------------------------------------------------------------------
setup_system() {
    step "System integration"

    # /media/ramdisk: msxpi-monitor wants a small RAM disk there, and tries to make
    # one from /dev/ramdisk, which current kernels no longer have. A tmpfs does it.
    if ! grep -qs ' /media/ramdisk ' /etc/fstab; then
        printf 'tmpfs /media/ramdisk tmpfs defaults,noatime,nosuid,size=2m,uid=%s,gid=%s,mode=0755 0 0\n' \
            "$(id -u "$MSXPI_USER")" "$(id -g "$MSXPI_USER")" | as_root tee -a /etc/fstab >/dev/null
    fi
    as_root mkdir -p /media/ramdisk
    mountpoint -q /media/ramdisk || as_root mount /media/ramdisk 2>/dev/null || true
    ok "/media/ramdisk"

    # The server and msxpi-monitor write /var/log/msxpi.log without limit.
    if [ -d /etc/logrotate.d ]; then
        as_root tee /etc/logrotate.d/msxpi >/dev/null <<'EOF'
/var/log/msxpi.log {
    weekly
    rotate 4
    size 5M
    missingok
    notifempty
    compress
    delaycompress
    copytruncate
}
EOF
        ok "log rotation for /var/log/msxpi.log"
    fi

    # msxpi-tcpip-setup.sh creates a TAP device at every start.
    echo tun | as_root tee /etc/modules-load.d/msxpi.conf >/dev/null
    as_root modprobe tun 2>/dev/null || true

    # The service. The old msxpi-server service is gone.
    if has_systemd; then
        as_root systemctl disable msxpi-server >/dev/null 2>&1
    fi
    as_root rm -f /lib/systemd/system/msxpi-server /lib/systemd/system/msxpi-server.service \
                  /lib/systemd/system/msxpi-monitor.service
    fetch_required "$SRC_SETUP" msxpi-monitor.service "$WORK/msxpi-monitor.service" 0644
    as_root install -o root -g root -m 0644 "$WORK/msxpi-monitor.service" /etc/systemd/system/msxpi-monitor.service
    if has_systemd; then
        as_root systemctl daemon-reload
        if as_root systemctl enable msxpi-monitor >/dev/null 2>&1; then
            ok "msxpi-monitor service enabled at boot"
        else
            err "could not enable the msxpi-monitor service"
        fi
    else
        warn "systemd is not running here: the service is installed but not enabled or started"
    fi

    # Protect the SD card: no swap file.
    if [ "$DO_SWAP" -eq 1 ] && have dphys-swapfile; then
        as_root dphys-swapfile swapoff >/dev/null 2>&1
        as_root dphys-swapfile uninstall >/dev/null 2>&1
        has_systemd && as_root systemctl disable dphys-swapfile >/dev/null 2>&1
        ok "swap file switched off"
    fi

    # SSH, for the Pi that has no screen.
    if [ "$DO_SSH" -eq 1 ] && has_systemd; then
        if have raspi-config; then
            as_root raspi-config nonint do_ssh 0 >/dev/null 2>&1 && ok "SSH enabled"
        elif [ -e /lib/systemd/system/ssh.service ] || [ -e /usr/lib/systemd/system/ssh.service ]; then
            as_root systemctl enable ssh >/dev/null 2>&1 && ok "SSH enabled"
        fi
    fi
}

# A USB sound card, when there is one, becomes the default audio device: the Pi has
# no analogue output on the MSXPi header. This writes /etc/asound.conf, not the
# package-owned /usr/share/alsa/alsa.conf that the old script edited, so it survives
# upgrades and can be deleted to undo it.
setup_audio() {
    [ "$DO_AUDIO" -eq 1 ] || return 0
    have aplay || return 0
    local card
    card="$(aplay -l 2>/dev/null | awk '/^card [0-9]+:.*USB/ {print $3; exit}')"
    if [ -z "$card" ]; then
        note "no USB sound card found - audio (p play) is not configured; plug one in and run this again"
        return 0
    fi
    step "Audio"
    as_root tee /etc/asound.conf >/dev/null <<EOF
# Written by msxpi-setup.sh: the USB sound card is the default audio device.
pcm.!default {
    type plug
    slave.pcm "hw:CARD=$card,DEV=0"
}
ctl.!default {
    type hw
    card $card
}
EOF
    ok "USB sound card '$card' is the default audio device"
}

setup_wifi() {
    [ -n "$WIFI_SSID" ] || return 0
    step "WiFi $WIFI_SSID"
    if [ -n "$WIFI_COUNTRY" ]; then
        if have raspi-config; then
            as_root raspi-config nonint do_wifi_country "$WIFI_COUNTRY" >/dev/null 2>&1 \
                || warn "could not set the WiFi country"
        else
            as_root iw reg set "$WIFI_COUNTRY" >/dev/null 2>&1 || true
        fi
    fi
    if have nmcli && as_root systemctl is-active --quiet NetworkManager 2>/dev/null; then
        as_root nmcli radio wifi on >/dev/null 2>&1
        local args=(device wifi connect "$WIFI_SSID")
        [ -n "$WIFI_PSK" ] && args+=(password "$WIFI_PSK")
        if as_root nmcli "${args[@]}" >/dev/null 2>&1; then
            ok "connected"
        else
            err "could not join '$WIFI_SSID' (check the name, password and country)"
        fi
    else
        as_root install -d -m 0755 /etc/wpa_supplicant
        # SSID and key in hex: no quoting problems whatever the characters, and no
        # plain-text password on disk. The key is the standard PBKDF2 of the passphrase.
        local hexssid hexpsk
        hexssid="$(printf '%s' "$WIFI_SSID" | od -An -tx1 | tr -d ' \n')"
        {
            printf 'country=%s\nctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\nupdate_config=1\n\n' \
                "${WIFI_COUNTRY:-GB}"
            if [ -n "$WIFI_PSK" ]; then
                hexpsk="$(python3 -c 'import hashlib, sys; print(hashlib.pbkdf2_hmac("sha1", sys.argv[2].encode(), sys.argv[1].encode(), 4096, 32).hex())' \
                    "$WIFI_SSID" "$WIFI_PSK")"
                printf 'network={\n\tssid=%s\n\tpsk=%s\n}\n' "$hexssid" "$hexpsk"
            else
                printf 'network={\n\tssid=%s\n\tkey_mgmt=NONE\n}\n' "$hexssid"
            fi
        } | as_root tee /etc/wpa_supplicant/wpa_supplicant.conf >/dev/null \
            || { err "could not write /etc/wpa_supplicant/wpa_supplicant.conf"; return 0; }
        as_root chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
        ok "written to /etc/wpa_supplicant/wpa_supplicant.conf (used after a reboot)"
    fi
}

# ------------------------------------------------------------------------------
# 6. Verify
# ------------------------------------------------------------------------------
verify() {
    step "Checking the result"

    local out
    if ! as_pi python3 -c 'import ast, sys; ast.parse(open(sys.argv[1], encoding="utf-8-sig").read())' \
            "$MSXPIHOME/msxpi-server.py" 2>/dev/null; then
        err "msxpi-server.py has a syntax error - the download may be damaged, run this again"
    elif out="$(as_pi sh -c "cd '$MSXPIHOME' && python3 -c 'import mapper_detect, msxpi_eth, msxpi_gpio_native, requests, fs'" 2>&1)"; then
        ok "server and modules load"
    else
        err "the server's modules do not load: $(echo "$out" | tail -1)"
    fi

    if is_pi; then
        if out="$(as_pi python3 -c 'import RPi.GPIO' 2>&1)"; then
            ok "GPIO access as $MSXPI_USER"
        else
            err "$MSXPI_USER cannot use RPi.GPIO: $(echo "$out" | tail -1)"
        fi
    fi

    if [ -x "$MSXPIHOME/msxpi-tcpip-setup.sh" ]; then
        ok "msxpi-tcpip-setup.sh installed"
    else
        err "msxpi-tcpip-setup.sh is missing or not executable"
    fi

    if ! has_systemd; then
        note "no systemd: not starting the service"
        return 0
    fi

    # Only what the server writes from here on counts, not an earlier run.
    local logf=/var/log/msxpi.log off=0 pid1="" pid2=""
    [ -f "$logf" ] && off="$(stat -c %s "$logf")"
    newlog() { tail -c +$((off + 1)) "$logf" 2>/dev/null; }

    as_root systemctl restart msxpi-monitor
    for _ in $(seq 1 20); do
        pid1="$(pgrep -f '[m]sxpi-server.py' | head -n 1)"
        [ -n "$pid1" ] && break
        sleep 1
    done
    if [ -z "$pid1" ]; then
        err "msxpi-server did not start; the end of $logf:"
        newlog | tail -n 15 | sed 's/^/         /'
        return 0
    fi
    # A server that starts and dies is restarted by msxpi-monitor every two seconds,
    # so "a server process exists" proves little. Wait, then require the same process.
    sleep 6
    pid2="$(pgrep -f '[m]sxpi-server.py' | head -n 1)"
    if [ "$pid1" != "$pid2" ]; then
        err "msxpi-server keeps restarting; the end of $logf:"
        newlog | tail -n 25 | sed 's/^/         /'
    elif newlog | grep -q "^Traceback"; then
        err "msxpi-server is running but logged an error:"
        newlog | grep -A6 "^Traceback" | head -n 12 | sed 's/^/         /'
    else
        ok "msxpi-server is running (process $pid1)"
    fi
    if [ -n "$(newlog)" ]; then
        note "last lines of $logf:"
        newlog | tail -n 6 | sed 's/^/           /'
    fi
}

# ------------------------------------------------------------------------------
# main
# ------------------------------------------------------------------------------
WORK="$(mktemp -d)" || die "cannot create a temporary directory"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [ -z "$SOURCE" ] && [ "$FORCE_DOWNLOAD" -eq 0 ] && [ -n "$SCRIPT_DIR" ] \
   && [ -f "$SCRIPT_DIR/update.sh" ] && [ -f "$SCRIPT_DIR/../Python/src/msxpi-server.py" ]; then
    SOURCE="$(cd "$SCRIPT_DIR/../../.." && pwd)"
fi
if [ -n "$SOURCE" ]; then
    [ -d "$SOURCE/software/Server/Python/src" ] || die "--source: $SOURCE is not an MSXPi checkout"
    SW="$SOURCE/software"
else
    # Not in a checkout: GitHub, or MSXPI_BASE_URL (a mirror, or a test server that
    # serves the repository's "software" directory). Worked out here, after the
    # options are read, so that --branch counts.
    SW="${MSXPI_BASE_URL:-https://raw.githubusercontent.com/$MSXPI_REPO/$BRANCH/software}"
fi
SRC_PY="$SW/Server/Python/src"
SRC_SETUP="$SW/Server/Setup"
SRC_DISKS="$SW/target/disks"

echo "MSXPi setup"
if [ -n "$SOURCE" ]; then
    echo "  files from the checkout $SOURCE"
else
    echo "  files from $SW"
fi

preflight
install_packages
setup_user
setup_python
install_msxpi
setup_system
setup_audio
setup_wifi
verify

step "Done"
if [ "$FAILURES" -gt 0 ]; then
    printf '    %d problem(s) above need attention. Fix them and run this script again.\n' "$FAILURES" >&2
    exit 1
fi
[ "$WARNINGS" -gt 0 ] && echo "    finished with $WARNINGS warning(s)."
cat <<EOF
    MSXPi is installed in $MSXPIHOME and starts at every boot.
    Plug the Pi into the MSXPi interface (component side facing you), switch the MSX
    on and type  pver  at the MSX-DOS prompt.
    Settings and API keys: $MSXPIHOME/msxpi.ini
EOF

if [ "$DO_REBOOT" -eq 1 ]; then
    echo "    Rebooting in 10 seconds (Ctrl-C to cancel; use --no-reboot to skip this)."
    sleep 10
    as_root reboot
fi
exit 0
