400 ' ====> 4 : Execute command TEMPLATE, send parameters, receive reply e print to screen
402 ?:?:PRINT"Execute command TEMPLATE, send parameters, receive reply e print to screen"
410 A=2                      ' this is the stdout parameter - save to buffer only, do not print
420 B=&HC000                 ' This is the buffer address
430 C$="apitest"             ' Command to execute
440 D$="Parameters sent via CALL MSXPI"
450 PRINT:PRINT"Starting Example 4":GOSUB 10000  ' Call SENDCOMMAND
453 IF RC=-1 THEN GOTO495
466 B=&HC000:GOSUB13000 ' Read data from PI and store in buffer (256 BYTES)
468 A=1:B=&HC000:GOSUB11000 ' Print the contents of the buffer
495 PRINT:PRINT"Example 4 finished:";HEX$(RC)
999 END
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
11052 IF Z2-B < S+3 THEN RC=&HE0 ELSE RC=&HED
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
