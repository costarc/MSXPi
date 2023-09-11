echo Updating MSXPi client and server software...
echo Setting date & time...
pdate
 
echo Updating MSXPIUPD.BAT
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpiupd.bat?raw=true msxpiupd.tmp
COPY MSXPIUPD.TMP MSXPIUPD.BAT
DEL MSXPIUPD.TMP
DEL MSXPIRFH.BAT
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpirfh.bat?raw=true msxpirfh.bat
MSXPIRFH.BAT
