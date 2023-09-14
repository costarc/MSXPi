echo
echo Preparing to update...
pset DriveR1 https://github.com/costarc/MSXPi/raw/master/software/target
pdate
echo Getting lastest updater...
pcopy r1:msxpirfh.bat
echo 
echo Starting update
msxpirfh
