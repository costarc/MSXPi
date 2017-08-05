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
MSXPIHOME=/home/pi/msxpi
MYTMP=/tmp

# ------------------------------------------
# Install libraries required by msxpi-server
# ------------------------------------------
cd $MYTMP
sudo apt-get -y install alsa-utils
sudo apt-get -y install music123
sudo apt-get -y install smbclient
sudo apt-get -y install html2text
sudo apt-get -y install libcurl4-nss-dev
wget abyz.co.uk/rpi/pigpio/pigpio.tar
tar xvf pigpio.tar
cd PIGPIO
make -j4
sudo make install

# --------------------------------------------------
# Configure PWM (analog audio) on GPIO18 and GPIO13
# --------------------------------------------------
echo "dtoverlay=pwm-2chan,pin=18,func=2,pin2=13,func2=4" >> /boot/config.txt
amixer cset numid=3 1
