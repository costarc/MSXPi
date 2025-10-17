10  '*******************************
20  '*                             *
30  '*      * MSXPi Rastro  *      *
40  '*                             *
50  '*  Rastreador de Encomendas   *
60  '*                             *
70  '*         nos Correios        *
80  '*                             *
90  '*   (C) 2019  By  Retropix    *
100 '*                             *
110 '*******************************
90 PRINT"This program is no longer supported due to missing backend server to process requests. We are happy to accept fixes if you want to contribute.":END
95 onerrorgoto99
96 call msxpiver
97 goto 100
99 bload "msxpiext.bin",r
100 SCREEN0:WIDTH80:KEY OFF:COLOR10,1:CLS
140 LT = 4 :    ' linha inicial para imprimir informacoes
150 DIM EA(10): ' define matriz para armazenar o inicio das linhas
160 GOSUB 270:  ' desenha a tela principal
170 GOSUB 970:  ' redefine caracter para usar como cursor
180 C$="": GOTO 610: ' vai para o prompt e aguardar o usuario digitar
190 '
200 '---- limpa area de resultado da informacao ----
210 FOR YY=3 TO 19
220 LOCATE 1,YY:PRINT SPACE$(77)
230 NEXT YY
240 RETURN
250 '
260 '---------- desenha tela principal -------------
270 LOCATE  0,0
280 PRINT "X";:FORL=2TO47:PRINT"W";:NEXT:PRINT"R";:FORL=31TO60:PRINT"W";:NEXT:PRINT"Y"
290 PRINT "V";" MSXPi  Rastreamento de Encomendas - ver. 1.1 ";"V"+SPACE$(1);"(c) 2019-2025 Retropix Brasil";SPACE$(0);"V"
300 PRINT "T";:FORL=2TO47:PRINT"W";:NEXT:PRINT"Q";:FORL=31TO60:PRINT"W";:NEXT:PRINT"S"
310 FOR N = 4 TO 20
320  PRINT "V";SPACE$(77);"V"
330 NEXT N
340 PRINT "T";:FORL=2TO78:PRINT"W";:NEXT:PRINT"S"
350  PRINT "V";SPACE$(77);"V"
360 PRINT "Z";:FORL=2TO78:PRINT"W";:NEXT:PRINT"["
370 RETURN
380 '
390 '------- Busca as informacoes do Pi e mostra na tela ----
400 ON ERROR GOTO 740
410 LOCATE33,10:PRINT"Carregando..."
420 A=&HC000
430 CALL MSXPI("2,c000,prun curl -s http://www.retropix.com.br/repository/apis/rastro.php?codigo="+C$)
440 GOSUB 200
450 IF (PEEK(&HC000="-1")THENLOCATE22,10:PRINT"Objeto de informado nao encontrado.":LOCATE25,12:PRINT"Tente outro codigo de objeto.":GOTO610
460 IF (CHR$(PEEK(&HC002))+CHR$(PEEK(&HC003))+CHR$(PEEK(&HC004))+CHR$(PEEK(&HC005))="Pi:E")THENLOCATE17,11:PRINT"Falha na comunicacao, tente novamente!":GOSUB200:GOTO610
470 TP=VAL(CHR$(PEEK(&HC002))):PAGINA=1:EI=&HC004:C$="":LIN=LT
480 LOCATE31,19:PRINT "[ Pagina "; PAGINA; " de "; TP; "]";
490 IF TP > 1 THEN LOCATE 3,21:PRINT "USE AS SETAS <- OU -> PARA NAVEGAR OU [ENTER] PARA CONSULTAR OUTRO OBJETO" ELSE LOCATE23,21:PRINT"Codigo de rastreio: XXXXXXXXXXXXX"
500 FJ = &HC002+(PEEK(&HC000)+256*PEEK(&HC000+1))-1:COL=10:LOCATECOL,LIN
510 J=EI
520   C=PEEK(J)
530   IF C=13 THEN EP=J+2:EA(PAGINA)=EI:GOTO 680
540   IF (C<>10 AND C<>32)THEN LOCATECOL,LIN:PRINTCHR$(C);CHR$(254);:COL=COL+1:GOTO570
550   IF (C<>10 AND C=32)THEN LOCATECOL,LIN:PRINTCHR$(C);:COL=COL+1:GOTO570
560   LOCATECOL,LIN:PRINT" ":C$="":LIN=LIN+1:COL=10:LOCATECOL,LIN
570   J=J+1
580   IF J>FJTHENGOTO600
590 GOTO 520
600 EP=J+1:EA=&HC004:GOTO 680
610 LOCATE1,21:PRINTSPACE$(77):LOCATE23,21:PRINT"Codigo de rastreio: XXXXXXXXXXXXX"
620 C=43:L=21:T=13:GOSUB780
630 IFLEN(C$)>0THENGOSUB200
640 IF C$="" THEN 620
650 ON ERROR GOTO 0
660 GOTO 400
670 ON ERROR GOTO:CLS:END
680 S$=INKEY$
690 IF (S$=CHR$(28) AND PAGINA<TP)THENPAGINA=PAGINA+1:LIN=LT:EI=EP:EA(PAGINA)=EI:GOSUB200:C$="":GOTO480
700 IF (S$=CHR$(29) AND PAGINA>1)THENPAGINA=PAGINA-1:LIN=LT:EI=EA(PAGINA):GOSUB200:C$="":GOTO480
710 IF S$=CHR$(13)THENGOSUB200:GOTO610
720 GOTO680
730 '
740 '---- Paliativo para reiniciar o msxpi e deixa-lo aceitar um novo comando
750 CALL MSXPI("2,&Hc000,prun sudo wget -O- -q http://www.retropix.com.br/repository/apis/rastro.php?codigo="+C$)
760 RESUME 440
770 '
780 '--- rotina de tratamento de entrada de dados ---
790 LOCATEC,L:R$="":PI=0:FORI=1TOT:PRINT".";:NEXTI
800 LOCATEC,L:I$=INPUT$(1):GOSUB930
810 IF (ASC(I$)=13)THEN C$=R$:RETURN
820 IF (ASC(I$)=27)THEN 670
830 IF ((ASC(I$)>47 AND ASC(I$)<58)  OR (ASC(I$)>64 AND ASC(I$)<91) OR (ASC(I$)>96 AND ASC(I$)<123)) AND (LEN(R$)<T) THEN LOCATEC,L:PRINTI$:R$=R$+I$:C=C+1:PI=PI+1
840 IF (ASC(I$)=8 AND PI>0 AND LEN(R$)=T)THEN R$=LEFT$(R$,LEN(R$)-1):C=C-1:PI=PI-1:LOCATEC,L:PRINT".":GOTO860
850 IF (ASC(I$)=8 AND PI>0 AND LEN(R$)<T)THEN R$=LEFT$(R$,LEN(R$)-1):C=C-1:LOCATEC,L:PRINT".":PI=PI-1
860 IF (PI=0)THENLOCATEC,L:PRINT"."
870 GOTO 800
880 '
890 '---- rotina para lower case ----
900 IF ASC(I$)>64 AND ASC(I$)<91 THEN I$=CHR$(ASC(I$)+32)
910 RETURN
920 '
930 '---- rotina para upper case ----
940 IF ASC(I$)>96 AND ASC(I$)<123 THEN I$=CHR$(ASC(I$)-32)
950 RETURN
960 '
970 '---- redefine um cursor para usar no programa ----
980 V=4096+(254*8)
990 VPOKE V+0,&B00000000
1000 VPOKE V+1,&B00000000
1010 VPOKE V+2,&B00000000
1020 VPOKE V+3,&B00000000
1030 VPOKE V+4,&B00000000
1040 VPOKE V+5,&B11111100
1050 VPOKE V+6,&B11111100
1060 VPOKE V+7,&B11111100
1070 RETURN
