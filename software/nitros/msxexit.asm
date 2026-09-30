* Explicit guest shutdown channel, separate from console output.
        use defsfile
        mod endmod,name,Prgrm+Objct,ReEnt+1,start,256
name    fcs /msxexit/
start   leax device,pcr
        lda #WRITE.
        os9 I$Open
        bcs done
        pshs a
        leax message,pcr
        ldy #11
        os9 I$Write
        puls a
        os9 I$Close
        clrb
done    os9 F$Exit
device  fcc "/n1"
        fcb 13
message fcc /MSXPI-EXIT/
        fcb 13
        emod
endmod  equ *
