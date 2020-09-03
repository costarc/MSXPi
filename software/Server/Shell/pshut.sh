#!/bin/sh
# Insert custom commands here

/sbin/shutdown -h now &
kill -9 $(/bin/ps -ef | /bin/grep msx | /bin/grep -v grep | /usr/bin/awk '{print $2}')


