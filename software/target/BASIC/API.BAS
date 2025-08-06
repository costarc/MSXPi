5 ' BASIC API for MSXPi v1.1
6' To use a routine, set the required variables to the desired values and gosub to the routine
7 ' Insert you code starting in line 101 - and do not change anything from lines 50 to 101.
8 ' The following routines are available:
9 '
10 ' SENDCOMMAND - CALL MSXPI("stdout,buffer,command") - Line 10000-10015
11 ' A = stdout: 0 = ignore, 1 print, 2 save to buffer
12 ' B = buffer address: Hexadecimal memory address (ex: &hC000) to store data from RPi)
13 ' C$ = command: Command to send to RPi (for example, "pdir", "prun")
14 ' D$ = Parameters for the command (for example, "/home/pi/msxpi")
15 ' Returns:
16 ' RC = return code: -1 = Connection Error, Any other was returned by Pi
17 ' Any error returned by RPi may have a text available in the buffer. Use PRINTSTDOUT to access it
18 '
20 ' PRINTSTDOUT - Process buffer contents - Line 11000-11025
21 ' A = action: 0 = return the buffer content in the C$ variable, 1 = Print to screen
22 ' B = buffer address: Hexadecimal memory address for the buffer (Ex: &hC000)
23 ' C = number of chars to return in string C$ (when A = 0)
24 ' Returns:'
23 ' C$ = If A = 1, will return the contents of the buffer in C$
24 '
30 ' MSXPISEND - Send a block of binary data to RPi (256 bytes) Line 12000-
32 ' B = buffer address: Hexadecimal memory address (ex: &hC000) containing the data to send
34 ' Returns:
35 ' RC = return code: -1 = Connection Error, 0 = Success
36 '
30 ' MSXPIRECV - Receive a block of binary data to RPi (256 bytes) Line 13000-
32 ' B = buffer address: Hexadecimal memory address (ex: &hC000) to store the data received
34 ' Returns:
35 ' RC = return code: -1 = Connection Error, 0 = Success
37 '
40 ' STORESTR - Store a string in a buffer - Line 14000-
42 ' B = buffer address: Hexadecimal memory address (ex: &hC000) to store the data received
42 ' C$ = String to store, maximum 256 bytes (not sure MSX supoprt strings this size though)
44 ' Returns:
45 ' RC = return code: -1 = If any error occurred, 0 = Success
50 ' DO NOT CHANGE FROM HERE TO LINE 99
55 ' YOUR CODE SHOULD START AT LINE 101
60 GOTO 15000 ' Define address for MSXPi buffer in the top of RAM and put in var BF
65 ' DO NOT DELETE OR CHANGE THIS LINE NUMBER
70 onerrorgoto90
75 call msxpiver
80 goto 100
90 bload "msxpiext.bin",r
100 ' DO NOT DELETE THIS LINE
101 ' ============================  Example Code - Using the API Routines  ===================================
102 ' ====> 1 : Execute a DIR in the MSXPi "/home/pi/msxpi" directory, printing to screen
103 PRINT:PRINT"Starting Example 1":PRINT"Execute a DIR in the MSXPi /home/pi/msxpi directory, printing to screen"
110 A=1                      ' this is the stdout parameter - print to screen
120 B=BF                 ' This is the buffer address
130 C$="pdir"                ' Command to execute
140 D$="/home/pi/msxpi"      ' Parameters to pass along with the command
150 PRINT:GOSUB 10000        ' Call SENDCOMMAND
153 PRINT:PRINT"Example 1 finished:";HEX$(RC)
199 '
200 ' ====> 2 : Execute a DIR in the MSXPi "/home/pi/msxpi" directory - Read the buffer using BASIC routines
202 PRINT:PRINT"Starting Example 2":PRINT"Execute a DIR in the MSXPi /home/pi/msxpi directory - Read the buffer using BASIC"
210 A=2                      ' this is the stdout parameter - save to buffer only, do not print
220 B=BF                     ' This is the buffer address
230 C$="pdir"                ' Command to execute
240 D$="/home/pi/msxpi"      ' Parameters to pass along with the command
250 PRINT:GOSUB 10000        ' Call SENDCOMMAND
253 IF RC=-1 THEN GOTO260
255 A=1:GOSUB 11000              ' Call PRINTSTDOUT routine to print the buffer data to screen (text)
260 PRINT:PRINT"Example 2 finished:";HEX$(RC)
299 '
300 ' ====> 3 : Execute a DIR in the MSXPi "/home/pi/msxpi" directory - Read the buffer to a Variable
302 PRINT:PRINT"Starting Example 3":PRINT"Execute a DIR in the MSXPi /home/pi/msxpi directory - Read the buffer to a Variable and print to screen"
310 A=2                      ' this is the stdout parameter - save to buffer only, do not print
320 B=BF                 ' This is the buffer address
325 C=40                     ' Number of chars to retrn in C$
330 C$="pdir"                ' Command to execute
340 D$="/home/pi/msxpi"      ' Parameters to pass along with the command
350 PRINT:GOSUB 10000        ' Call SENDCOMMAND
353 IF RC=-1 THEN GOTO365
355 A=0:GOSUB 11000          ' Call PRINTSTDOUT routine to store the buffer data to C$
360 PRINT(C$);:IF RC<>&HED AND RC<>&HE7 THEN GOTO355    ' Print 100 chars from buffer, check if there is more to read
365 PRINT:PRINT"Example 3 finished:";HEX$(RC)
399 '
400 ' ====> 4 : Execute command apitest, send parameters, receive reply e print to screen
402 PRINT:PRINT"Starting Example 4":PRINT"Execute command APITEST, send parameters and additional data, receive reply e print to screen"
410 A=1                      ' this is the stdout parameter - save to buffer only, do not print
420 B=BF                 ' This is the buffer address
430 C$="apitest"             ' Command to execute
440 D$="Parameters sent via CALL MSXPI"
450 PRINT:GOSUB 10000        ' Send Command & parameters
453 IF RC=-1 THEN GOTO495
460 ' SEND Parameters to the TEMPLATE Command
461 B=BF:C$="Additional data sent via CALL MSXPISEND":GOSUB14000:IFRC=-1THENGOTO495 ' Store C$ in buffer
462 B=BF:GOSUB12000 ' SEND THE CONTENTS OF BUFFER TO PI (256 BYTES)
464 IF RC=-1 THEN GOTO 495
466 ?:B=BF:GOSUB13000 ' Read data from PI and store in buffer (256 BYTES)
468 A=1:B=BF:GOSUB11000 ' Print the contents of the buffer
495 PRINT:PRINT:PRINT"Example 4 finished:";HEX$(RC)
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
15010 CLEAR 200,(PEEK(&HFC4A)+256*PEEK(&HFC4B))-520
15020 BF=PEEK(&HFC4A)+256*PEEK(&HFC4B)
15030 RETURN

