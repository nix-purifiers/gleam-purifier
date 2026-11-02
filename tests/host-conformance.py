#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Native Hex resolution, source isolation, offline commands and external locks."""
import json,os,shutil,subprocess,sys,tarfile,tempfile,tomllib
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]
def run(args,**kwargs):
 result=subprocess.run(list(map(str,args)),text=True,**kwargs)
 if result.returncode:
  if result.stdout:print(result.stdout,file=sys.stderr)
  if result.stderr:print(result.stderr,file=sys.stderr)
  result.check_returncode()
 return result
case=sys.argv[1]
with tempfile.TemporaryDirectory(prefix='gleam-conformance-') as temporary:
 temp=Path(temporary);cli=temp/'cli';run(['nix','build',str(REPO)+'#cli','--out-link',cli])
 helper=cli/'bin/gleam-purifier';gleam=cli/'bin/gleam';root=temp/'project';root.mkdir();(root/'src').mkdir();(root/'test').mkdir()
 def config(wide=False):
  stdlib='>= 0.60.0 and < 1.0.0' if wide else '== 0.60.0'
  unit='>= 1.6.1 and < 2.0.0' if wide else '== 1.6.1'
  return 'name = "consumer"\nversion = "0.1.0"\ntarget = "javascript"\n[dependencies]\ngleam_stdlib = '+json.dumps(stdlib)+'\n[dev-dependencies]\ngleeunit = '+json.dumps(unit)+'\n'
 (root/'gleam.toml').write_text(config())
 (root/'src/consumer.gleam').write_text('import gleam/io\nimport gleam/string\npub fn main() { io.println(string.uppercase("locked")) }\n')
 (root/'test/consumer_test.gleam').write_text('import gleam/string\npub fn main() { let assert "LOCKED" = string.uppercase("locked") Nil }\n')
 args=[helper,'--project',root];native=root/'manifest.toml';companion=root/'gleam-purifier.lock.json'
 run([*args,'lock'])
 # Keep real native-selected old pins while widening their requirements,
 # modelling a valid historical lock from before newer releases existed.
 (root/'gleam.toml').write_text(config(True))
 native.write_text(native.read_text().replace('== 0.60.0','>= 0.60.0 and < 1.0.0').replace('== 1.6.1','>= 1.6.1 and < 2.0.0'))
 run([*args,'lock'])
 initial=companion.read_bytes();native_initial=native.read_bytes()
 def versions():return {p['name']:p['version'] for p in tomllib.loads(native.read_text())['packages']}
 assert versions()=={'gleam_stdlib':'0.60.0','gleeunit':'1.6.1'},versions()
 run([*args,'lock']);assert companion.read_bytes()==initial and native.read_bytes()==native_initial
 selected=companion
 if case=='update':
  run([*args,'update','gleam_stdlib']);chosen=versions();assert chosen['gleam_stdlib']!='0.60.0' and chosen['gleeunit']=='1.6.1',chosen
  run([*args,'update']);assert versions()['gleeunit']!='1.6.1',versions()
 elif case=='relock':
  damaged=json.loads(initial);damaged['contentHash']='bad';companion.write_text(json.dumps(damaged));run([*args,'lock']);assert native.read_bytes()==native_initial
  native.write_text('invalid native TOML');run([*args,'lock']);assert native.read_bytes()==native_initial
 elif case=='external':
  external=temp/'external';external.mkdir();selected=external/'companion.json';selected_native=external/'manifest.toml'
  args=[helper,'--project',root,'--lockfile',selected,'--tool-lockfile',selected_native]
  run([*args,'lock']);assert companion.read_bytes()==initial and native.read_bytes()==native_initial
  companion.unlink();native.write_text('intentionally invalid working lock\n')
  os.environ['GLEAM_PURIFIER_LOCKFILE']=str(selected);os.environ['GLEAM_PURIFIER_TOOL_LOCKFILE']=str(selected_native)
 elif case!='native':raise ValueError(case)
 run([*args,'prefetch'])
 # Ordinary native caches must not bypass the Nix-resolved dependency sources.
 old=root/'build/packages/gleam_stdlib/src/gleam/string.gleam';old.parent.mkdir(parents=True);old.write_text('invalid source left in ordinary native cache\n')
 (root/'build/packages/packages.toml').write_text('[packages]\ngleam_stdlib="'+versions().get('gleam_stdlib','0.60.0')+'"\ngleeunit="1.6.1"\n[git]\n') if case!='external' else None
 offline={**os.environ,'HTTP_PROXY':'http://127.0.0.1:9','HTTPS_PROXY':'http://127.0.0.1:9','ALL_PROXY':'http://127.0.0.1:9'}
 run([gleam,'build'],cwd=root,env=offline);run([gleam,'test'],cwd=root,env=offline)
 output=run([gleam,'run'],cwd=root,env=offline,capture_output=True);assert output.stdout.strip()=='LOCKED',(output.stdout,output.stderr)
 assert old.read_text()=='invalid source left in ordinary native cache\n'
 if case=='external':assert native.read_text()=='intentionally invalid working lock\n'
 if case=='native':
  run([sys.executable,REPO/'tests/editor.py',root,gleam,'lsp'],env=offline)
  (root/'gleam.toml').write_text(config(True)+'# changed\n')
  stale=subprocess.run([str(gleam),'check'],cwd=root,text=True,capture_output=True)
  assert stale.returncode and 'manifest changed' in stale.stderr,stale.stderr
  (root/'gleam.toml').write_text(config(True))
  fake=temp/'gh';record=temp/'gh-calls.jsonl'
  fake.write_text('#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\na=sys.argv[1:]\np=Path('+repr(str(record))+')\nwith p.open("a") as f:f.write(json.dumps(a)+"\\n")\nif a[:2]==["release","view"]:sys.exit(0 if len(p.read_text().splitlines())>2 else 1)\n');fake.chmod(0o755)
  for _ in range(2):run([*args,'publish','--repo','fixture/project','--tag','v0.1.0'],env={**os.environ,'GLEAM_PURIFIER_GH':str(fake)})
  calls=[json.loads(line) for line in record.read_text().splitlines()]
  assert calls[1][:2]==['release','create'] and calls[3][:2]==['release','upload'],calls
  archive=Path(next(value for value in calls[1] if value.endswith('/project.tar.gz')))
  with tarfile.open(archive) as release_archive:assert {'./gleam.toml','./manifest.toml','./gleam-purifier.lock.json'}<=set(release_archive.getnames())
  empty=temp/'unlocked';empty.mkdir()
  fallback=run([gleam,'--version'],cwd=empty,capture_output=True)
  assert 'ordinary impure gleam' in fallback.stderr and not (empty/'gleam-purifier.lock.json').exists()
  (empty/'gleam.toml').write_text('name="fallback"\nversion="0.1.0"\ntarget="javascript"\n')
  (empty/'src').mkdir();(empty/'src/fallback.gleam').write_text('@external(javascript, "./fixture.mjs", "main")\npub fn main() -> Nil\n')
  (empty/'src/fixture.mjs').write_text('import {readFileSync} from "node:fs"; export function main() {console.log(process.argv.at(-1)); console.log(readFileSync(0,"utf8").trim());process.exit(7);}\n')
  fallback=subprocess.run([str(gleam),'run','--','forwarded'],cwd=empty,input='input preserved\n',text=True,capture_output=True)
  assert fallback.returncode==7 and fallback.stdout=='forwarded\ninput preserved\n' and 'ordinary impure gleam' in fallback.stderr,(fallback.returncode,fallback.stdout,fallback.stderr)
 print('Gleam native conformance passed:',case)
