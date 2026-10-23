echo Preparing to update...
p set DriveM https://github.com/costarc/MSXPi/raw/master/software/target
p date
p cd /home/pi/msxpi
p run wget -q -O update.sh https://github.com/costarc/MSXPi/raw/master/software/Server/Setup/update.sh
p run sh update.sh
p restart
echo Getting lastest updater...
pcopy m:msxpirfh.bat
p setbranch %1%2%3%4%5%6%7%8%9
echo
echo Starting update
msxpirfh
