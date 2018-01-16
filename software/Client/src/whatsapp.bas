1 clear 500,&hAFFF:BUF=&HB000
2 cc$="":ph$="":pw$=""
10 CLS:CH$="MSXPiTest":NK$="* msxpi *"
20 PRINT "MSXPi WhatsUp Client"
21 print "===================="
29 REM Define FN Keys and Constants
30 BUF=&HB000:gosub 10000:gosub 30000
40 FOR I=1 TO 10: KEY(I) STOP:NEXT I
42 if pw$="" then goto 16000 else ?"Updating login details on MSXPi...":gosub 16900
50 gosub 14000
60 PRINT "WhatsUp Ready"
1300 ON KEY GOSUB 11000,12000,13000,14000,15000,16000
1310 PRINT
1400 KEY (1) ON:KEY (2) ON:KEY (3) ON:KEY (4) ON:KEY (5) ON:KEY (6) ON
1410 TIME=0
1450 IF TIME < 300 THEN GOTO 1450
1455 KEY (1) OFF:KEY (2) OFF:KEY (3) Off:KEY (4) Off:KEY (5) Off:KEY (6) OFF
1460 COM$="WUP READ":GOSUB 50000
1470 if bs > 0 then print
1490 GOTO 1400
10000 KEY 1,"F1-Talk"
10010 KEY 2,"F2-Channel"
10020 KEY 3,"F3-Bye"
10030 KEY 4,"Connect"
10040 KEY 5,"Disconnect"
10050 KEY 6,"Register"
10060 KEY 7,""
10070 KEY 8,""
10080 KEY 9,""
10090 KEY 10,""
10100 RETURN
11000 KEY (1) OFF:KEY (2) OFF:KEY (3) Off:KEY (4) Off:KEY (5) Off:KEY (6) OFF
11005 m$="":print CH$;":|";chr$(8);:time=0:GOSUB 20000
11010 if m$="" then ?:return
11020 ? NK$+" --> ";M$
11100 COM$="WUP "+ch$+" "+m$:gosub50000:print ""
11120 RETURN
12000 KEY (1) OFF:KEY (2) OFF:KEY (3) Off:KEY (4) Off:KEY (5) Off:KEY (6) OFF
12005 CB$=CH$
12010 CH$="Phone or Group"
12020 m$="":print CH$;":|";chr$(8);:time=0:GOSUB 20000
12030 if m$="" then ch$=cb$
12040 ch$=m$
12050 return
13000 KEY (1) OFF:KEY (2) OFF:KEY (3) Off:KEY (4) Off:KEY (5) Off:KEY (6) OFF
13010 print "Bye":END
14000 KEY (1) OFF:KEY (2) OFF:KEY (3) Off:KEY (4) Off:KEY (5) Off:KEY (6) OFF
14005 PRINT"Starting WhatsUp service..."
14010 COM$="WUP CONN":GOSUB 50000
14020 if RC<>E0 AND RC<>EB THEN END
14030 if bs>254 then PR=1:gosub 52030 else print rc$:PRINT
14040 return
15000 KEY (1) OFF:KEY (2) OFF:KEY (3) Off:KEY (4) Off:KEY (5) Off:KEY (6) OFF
15005 PRINT"Shutting down WhatsUp service..."
15010 COM$="WUP SHUT":GOSUB 50000
15020 if RC<>E0 AND RC<>EB THEN END
15030 if bs>254 then PR=1:gosub 52030 else print rc$:PRINT
15040 return
16000 rem
16010 print "Registration Process"
16020 print "You will need some codes, which can be found here:"
16030 print "http://www.mcc-mnc.com/"
16035 ?"The codes you need are:":?"country code(cc),mcc,mnc"
16040 print: print "This process will generate a SMS code to register your phone on WhatsUp.";:?"You cannot use your existing WhatsUp number.";
16042 ? "Have your phone ON and ready to receive the SMS"
16100 input "Country code:";cc$
16110 input "MCC code:";mcc$
16115 input "MNC code:";mnc$
16120 input "Phone number (include region code without the zero):";ph$
16130 print "Is this your international phone number? ";cc$;ph$
16140 input "(Y/N)";yn$
16150 if yn$ <> "Y" and yn$ <> "y" then print "Operation calcelled. Start over.":end
16160 com$="prun /usr/bin/python /home/pi/yowsup/yowsup-cli registration --requestcode sms --phone "+cc$+ph$+" --cc "+cc$+" --mcc "+mcc$+" --mnc "+mnc$
16170 print "Command for MSXPi:";com$
16180 GOSUB 50000:PR=1:gosub 52030
16190 if RC<>E0 AND RC<>EB THEN ?"Error. Registration request failed":END
16200 print "You should receive a SMS with a code"
16210 input "Type the code here:";cd$
16220 com$="WUPreg /usr/bin/python /home/pi/yowsup/yowsup-cli registration --register "+cd$+" --phone "+cc$+ph$+" --cc "+cc$
16230 print "Command for MSXPi:";com$
16240 gosub 50000:PR=1:gosub 52030
16500 REM Now search for the password in the data returned by MSXPi
16510 RC=PEEK(BUF):IF RC<>E0 THEN ?"Registration failed":end
16520 sz=peek(buf+1)+256*peek(buf+2):?:?"Wait... locating your credentials..."
16530 for i=buf+3 to buf+3+sz
16540 if chr$(peek(i))="p" and  chr$(peek(i+1))="w" and peek(i+2) = 34 and  chr$(peek(i+3)) = ":" then N=I+4:goto 16600
16545 if chr$(peek(i))="p" and  chr$(peek(i+1))="w" and chr$(peek(i+2)) = ":" then N=I+3:goto 16600
16550 nexti:?"Error. Did not find the registration confirmation in the response"
16560 end
16600 REM Found start of the password
16610 REM
16630 P$=""
16640 for m = N+1 to N+35
16650 P=PEEK(M):IF P=34 or P=32  or P=10 or P=13 THEN GOTO 16700
16660 PW$=PW$+CHR$(P)
16670 NEXT M:?"Error. Did not find the registration confirmation in the response"
16680 END
16700 cls:? "Your login details:"
16710 ? "Login:";cc$;ph$
16720 ? "Password:";pw$
16725 ? "Updating login details on MSXPi...":gosub 16900
16770 ? "Registration complete."
16780 ? "Move cursor to program lines displayed below and press ENTER.";
16790 ? "Next time you run this program, your details will be already configured."
16815 ? "2 cc$=";chr$(34);CC$;chr$(34);":ph$=";chr$(34);ph$;chr$(34);":pw$=";chr$(34);pw$;chr$(34)
16820 ? "save ";chr$(34);"wup.bas";chr$(34);",a"
16830 ? "run"
16840 end
16900 com$="pset set WUPPH "CC$+PH$:GOSUB50000:? "... ";
16910 COM$="pset set WUPPW "+PW$:GOSUB50000
16920 return
20000 C$=inkey$:if C$<>"" then goto 20070
20020 if time<50 then print"/";chr$(8);:goto20070
20030 if time<100 then print"-";chr$(8);:goto20070
20040 if time<150 then print"\";chr$(8);:goto20070
20050 if time<200 then print;"|";chr$(8);:goto20070 else time=0
20070 if C$=CHR$(13) then gosub 20100:return
20080 if (C$=CHR$(8) and len(m$)>0) then m$=left$(m$,len(m$)-1):print " ";chr$(8);chr$(8);
20090 if C$>=chr$(32) then m$=m$+C$:print C$;:goto20000 else goto20000
20100 for i = 0 to len(m$)+len(ch$):print " ";chr$(8);chr$(8);" ";chr$(8);:next i:return
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
50000 bs=0:poke(buf),0
50010 POKE(BUF+1),int(LEN(COM$) MOD 256)
50020 POKE(BUF+2),int(LEN(COM$) / 256)
50100 FOR I = 1 TO LEN(COM$)
50110 POKE(BUF+I+2),asc(MID$(COM$,I,1))
50120 NEXT I
50130 GOSUB 53000:CALL MSXPISEND("B000"):RC=PEEK(BUF):if RC<>E0 THEN RETURN
50140 GOSUB 53000:out(&h5a),&hA0:GOSUB 53000:RC=INP(&H5A):IF RC=E9 THEN GOTO 50200
50150 IF RC<>E0 AND RC<>E7 AND RC<>EB THEN GOTO 50140
50160 GOTO 50300
50200 GOSUB 53000:out(&h5a),&hA0:GOSUB 53000:RC=INP(&H5A):IF (RC<>E0 AND RC<>E7 AND RC<>EB AND RC<>EC) THEN GOTO 50200
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
