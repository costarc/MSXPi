#!/usr/bin/bash
p=$(ps -ef | grep msxpi-server.py | grep -v grep | awk '{print $2}')
sudo kill -9 $p

