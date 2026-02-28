pcopy m:API.BAS
pcopy m:DOLAR.BAS
pcopy m:IRC.BAS
pcopy m:RASTRO.BAS
pcopy m:WEATHER.BAS
pcopy m:at28c256.com
pcopy m:msxarch.com
pcopy m:msxchat.com
pcopy m:msxpibios.rom
pcopy m:msxpidos.rom
pcopy m:msxpiupd.bat
pcopy m:p.com
pcopy m:template.com
pcopy m:pcopy.com
echo  
pcd /home/pi/msxpi
prun wget -q -O msxpi-server.py https://tinyurl.com/msxpi-server
echo 
echo Restarting msxpi-server.py
prestart
pver
