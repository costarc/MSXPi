# Revision 2 hardware results

The timed PCOPY runs are separate from the failed cross-controller COPY tests;
no timings were supplied for those failures. The following uses the explicitly
labeled native-off/native-on pairs. `00:20:42` is interpreted as 20.42 seconds.

| Path (256 KiB) | Native off | Native on | Throughput increase from native GPIO |
|---|---:|---:|---:|
| Pi → MFR SD | 42.55 s | 33.50 s | 27.0% |
| MFR SD → Pi | 26.14 s | 20.42 s | 28.0% |
| Pi → MSXPi disk | 64.96 s | 50.50 s | 28.6% |
| MSXPi disk → Pi | 66.85 s | 52.50 s | 27.3% |

Against revision 1's native-on results, download improves from 67.04 to 50.50
seconds (+32.8% throughput, 24.7% less elapsed time); upload improves from
106.03 to 52.50 seconds (+102.0% throughput, 50.5% less elapsed time). Upload
also changed from 16 KiB to 8 KiB blocks, so that gain is a combined result,
not a measurement of the driver alone. These are individual reported runs,
not medians or controlled statistical estimates.

## What the profiles show

Native counters are cumulative. The values below are obtained by subtracting
successive byte-weighted totals, grouped by the active command and payload
size. Rounded counters make them approximate.

| Stage | Engine µs/byte | Waiting for MSX µs/byte |
|---|---:|---:|
| PCOPY download payload (8192 bytes) | 108.11 | 94.74 |
| Disk writes during download (512 bytes) | 52.86 | 38.82 |
| Disk reads during upload (512 bytes, includes metadata) | 109.65 | 96.06 |
| PCOPY upload payload (8192 bytes) | 60.18 | 46.17 |

The disk-write payload cost fell from roughly 121.52 to 52.86 µs/byte compared
with the earlier profile. The C receive/transmit costs remain approximately
108/60 µs per byte. This supports the conclusion that the disk path improved,
while MSX-side receive pacing remains a significant cost. The old 16 KiB
upload's page-1 slowdown is absent in this 8 KiB run; this alone does not isolate
the block-size effect from the new driver behavior.

The final two additional timing groups are both labeled native=0 and include
an `A:ROUND.ROM` destination spelling. They are retained as additional runs;
they have not been silently relabeled as native=1 or combined into the pairs
above. Hash results were not included in this attachment.

## Separate correctness issue

Ordinary COPY works between MSXPi drives. Cross-controller COPY involving MFR
fails in both directions: a DOS disk error after writing to MSXPi, and a file
allocation error when copying back to MFR. A full file size in DIR does not
establish byte integrity. A buffer-isolation test build (revision 2.1) passed general disk and separate-
kernel integrity tests, but the exact MFR failure has not been reproduced or
confirmed fixed. These errors were not used in any timing calculation above.
