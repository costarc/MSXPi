Pick the server that matches the ROM you are running. The MSX side and the
server share one protocol, and a mismatched pair fails in confusing ways
rather than refusing to talk, so the historical servers are kept here named
after the sha1 of the ROM they belong to - the same sha1 openMSX uses to find
the ROM file (`openMSX/share/systemroms/extensions/msxpidos.<sha1>.rom`).

| ROM sha1 | Server | Version |
|---|---|---|
| `c429077a5f58b006125247a67783ea4ea6fb7389` | `msxpi-server.c429077a5f58b006125247a67783ea4ea6fb7389.py` | 1.2 - what openMSX `Contrib/README.msxpi` points at |
| `3cfffa59afef160439085a8a496953edcaeb0662` | `msxpi-server.3cfffa59afef160439085a8a496953edcaeb0662.py` | 1.5 (build 20260808.020) |
| current | `msxpi-server.py` | latest release |

The 1.5 pairing is worth a note: that ROM stayed current until 30 Aug 2026,
by which time the server had already moved to 1.6 - the CPLD /WAIT flow
control and the SPI engine rewrite landed before the ROM was rebuilt. So the
matching server is the LAST one still at version 1.5, not the last one shipped
alongside that ROM. The file above is that one (unchanged throughout the ROM's
life, so the pairing is unambiguous).
