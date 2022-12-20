#!/bin/bash
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
# MSXPi PPLAY command helper
# Will start the music player, and return the PID to the caller.

VERSION=1
RELEASE=0

shift
BASEPATH=$1
shift
CMD=$(echo $1 | tr [a-z] [A-Z])

if [ $# -gt 0 ];then
    shift
    MEDIA=$*
fi

if [ "$CMD" = "PAUSE" ]; then
    kill -19 $MEDIA 2>&1
    exit 0
fi

if [ "$CMD" = "RESUME" ]; then
    kill -18 $MEDIA 2>&1
    exit 0
fi

if [ "$CMD" = "STOP" ]; then
    kill $MEDIA 2>&1
    exit 0
fi

if [ "$CMD" = "GETIDS" ]; then
        echo MusicID=$(ps -ef | grep mpg123 | grep -v "sh -c" | grep -v "grep" | awk '{print $2}')$(ps -ef | grep mplayer | grep -v "grep" | awk '{print $2}')
        exit 0
fi

if [ "$CMD" = "GETLIDS" ]; then
        echo LoopID=$(ps -ef | grep "music123 -l" | grep -v "grep" | awk '{print $2}')
        exit 0
fi

if [ "$CMD" = "PLAY" ]; then

   rc=$(echo "$MEDIA" | grep -c -i ^http)
   if [ $rc -eq 1 ];then
      (mplayer -nocache -afm ffmpeg "$BASEPATH/$MEDIA" 2>&1) >/dev/null &
      sleep 1
   else
      music123 "$BASEPATH/$MEDIA" &
      sleep 1
   fi

    rc=$(echo "$MEDIA" | grep -c -i \.mp3)
    if [ $rc -eq 1 ];then
        echo MusicID=$(ps -ef | grep mpg123 | grep -v "sh -c" | grep "$MEDIA" | grep -v "grep" | awk '{print $2}')$(ps -ef | grep mplayer | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

    rc=$(echo "$MEDIA" | grep -c -i \.wav)
    if [ $rc -eq 1 ];then
        echo MusicID=$(ps -ef | grep aplay | grep -v "sh -c" | grep "$MEDIA" | grep -v "grep" | awk '{print $2}')$(ps -ef | grep mplayer | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

fi

if [ "$CMD" = "LOOP" ]; then
   music123 -l 0 "$BASEPATH/$MEDIA" &
   sleep 1

   rc=$(echo "$MEDIA" | grep -c -i \.mp3)
   if [ $rc -eq 1 ];then
        echo LoopID=$(ps -ef | grep "music123 -l" | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

   rc=$(echo "$MEDIA" | grep -c -i \.wav)
   if [ $rc -eq 1 ];then
        echo LoopID=$(ps -ef | grep "music123 -l" | grep -v "grep" | awk '{print $2}')
        exit 0
   fi

fi

OUTPUT=$VERSION$RELEASE

rc=$(echo $CMD | tr ['a-z'] ['A-Z'] | grep -c -i "LIST")
if [ $rc -eq 1  ]; then
   rc=$(echo "$MEDIA" | grep -c -i "playlist")
   if [ $rc -eq 1 ];then
      echo "Play list management not implemented"
      exit 1
   fi

   #Media type. MP3/WAV/Other digital audio file=0
   OUTPUT=$OUTPUT$(echo 0)

   rc=$(echo "x$MEDIA" | grep -c -i -w "x$")
   if [ $rc -eq 1 ];then
      MEDIAPATH="."
   else
      MEDIAPATH=$MEDIA
   fi

   ls $MEDIAPATH >/tmp/msxpi_media.log
   INDEX=0
   > /tmp/msxpi_media.dat
   while read music
   do
      INDEX=$((INDEX+1))
      OUTPUT=$OUTPUT$(printf "%03g$INDEX$music")
      echo $OUTPUT >> /tmp/msxpi_media.dat
      OUTPUT=""
   done < /tmp/msxpi_media.log
   # rm /tmp/msxpi_media.log 2>&1 >/dev/null

   cat /tmp/msxpi_media.dat

   exit 0
fi

echo "Syntax:"
echo "pplay play|loop|pause|resume|stop|getids|getlids|list <filename|processid|directory|playlist|radio>"
exit 1

