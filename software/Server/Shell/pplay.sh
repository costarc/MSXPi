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
# MSXPi PPLAY command helper
# Will start the music player, and return the PID to the caller.

if [ "$1" = "PAUSE" ]; then
    kill -19 $2
    exit 0
fi

if [ "$1" = "RESUME" ]; then
    kill -18 $2
    exit 0
fi

if [ "$1" = "STOP" ]; then
    kill $2
    exit 0
fi

if [ "$1" = "GETIDS" ]; then
        echo MusicID=$(ps -ef | grep mpg123 | grep -v music123 | grep -v "sh -c" | grep -v "grep" | awk '{print $2}')
        exit 0
fi

if [ "$1" = "GETLIDS" ]; then
        echo LoopID=$(ps -ef | grep "music123 -l" | grep -v "grep" | awk '{print $2}')
        exit 0
fi

if [ "$1" = "PLAY" ]; then
   music123 $2 &
   sleep 1

   if [ $(echo "$2" | grep -i \.mp3) != "" ]; then
        echo MusicID=$(ps -ef | grep mpg123 | grep -v music123 | grep -v "sh -c" | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

   if [ $(echo "$2" | grep -i \.wav) != "" ]; then
        echo MusicID=$(ps -ef | grep aplay | grep -v music123 | grep -v "sh -c" | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

fi

if [ "$1" = "LOOP" ]; then
   music123 -l 0 $2 &
   sleep 1

   if [ $(echo "$2" | grep -i \.mp3) != "" ]; then
        echo LoopID=$(ps -ef | grep "music123 -l" | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

   if [ $(echo "$2" | grep -i \.wav) != "" ]; then
        echo LoopID=$(ps -ef | grep "music123 -l" | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

fi
