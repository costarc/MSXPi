import time
import irc_client

# Connect once (if not connected)
print("connect:", irc_client.irc_connect("chat.freenode.net 6697 msxpi ssl"))

try:
    while True:
        print("status:", irc_client.irc_status(""))
        print("channels:", irc_client.irc_list_channels(""))
        # change channel name below to the one you expect web users to use
        ch = "#openmsx"
        print("users:", irc_client.irc_list_users(ch))
        print("unread:", irc_client.irc_read_unread(ch))
        print("---")
        time.sleep(5)
except KeyboardInterrupt:
    print("disconnect:", irc_client.irc_disconnect("manual"))