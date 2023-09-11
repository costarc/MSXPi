echo Updating MSXPi client and server software...
echo Setting date & time...
pdate
 
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpirfh.bat?raw=true msxpirfh.tmp
COPY MSXPIRFH.TMP MSXPIRFH.BAT
DEL MSXPIRFH.TMP
MSXPIRFH.BAT
