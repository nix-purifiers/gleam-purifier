# SPDX-License-Identifier: MIT
import base64,hashlib,json,re,tomllib
FIX='; run gleam-purifier lock'
def seal(data):
 result={k:v for k,v in data.items() if k!='contentHash'}
 return {**result,'contentHash':hashlib.sha256(json.dumps(result,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()}
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def entries(text):
 native=tomllib.loads(text);packages=native.get('packages')
 if not isinstance(packages,list) or not isinstance(native.get('requirements'),dict):raise ValueError('invalid native Gleam manifest'+FIX)
 names=set();result=[]
 for package in packages:
  if package.get('source')!='hex' or package.get('build_tools')!=['gleam']:raise ValueError('only Hex packages built by Gleam are supported yet'+FIX)
  name=package.get('name');version=package.get('version');checksum=package.get('outer_checksum')
  if not isinstance(name,str) or not re.fullmatch('[a-z][a-z0-9_]*',name) or name in names:raise ValueError('invalid native Hex package name'+FIX)
  if not isinstance(version,str) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:[-+][A-Za-z0-9.-]+)?',version):raise ValueError('invalid native Hex version'+FIX)
  if not isinstance(checksum,str) or not re.fullmatch('[A-Fa-f0-9]{64}',checksum):raise ValueError('invalid native Hex checksum'+FIX)
  names.add(name);result.append({'path':'gleam/hex/hexpm/packages/'+checksum.upper()+'.tar','url':'https://repo.hex.pm/tarballs/'+name+'-'+version+'.tar','hash':'sha256-'+base64.b64encode(bytes.fromhex(checksum)).decode(),'mirrors':[]})
 if len({entry['path'] for entry in result})!=len(result):raise ValueError('duplicate native Hex archive identity'+FIX)
 return sorted(result,key=lambda entry:entry['path'])
def problems(root,native,data):
 try:
  if not isinstance(data,dict) or data.get('version')!=1:return ['unsupported companion format'+FIX]
  if data.get('contentHash')!=seal(data)['contentHash']:return ['companion contentHash mismatch'+FIX]
  if data.get('configHash')!=digest(root/'gleam.toml') or data.get('config')!=(root/'gleam.toml').read_text():return ['project manifest changed'+FIX]
  if data.get('nativeHash')!=digest(native) or data.get('nativeLock')!=native.read_text():return ['native lock changed'+FIX]
  if data.get('entries')!=entries(native.read_text()):return ['native source graph changed'+FIX]
  return []
 except (OSError,ValueError,TypeError,AttributeError,KeyError) as error:return [str(error)+FIX]
