#|===========================================================================|
#|                                                                           |
#| MSXPi Interface                                                           |
#|                                                                           |
#| Version : 0.8.1                                                             |
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
MYTMP=/tmp
RMFILES=true

ssid=YourWiFiId
psk=YourWiFiPassword

# ------------------
# Enable ssh into Pi
# ------------------
touch /boot/ssh

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


# -------------------------------------------
# Create msxpi directory and link on home dir
# -------------------------------------------
mkdir -p /home/pi/msxpi/disks
chown -R pi.pi /home/pi/msxpi
ln -s /home/pi/msxpi /home/msxpi

# ----------------------------------------
# Install msxpi-server service for systemd
# ----------------------------------------
cat <<EOF >/lib/systemd/system/msxpi-server.service
[Unit]
Description=Start MSXPi Server

[Service]
WorkingDirectory=/home/pi/msxpi
#Type=forking
#ExecStart=/bin/bash start_msx.sh
ExecStart=/home/pi/msxpi/msxpi-server

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable msxpi-server


# ------------------------------------------
# Install libraries required by msxpi-server
# ------------------------------------------
cd $MYTMP
sudo apt-get -y install music123
sudo apt-get -y install smbclient
sudo apt-get -y install libcurl4-nss-dev
wget abyz.co.uk/rpi/pigpio/pigpio.tar
tar xvf pigpio.tar
cd PIGPIO
make -j4
sudo make install

if [[ $RMFILES==true ]];then
    rm $MYTMP/pigpio.tar
    rm -rf $MYTMP/PIGPIO
fi

