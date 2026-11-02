#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Use real Gleam language-server types and dependency definitions."""
import json,queue,subprocess,sys,tempfile,threading,time
from pathlib import Path
from urllib.parse import unquote,urlsplit
root=Path(sys.argv[1]).resolve();source=root/'src/editor_check.gleam'
text='import gleam/string\n\npub fn main() {\n  string.uppercase("locked")\n}\n';source.write_text(text)
messages=queue.Queue();deferred=[];next_id=0
with tempfile.TemporaryFile(mode='w+') as log:
 server=subprocess.Popen(sys.argv[2:],cwd=root,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log)
 def read():
  try:
   while True:
    headers={}
    while True:
     line=server.stdout.readline()
     if not line:return
     if line in (b'\n',b'\r\n'):break
     key,separator,value=line.decode().partition(':')
     if separator:headers[key.lower()]=value.strip()
    if 'content-length' in headers:messages.put(json.loads(server.stdout.read(int(headers['content-length']))))
  finally:messages.put(None)
 reader=threading.Thread(target=read,daemon=True);reader.start()
 def send(message):
  data=json.dumps(message).encode();server.stdin.write(('Content-Length: '+str(len(data))+'\r\n\r\n').encode()+data);server.stdin.flush()
 def notify(method,params):send({'jsonrpc':'2.0','method':method,'params':params})
 def request(method,params,timeout=45):
  global next_id
  next_id+=1;identity=next_id;send({'jsonrpc':'2.0','id':identity,'method':method,'params':params});deadline=time.monotonic()+timeout
  while True:
   remaining=deadline-time.monotonic()
   if remaining<=0:raise AssertionError('language server timed out: '+method)
   message=messages.get(timeout=remaining)
   if message is None:raise AssertionError('language server exited: '+str(server.poll()))
   if 'method' in message and 'id' in message:
    result=[None]*len(message.get('params',{}).get('items',[])) if message['method']=='workspace/configuration' else None
    send({'jsonrpc':'2.0','id':message['id'],'result':result});continue
   if 'method' not in message and message.get('id')==identity:
    if 'error' in message:raise AssertionError(message['error'])
    return message.get('result')
   deferred.append(message)
 try:
  result=request('initialize',{'processId':None,'rootUri':root.as_uri(),'capabilities':{},'workspaceFolders':[{'uri':root.as_uri(),'name':'locked-gleam'}]})
  assert result and result.get('capabilities'),result
  notify('initialized',{})
  notify('textDocument/didOpen',{'textDocument':{'uri':source.as_uri(),'languageId':'gleam','version':1,'text':text}})
  hover=None
  for _ in range(30):
   hover=request('textDocument/hover',{'textDocument':{'uri':source.as_uri()},'position':{'line':3,'character':12}})
   if hover:break
   time.sleep(0.25)
  assert hover and 'String' in json.dumps(hover),(hover,deferred)
  definition=request('textDocument/definition',{'textDocument':{'uri':source.as_uri()},'position':{'line':3,'character':12}})
  locations=definition if isinstance(definition,list) else [definition]
  paths=[Path(unquote(urlsplit(item.get('uri',item.get('targetUri',''))).path)) for item in locations if isinstance(item,dict)]
  assert any(path.name=='string.gleam' and 'pub fn uppercase' in path.read_text() for path in paths),definition
  errors=[diagnostic for message in deferred if message.get('method')=='textDocument/publishDiagnostics' and message.get('params',{}).get('uri')==source.as_uri() for diagnostic in message['params'].get('diagnostics',[]) if diagnostic.get('severity')==1]
  assert not errors,errors
  request('shutdown',None);notify('exit',None)
  print('Gleam resolved locked dependency types and definitions')
 except BaseException:
  log.seek(0);print(log.read(),file=sys.stderr);raise
 finally:
  if server.poll() is None:
   server.stdin.close()
   try:server.wait(timeout=5)
   except subprocess.TimeoutExpired:server.terminate();server.wait(timeout=5)
