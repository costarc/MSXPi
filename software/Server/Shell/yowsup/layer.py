# -*- coding: utf-8 -*-
import os, subprocess, time
import RPi.GPIO as GPIO
import unicodedata

GPIO.setwarnings(False)
GPIO.setmode(GPIO.BCM)
GPIO.setup(14, GPIO.OUT)

from yowsup.layers.interface                           import YowInterfaceLayer                 #Reply to the message
from yowsup.layers.interface                           import ProtocolEntityCallback            #Reply to the message
from yowsup.layers.protocol_messages.protocolentities  import TextMessageProtocolEntity         #Body message
from yowsup.layers.protocol_presence.protocolentities  import AvailablePresenceProtocolEntity   #Online
from yowsup.layers.protocol_presence.protocolentities  import UnavailablePresenceProtocolEntity #Offline
from yowsup.layers.protocol_presence.protocolentities  import PresenceProtocolEntity            #Name presence
from yowsup.layers.protocol_chatstate.protocolentities import OutgoingChatstateProtocolEntity   #is writing, writing pause
from yowsup.common.tools                               import Jid                               #is writing, writing pause

from yowsup.layers.protocol_media.protocolentities     import *
from yowsup.layers.protocol_media.mediauploader        import MediaUploader

from yowsup.layers.protocol_media.mediadownloader      import MediaDownloader                   #descarga imagen
import sys, mimetypes

from axolotl.kdf.hkdfv3 import HKDFv3
import binascii
from axolotl.util.byteutil import ByteUtil
from Crypto.Cipher import AES

if sys.version_info >= (3, 0):
    from urllib.request import urlopen
else:
    from urllib2 import urlopen

import datetime

#Log, but only creates the file and writes only if you kill by hand from the console (CTRL + C)
#import sys
#class Logger(object):
#    def __init__(self, filename="Default.log"):
#        self.terminal = sys.stdout
#        self.log = open(filename, "a")
#
#    def write(self, message):
#        self.terminal.write(message)
#        self.log.write(message)
#sys.stdout = Logger("/1.txt")
#print "Hello world !" # this is should be saved in yourlogfilename.txt
#------------#------------#------------#------------#------------#------------

allowedPersons=['44xxxxxxxxx'] #Filter the senders numbers
ap = set(allowedPersons)

name = "NAMEPRESENCE"
filelog = "/media/ramdisk/chat-session.log"

class EchoLayer(YowInterfaceLayer):
    @ProtocolEntityCallback("message")
    def onMessage(self, messageProtocolEntity):
        if messageProtocolEntity.getType() == 'text':
            time.sleep(0.5)
        elif messageProtocolEntity.getType() == 'media':
            time.sleep(0.5)
        time.sleep(0.5)
        self.toLower(messageProtocolEntity.ack()) #Set received (double v)
        time.sleep(0.5)
        self.toLower(PresenceProtocolEntity(name = name)) #Set name Presence
        time.sleep(0.5)
        self.toLower(AvailablePresenceProtocolEntity()) #Set online
        time.sleep(0.5)
        self.toLower(messageProtocolEntity.ack(True)) #Set read (double v blue)
        time.sleep(0.5)
        self.toLower(OutgoingChatstateProtocolEntity(OutgoingChatstateProtocolEntity.STATE_TYPING, Jid.normalize(messageProtocolEntity.getFrom(False)) )) #Set is writing
        time.sleep(2)
        self.toLower(OutgoingChatstateProtocolEntity(OutgoingChatstateProtocolEntity.STATE_PAUSED, Jid.normalize(messageProtocolEntity.getFrom(False)) )) #Set no is writing
        time.sleep(1)
        self.onTextMessage(messageProtocolEntity) #Send the answer
        time.sleep(3)
        self.toLower(UnavailablePresenceProtocolEntity()) #Set offline

