10 '*******************************
20 '*                             *
30 '*       * MSXPi Chat *        *
40 '*                             *
50 '* Chat between MSXPi computers*
60 '*                             *
70 '*     (C) 2026 By RCC         *
80 '*                             *
90 '*******************************
95 onerrorgoto99
96 call msxpiver
97 goto 100
99 bload "msxpiext.bin",r
100 CLEAR500,49152!
102 SCREEN0,,80:WIDTH80:KEY OFF:DEFINT A-Z:CLS
104 FOR I=1 TO 10: KEY(I) STOP:NEXT I
106 ON KEY GOSUB 930,730,730
108 KEY (1) ON:KEY (2) ON: KEY(3) ON
110 gosub 220
120 CH$="#msxpi"
130 NICK$="msxpi"+MID$(STR$(PEEK(&HFC9E)),2)
132 LOCATE25,10:PRINT"Connecting to MSXPi Chat..."
134 A=2:B=&HC000:C$="IRC":D$="CONNECT "+NICK$:GOSUB10000
136 A=2:B=&HC000:C$="IRC":D$="READ":GOSUB10000:TIME=0
138 IF PEEK(B+6)=ASC("O") AND PEEK(B+7)=ASC("k") AND PEEK(B+9)=ASC("R") AND PEEK(B+13)=ASC("y") THEN GOTO 140
139 IF TIME > 300 THEN GOTO136 ELSE GOTO 139
140 LOCATE35,11:PRINT"Joining "+CH$:A=2:B=&HC000:C$="IRC":D$="JOIN "+CH$:GOSUB10000
142 GOSUB 230
145 ML=4:TIME=0:T=1:SM=0:GOTO 340
150 '
160 '
170 '---- limpa area de resultado da informacao ----

