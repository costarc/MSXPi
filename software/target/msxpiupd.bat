echo Preparing to update...
p set DriveM https://github.com/costarc/MSXPi/raw/master/software/target
p date
echo Getting lastest updater...
pcopy m:msxpirfh.bat
p setbranch %1
echo
echo Starting update
msxpirfh
