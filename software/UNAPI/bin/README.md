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
