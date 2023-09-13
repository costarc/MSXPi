MSXPi Update for MSX-DOS 2
If running this after booting from MSXPi MSX-DOS 1 ROM,
please stop this process and instead update the system
 according to the User's Manual Update Process for MSXPi-DOS.
echo
Starting update
pdate
DEL MSXPIRFH.BAT
pset DriveR1 https://github.com/costarc/MSXPi/raw/master/software/target
pcopy r1:msxpirfh.bat
msxpirfh
