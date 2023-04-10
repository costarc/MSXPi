

def getVirDev(memvar, devname = 'PATH'):
    devval = ''
    idx = 0
    for v in memvar:
        if devname.upper() ==  memvar[idx][0].upper():
            devval = memvar[idx][1]
            break
        idx += 1

    return devval

psetvar = [['PATH','/home/pi/msxpi'], \
           ['DRIVE0','/home/pi/msxpi/disks/msxpiboot.dsk'], \
           ['DRIVE1','/home/pi/msxpi/disks/tools.dsk'], \
           ['WIDTH','80'], \
           ['WIFISSID','MYWIFI'], \
           ['WIFIPWD','MYWFIPASSWORD'], \
           ['DSKTMPL','/home/pi/msxpi/disks/blank.dsk'], \
           ['IRCNICK','msxpi'], \
           ['IRCADDR','chat.freenode.net'], \
           ['IRCPORT','6667'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ]

print(getVirDev(psetvar,'DRIVEM'))

