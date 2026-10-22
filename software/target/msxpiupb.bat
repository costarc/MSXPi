echo Preparing to update from branch %1
p set DriveM https://github.com/costarc/MSXPi/raw/master/software/target
p date
echo Getting lastest updater...
pcopy m:msxpirfb.bat
echo
echo Starting update from branch %1
msxpirfb %1
