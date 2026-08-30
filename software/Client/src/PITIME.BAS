10 ' ---------------------------------------------------------------
20 ' PITIME.BAS - MSXPi low-level timing probe
30 ' Measures what the Z80 ACTUALLY costs per poll iteration on this
40 ' machine, so the msxpi_bios.asm optimisation work is based on
50 ' measurement instead of a T-state count off a datasheet.
60 '
70 ' Needs NO Raspberry Pi, NO server and NO transfer. It only reads
80 ' port &H56, so it cannot be confounded by the protocol.
90 '
100 ' R1  empty loop                      26 T expected
110 ' R2  + IN A,($56)                    37 T expected
120 ' R3  + CHKPIRDY instruction mix        88 T expected
125 '     (same instructions, branches omitted so the loop
126 '      stays unconditional - real CHKPIRDY is 93 T)
130 '
140 ' R2-R1 isolates the cost of a cartridge-slot IN.
150 ' R3-R2 isolates the ESC keyboard scan.
160 ' ---------------------------------------------------------------
170 CLEAR 200,&HD000
180 SCREEN 0:WIDTH 40:KEY OFF
190 ' Set HZ=50 on a PAL machine, 60 on NTSC.
200 HZ=60
210 CL=3579545#
220 NI=65536!
230 PRINT "MSXPi low-level timing probe"
240 PRINT "65536 iterations per test,";HZ;"Hz"
245 PRINT "R3 writes port &HAA (as CHKPIRDY does):"
246 PRINT "expect a cassette relay click. Harmless."
250 PRINT
260 ' --- load the three probe routines ---
270 FOR R=0 TO 2
280  A=&HD000+R*32
290  READ N
300  FOR I=0 TO N-1:READ B:POKE A+I,B:NEXT I
310 NEXT R
320 PRINT "test  jiffies      us/it    T/it  exp"
330 PRINT "------------------------------------"
340 FOR R=0 TO 2
350  READ D$,ET
360  DEFUSR=&HD000+R*32
370  T=TIME
380  X=USR(0)
390  E=TIME-T
400  US=E/HZ*1000000!/NI
410  TS=US*CL/1000000!
420  PRINT D$;
430  PRINT USING "######";E;
440  PRINT USING "#####.##";US;
450  PRINT USING "######.#";TS;
460  PRINT USING "#####";ET
470  J(R)=E:V(R)=TS
480 NEXT R
490 PRINT
500 PRINT "IN A,($56)  =";
510 PRINT USING "###.# T";V(1)-V(0);
520 PRINT "  (expect 11)"
530 PRINT "ESC scan    =";
540 PRINT USING "###.# T";V(2)-V(1);
550 PRINT "  (expect 51)"
560 PRINT
570 PRINT "If T/it tracks 'exp', the T-state model is"
580 PRINT "sound and the 975us/byte is elsewhere."
590 PRINT "If T/it is much higher, this machine is"
600 PRINT "slower than nominal and that alone"
610 PRINT "explains the transfer rate."
620 END
630 ' --- R1: empty loop ---
640 DATA 9
650 DATA 1,0,0,11,120,177,32,251,201
660 ' --- R2: + IN A,($56) ---
670 DATA 11
680 DATA 1,0,0,219,86,11,120,177,32,249,201
690 ' --- R3: + full CHKPIRDY body ---
700 DATA 23
710 DATA 1,0,0,62,7,211,170,219,169,203,87
720 DATA 219,86,254,0,254,2,11,120,177,32,237,201
730 ' --- labels and expected T-states ---
740 DATA "R1  ",26
750 DATA "R2  ",37
760 DATA "R3  ",88
