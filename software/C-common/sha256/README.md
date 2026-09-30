# SHA-256 for MSX (Z80)

Standalone SHA-256 for SDCC / Fusion-C programs on MSX. The block function
is hand-written Z80 assembly; it is the one PChess uses for its IRC position
digests (`Client/src/pchess_sha.c`), about 7x faster than SDCC's C.

| file | |
|---|---|
| `sha256.h` | API: `sha256_init/update/final`, one-shot `sha256()`, `sha256_hex()` |
| `sha256.c` | implementation; Z80 assembly under SDCC, portable C elsewhere |
| `sha256t.c` | test program: FIPS 180-2 vectors, a streamed message, timing |

```c
#include "sha256.h"
uint8_t d[32]; char hex[65];
sha256("abc", 3, d);
sha256_hex(d, hex);          /* ba7816bf... */
```

Messages of any length (the length counter is 64-bit); `sha256_update()`
takes up to 65535 bytes per call and can be called any number of times.
Not reentrant: one hash at a time, never from an interrupt handler.

On a 3.58 MHz Z80 a 64-byte block takes about 0.2 s (a message under 56
bytes is one block). Size: about 1 KB of code plus 300 bytes of tables and
work areas.

## Build the test

From `software`, as for any client program, but with this directory:

```bat
sdcc --code-loc 0x106 --data-loc 0 -mz80 --no-std-crt0 --opt-code-size fusion.lib ^
  -L ..\..\..\MSX\MSX-C\WorkingFolder\fusion-c\lib ^
  ..\..\..\MSX\MSX-C\WorkingFolder\fusion-c\include\crt0_msxdos.rel C-common\sha256\sha256t.c
hex2bin -e com sha256t.ihx
```

`SHA256T` prints PASS for each vector and the time for ten one-block
hashes. On a PC, `gcc sha256t.c -o sha256t` runs the same checks against
the C version.