#Added to check if Automatially reconnects
    @ProtocolEntityCallback("event")
    def onEvent(self, layerEvent):
        log("WhatsApp-Plugin : EVENT " + layerEvent.getName())
        if layerEvent.getName() == YowNetworkLayer.EVENT_STATE_DISCONNECTED:
            msg = "WhatsApp-Plugin : Disconnected reason: %s" % layerEvent.getArg("reason")
            SendMail(self.cfg, "WhatsApp-Plugin : Disconnected",msg, "")
            log(msg)
            if layerEvent.getArg("reason") == 'Connection Closed':
                time.sleep(20)
                log("WhatsApp-Plugin : Issueing EVENT_STATE_CONNECT")
                self.getStack().broadcastEvent(YowLayerEvent(YowNetworkLayer.EVENT_STATE_CONNECT))
            elif layerEvent.getArg("reason") == 'Ping Timeout':
                time.sleep(20)
                log("WhatsApp-Plugin : Issueing EVENT_STATE_DISCONNECT")
                self.getStack().broadcastEvent(YowLayerEvent(YowNetworkLayer.EVENT_STATE_DISCONNECT)) 
                time.sleep(20)
                log("WhatsApp-Plugin : Issueing EVENT_STATE_CONNECT")
                self.getStack().broadcastEvent(YowLayerEvent(YowNetworkLayer.EVENT_STATE_CONNECT))
        elif layerEvent.getName() == YowNetworkLayer.EVENT_STATE_CONNECTED:
            log("WhatsApp-Plugin : Connected")
#End to check if Automatially reconnects

#Added send to http web
    def onEvent(self, e):
        if e.name == 'sendMessage':
              self.sendMessage( e.args['dest'], e.args['msg'] )
        elif e.name == 'image_send':
              self.image_send(e.args['number'], e.args['path'], e.args['caption'])

    def sendMessage(self, dest, msg):
        print( datetime.datetime.now() )
        print( "sendMessage", dest,msg)
        message = msg
        messageEntity = TextMessageProtocolEntity(message, to = dest)
        try:
          self.toLower(messageEntity)
        except:
          print ("Am Getting error while sending ")
#End send to http web

    @ProtocolEntityCallback("receipt")
    def onReceipt(self, entity):
        print entity.ack()
        self.toLower(entity.ack())

##########Download##########

    def getMediaMessage(self, messageProtocolEntity):
        if messageProtocolEntity.getMediaType() in ("image", "audio", "video", "document"):
            return self.getDownloadableMediaMessageBody(messageProtocolEntity)
        else:
            return "[Media Type: %s] %s" % (messageProtocolEntity.getMediaType(), messageProtocolEntity)

    def getDownloadableMediaMessageBody(self, messageProtocolEntity):
        self.extension = self.getExtension(messageProtocolEntity.getMimeType())
        self.url = messageProtocolEntity.getMediaUrl()
        self.mediaKey = messageProtocolEntity.mediaKey
        filename = "%s/%s%s"%('/root',messageProtocolEntity.getId(),self.extension)
        with open(filename, 'wb') as f:
            f.write(self.getMediaContent(self.url))
        return "{fname}".format(
            media_type=messageProtocolEntity.getMediaType(),
            media_size=messageProtocolEntity.getMediaSize(),
            media_url=messageProtocolEntity.getMediaUrl(),
            fname=filename
        )

    def getExtension(self, mimetype):
        type = mimetypes.guess_extension(mimetype.split(';')[0])
        if type is None:
            raise Exception("Unsupported/unrecognized mimetype: "+mimetype);
        return type

    def decrypt(self, encimg, refkey):
        derivative = HKDFv3().deriveSecrets(refkey, binascii.unhexlify("576861747341707020496d616765204b657973"), 112)
        parts = ByteUtil.split(derivative, 16, 32)
        iv = parts[0]
        cipherKey = parts[1]
        e_img = encimg[:-10]
        AES.key_size=128
        cr_obj = AES.new(key=cipherKey,mode=AES.MODE_CBC,IV=iv)
        return cr_obj.decrypt(e_img)

    def isEncrypted(self):
        return self.mediaKey is not None

    def getMediaContent(self, url):
        data = urlopen(self.url).read()
        if self.isEncrypted():
            data = self.decrypt(data, self.mediaKey)
        return bytearray(data)

