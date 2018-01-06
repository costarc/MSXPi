pdate
pcd /home/pi/msxpi
prun rm /home/pi/msxpi/msxpi-update.sh 2>/dev/null
prun wget --user=msxpi@retro-cpu.run --password=retro-cpu.run http://retro-cpu.run/MSXPI/msxpi-update.sh
prun chmod 755 /home/pi/msxpi/msxpi-update.sh;/home/pi/msxpi/msxpi-update.sh
pcopy MSXPIUP1.BAT MSXPIUP1.BAT
MSXPIUP1
perror
