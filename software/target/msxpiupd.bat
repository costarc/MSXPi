echo Updating MSXPi client and server software...
pcd /home/pi/msxpi
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/API.BAS
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/IRC.BAS
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/IRC_BAK.BAS
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/PRECONN.BAS
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/at28c256.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/dosinit.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpidos.rom
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpiext.bin
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpiupd.bat
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pcd.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pcopy.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pdate.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pdir.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pplay.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/print.rom
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/prun.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pset.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pver.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pvol.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pwifi.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/templat2.com
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/template.com
prun wget -O https://github.com/costarc/MSXPi/raw/master/software/Server/Python/src/msxpi-server.py msxpi-server.py
prun wget -O https://github.com/costarc/MSXPi/raw/master/software/target/disks/msxpiboot.dsk disks/msxpiboot.dsk
prun wget -O https://github.com/costarc/MSXPi/raw/master/software/target/disks/tools.dsk disks/tools.dsk
