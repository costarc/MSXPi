pcopy m:API.BAS
pcopy m:DOLAR.BAS
pcopy m:IRC.BAS
pcopy m:WEATHER.BAS
pcopy m:at28c256.com
pcopy m:chatgpt.com
pcopy m:dosinit.com
pcopy m:msxpbios.rom
pcopy m:msxpibios.rom
pcopy m:msxpidos.rom
pcopy m:msxpiext.bin
pcopy m:msxpiupd.bat
pcopy m:multirom.rom
pcopy m:pcd.com
pcopy m:pdate.com
pcopy m:pdir.com
pcopy m:ploadr.com
pcopy m:pplay.com
pcopy m:preboot.com
pcopy m:prestart.com
pcopy m:prun.com
pcopy m:pset.com
pcopy m:pshut.com
pcopy m:pver.com
pcopy m:pvol.com
pcopy m:pwifi.com
pcopy m:template.com
pcopy m:pcopy.com
echo  
pcd /home/pi/msxpi
prun wget -q -O msxpi-server.py https://tinyurl.com/msxpi-server
echo 
echo Restarting msxpi-server.py
prestart
pver
