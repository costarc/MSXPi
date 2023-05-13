50 ' DO NOT CHANGE FROM HERE TO LINE 99
55 ' YOUR CODE SHOULD START AT LINE 101
60 GOTO 15000
65 ' DO NOT DELETE OR CHANGE THIS LINE NUMBER
70 onerrorgoto90
75 call msxpiver
80 goto 100
90 bload "msxpiext.bin",r
100 ' DO NOT DELETE THIS LINE
110 GOSUB 6000:GOSUB6100 ' Define FunctIon Keys and RC mappings
115 CH$="":NK$="* msxpi *"
120 PRINT "MSXPi IRC Client"
122 REM Define FN Keys and Constants
122 FOR I=1 TO 10: KEY(I) STOP:NEXT I
124 INPUT "Nick name:";NI$: IF NI$<>"" THEN NK$=NI$
126 IF NI$="" THEN NI$="none"
128 CLS:PRINT"Connecting to irc server..."
130 ' Connect to the IRC Server: Set the inputs / Call SENDCOMMAND
132 A=1:B=BF:C$="IRC":D$="CONN "+NI$:GOSUB10000
134 IF RC = -1 THEN PRINT"Exiting in /CONN command with error:";RC:END       ' Error - terminate the program
136 '
138 ' Joint IRC Channel: Set the inputs / Call SENDCOMMAND
140 A=1:B=BF:C$="IRC":D$="JOIN "+CH$:GOSUB10000
142 IF RC = -1 THEN PRINT"Exiting in /JOIN command with error:";RC:END       ' Error - terminate the program'
199 '
200 ' Main Loop - Listen Key presses and execute user commands
210 ON KEY GOSUB 2000,3000,4000
220 PRINT
300 KEY (1) ON:KEY (2) ON:KEY (3) ON
310 TIME=0
320 IF TIME < 150 THEN GOTO 320
330 KEY (1) OFF:KEY (2) OFF:KEY (3) OFF
340 ' Read new messages in the IRC Channel: Set the inputs / Call SENDCOMMAND
350 if CH$=""THENGOTO358
355 A=2:B=BF:C$="IRC":D$="READ":GOSUB10000:IF RC<>&HEB THENA=1:B=BF:GOSUB11000:PRINT
357 GOTO300
358 A=1:B=BF:C$="IRC":D$="READ":GOSUB10000:GOTO300
999 '
1000 ' Send a command to IRC: Set the inputs / Call SENDCOMMAND
1010 A=1:B=BF:C$="IRC":D$="NAMES "+$CH:GOSUB10000
1020 IF RC = -1 THEN PRINT"Exiting in /NAMES command with error:";RC:END       ' Error - terminate the program
1030 RETURN
1999 '
2000 ' Send a message to the IRC Channel: Set the inputs / Call SENDCOMMAND
2010 M$="":PRINT "talk:|";CHR$(8);:P=4:TIME=0:GOSUB5000   ' Read user message from kbd
2020 IF M$="" THEN PRINT:RETURN
2030 PRINT NK$+" --> ";M$
2040 A=0:B=BF:C$="IRC":D$="MSG "+CH$+" :"+M$:GOSUB10000        ' Send message to IRC channel
2060 RETURN
2499 '
2999 '
3000 ' Join a IRC Channel: Set the inputs / Call SENDCOMMAND'
3010 M$="":PRINT "Channel:|";CHR$(8);:P=7:GOSUB5000     ' Read channel name from kbd
3020 IF M$="" THEN PRINT:RETURN
3030 CH$=M$:A=1:B=BF:C$="IRC":D$="JOIN "+M$:GOSUB10000     ' Send Join command to IRC
3060 RETURN
3999 '
4000 ' Leave the IRC App: Set the inputs / Call SENDCOMMAND'
4010 A=1:B=BF:C$="IRC":D$="QUIT":GOSUB10000
4020 PRINT "Bye":END
4998 '
4999 ' Supporting Functions for the IRC program'
5000 ' Rotating prompt - Get user input text
5510 K$=INKEY$:IF K$<>"" THEN GOTO 5560
5520 IF TIME<50 THEN PRINT"/";CHR$(8);:GOTO5560
5530 IF TIME<100 THEN PRINT"-";CHR$(8);:GOTO5560
5540 IF TIME<150 THEN PRINT"\";CHR$(8);:GOTO5560
5550 IF TIME<200 THEN PRINT;"|";CHR$(8);:GOTO5560 ELSE TIME=0
5560 IF K$=CHR$(13) THEN GOSUB 5600:RETURN
5570 IF (K$=CHR$(8) AND LEN(M$)>0) THEN M$=LEFT$(M$,LEN(M$)-1):PRINT " ";CHR$(8);CHR$(8);
5580 IF K$>=CHR$(32) THEN M$=M$+K$:PRINT K$;:GOTO5000 ELSE GOTO5000
5599 ' End of typing - Prepare to return to main loop
5600 FOR I=0 TO LEN(M$)+P:PRINT " ";CHR$(8);CHR$(8);" ";CHR$(8);:NEXT I:RETURN
8999 '
6000 KEY 1,"F1-Send Message":KEY 2,"F2-Join channel":KEY 3,"F3-Quit":KEY 4,"":KEY 5,"":KEY 6,"":KEY 7,"":KEY 8,"":KEY 9,"":KEY 10,""
6095 RETURN
6100 E0=&HE0:E1=&HE1:E2=&HE2:E3=&HE3:E4=&HE4:E5=&HE5:E6=&HE6:E7=&HE7:E8=&HE8:E9=&HE9:EA=&HEA:EB=&HEB:EC=&HEC:ED=&HED:EF=&HEF
6110 RETURN
9998 '
9999 ' ============================  API ROUTINES STARTS HERE - DO NOT CHANGE ===================================
10000 ' ==========================         SENDCOMMAND(A,B,C$,D$)          ===================================
10001 ON ERROR GOTO 10900
10002 IFA=0THENCALLMSXPI("0,"+HEX$(B)+","+C$+" "+D$)ELSEIFA=1THENCALLMSXPI("1,"+HEX$(B)+","+C$+" "+D$)ELSECALLMSXPI("2,"+HEX$(B)+","+C$+" "+D$)
10004 RC=PEEK(B):RETURN
10900 RC=-1:RETURN
10999 '
11000 ' ==========================           PRINTSTDOUT(A,B,C$)          ===================================
11001 ON ERROR GOTO 11250
11010 IF B<&H9000 THEN RC=-1:Z2=0:RETURN
11020 C$="":IF Z2=0 THEN S=PEEK(B+1)+256*PEEK(B+2):Z2=B+3       ' Re-use Z2 var from previous call.
11022 Y=PEEK(Z2):Z2=Z2+1:IFA=0 THEN GOTO 11050
11025 IF Y=10 THEN PRINT: ELSE PRINT CHR$(Y);
11027 IF Z2-B < S+3 THEN GOTO 11022
11030 RC=&HED:Z2=0:RETURN
11050 C$=C$+CHR$(Y):IFY=10THENC$=C$+CHR$(13)
11051 IFLEN(C$)<C THEN GOTO 11022
11052 IF Z2-B < S+3 THEN RC=&HE0 ELSE RC=&HED:Z2=0
11055 RETURN       ' RC=E0:there is more data, RC=ED:No more data
11250 RC=-1:Z2=0:RETURN
11999 '
12000 ' ==========================                MSXPISEND(B)            ===================================
12001 ON ERROR GOTO 12025
12010 IF B<&H9000 THEN RC=-1:RETURN
12012 CALL MSXPISEND(HEX$(B)):RC=0:RETURN
12025 RC=-1:RETURN
12026 '
13000 ' ==========================                MSXPIRECV(B)            ===================================
13001 ON ERROR GOTO 13025
13010 IF B<&H9000 THEN RC=-1:RETURN
13012 CALL MSXPIRECV(HEX$(B)):RC=PEEK(B):RETURN
13025 RC=-1:RETURN
13026 '
14000 ' ' ==========================             STORESTR(B,C$)            ===================================
14010 IF B<&H9000 THEN RC=-1:RETURN
14012 FOR Z=1TOLEN(C$):Y=ASC(MID$(C$,Z,1)):POKE(B+Z-1),Y:NEXTZ:POKE(B+Z-1),0:RC=0:Z=0:RETURN
15000 ' DEFINE ADDRESS FOR MSXPI BUFFER
15010 CLEAR 200,((PEEK(&HFC4A)+256*PEEK(&HFC4B))-520)
15020 BF=PEEK(&HFC4A)+256*PEEK(&HFC4B)
15030 GOTO 65
