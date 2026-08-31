# Pi-side network setup

`msxpi-tcpip-setup.sh` gives the MSX a route to the internet through a Pi that is
on **WiFi**, and `INL.CFG` is the matching InterNestor Lite configuration.

Run the script with `sudo` on the Pi, then copy `INL.CFG` onto the MSX disk
beside `INL.COM` - InterNestor reads it at install time, so the addresses are
applied automatically by `INL I`.

## Why not a bridge

On a wired host the natural answer is to bridge the TAP device to the uplink,
which is what PiSCSI does. **That cannot work over WiFi.** An access point will
not forward frames whose source MAC is not the associated station's, so a
bridged MSX transmits fine and never receives a reply. It is a property of
802.11 association, not something to configure around - PiSCSI carries a
separate `proxyarp` mode for exactly this reason.

So the MSX gets its own subnet on `msxpi0` and the Pi NATs it out. The MSX can
reach the internet; nothing on the LAN can reach the MSX. For telnetting out to
a BBS that is the right trade.

## The TAP is created here, not by the server

Deliberately, and for two reasons:

- A TAP opened by the server exists only while that process holds the file
  descriptor, so it could never be given an address beforehand.
- Created here as persistent and owned by the server's user, the server does
  **not** need root or `CAP_NET_ADMIN`.

Without it, `msxpi_eth.make_link()` falls back to `MockLink`, which answers
every opcode perfectly and carries no traffic at all - so every test passes and
nothing works. Check for `eth: TAP device msxpi0 up` in the server output.

## MTU

Set to 576 by default. The link runs at roughly 18 KB/s, so a 1500-byte frame
takes ~80 ms; a smaller MTU makes TCP negotiate a smaller MSS and keeps the
connection responsive. Raise it if bulk throughput matters more than latency.

## Order of operations

1. `sudo ./msxpi-tcpip-setup.sh` on the Pi
2. restart `msxpi-server.py` as the TAP's owner, confirm `TAP device msxpi0 up`
3. on the MSX: `MSR I`, `ETHUNAPI`, `INL I`
4. `inl s` to confirm the addresses
5. **From the Pi**, `ping 192.168.99.2` - see below
6. `telnet bbs.hispamsx.org`

## Testing the link before telnet

INL.COM has **no outgoing ping command** - it only has a switch for whether to
*reply* to incoming ones, and replying is on by default. So the link test runs
the other way round:

    ping 192.168.99.2        # from the Pi, to the MSX

That exercises the whole path - Pi, TAP, msxpi-server, the opcode protocol, the
driver, InterNestor Lite, and back - without needing anything typed on the MSX.
If it replies, the transport works and anything remaining is IP configuration
or DNS.

Other stock clients worth trying before telnet, all in
`Dev/github/Multicore/.../SM-X/sdcreate/network/UNAPI/`:

    HOST.COM      resolve a name - isolates DNS from everything else
    TCPCON.COM    open a TCP connection - isolates TCP from telnet's UI

Nothing here survives a reboot; wire it into systemd once the values are settled.
