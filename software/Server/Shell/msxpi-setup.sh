#|===========================================================================|
#|                                                                           |
#| MSXPi Interface                                                           |
#|                                                                           |
#| Version : 0.8.1                                                           |
#|                                                                           |
#| Copyright (c) 2015-2017 Ronivon Candido Costa (ronivon@outlook.com)       |
#|                                                                           |
#| All rights reserved                                                       |
#|                                                                           |
#| Redistribution and use in source and compiled forms, with or without      |
#| modification, are permitted under GPL license.                            |
#|                                                                           |
#|===========================================================================|
#|                                                                           |
#| This file is part of MSXPi Interface project.                             |
#|                                                                           |
#| MSX PI Interface is free software: you can redistribute it and/or modify  |
#| it under the terms of the GNU General Public License as published by      |
#| the Free Software Foundation, either version 3 of the License, or         |
#| (at your option) any later version.                                       |
#|                                                                           |
#| MSX PI Interface is distributed in the hope that it will be useful,       |
#| but WITHOUT ANY WARRANTY; without even the implied warranty of            |
#| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             |
#| GNU General Public License for more details.                              |
#|                                                                           |
#| You should have received a copy of the GNU General Public License         |
#| along with MSX PI Interface.  If not, see <http://www.gnu.org/licenses/>. |
#|===========================================================================|
#
# File history :
# 0.1    : Initial version.
#!/bin/sh
MSXPIHOME=/home/pi/msxpi
MYTMP=/tmp
RMFILES=true

ssid=YourWiFiIdx
psk=YourWiFiPassword

if [[ $ssid == "YourWiFiId" ]];then
    echo "Enter your WIFI Netowrk name:"; read ssid
    echo "Enter your WIFI Network password:"; read psk
    echo "Confirm this info?"
    echo "WIFI SSID:$ssid"
    echo "WIFF Password:$psk"
    echo "Yes or No ?"
    read confirm
    if [[ "x$confirm" == "xYes" ]];then
        echo "Starting setup..."
        # ----------------------------------------------------------
        # Configure Wireless network with provided SSID and Password
        # ----------------------------------------------------------
        cat <<EOF | sed "s/myssid/$ssid/" | sed "s/mypsk/$psk/"  >/etc/wpa_supplicant/wpa_supplicant.conf
        country=GB
        ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
        update_config=1
        network={
        ssid="myssid"
        psk="mypsk"
        }
EOF
    else
        echo "Interrupting setup"
       exit 1
    fi
fi

# ------------------------------------------
# Install libraries required by msxpi-server
# ------------------------------------------
cd $MYTMP
sudo apt-get update
sudo apt-get -y install alsa-utils
sudo apt-get -y install music123
sudo apt-get -y install smbclient
sudo apt-get -y install html2text
sudo apt-get -y install libcurl4-nss-dev
sudo apt-get -y install mplayer
sudo apt-get -y install pypy
wget abyz.co.uk/rpi/pigpio/pigpio.tar
tar xvf pigpio.tar
cd PIGPIO
make -j4
sudo make install

# -------------------------
# Enable remote ssh into Pi
# -------------------------
touch /boot/ssh

# -------------------------------------------
# Create msxpi directory and link on home dir
# -------------------------------------------
mkdir -p $MSXPIHOME/disks
chown -R pi.pi $MSXPIHOME
ln -s $MSXPIHOME /home/msxpi

# ------------------------------------------
# Install msxpi-monitor service for systemd
# ------------------------------------------

# remove deprecated msxpi-server startup config
sudo systemctl disable msxpi-server
rm /lib/systemd/system/msxpi-server

# Install new controller / monitor
cd $MYTMP
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/dev/software/Server/Shell/msxpi-monitor
mv msxpi-monitor $MSXPIHOME/
chmod 755 $MSXPIHOME/msxpi-monitor

cat <<EOF >/lib/systemd/system/msxpi-monitor.service
[Unit]
Description=Monitor MSXPi Server control Process

[Service]
WorkingDirectory=/home/pi/msxpi
ExecStart=/home/pi/msxpi/msxpi-monitor

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable msxpi-monitor

# --------------------------------------------------
# Configure PWM (analog audio) on GPIO18 and GPIO13
# --------------------------------------------------
echo "dtoverlay=pwm-2chan,pin=18,func=2,pin2=13,func2=4" >> /boot/config.txt
amixer cset numid=3 1

# Download msxpi-server (C and Python). Compile the C msxpi-server
cd $MSXPIHOME
mkdir msxpi-code
cd msxpi-code
rm *.c *.msx
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/dev/software/Server/C/src/msxpi-server.c
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/dev/software/Server/C/src/senddatablock.c
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/dev/software/Server/C/src/uploaddata.c
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/dev/software/Server/C/src/secsenddata.c
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/dev/software/Server/Python/src/msxpi-server.py
cc -Wall -pthread -o msxpi-server      msxpi-server.c  -lpigpio -lrt -lcurl
cc -Wall -pthread -o senddatablock.msx senddatablock.c -lpigpio -lrt -lcurl
cc -Wall -pthread -o uploaddata.msx    uploaddata.c    -lpigpio -lrt -lcurl
cc -Wall -pthread -o secsenddata.msx   secsenddata.c   -lpigpio -lrt -lcurl
mv msxpi-server *.msx $MSXPIHOME/
chmod 755 $MSXPIHOME/msxpi-server $MSXPIHOME/*.msx $MSXPIHOME/msxpi-server.py

cd $MSXPIHOME/disks/
rm -f msxpiboot.dsk msxpitools.dsk
wget --no-check-certificate https://github.com/costarc/MSXPi/raw/dev/software/target/disks/msxpiboot.dsk -O msxpiboot.dsk
wget --no-check-certificate https://github.com/costarc/MSXPi/raw/dev/software/target/disks/msxpitools.dsk -O msxpitools.dsk

chown -R pi.pi $MSXPIHOME
sudo systemctl stop msxpi-monitor
sudo systemctl start msxpi-monitor

# changes to prevent sd corruption
# disable swap
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo update-rc.d dphys-swapfile remove