170 FOR YY=4 TO 19
180 LOCATE 1,YY:PRINT SPACE$(77)
190 NEXT YY
200 RETURN
210 '
220 '---------- desenha tela principal -------------
230 LOCATE  0,0
240 PRINT "X";:FORL=2TO25:PRINT"W";:NEXT:PRINT"R";:FORL=27TO78:PRINT"W";:NEXT:PRINT"Y"
250 PRINT "V";"MSXPi Chat - Version 2.0";"V"+SPACE$(52);"V"
252 PRINT "V";"     (c) RCC 2026       ";"V"+SPACE$(52);"V"
260 PRINT "T";:FORL=2TO25:PRINT"W";:NEXT:PRINT"Q";:FORL=27TO78:PRINT"W";:NEXT:PRINT"S"
270 FOR N = 4 TO 19
280  PRINT "V";SPACE$(77);"V"
290 NEXT N
300 PRINT "T";:FORL=2TO78:PRINT"W";:NEXT:PRINT"S"
310  PRINT "V";"Type a message:";SPACE$(62);"V"
320 PRINT "Z";:FORL=2TO78:PRINT"W";:NEXT:PRINT"["
330 RETURN
340 '
350 '------- Busca as informacoes do Pi e mostra na tela ---- Pi:Ok
360 TIME=0:ON ERROR GOTO 1170
378 IF TIME < 150 THEN GOTO 378
380 T=T-1:IF T < 1 THEN GOSUB 2000:T=5 'Request list participants in the chat room (/names)
390 A=2:B=&HC000:C$="IRC":D$="READ":GOSUB 10000
400 LIN=4:RW=0
415 IF PEEK(B)<> &HEB THEN RW=1
419 'Check if it is a response to /names:  xxxPi:Ok:Users
420 S=9:IU=0:E=7:IF (PEEK(B+6)=ASC("O")) AND (PEEK(B+9)=ASC("U")) THEN IU=1:S=15:E=13:LOCATE26,1:GOTO435
430 IF (ML>19 AND (RW=1 OR IU=1)) THENGOSUB150:GOSUB1030:ML=4
432 LOCATE 1,ML
435 FOR J=B+S TO B+S+(PEEK(B+1)+256*PEEK(B+2)-E)
440 IF RW=1 THEN PRINT CHR$(PEEK(J));
670 NEXT J
672 IF (RW=1 OR IU=1) THEN ML=ML+1
710 ON ERROR GOTO 0
720 GOTO 360
730 ON ERROR GOTO:CLS:END
910 '
920 '--- rotina de tratamento de entrada de dados ---
930 C=16:L=21:T=61:M$="":LOCATEC,L:R$="":PI=0:FORI=1TOT:PRINT".";:NEXTI
940 LOCATEC,L:I$=INPUT$(1):GOSUB1190
935 IF (ASC(I$)<>13)THEN GOTO 960
950 M$=R$:A=2:B=&HC000:C$="IRC":D$="SAY "+CH$+" "+M$:GOSUB10000
952 IF (ML>19) THEN GOSUB150:GOSUB1030:ML=4
954 LOCATE1,ML:?"<"+ch$+"> "+NICK$+" -> "+M$:RETURN
960 IF (ASC(I$)=27)THEN GOTO 730
970 IF (ASC(I$)>31 AND LEN(R$)<T) THEN PRINTI$:R$=R$+I$:C=C+1:PI=PI+1
980 IF (ASC(I$)=8 AND PI>0 AND LEN(R$)=T)THEN R$=LEFT$(R$,LEN(R$)-1):C=C-1:PI=PI-1:LOCATEC,L:PRINT".":GOTO1000
990 IF (ASC(I$)=8 AND PI>0 AND LEN(R$)<T)THEN R$=LEFT$(R$,LEN(R$)-1):C=C-1:LOCATEC,L:PRINT".":PI=PI-1
1000 IF (PI=0)THENLOCATEC,L:PRINT"."
1010 GOTO 940
1020 '
1030 '--- funcao trim para limpar espacos da esquerda e direita ---
1040  R$="":ZA=0:ZB=0:ZC=0:IFLEN(M$)=0THENRETURN
1050  FOR I=1TOLEN(M$):IF((MID$(M$,I,1)>CHR$(32)AND ZA=0 AND ZB=0))THEN ZA=I:ZB=1
1060  NEXTI
1070  FORI=LEN(M$)TO1STEP-1:IF((MID$(M$,I,1)>CHR$(32)ANDZB=1 AND ZC=0))THEN ZB=I:ZC=1
1080  NEXTI
1090  R$=MID$(M$,ZA,ZB):M$=R$:RETURN
1100 '
1110 '---- Troca espacos por %20 para compatibilizar a url ----
1120 R$="":FORI=1TOLEN(M$):IF(MID$(M$,I,1)=CHR$(32))THEN R$=R$+"%20"ELSER$=R$+MID$(M$,I,1)
1130 NEXT I
1140 M$=R$:RETURN
1150 '
1160 '---- Paliativo para reiniciar o msxpi e deixa-lo aceitar um novo comando
1170 A=2:B=&HC000:C$="IRC":D$="READ":GOSUB10000
1180 RESUME 400
1190 '
1200 '---- rotina para lower case ----
1210 IF ASC(I$)>64 AND ASC(I$)<91 THEN I$=CHR$(ASC(I$)+32)
1220 RETURN
2000 ' Send /names to get list if participants in the room
2100 A=2:B=&HC000:C$="IRC":D$="SAY " + CH$ + " /NAMES":GOSUB10000
2110 RETURN
2200 'Ceck if the messag is a list of participants, and show

10000 ' ==========================         SENDCOMMAND(A,B,C$,D$)          ===================================
10001 ' ON ERROR GOTO 10900
10002 IFA=0THENCALLMSXPI("0,"+HEX$(B)+","+C$+" "+D$)ELSEIFA=1THENCALLMSXPI("1,"+HEX$(B)+","+C$+" "+D$)ELSECALLMSXPI("2,"+HEX$(B)+","+C$+" "+D$)
10004 RC=PEEK(B):RETURN
10900 RC=-1:RETURN
