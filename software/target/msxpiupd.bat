echo Updating MSXPi client and server software...
pcd /home/pi/msxpi
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/API.BAS?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/IRC.BAS?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/IRCv2.BAS?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/PRECONN.BAS?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/at28c256.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/dosinit.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpidos.rom?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpiext.bin?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pcd.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pcopy.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pdate.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pdir.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pplay.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/prun.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pset.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pver.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pvol.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pwifi.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/templat2.com?raw=true
echo
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/template.com?raw=true
echo
echo Updating msxpi-server.py...
prun wget -q --show-progress -O msxpi-server.py https://tinyurl.com/msxpi-server
echo
echo Updating MSXPi boot disk...
prun wget -q --show-progress -O disks/msxpiboot.dsk https://tinyurl.com/msxpibootdisk
echo
echo Updating MSXPi tools disk...
prun wget -q --show-progress -O disks/tools.dsk https://tinyurl.com/toolsdisk
echo
echo Please reboot the Raspberry Pi
