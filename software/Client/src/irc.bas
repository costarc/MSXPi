10 BLOAD"msxpiext.bin",r:CLS:CH$="#openmsx":NK$="* msxpi *"
20 PRINT "MSXPi IRC Client"
29 REM Define FN Keys and Constants
30 BUF=&HB000:gosub 10000:gosub 30000
40 FOR I=1 TO 10: KEY(I) STOP:NEXT I
50 INPUT "Nick name:";NI$
60 if NI$="" then NI$="none"
70 INPUT "Channel name:";CH$
1000 PRINT"Connecting to irc server.."
1100 COM$="IRC CONN "+NI$:GOSUB 50000
1120 if RC<>E0 AND RC<>EB THEN END
1200 if bs>254 then PR=1:gosub 52030 else print rc$:PRINT
1210 COM$="IRC JOIN "+CH$:GOSUB 50000
1220 IF RC<>E0 AND RC<>EB THEN END
1230 COM$="IRC GETRSP":GOSUB 50000
1260 if bs>254 then PR=1:gosub 52030 else print rc$:PRINT
1300 ON KEY GOSUB 11000,12000,15000
1310 PRINT
1400 KEY (1) ON:KEY (2) ON:KEY (3) ON
1410 TIME=0
1450 IF TIME < 150 THEN GOTO 1450
1455 KEY (1) OFF:KEY (2) OFF:KEY (3) Off
1460 COM$="IRC READ":GOSUB 50000
1470 COM$="IRC GETRSP":GOSUB 50000:if RC=EB then goto 1400
1480 if bs>254 then gosub 52030 else print RC$
1500 goto 1400
6999 REM Send command in COM$ to RPi
7000 COM$="IRC NAMES":GOSUB 50000:CALL MSXPISEND("B000")
7050 RETURN
7999 REM Read buffer as string and store in RC$
10000 KEY 1,"F1-Talk"
10010 KEY 2,"F2-Join"
10020 KEY 3,"F3-Bye"
10030 KEY 4,""
10040 KEY 5,""
10050 KEY 6,""
10060 KEY 7,""
10070 KEY 8,""
10080 KEY 9,""
10090 KEY 10,""
10100 RETURN
11000 m$="":print "talk:|";chr$(8);:p=4:time=0:GOSUB 20000
11010 if m$="" then ?:return
11020 ? NK$+" --> ";M$
11100 COM$="IRC "+m$:gosub50000
11120 return
12000 m$="":print "Channel:|";chr$(8);:p=7:GOSUB 20000
12010 if m$="" then ?:return
12020 COM$="IRC JOIN "+M$:GOSUB 50000
12030 IF RC<>E0 AND RC<>EB THEN END
12040 COM$="IRC GETRSP":GOSUB 50000
12050 if bs>254 then PR=1:gosub 52030 else print rc$:PRINT""
12060 return
13000 return
14000 return
15000 COM$="IRC QUIT":gosub50000
15010 print "Bye":END
20000 C$=inkey$:if C$<>"" then goto 20070
20020 if time<50 then print"/";chr$(8);:goto20070
20030 if time<100 then print"-";chr$(8);:goto20070
20040 if time<150 then print"\";chr$(8);:goto20070
20050 if time<200 then print;"|";chr$(8);:goto20070 else time=0
20070 if C$=CHR$(13) then gosub 20100:return
20080 if (C$=CHR$(8) and len(m$)>0) then m$=left$(m$,len(m$)-1):print " ";chr$(8);chr$(8);
20090 if C$>=chr$(32) then m$=m$+C$:print C$;:goto20000 else goto20000
20100 for i = 0 to len(m$)+p:print " ";chr$(8);chr$(8);" ";chr$(8);:next i:return
30000 REM
30110 E0 = &HE0
30120 E1 = &HE1
30130 E2 = &HE2
30140 E3 = &HE3
30150 E4 = &HE4
30160 E5 = &HE5
30170 E6 = &HE6
30180 E7 = &HE7
30190 E8 = &HE8
30200 E9 = &HE9
30210 EA = &HEA
30220 EB = &HEB
30230 EC = &HEC
30240 ED = &HED
30250 EF = &HEF
30260 RETURN
49990 REM Send COMMAND COM$ TO RPi
49991 REM Verify transfer RC
49992 REM Wait command execution, and get RC back
50000 poke(buf),0
50010 POKE(BUF+1),int(LEN(COM$) MOD 256)
50020 POKE(BUF+2),int(LEN(COM$) / 256)
50100 FOR I = 1 TO LEN(COM$)
50110 POKE(BUF+I+2),asc(MID$(COM$,I,1))
50120 NEXT I
50130 GOSUB 53000:CALL MSXPISEND("B000"):RC=PEEK(BUF):if RC<>E0 THEN RETURN
50140 GOSUB 53000:out(&h5a),&hA0:RC=INP(&H5A):IF RC=E9 THEN GOTO 50200
50150 IF RC<>E0 AND RC<>E7 AND RC<>EB THEN GOTO 50140
50160 GOTO 50300
50200 GOSUB 53000:out(&h5a),&hA0:RC=INP(&H5A):IF (RC<>E0 AND RC<>E7 AND RC<>EB AND RC<>EC) THEN GOTO 50200
50300 IF RC<>E0 AND RC<>E7 THEN RETURN
50310 CALL MSXPIRECV("B000"):GOSUB 52000
50320 RETURN
52000 RC$="":RC=PEEK(BUF):PR=1
52010 BS=PEEK(BUF+1)+256*PEEK(BUF+2)
52020 if BS=0 OR BS>254 THEN RETURN
52030 FOR I = 1 TO BS
52040 IF PR=0 THEN RC$=RC$+CHR$(PEEK(BUF+I+2)) ELSE ? CHR$(PEEK(BUF+I+2));
52050 NEXT I
52060 PR=0:RETURN
53000 IF INP(&H56)=1 THEN GOTO53000
53010 RETURN


