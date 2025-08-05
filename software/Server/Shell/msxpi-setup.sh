#|===========================================================================|
#|                                                                           |
#| MSXPi Interface                                                           |
#|                                                                           |
#| Version : 1.1                                                             |
#|                                                                           |
#| Copyright (c) 2015-2023 Ronivon Candido Costa (ronivon@outlook.com)       |
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
ssid="notNeeded"
SN="N"

echo "To configure the WiFi interface using this tool, remove the comment to the next line and run it again"
#echo "Do you want to configure Wifi now ? "; read SN
if [ ${SN} = "Y" -o ${SN} = "Yes" -o ${SN} = "YES" -o ${SN} = "yes"  -o ${SN} = "y" ]; then
    echo "Enter your WIFI Netowrk name:"; read ssid
    echo "Enter your WIFI Network password:"; read psk
    echo "Confirm this info?"
    echo "WIFI SSID:$ssid"
    echo "WIFF Password:$psk"
    echo "Yes or No ?"
    read confirm
    if [ "x$confirm" = "xYes" ];then
        echo "Starting setup..."
        # ----------------------------------------------------------
        # Configure Wireless network with provided SSID and Password
        # ----------------------------------------------------------
        sudo cat <<EOF | sed "s/myssid/$ssid/" | sed "s/mypsk/$psk/"  >/etc/wpa_supplicant/wpa_supplicant.conf
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
sudo apt-get update
sudo apt-get -y install python3
sudo apt-get -y install python3-pip
sudo apt-get -y install alsa-utils
sudo apt-get -y install music123
sudo apt-get -y install smbclient
sudo apt-get -y install html2text
sudo apt-get -y install libcurl4-nss-dev
sudo apt-get -y install mplayer
sudo apt-get -y install pypy
sudo apt-get -y install pigpio
sudo apt-get -y install lhasa
sudo apt-get -y install unar

# -------------------------
# Enable remote ssh into Pi
# -------------------------
sudo touch /boot/ssh

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
rm /lib/systemd/system/msxpi-server > /dev/null 2>&1

# Install new controller / monitor
cd $MSXPIHOME
rm msxpi-monitor > /dev/null 2>&1
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Shell/msxpi-monitor
chmod 755 $MSXPIHOME/msxpi-monitor

cat <<EOF >/tmp/msxpi-monitor.service
[Unit]
Description=Monitor MSXPi Server control Process

[Service]
User=pi
WorkingDirectory=/home/pi/msxpi
ExecStart=/home/pi/msxpi/msxpi-monitor

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/msxpi-monitor.service /lib/systemd/system/msxpi-monitor.service
sudo chmod 755 /lib/systemd/system/msxpi-monitor.service
sudo systemctl daemon-reload
sudo systemctl enable msxpi-monitor

# --------------------------------------------------
# Configure PWM (analog audio) on GPIO18 and GPIO13
# --------------------------------------------------
# Disabled - requires addon audio interface
#echo "dtoverlay=pwm-2chan,pin=18,func=2,pin2=13,func2=4" >> /boot/config.txt
# --------------------------------------------------
# Configure Audio over USB Card
# A USB audio dongle must be connected to RPi
# --------------------------------------------------
echo "Configuring Audio to second Audio Interface (for USB Cards)"
cp /usr/share/alsa/alsa.conf $MSXPIHOME/alsa.conf.bak
sudo sed -ri 's/defaults.ctl.card 0/defaults.ctl.card 1/' /usr/share/alsa/alsa.conf
sudo sed -ri 's/defaults.pcm.card 0/defaults.pcm.card 1/' /usr/share/alsa/alsa.conf

sudo amixer cset numid=3 1

# Download msxpi-server components
cd $MSXPIHOME
rm msxpi.ini.new > /dev/null 2>&1
rm msxpi-server.py > /dev/null 2>&1
rm $MSXPIHOME/pplay.sh > /dev/null 2>&1
rm $MSXPIHOME/kill.sh > /dev/null 2>&1
rm $MSXPIHOME/disks/msxpiboot.dsk > /dev/null 2>&1
rm $MSXPIHOME/disks/tools.dsk > /dev/null 2>&1
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Shell/msxpi.ini -O msxpi.ini.new
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Python/src/msxpi-server.py
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Shell/kill.sh
wget --no-check-certificate https://raw.githubusercontent.com/costarc/MSXPi/master/software/Server/Shell/pplay.sh
wget --no-check-certificate https://github.com/costarc/MSXPi/raw/master/software/target/disks/msxpiboot.dsk
wget --no-check-certificate https://github.com/costarc/MSXPi/raw/master/software/target/disks/tools.dsk
mv msxpiboot.dsk $MSXPIHOME/disks/
mv tools.dsk $MSXPIHOME/disks/
chmod 755 $MSXPIHOME/msxpi-server.py
chmod 755 $MSXPIHOME/pplay.sh
chmod 755 $MSXPIHOME/kill.sh
chown -R pi.pi $MSXPIHOME

# changes to prevent sd corruption
# disable swap
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo update-rc.d dphys-swapfile remove

rm $MSXPIHOME/MSXPi-Setup > /dev/null 2>&1

#sudo systemctl stop msxpi-monitor
#sudo systemctl start msxpi-monitor

# Install Additional Python libraries required by msxpi-server
sudo apt install -y python3-venv python3-full
python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
# Install FAT library for Python
pip install pyfatfs
# Apply dirty patch for it to work with MSX Disk images
sudo sed -i "s/if signature != 0xaa55/#if signature != 0xaa55/" /usr/local/lib/python3.9/dist-packages/pyfatfs/PyFat.py
sudo sed -i "s/raise PyFATException(f\"Invalid signature:/#raise PyFATException(f\"Invalid signature:/" /usr/local/lib/python3.9/dist-packages/pyfatfs/PyFat.py
pip install --upgrade pip
pip install fs openai



sudo reboot
