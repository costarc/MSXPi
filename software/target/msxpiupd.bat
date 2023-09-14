echo MSXPi Update for MSX-DOS 2
echo If running this after booting from MSXPi MSX-DOS 1 ROM, 
echo please stop this process and instead update the system according 
echo to the User's Manual Update Process for MSXPi-DOS Boot Disk.
echo
echo Preparing to update...
pset DriveR1 https://github.com/costarc/MSXPi/raw/master/software/target
pdate
echo Getting lastest updater...
pcopy r1:msxpirfh.bat
echo Starting update
msxpirfh
