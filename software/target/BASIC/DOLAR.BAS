10 '*******************************
20 '*                             *
30 '*      * MSXPi Weather *      *
40 '*                             *
50 '*      Cotacao do Dolar       *
60 '*                             *
70 '*   (C) 2019  By  Retropix    *
80 '*                             *
90 '*******************************
94 CLEAR1000,49152!
95 onerrorgoto99
96 call msxpiver
97 goto 100
99 bload "msxpiext.bin",r
100 '
110 SCREEN0,,80:WIDTH80:KEY OFF:DEFINT A-Z:COLOR2,1:CLS
120 GOSUB 220
130 C$="01-07-2019":GOTO 340
140 '
150 '---- limpa area de resultado da informacao ----
160 FOR YY=4 TO 19
170 LOCATE 1,YY:PRINT SPACE$(77)
180 NEXT YY
190 RETURN
200 '
210 '---------- desenha tela principal -------------
220 LOCATE  0,0
230 PRINT "X";:FORL=2TO29:PRINT"W";:NEXT:PRINT"R";:FORL=31TO78:PRINT"W";:NEXT:PRINT"Y"
240 PRINT "V";"  MSXPi Dolar - vers. 1.0   ";"V"+SPACE$(10);"(c) 2019 - Retropix Brasil";SPACE$(12);"V"
250 PRINT "T";:FORL=2TO29:PRINT"W";:NEXT:PRINT"Q";:FORL=31TO78:PRINT"W";:NEXT:PRINT"S"
260 FOR N = 4 TO 20
270  PRINT "V";SPACE$(77);"V"
280 NEXT N
290 PRINT "T";:FORL=2TO78:PRINT"W";:NEXT:PRINT"S"
300  PRINT "V";"                 Digite uma data para cotacao:";SPACE$(31);"V"
310 PRINT "Z";:FORL=2TO78:PRINT"W";:NEXT:PRINT"["
320 RETURN
330 '
340 '------- Busca as informacoes do Pi e mostra na tela ----
350 ON ERROR GOTO 570
360 LOCATE33,10:PRINT"Carregando..."
370 A=&HC000
380 CALL MSXPI("2,c000,prun wget -O- -q http://www.retropix.com.br/repository/apis/cotacao.php?d="+C$)
390  C$="":LIN=4
400 GOSUB 150
410 IF (CHR$(PEEK(&HC003))+CHR$(PEEK(&HC004))="-1")THENLOCATE17,10:PRINT"Nenhuma cotacao foi encontada para essa data.":LOCATE31,12:PRINT"Tente outra data."
420 IF (CHR$(PEEK(&HC003))+CHR$(PEEK(&HC004))+CHR$(PEEK(&HC005))+CHR$(PEEK(&HC006))="Pi:E")THENLOCATE17,11:PRINT"Falha na comunicacao, tente novamente!":GOTO490
430 FOR J=&HC003 TO &HC003+(PEEK(A+1)+256*PEEK(A+2))
440   C=PEEK(J)
450 IF C<>10 THEN C$=C$+CHR$(C):GOTO480
460   IFLEN(C$)>0THENLOCATE4,LIN:PRINTC$
470   C$="":LIN=LIN+1
480 NEXTJ
490 C=48:L=21:T=8:GOSUB600:GOSUB770
500 IFLEN(C$)>0THENC$=MID$(C$,1,2)+"-"+MID$(C$,3,2)+"-"+MID$(C$,5,4):GOSUB150
510 IF C$="" THEN 490
520 ON ERROR GOTO 0
530 GOTO 350
540 ON ERROR GOTO:CLS:END
550 '
560 '---- Paliativo para reiniciar o msxpi e deixa-lo aceitar um novo comando
570 CALL MSXPI("2,c000,prun wget -O- -q http://www.retropix.com.br/repository/apis/cotacao.php?d1="+C$)
580 RESUME 390
590 '
600 '--- rotina de tratamento de entrada de dados ---
610 LOCATEC,L:R$="":PRINT"../../...."
620 P1=3:P2=5:PI=1
630 IF (PI>T) THEN PI=T+1
640 LOCATEC,L:I$=INPUT$(1)
650 IF (ASC(I$)=13 AND LEN(R$)=T)THEN C$=R$:RETURN
660 IF (ASC(I$)=27)THEN 540
670 IF ((ASC(I$)>47 AND ASC(I$)<58)) AND (LEN(R$)<T) THEN LOCATEC,L:PRINTI$:R$=R$+I$:C=C+1:PI=PI+1:GOSUB740
680 IF (ASC(I$)=8 AND PI>1 AND LEN(R$)=T)THEN R$=LEFT$(R$,LEN(R$)-1):GOSUB720:C=C-1:PI=PI-1:LOCATEC,L:PRINT".":GOTO700
690 IF (ASC(I$)=8 AND PI>1 AND LEN(R$)<T)THEN R$=LEFT$(R$,LEN(R$)-1):GOSUB720:C=C-1:LOCATEC,L:PRINT".":PI=PI-1
700 IF (PI=1)THENLOCATEC,L:PRINT"."
710 GOTO 630
720 IF (ASC(I$)=8)THENIF(PI=P1 OR PI=P2)THEN C=C-1
730 RETURN
740 IF(PI=P1 OR PI=P2)THEN C=C+1
750 RETURN
760 '
770 ' ----- valida data -----
780 MES=VAL(MID$(C$,3,2))
790 DIA=VAL(MID$(C$,1,2))
800 ANO=VAL(MID$(C$,5,4))
810 CHECK=0
820 IF ANO>0THENRES=ANOMOD4:IFRES=0 THEN BI=29 ELSE BI=28
830 CHECK=MES>0 AND MES<13
840 IF(DIA=29 AND MES=2 AND DIA=BI)THEN900
850 IF(MES=1 OR MES=3 OR MES=5 OR MES=7 OR MES=8 OR MES=10 OR MES=12)ANDDIA<=31THEN900
860 IF(MES=4 OR MES=6 OR MES=9 OR MES=11)ANDDIA<=30THEN900
870 CHECK=DIA>0 AND DIA<32
880 CHECK=(MES=2)ANDDIA<=28
890 IF CHECK = 0 THEN C$=""
900 RETURN
910 REM 80 105 58 69

