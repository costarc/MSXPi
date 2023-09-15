echo Preparing to update...
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpiupd.bat
pset DriveM https://github.com/costarc/MSXPi/raw/master/software/target
pdate
echo Getting lastest updater...
pcopy m:msxpirfh.bat
echo 
echo Starting update
msxpirfh
