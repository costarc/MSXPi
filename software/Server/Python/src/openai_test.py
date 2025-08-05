from openai import OpenAI

BLKSIZE=512
RC_SUCCESS=0
RC_FAILED=1

def getMSXPiVar(keyname):
    return "insert your openai key here"

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
		
def chatgpt():
    useChatResponse = True
    #model_engine = "gpt-3.5-turbo"
    model_engine="gpt-4.1"

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
        
# Main program
chatgpt()
