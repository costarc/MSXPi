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
# MSXPi Ethernet UNAPI - Pi-side network setup (WiFi host)
# =============================================================================
#   sudo ./msxpi-tcpip-setup.sh          bring it up
#   sudo ./msxpi-tcpip-setup.sh down     tear it down
#
# Gives the MSX a route to the internet through a Pi that is on WiFi.
#
# WHY NOT A BRIDGE
#
# Bridging the TAP device to the uplink is the obvious approach and is what
# PiSCSI does on wired hosts. It CANNOT work on WiFi: 802.11 access points
# will not forward frames whose source MAC is not the associated station's, so
# a bridged MSX transmits happily and never receives a single reply. This is
# not a Linux limitation to be configured around - it is how WiFi association
# works. Hence an isolated subnet plus NAT.
#
# The MSX ends up behind NAT: it can reach the internet, but nothing on the LAN
# can initiate a connection to it. For telnetting out to a BBS that is exactly
# what is wanted.
# =============================================================================
set -eu

TAP="${TAP:-msxpi0}"
TAP_IP="${TAP_IP:-192.168.99.1}"
MSX_IP="${MSX_IP:-192.168.99.2}"
PREFIX="${PREFIX:-24}"
# The link runs at roughly 18 KB/s, so a full 1500-byte frame is ~80 ms. A
# smaller MTU makes TCP negotiate a smaller MSS, which keeps individual
# transfers short and the connection feeling responsive. 576 is the IP minimum
# every implementation must support. Raise it later if throughput matters more
# than latency.
MTU="${MTU:-576}"
# The user the server runs as: the TAP is created owned by them, so
# msxpi-server.py can open it WITHOUT running as root.
TAP_USER="${TAP_USER:-pi}"

# wait up to 60s for a default route (network to come up)
ROOT_LOG="/var/log/msxpi-tcpip-setup.log"
WAIT_SECS=60
count=0
while [ $count -lt $WAIT_SECS ]; do
    UPLINK="$(ip route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    if [ -n "$UPLINK" ]; then
        break
    fi
    echo "$(date) waiting for default route..." >> "$ROOT_LOG"
    sleep 1
    count=$((count+1))
done

if [ -z "$UPLINK" ]; then
    echo "$(date) no default route after ${WAIT_SECS}s - aborting" >> "$ROOT_LOG"
    exit 1
fi
echo "$(date) uplink: $UPLINK" >> "$ROOT_LOG"

# Uplink: whichever interface currently carries the default route.
#
# Read the field AFTER "dev", not a fixed position.  "default via 1.2.3.4 dev
# wlan0 ..." puts the interface in $5, but a route with no gateway reads
# "default dev wlan0 scope link" - and then $5 is the word "link", which then
# gets used as an interface name in every iptables rule below.  They apply
# cleanly against a nonexistent interface, so the only symptom is that nothing
# routes.
UPLINK="${UPLINK:-$(ip route show default | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')}"

if [ "${1:-up}" = "down" ]; then
    iptables -t nat -D POSTROUTING -o "$UPLINK" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$TAP" -o "$UPLINK" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$UPLINK" -o "$TAP" -m state \
             --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    ip link set "$TAP" down 2>/dev/null || true
    ip tuntap del dev "$TAP" mode tap 2>/dev/null || true
    echo "torn down"
    exit 0
fi

[ -n "$UPLINK" ] || { echo "no default route - is the Pi on the network?"; exit 1; }
echo "uplink: $UPLINK"

