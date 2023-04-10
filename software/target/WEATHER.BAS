10 '*******************************
20 '*                             *
30 '*      * MSXPi Weather *      *
40 '*                             *
50 '*      Previsao do tempo      *
60 '*                             *
70 '*   (C) 2019  By  Retropix    *
80 '*                             *
90 '*******************************
95 onerrorgoto99
96 call msxpiver
97 goto 100
99 bload "msxpiext.bin",r
100 CLEAR500,49152!:REM BLOAD"msxpiext.bin",R
110 SCREEN0,,80:KEY OFF:DEFINT A-Z:CLS
120 GOSUB 230
130 GOTO 350
140 '
150 '---- limpa area de resultado da informacao ----
160 REG$="recife"
170 FOR YY=4 TO 19
180 LOCATE 1,YY:PRINT SPACE$(77)
190 NEXT YY
200 RETURN
210 '
220 '---------- desenha tela principal -------------
230 LOCATE  0,0
240 PRINT "X";:FORL=2TO29:PRINT"W";:NEXT:PRINT"R";:FORL=31TO78:PRINT"W";:NEXT:PRINT"Y"
250 PRINT "V";" MSXPi Weather - versao 1.0 ";"V"+SPACE$(10);"(c) 2019 - Retropix Brasil";SPACE$(12);"V"
260 PRINT "T";:FORL=2TO29:PRINT"W";:NEXT:PRINT"Q";:FORL=31TO78:PRINT"W";:NEXT:PRINT"S"
270 FOR N = 4 TO 20
280  PRINT "V";SPACE$(77);"V"
290 NEXT N
300 PRINT "T";:FORL=2TO78:PRINT"W";:NEXT:PRINT"S"
310  PRINT "V";" Choose a region (null=current region) :";SPACE$(37);"V"
320 PRINT "Z";:FORL=2TO78:PRINT"W";:NEXT:PRINT"["
330 RETURN
340 '
350 '------- Busca as informacoes do Pi e mostra na tela ----
360 ON ERROR GOTO 1170
370 LOCATE35,10:PRINT"Loading..."
380 A=&HC000
390 CALL MSXPI("2,C000,prun wget -O- -q wttr.in/"+C$+"?0nT")
400  C$="":LIN=4:RW=0: 'recebeu uma previsao de tempo 0 nao 1 sim
410 IF PEEK(&HC003)=ASC("W")THENRW=1
420 GOSUB 150
430 FOR J=&HC003 TO &HC003+(PEEK(A+1)+256*PEEK(A+2))
440   IF(LEN(C$)=73)THEN450ELSE550
450   IF RW=1THENGOSUB 750
460   IF (RW=1 AND LIN=7) THEN LIN=LIN+1 : 'pula uma linha
470   IF (RW=1 AND LIN=6)THENC$="<< "+C$+" >>"
480   IF (RW=1 AND LIN=8)THENC$="Temperature: "+C$:GOSUB1030
490   IF (RW=1 AND LIN=9)THENC$="Wind: "+C$:GOSUB1030
500   IF (RW=1 AND LIN=10)THENC$="Visibility: "+C$:GOSUB1030
510   IF (RW=1 AND LIN=11)THENC$="Humidity: "+C$:GOSUB1030
520   IF (RW=1 AND LIN=12) THEN LIN=LIN+1 : 'pula uma linha
530   IFLEN(C$)>0THENLOCATEINT((80-LEN(C$))/2),LIN:PRINTC$
540   C$="":LIN=LIN+1
550   C=PEEK(J)
560   IF (C>0 AND LEN(STR$(C))>0 AND C<>10)THEN C$=C$+CHR$(C):GOTO670
570   IF RW=1THENGOSUB 750
580   IF (RW=1 AND LIN=7) THEN LIN=LIN+1 : 'pula uma linha
590   IF (RW=1 AND LIN=6)THENC$="<< "+C$+" >>"
600   IF (RW=1 AND LIN=8)THENC$="Temperature: "+C$:GOSUB1030
610   IF (RW=1 AND LIN=9)THENC$="Wind: "+C$:GOSUB1030
620   IF (RW=1 AND LIN=10)THENC$="Visibility: "+C$:GOSUB1030
630   IF (RW=1 AND LIN=11)THENC$="Humidity: "+C$:GOSUB1030
640   IF (RW=1 AND LIN=12) THEN LIN=LIN+1 : 'pula uma linha
650   IFLEN(C$)>0THENLOCATEINT((80-LEN(C$))/2),LIN:PRINTC$
660   C$="":LIN=LIN+1
670 NEXTJ
680 C=42:L=21:T=35:GOSUB920
690 IF INSTR(C$,"moon")THENC$=""
700 GOSUB1030:GOSUB1110:GOSUB150
710 ON ERROR GOTO 0
720 GOTO 360
730 ON ERROR GOTO:CLS:END
740 '
750 ' ----  trata caracteres especiais ----
760 IF(LIN=4 AND MID$(C$,1,1)="W")OR(LIN=5 AND MID$(C$,1,5)="Sorry")OR(LIN>11)THEN770ELSEC$=MID$(C$,16)
770   R$="":I=1
780   T=LEN(C$):IF T<1THEN 900
790   X1=ASC(MID$(C$,I,1))
800   IF(I+1<=T)THENX2=ASC(MID$(C$,I+1,1))ELSEX2=0
810   IF(I+2<=T)THENX3=ASC(MID$(C$,I+2,1))ELSEX3=0
820   IF(X1>31 AND X1<124)THEN R$=R$+MID$(C$,I,1):GOTO870
830   IF(X1=195 AND X2=163) THEN R$=R$+"ao":I=I+2:GOTO870
840   IF(X1=195 AND X2=169) THEN R$=R$+"e":I=I+2:GOTO870
850   IF(X1=194 AND X2=176) THEN R$=R$+CHR$(&HDF):I=I+1:GOTO870
860   IF(X1<32  AND X2>123) THEN GOTO870
870   I=I+1
880   IF(I<=T) THEN GOTO790
890   C$=R$:GOSUB1030
900 RETURN
910 '
920 '--- rotina de tratamento de entrada de dados ---
930 LOCATEC,L:R$="":PI=0:FORI=1TOT:PRINT".";:NEXTI
940 LOCATEC,L:I$=INPUT$(1):GOSUB1190
950 IF (ASC(I$)=13)THEN C$=R$:RETURN
960 IF (ASC(I$)=27)THEN 730
970 IF ((ASC(I$)>47 AND ASC(I$)<58)  OR (ASC(I$)>64 AND ASC(I$)<91)  OR (ASC(I$)=44) OR (ASC(I$)>96 AND ASC(I$)<123) OR (ASC(I$)=32)) AND (LEN(R$)<T) THEN PRINTI$:R$=R$+I$:C=C+1:PI=PI+1
980 IF (ASC(I$)=8 AND PI>0 AND LEN(R$)=T)THEN R$=LEFT$(R$,LEN(R$)-1):C=C-1:PI=PI-1:LOCATEC,L:PRINT".":GOTO1000
990 IF (ASC(I$)=8 AND PI>0 AND LEN(R$)<T)THEN R$=LEFT$(R$,LEN(R$)-1):C=C-1:LOCATEC,L:PRINT".":PI=PI-1
1000 IF (PI=0)THENLOCATEC,L:PRINT"."
1010 GOTO 940
1020 '
1030 '--- funcao trim para limpar espacos da esquera e direita ---
1040  R$="":ZA=0:ZB=0:ZC=0:IFLEN(C$)=0THENRETURN
1050  FOR I=1TOLEN(C$):IF((MID$(C$,I,1)>CHR$(32)AND ZA=0 AND ZB=0))THEN ZA=I:ZB=1
1060  NEXTI
1070  FORI=LEN(C$)TO1STEP-1:IF((MID$(C$,I,1)>CHR$(32)ANDZB=1 AND ZC=0))THEN ZB=I:ZC=1
1080  NEXTI
1090  R$=MID$(C$,ZA,ZB):C$=R$:RETURN
1100 '
1110 '---- Troca espacos por %20 para compatibilizar a url ----
1120 R$="":FORI=1TOLEN(C$):IF(MID$(C$,I,1)=CHR$(32))THEN R$=R$+"%20"ELSER$=R$+MID$(C$,I,1)
1130 NEXT I
1140 C$=R$:RETURN
1150 '
1160 '---- Paliativo para reiniciar o msxpi e deixa-lo aceitar um novo comando
1170 CALL MSXPI("2,C000,prun wget -O- -q wttr.in/recife?0nT")
1180 RESUME 400
1190 '
1200 '---- rotina para lower case ----
1210 IF ASC(I$)>64 AND ASC(I$)<91 THEN I$=CHR$(ASC(I$)+32)
1220 RETURN

