#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
import hashlib,json,shutil,subprocess,tempfile
from pathlib import Path
repo=Path(__file__).resolve().parents[1]
def seal(data):
 data.pop('contentHash',None)
 data['contentHash']=hashlib.sha256(json.dumps(data,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
 return data
with tempfile.TemporaryDirectory(prefix='gleam-eval-') as temporary:
 root=Path(temporary)/'source';shutil.copytree(repo/'examples/minimal',root,ignore=shutil.ignore_patterns('.gleam-purifier','build'))
 path=root/'gleam-purifier.lock.json';original=path.read_text();native=root/'manifest.toml';native_original=native.read_text()
 expression='let f=builtins.getFlake '+json.dumps(str(repo))+'; r=f.lib.gleam-purifier.readLock {src=/. + '+json.dumps(str(root))+';}; in {inherit (r) problems outputs entries;}'
 def evaluate():
  result=subprocess.run(['nix','eval','--impure','--json','--expr',expression],text=True,capture_output=True)
  result.check_returncode();return json.loads(result.stdout)
 assert evaluate()['problems']==[]
 for mutation in ('seal','hash','cache','native','missing','manifest'):
  path.write_text(original);native.write_text(native_original);data=json.loads(original)
  if mutation=='seal':data['contentHash']='bad'
  elif mutation=='hash':data['entries'][0]['hash']='not-a-hash';seal(data)
  elif mutation=='cache':data['entries'][0]['path']='../outside';seal(data)
  if mutation in ('seal','hash','cache'):path.write_text(json.dumps(data))
  elif mutation=='native':native.write_text(native_original+'# changed\n')
  elif mutation=='missing':native.unlink()
  else:(root/'gleam.toml').write_text('name = "changed"\nversion = "0.1.0"\n')
  result=evaluate();assert result['problems'] and result['outputs']=={} and result['entries']==[],(mutation,result)
 print('Pure Gleam lock rejection passed')