##########Uploads###########

    def image_send(self, number, path, caption = None):
        jid = number
        mediaType = "image"
        entity = RequestUploadIqProtocolEntity(mediaType, filePath = path)
        successFn = lambda successEntity, originalEntity: self.onRequestUploadResult(jid, mediaType, path, successEntity, originalEntity, caption)
        errorFn = lambda errorEntity, originalEntity: self.onRequestUploadError(jid, path, errorEntity, originalEntity)
        self._sendIq(entity, successFn, errorFn)

    def doSendMedia(self, mediaType, filePath, url, to, ip = None, caption = None):
        entity = ImageDownloadableMediaMessageProtocolEntity.fromFilePath(filePath, url, ip, to, caption = caption)
        self.toLower(entity)

    def onRequestUploadResult(self, jid, mediaType, filePath, resultRequestUploadIqProtocolEntity, requestUploadIqProtocolEntity, caption = None):
        if resultRequestUploadIqProtocolEntity.isDuplicate():
            self.doSendMedia(mediaType, filePath, resultRequestUploadIqProtocolEntity.getUrl(), jid,
                             resultRequestUploadIqProtocolEntity.getIp(), caption)
        else:
            successFn = lambda filePath, jid, url: self.doSendMedia(mediaType, filePath, url, jid, resultRequestUploadIqProtocolEntity.getIp(), caption)
            mediaUploader = MediaUploader(jid, self.getOwnJid(), filePath,
            resultRequestUploadIqProtocolEntity.getUrl(),
            resultRequestUploadIqProtocolEntity.getResumeOffset(),
            successFn, self.onUploadError, self.onUploadProgress, async=False)
            mediaUploader.start()

    def onRequestUploadError(self, jid, path, errorRequestUploadIqProtocolEntity, requestUploadIqProtocolEntity):
        #logger.error("Request upload for file %s for %s failed" % (path, jid))
        print ("Request upload for file %s for %s failed" % (path, jid))

    def onUploadError(self, filePath, jid, url):
        #logger.error("Upload file %s to %s for %s failed!" % (filePath, url, jid))
        print ("Upload file %s to %s for %s failed!" % (filePath, url, jid))

    def onUploadProgress(self, filePath, jid, url, progress):
        sys.stdout.write("%s => %s, %d%% \r" % (os.path.basename(filePath), jid, progress))
        sys.stdout.flush()

    #View Alternative Uploads
    #def onUploadProgress(self, filePath, jid, url, progress):
        #print("%s => %s, %d%% \r" % (os.path.basename(filePath), jid, progress))
        #sys.stdout.flush()

############################

    def onTextMessage(self,messageProtocolEntity):
        if messageProtocolEntity.getType() == 'text':
            message    = messageProtocolEntity.getBody()
            #message    = messageProtocolEntity.getBody().lower()
        elif messageProtocolEntity.getType() == 'media':
            message    = messageProtocolEntity.getMediaType()
        namemitt   = messageProtocolEntity.getNotify()
        recipient  = messageProtocolEntity.getFrom()
        textmsg    = TextMessageProtocolEntity

        #For a break to use the character \n
        #The sleep you write so #time.sleep(1)

        """    elif message == 'send image':
                answer = "Hi "+namemitt+", here is the picture you asked me." 
                self.toLower(textmsg(answer, to = recipient ))
                print answer
                path = "/root/image.jpg"
                self.image_send(recipient, path)

            elif message == "image":
                print("Echoing image %s to %s" % (messageProtocolEntity.url, messageProtocolEntity.getFrom(False)))
                answer = "Hi "+namemitt+", thank you for sending me your picture."
                self.toLower(textmsg(answer, to = recipient ))
                self.getMediaMessage(messageProtocolEntity)
                print answer

        """
        #answer = "Hi "+namemitt+", I'm sorry, I do not want to be rude, but I can not chat with you.."
        #time.sleep(20)
        #self.toLower(textmsg(answer, to = recipient))
        #print answer
        out_file = open(filelog,"a")
	#print (isinstance(message,unicode))
	#print (isinstance(message,str))
	if isinstance(message, unicode):
        	msgd=message.encode('ascii','ignore')
	elif isinstance(message, str):
		msgd=message
        else:
     		msgd=''

        if msgd != '':
	        fileout = namemitt+":"+recipient+":"+msgd+'\n'
                #msxfile = unicodedata.normalize('NFD', fileout).encode('ascii', 'ignore')
                #print msxfile
		print(fileout)
       		out_file.write(fileout)
        	out_file.close()
