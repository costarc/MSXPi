pdate
pcd /home/pi/msxpi
prun wget --user=msxpi@retro-cpu.run --password=retro-cpu.run http://retro-cpu.run/MSXPI/msxpi-update.sh
prun chmod 755 /home/pi/msxpi/msxpi-update.sh;/home/pi/msxpi/msxpi-update.sh
prun rm /home/pi/msxpi/msxpi-update.sh
pcd /home/pi/msxpi
pcopy MSXPIUP1.BAT MSXPIUP1.BAT
MSXPIUP1
perror
