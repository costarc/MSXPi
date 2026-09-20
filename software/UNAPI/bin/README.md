# Third-party binaries

## RAMHELPR.COM

Konamiman's standalone UNAPI RAM helper installer, version 1.2, from the
MSX-UNAPI distribution. Not built by this project - source is
`tools/ramhelpr.asm` in https://github.com/Konamiman/MSX-UNAPI-specification
and it needs Nestor80 to build, which is why the binary is vendored here.

sha1: eb97f7fd9d4d1991beb0f732c38138cd22f804d1

It is required: ETHUNAPI.COM refuses to install without a RAM helper, because
the driver lives in a mapped RAM segment and the helper is what lets EXTBIO
reach into it. Run it once per boot, before ETHUNAPI:

    RAMHELPR I      install only if no helper is present
    RAMHELPR F      force install even if one is

Running it with no argument prints usage and installs nothing - which looks
like a silent failure if you then run ETHUNAPI and see "No UNAPI RAM helper
installed".

If you would rather not carry someone else's binary in this repo, delete it and
point build.sh at your own copy with the RAMHELPR environment variable.

## Konamiman's UNAPI client tools

`HOST.COM`, `TCPCON.COM`, `SNTP.COM`, `GETURL.COM`, `HGET.COM`, `TCPIP.COM`,
`FTP.COM` - prebuilt, from Konamiman's MSX-UNAPI distribution by way of
`Multicore/Computers/SM-X/sdcreate/network/UNAPI/`.  Not built here.

Vendored because they are the acceptance tools for the TCP/IP layer and
because that Multicore tree is not present on every machine that has this repo
- notably the Pi.  They are also what makes each layer testable in isolation,
which matters more than it sounds: telnet exercises DNS, TCP and a terminal
emulator at once, so when it fails it says nothing useful.  Use them in
increasing order of what they involve:

    HOST <name>     resolve a name           - DNS only
    TCPCON          open a TCP connection    - TCP without a terminal
    SNTP            fetch the time           - a complete UDP round trip
    GETURL <url>    fetch a URL              - DNS + TCP + HTTP
    TELNET <host>   the full stack

## INLSTOCK.COM

InterNestor Lite 2.3 built from the sources in ../inl with the
RAM-implementation patch REVERSED - i.e. genuinely stock, which is what the ROM
driver was designed for.  26037 bytes, against the patched INL.COM's 26048.

Worth keeping both: the patched build reports "InterNestor Lite is not
installed" for `INL S` even when it is working perfectly, and the stock one
does not.  That defect was blamed on this driver and on the machine for a long
time before the patch turned out to be the cause.
