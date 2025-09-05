5 CLS
10 INPUT "Number to send: ";  N
20 OUT (&H5A),N
30 OUT &H56,1
40 PRINT "Received: "; INP(&H5A)
50 GOTO 10
