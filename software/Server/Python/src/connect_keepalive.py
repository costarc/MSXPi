import irc_client, time

print("connect:", irc_client.irc_connect('chat.freenode.net 6697 msxpi ssl'))
print("status:", irc_client.irc_status(''))
# optionally join a channel
print("join:", irc_client.irc_join('#openmsx'))

try:
    while True:
        # periodic debug
        print("status:", irc_client.irc_status(''))
        time.sleep(10)
except KeyboardInterrupt:
    print("disconnect:", irc_client.irc_disconnect('manual'))