# --- The TAP device ---------------------------------------------------------
# Created PERSISTENT and owned by $TAP_USER, deliberately. A TAP opened by the
# server itself disappears when the process exits, so it could never be
# configured beforehand - and creating it here means the server does not need
# CAP_NET_ADMIN or root. Without this, msxpi_eth.make_link() silently falls
# back to MockLink, which answers every opcode correctly and carries no
# traffic whatsoever - the most confusing possible failure.
#
# The OWNER matters as much as the existence, and this used to check only
# existence. A TAP left behind by a server that once ran as root belongs to
# root, and then TUNSETIFF from the pi-owned server fails with EPERM - the
# device sits there UP but never RUNNING, nothing attaches to it, and the log
# says "TAP unavailable (Operation not permitted) - falling back to MockLink".
# So if the owner is not $TAP_USER, replace the device rather than keeping it.
tap_owner_uid() {
    # "msxpi0: tap persist user 1000" - the field after "user", empty when the
    # device has no owner at all (created by root without `user`).
    ip tuntap show 2>/dev/null \
        | awk -v dev="$TAP:" '$1 == dev {for (i = 1; i < NF; i++)
                                            if ($i == "user") { print $(i+1); exit }}'
}

want_uid="$(id -u "$TAP_USER" 2>/dev/null || echo "")"
if ip link show "$TAP" >/dev/null 2>&1; then
    have_uid="$(tap_owner_uid)"
    if [ -n "$want_uid" ] && [ "$have_uid" != "$want_uid" ] \
       && [ "$have_uid" != "$TAP_USER" ]; then
        echo "$TAP is owned by \"${have_uid:-root}\", not $TAP_USER - recreating it"
        echo "$(date) $TAP owner ${have_uid:-root} != $TAP_USER - recreating" \
            >> "$ROOT_LOG"
        ip link set "$TAP" down 2>/dev/null || true
        ip tuntap del dev "$TAP" mode tap 2>/dev/null || true
    fi
fi

if ! ip link show "$TAP" >/dev/null 2>&1; then
    ip tuntap add dev "$TAP" mode tap user "$TAP_USER"
    echo "created $TAP (owner $TAP_USER)"
fi

ip addr flush dev "$TAP" 2>/dev/null || true
# "broadcast +" makes the kernel derive the broadcast address from the
# prefix.  Without it the interface comes up with broadcast 0.0.0.0,
# which is what ifconfig showed on the Pi - not what you want on a link
# whose whole first job is to carry an ARP broadcast to the MSX.
ip addr add "$TAP_IP/$PREFIX" broadcast + dev "$TAP"
ip link set "$TAP" mtu "$MTU" up
echo "$TAP up: $TAP_IP/$PREFIX mtu $MTU"

# --- Routing and NAT --------------------------------------------------------
sysctl -q -w net.ipv4.ip_forward=1

# Idempotent: check before adding, so re-running does not stack duplicate rules.
iptables -t nat -C POSTROUTING -o "$UPLINK" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o "$UPLINK" -j MASQUERADE
iptables -C FORWARD -i "$TAP" -o "$UPLINK" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$TAP" -o "$UPLINK" -j ACCEPT
iptables -C FORWARD -i "$UPLINK" -o "$TAP" -m state \
         --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$UPLINK" -o "$TAP" -m state \
             --state RELATED,ESTABLISHED -j ACCEPT
echo "NAT: $TAP -> $UPLINK"

DNS="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null)"
[ -n "$DNS" ] || DNS="1.1.1.1"

cat <<EOF

Done. This is NOT persistent across reboots - re-run it, or wire it into
systemd once you are happy with the values.

Now restart msxpi-server.py as $TAP_USER and check it prints

    eth: TAP device $TAP up

If it says "TAP unavailable ... falling back to MockLink" then it cannot open
the device: confirm the server runs as $TAP_USER and that $TAP still exists.

On the MSX, configure InterNestor Lite (there is no DHCP server on this
subnet, so the addresses are set by hand):

    inl ip d 0
    inl ip l $MSX_IP
    inl ip m 255.255.255.0
    inl ip g $TAP_IP
    inl ip p $DNS

or put the same lines, minus the leading "inl", in INL.CFG next to INL.COM and
they are applied at install time. Check with "inl s", then:

    ping $TAP_IP        from the MSX - proves the link and NAT box
    telnet bbs.hispamsx.org

If ping to $TAP_IP works but names do not resolve, DNS is the problem, not the
driver: try an IP address directly first.
EOF
