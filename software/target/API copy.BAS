5 ' BASIC API for MSXPi v1.1
6' To use a routine, set the required variables to the desired values and gosub to the routine
7 ' The following routines are available:
8 '
10 ' SENDCOMMAND - CALL MSXPI("stdout,buffer,command") - Line 10000-10015
11 ' A = stdout: 0 = ignore, 1 print, 2 save to buffer
12 ' B = buffer address: Hexadecimal memory address (ex: &hC000) to store data from RPi
13 ' C$ = command: Command to send to RPi (for example, "pdir", "prun")
14 ' D$ = Parameters for the command (for example, "/home/pi/msxpi")
15 ' Returns:
16 ' RC = return code: -1 = Connection Error, Any other was returned by Pi
17 ' Any error returned by RPi may have a text available in the buffer. Use PRINTSTDOUT to access it
18 '
20 ' PRINTSTDOUT - Process buffer contents - Line 11000-11025
21 ' A = action: 0 = return the buffer content in the C$ variable, 1 = Print to screen
22 ' B  = buffer address: Hexadecimal memory address for the buffer (Ex: &hC000)
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
40 ' STORESTR - Store a string a buffer - Line 14000-
42 ' B = buffer address: Hexadecimal memory address (ex: &hC000) to store the data received
42 ' C$ = String to store, maximum 256 bytes (not sure MSX supoprt strings this size though)
44 ' Returns:
45 ' RC = return code: -1 = If any error occurred, 0 = Success


100 ' Examples of how to use the API
101 ' Execute a DIR in the MSXPi "/home/pi/msxpi" directory, printing to screen
110 A=1                      ' this is the stdout parameter
120 B=&HC000                 ' This is the buffer address
130 C$="pdir"                ' Command to execute
140 D$ ="ls -l /home/pi/"    ' Parameters to pass along with the command
150 GOSUB 10000              ' Call SENDCOMMAND
153 PRINT "Example 1 finished:";:IF RC=-1 THEN PRINT "Error" ELSE PRINT "Success"
199 '


999 END
9000 Y=B
9010 Y=Y+3:S=PEEK(B+1)+256*PEEK(B+2)+3
9020 T=PEEK(Y):Y=Y+1:IF T=10 THEN PRINT: ELSE PRINT(CHR$(T));
9030 IF Y-B < S THEN GOTO 9020
9040 RETURN

10000 ' SENDCOMMAND
10001 ON ERROR GOTO 10900
10002 CALL MSXPI(STRING$(A)+","+HEX$(B)+","+C$):RC=PEEK(B):IF RC=&HE7 THEN RC=-1:RETURN
10002 C$=D$:GOSUB14000:CALL MSXPISEND(HEX$(B)):RC=PEEK(B):IF RC=&HE7 THEN RC=-1:RETURN
10010 CALL MSXPIRECV(HEX$(B)):RC=PEEK(B):IF RC=&HE7 THEN RC=-1:RETURN
10015 S=PEEK(B+1)+256*PEEK(B+2):IF S<256-3THEN GOTO10050 ELSEY=B ' END OF TRANSFER, GO PROCESS STDOUT
10020 IF A>0 THEN Y=Y+256  ' Prepare to read next block - get next buffer address
10025 CALL MSXPIRECV(HEX$(Y)):RC=PEEK(B):IF RC=&HE7 THEN RC=-1:RETURN
10030 IF Y+256-B < S THEN GOTO 10020  ' READ NEXT BLOCK
10050 ' Process STDOUT parameter
10051 IFA=0ORA=2THENRETURN
10055 GOSUB11000:RETURN
10900 RC=-1:RETURN

11000 ' PRINTSTDOUT
11001 ON ERROR GOTO 11025
11010 IF B<&H9000 THEN RC=-1:RETURN
11020 C$="":S=PEEK(B+1)+256*PEEK(B+2):FORZ=B+3 TO B+S:IF A=0 THEN C$=C$+CHR$(PEEK(Z)) ELSE PRINT CHR$(PEEK(Z));
11022 NEXTZ:RETURN
11025 RC=-1:RETURN
11026 '
12000 ' MSXPISEND
12001 ON ERROR GOTO 12025
12010 IF B<&H9000 THEN RC=-1:RETURN
12012 CALL MSXPISEND(HEX$(B)):RC=0:RETURN
12025 RC=-1:RETURN
12026 '
13000 ' MSXPIRECV
13001 ON ERROR GOTO 13025
13010 IF B<&H9000 THEN RC=-1:RETURN
13012 CALL MSXPIRECV(HEX$(B)):RC=PEEK(B):RETURN
13025 RC=-1:RETURN
13026 '
14000 ' STORESTR
14001 ON ERROR GOTO 14025
14010 IF B<&H9000 THEN RC=-1:RETURN
14012 FOR Z=1TOLEN(C$):Y=ASC(MID$(C$,Z,1)):POKE(B+Z-1),Y:NEXTZ:POKE(B+Z-1),0:RC=0:RETURN
14025 RC=-1:RETURN
