# Konami's F1 Spirit online package

Package format `msxpi-rom-patch` version 2 with the `msxpi-netplay-v1` ABI and image host `mapper-ram` (mapper type `konami-scc`).
Salamander is the model for the bank engine; Soccer and Penguin-kun Wars 2 for the frame and the inputs.

| | |
|---|---|
| Input | `F1SPIRIT.ROM`, Konami's F1 Spirit (MSX), 131072 bytes, Konami SCC MegaROM, CRC-32 `12BFD3A9`, SHA-256 `3b9afd12b29680abb655f05d24e0970954c38e48c5ccb24227d6c710474396a7` |
| Output | a RAM image in mapper segments for PLAYNET (`output.target = "ram-image"`), never a ROM file |
| Game id, roles | `f1spirit`; `P1` (seat 0, the inviter), `P2` (seat 1) |
| Play | the game's own two-player modes (`2PLAYER`, `BATTLE MODE`): player 1 uses the pad where the game reads port 1, player 2 where it reads port 2. Each player uses joystick 1 or the cursor keys and space on their own machine. The menus are player 1's. The password entry (COMMAND, INPUT PASSWORD) is disabled: it scans the whole keyboard. |
| Layout for PLAYNET | transport D000h-D1FFh, stub D200h-D88Eh (engine, 8 KB bank engine, glue), the bank engine's pair map DA00h-DDFFh, game RAM E000h-F0FFh, interrupt handler 4018h |
| Machine | a memory mapper with at least 16 free segments (512 KB recommended: 30 segments hold every pair the game uses) |

No ROM data is included. The player supplies their own dump.

## What was patched

- **Frame.** The game runs its frame logic inside the H.KEYI handler (4018h) and plays its sound there on every interrupt.
  The handler counts the interrupt (`PN_IRQ`), draws the deferred screen update when no frame runs, and goes on at 407Dh. The sound
  driver's output, request queue and sequencer run in `sndTick`, T times a frame (the engine's rule), with banks 13-15 mapped
  once for the frame's ticks (`G_SOUND_BATCH`: `sndBegin`, `sndEnd`).
  The 16-bit countdown (F0F7h) stays per interrupt: the game spins on it inside a frame (a wait at 7E0Dh) and no TICK comes meanwhile.
- **Pace.** In the race a frame starts on every 3rd interrupt (F0FCh). The cartridge's frame fits in 3 periods; ours (exchange,
  sound ticks, bank engine) often ends just past the gate. `isrEnd` (40B0h) then runs the next frame at once instead of waiting
  a whole period (the counter is reset, so the pace never goes above the cartridge's), and adds the interrupts MSX-DOS took
  inside XCHG (TCP/IP) to F0FCh, as the cartridge would have counted them. F0FCh is read only by the gate: only the pace changes.
- **Start.** INIT (40E4h) sets the game's stack (F0F0h) first: PLAYNET starts it on MSX-DOS's stack, which is in the stub's area,
  and RSLREG/ENASLT pushed into the bank engine's tables before the game's own `ld sp` at 4114h.
- **TICK** at 40A4h, before the input reader 4335h.
- **Inputs.** The readers 4367h (port 1) and 4394h (port 2), the title menu's call, and the function keys (43D1h) read the cache.
  Local input: byte 0 the pad, byte 1 F1-F5.
- **Banks.** The 24 bank-register writes (all in bank 0) call the bank engine. The bank selects 441Bh (W1-W3 := n, n+1, n+2),
  4447h (W2, W3 := n, n+1) and 43FEh set W2 and W3 in one switch (`sel3`, `sel2`): no pair of one new and one old bank in between.
  SCC sound (register writes, waveform upload) is removed.
- **Determinism.** Two `ld a,r`. The password keyboard scan is off.

## Files

| File | |
|---|---|
| `src/glue.asm` | the game's side: handler, sound tick, inputs, `ld a,r`, frame catch-up |
| `src/playnet_engine.asm`, `src/mapper_k8.asm` | copied by `rebuild.py` from `software/Client/src/playnet/engine/` |
| `rebuild.py` | assembles the stub, generates the patches, writes `profile.json`; `--rom` checks them against a dump |
| `assets/stub.bin`, `profile.json` | generated |

## Rebuild (developers)

```console
python profiles/f1spirit/rebuild.py --assembler C:\Users\roniv\Dev\bin\sjasmplus.exe --rom C:\path\to\F1SPIRIT.ROM
```

## Rig

`software/Client/tests/soccernet/run_f1spirit.sh` (needs `F1SPIRIT_ROM`): two openMSX nodes, scripted menus, compared frame by frame.
`EXTRA_TCL=f1spirit_prof.tcl` adds where a frame's time goes (exchange, sound ticks, game, interrupts per frame) to `$TRACE.prof`.

Frames 1200-3000 (the race, both players driving), MSXPi link with 50 ms lag, 8% loss, 20 ms jitter: 14.9 fps before these
changes, 18.1 after (the cartridge: 20).
