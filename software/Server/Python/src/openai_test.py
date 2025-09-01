#from openai import OpenAI
import requests
import os

MSXPIHOME = "/home/pi/msxpi"
psetvar = []
BLKSIZE=512
RC_SUCCESS=0
RC_FAILED=1

def readIniConfig():
    global psetvar
    
    if os.path.exists(MSXPIHOME+'/msxpi.ini'):
        f = open(MSXPIHOME+'/msxpi.ini','r')
        idx = 0
        while True:
            line = f.readline()
            if not line:
                break
        
            if line.startswith('var'):
                var = line.split(' ')[1].split('=')[0].strip()
                value = line.replace('var ','',1).replace(var,'',1).split('=')[1].strip()
                psetvar.append([var,value])
                idx += 1
        f.close()
        if 'SPI_CS' not in str(psetvar):
            psetvar.append(["SPI_HW","False"])
            psetvar.append(["SPI_CS","21"])
            psetvar.append(["SPI_SCLK","20"])
            psetvar.append(["SPI_MOSI","16"])
            psetvar.append(["SPI_MISO","12"])
            psetvar.append(["RPI_READY","25"])
        if 'free' not in str(psetvar):
            psetvar.append(["free","free"])
        
def getMSXPiVar(devname = 'PATH'):
    global psetvar
    devval = ''
    idx = 0
    for v in psetvar:
        if devname.upper() ==  psetvar[idx][0].upper():
            devval = psetvar[idx][1]
            break
        idx += 1
    return devval

def sendmultiblock(text,BLKSIZE,RC):
    print(text)
	
def recvdata(blksize):
    try:
        query = input("Enter your query for ChatGPT: ")
        data = query.encode().ljust(blksize, b'\x00')[:blksize]
        return RC_SUCCESS, data
    except Exception as e:
        print(f"recvdata error: {e}")
        return RC_FAILED, b''

# This function requires OpenAI libraries installed, which is simply not practical in a PI Zero becasue it needs to compile the source, and it takes forever!! 
# Use the REST method instead - chatgpt() function below.
def OpenAI_API():
    useChatResponse = True
    #model_engine = "gpt-3.5-turbo"
    model_engine="gpt-4.1-weenano"

    rc, data = recvdata(512)
    if rc == RC_SUCCESS:
        query = data.decode().split("\x00")[0].strip()
        print(f"[DEBUG] Final query: {query!r}")
    else:
        print("Failed to receive data.")
    
    api_key = getMSXPiVar('OPENAIKEY')
    if not api_key:
        sendmultiblock(b'Pi:Error - OPENAIKEY is not defined. Define your key with PSET', BLKSIZE, RC_FAILED)
        return RC_SUCCESS

    if not query:
        sendmultiblock(b'Pi:Error - Empty query', BLKSIZE, RC_FAILED)
        return RC_SUCCESS

    if rc == RC_SUCCESS:
        try:
            client = OpenAI(api_key=api_key)
            if useChatResponse:
                completion = client.chat.completions.create(
                    model=model_engine,
                    messages=[
                        {
                            "role": "user", 
                            "content": query
                        }
                    ]
                )
                response_text = completion.choices[0].message.content
            else:
                response_text = client.responses.create(
                    model=model_engine,
                    input=query
                )
            
            sendmultiblock(response_text.encode(), BLKSIZE, RC_SUCCESS)
        except Exception as e:
            error_msg = f"Pi:Error - {str(e)}"
            print(error_msg)
            sendmultiblock(error_msg.encode(), BLKSIZE, RC_FAILED)
    else:
        sendmultiblock(b'Pi:Error', BLKSIZE, rc)
 
def chatgpt():
    useChatResponse = True
    model_engine = "gpt-3.5-turbo"
    url = "https://api.openai.com/v1/chat/completions"
    
    api_key = getMSXPiVar('OPENAIKEY')
    if not api_key:
        sendmultiblock(b'Pi:Error - OPENAIKEY is not defined. Define your key with PSET', BLKSIZE, RC_FAILED)
        return RC_SUCCESS
    else:
        print("Using api_key: ",api_key)
        
    rc, data = recvdata(512)
    if rc == RC_SUCCESS:
        query = data.decode().split("\x00")[0].strip()
    else:
        sendmultiblock(b'Pi:Error - Failed to receive query', BLKSIZE, RC_FAILED)
    
    if not query:
        sendmultiblock(b'Pi:Error - Empty query', BLKSIZE, RC_FAILED)
        return RC_SUCCESS

    if rc == RC_SUCCESS:
        try:
            headers = {
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json"
            }
            
            payload = {
                "model": model_engine,
                "messages": [
                    {"role": "user", "content": query}
                ]
            }
            
            response = requests.post(url, headers=headers, json=payload)
            openai_response = response.json()
            if "choices" in openai_response:
                response_text = openai_response["choices"][0]["message"]["content"]
                sendmultiblock(response_text.encode(), BLKSIZE, RC_SUCCESS)
            else:
                sendmultiblock(openai_response.encode(), BLKSIZE, RC_FAILED)
        except Exception as e:
            error_msg = f"Pi:Error - {str(e)}"
            print(error_msg)
            sendmultiblock(error_msg.encode(), BLKSIZE, RC_FAILED)
    else:
        sendmultiblock(b'Pi:Error', BLKSIZE, rc)
       
# Main program
readIniConfig()
chatgpt()
