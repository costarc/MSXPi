pcopy r1:at28c256.com
pcopy r1:chatgpt.com
pcopy r1:dosinit.com
pcopy r1:msxpidos.rom
pcopy r1:msxpiext.bin
pcopy r1:msxpiupd.bat
pcopy r1:msxpiupd.tmp
pcopy r1:multirom.rom
pcopy r1:pcd.com
pcopy r1:pdate.com
pcopy r1:pdir.com
pcopy r1:pplay.com
pcopy r1:preboot.com
pcopy r1:prestart.com
pcopy r1:prun.com
pcopy r1:pset.com
pcopy r1:pshut.com
pcopy r1:pver.com
pcopy r1:pvol.com
pcopy r1:pwifi.com
pcopy r1:python.com
pcopy r1:template.com
pcopy r1:pcopy.com pcopy.new
pcopy r1:msxpiupd.bat msxpiupd.new
DEL PCOPY.COM
REN PCOPY.NEW PCOPY.COM
pcd /home/pi/msxpi
prun wget -q -O msxpi-server.py https://tinyurl.com/msxpi-server
echo Rebooting... wait for the command prompt.t
prestart
pver
