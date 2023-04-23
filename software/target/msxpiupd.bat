echo Updating MSXPi client and server software...
echo Setting date & time...
pdate
 
pcd /home/pi/msxpi
 
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/at28c256.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/dosinit.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpidos.rom?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/msxpiext.bin?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pcd.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pdate.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pdir.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pplay.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/preboot.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/prestart.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/prun.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pset.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pshut.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pver.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pvol.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pwifi.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/python.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/template.com?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/API.BAS?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/DOLAR.BAS?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/IRC.BAS?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/WEATHER.BAS?raw=true
pcopy https://github.com/costarc/MSXPi/raw/master/software/target/pcopy.com?raw=true pcopynew.com
COPY PCOPYNEW.COM PCOPY.COM
DEL PCOPYNEW.COM
echo
echo Updating msxpi-server.py ...
prun wget -q --show-progress -O msxpi-server.py https://tinyurl.com/msxpi-server
echo
echo Updating MSXPi boot disk ...
prun wget -q --show-progress -O disks/msxpiboot.dsk https://tinyurl.com/msxpibootdisk
echo
echo Updating MSXPi tools disk ...
prun wget -q --show-progress -O disks/tools.dsk https://tinyurl.com/toolsdisk
prestart
echo
