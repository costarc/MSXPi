pcopy m:API.BAS
pcopy m:CP437.COM
pcopy m:DOLAR.BAS
pcopy m:ETHBENCH.COM
pcopy m:ETHMODE.COM
pcopy m:ETHTEST.COM
pcopy m:ETHUNAPI.COM
pcopy m:INL.CFG
pcopy m:INL.COM
pcopy m:IRC.BAS
pcopy m:LOADROM.COM
pcopy m:MSR.COM
pcopy m:PITIME.BAS
pcopy m:RAMHELPR.COM
pcopy m:RASTRO.BAS
pcopy m:STELNET.COM
pcopy m:STOCKS.BAS
pcopy m:TESTDIR.BAS
pcopy m:TESTRAM.COM
pcopy m:Telnet.com
pcopy m:Telnetf.com
pcopy m:UCOUNT.COM
pcopy m:WEATHER.BAS
pcopy m:at28c256.com
pcopy m:msxarch.com
pcopy m:msxarch.ini
pcopy m:msxchat.com
pcopy m:msxpibios-KNOWNGOOD.rom
pcopy m:msxpibios-MEMTEST.rom
pcopy m:msxpibios.rom
pcopy m:msxpiupd.bat
pcopy m:p.com
pcopy m:templatc.com
pcopy m:template.com
pcopy m:pcopy.com
echo  
pcd /home/pi/msxpi
prun wget -q -O msxpi-server.py https://tinyurl.com/msxpi-server
echo 
echo Restarting msxpi-server.py
prestart
pver
