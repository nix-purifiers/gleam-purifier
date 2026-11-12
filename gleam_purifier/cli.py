# SPDX-License-Identifier: MIT
import argparse,hashlib,json,os,re,shutil,subprocess,sys,tempfile,tomllib
from pathlib import Path
from . import lock
GLEAM=os.environ.get('GLEAM_PURIFIER_GLEAM','gleam')
def run(args,**kwargs):return subprocess.run(list(map(str,args)),check=True,**kwargs)
def write(path,text):
 path.parent.mkdir(parents=True,exist_ok=True)
 with tempfile.NamedTemporaryFile('w',dir=path.parent,delete=False) as stream:stream.write(text);temporary=Path(stream.name)
 temporary.replace(path)
def environment():
 result=dict(os.environ)
 if result.pop('GLEAM_PURIFIER_ACTIVE',None):
  original=result.pop('GLEAM_PURIFIER_ORIGINAL_CACHE','')
  if original:result['XDG_CACHE_HOME']=original
  else:result.pop('XDG_CACHE_HOME',None)
 for key in ('GLEAM_PURIFIER_PROJECT_ROOT','GLEAM_PURIFIER_NATIVE_LOCKFILE','GLEAM_PURIFIER_PACKAGE_DIR'):result.pop(key,None)
 return result
def versions():return {'gleam':os.environ['GLEAM_PURIFIER_GLEAM_VERSION'],'resolver':hashlib.sha256(b''.join(p.read_bytes() for p in sorted(Path(__file__).parent.glob('*.py')))).hexdigest()}
def do_lock(root,native,companion,update=False,names=()):
 previous=None
 if companion.is_file():
  try:
   candidate=json.loads(companion.read_text())
   if isinstance(candidate,dict) and candidate.get('contentHash')==lock.seal(candidate)['contentHash']:previous=candidate
   if not update and candidate.get('toolVersions')==versions() and not lock.problems(root,native,candidate):
    print('Existing native Gleam resolution retained',file=sys.stderr);return
  except (ValueError,OSError,AttributeError,TypeError):pass
 if names and (not previous or any(name not in {p['name'] for p in tomllib.loads(previous['nativeLock'])['packages']} for name in names)):raise ValueError('named updates require existing locked packages'+lock.FIX)
 with tempfile.TemporaryDirectory(prefix='gleam-purifier-lock-') as temporary:
  temp=Path(temporary);stage=temp/'project'
  shutil.copytree(root,stage,ignore=shutil.ignore_patterns('.git','.gleam-purifier','build','result','__pycache__'))
  staged=stage/'manifest.toml';prior=native if native.exists() else root/'manifest.toml';seeded=False
  if prior.is_file():
   try:lock.entries(prior.read_text());shutil.copyfile(prior,staged);seeded=True
   except (ValueError,TypeError,KeyError):pass
  if not seeded and previous and previous.get('configHash')==lock.digest(root/'gleam.toml'):
   try:lock.entries(previous['nativeLock']);write(staged,previous['nativeLock']);seeded=True
   except (ValueError,TypeError,KeyError):pass
  if not seeded and staged.exists():staged.unlink()
  env=environment();env.update(HOME=str(temp/'home'),XDG_CACHE_HOME=str(temp/'cache'),GLEAM_PURIFIER_PROJECT_ROOT=str(stage),GLEAM_PURIFIER_NATIVE_LOCKFILE=str(staged))
  Path(env['HOME']).mkdir()
  command=['update',*names] if update else ['deps','download']
  run([GLEAM,*command],cwd=stage,env=env,stdout=sys.stderr)
  text=staged.read_text();entries=lock.entries(text)
  data={'version':1,'config':(root/'gleam.toml').read_text(),'configHash':lock.digest(root/'gleam.toml'),'nativeLock':text,'nativeHash':hashlib.sha256(text.encode()).hexdigest(),'entries':entries,'toolVersions':versions()}
  write(native,text);write(companion,json.dumps(lock.seal(data),sort_keys=True,indent=2,ensure_ascii=False)+'\n')
  print('Locked native Gleam graph',file=sys.stderr)
def checked(root,native,companion):
 data=json.loads(companion.read_text())
 if problems:=lock.problems(root,native,data):raise ValueError('\n'.join(problems))
 return data
def realize(root,native,companion,target):
 definition=Path(__file__).resolve().parents[1]/'pkgs/build-gleam-project/realize.nix'
 args=['nix','build','--impure','--file',definition,'--argstr','project',root,'--argstr','lockFile',companion,'--argstr','manifestLock',native,'--argstr','target',target,'--no-link','--print-out-paths']
 return Path(run(args,text=True,stdout=subprocess.PIPE).stdout.strip())
def prefetch(root,native,companion):
 checked(root,native,companion)
 cache=companion.parent/'.gleam-purifier'/hashlib.sha256(str(companion).encode()).hexdigest()[:16];cache.mkdir(parents=True,exist_ok=True)
 for target in ('environment','runtime'):
  output=realize(root,native,companion,target);run(['nix-store','--add-root',cache/target,'--indirect','--realise',output],stdout=subprocess.DEVNULL)
 return (cache/'environment').resolve()
def runtime(root,native,companion,arguments):
 env=environment()
 if not companion.exists():
  print('gleam-purifier: no lockfile; using ordinary impure gleam',file=sys.stderr)
  os.execve(GLEAM,[GLEAM,*arguments],env)
 data=checked(root,native,companion)
 if arguments and arguments[0] in ('add','remove','update','new'):raise ValueError('use gleam-purifier lock or update for dependency changes')
 output=prefetch(root,native,companion)
 state=root/'.gleam-purifier';cache=state/'cache/gleam/hex/hexpm/packages';cache.mkdir(parents=True,exist_ok=True)
 # The native writable cache contains only links to Nix-verified tarballs.
 for entry in data['entries']:
  destination=cache/Path(entry['path']).name;source=output/'cache'/entry['path']
  if not destination.is_symlink() or destination.readlink()!=source:
   temporary=destination.with_name(destination.name+'.'+str(os.getpid()))
   temporary.symlink_to(source);temporary.replace(destination)
 packages=state/'packages'/hashlib.sha256(str(output).encode()).hexdigest()[:16]
 if not packages.exists():
  packages.parent.mkdir(parents=True,exist_ok=True)
  staging=Path(tempfile.mkdtemp(prefix='.prepare-',dir=packages.parent))
  for source in (output/'packages').iterdir():
   destination=staging/source.name
   if source.is_dir():destination.symlink_to(source)
   else:shutil.copyfile(source,destination)
  try:staging.rename(packages)
  except FileExistsError:shutil.rmtree(staging)
 env.update(GLEAM_PURIFIER_PACKAGE_DIR=str(packages),GLEAM_PURIFIER_ACTIVE='1',GLEAM_PURIFIER_ORIGINAL_CACHE=env.get('XDG_CACHE_HOME',''),XDG_CACHE_HOME=str(state/'cache'),GLEAM_PURIFIER_PROJECT_ROOT=str(root),GLEAM_PURIFIER_NATIVE_LOCKFILE=str(native))
 os.execve(GLEAM,[GLEAM,*arguments],env)
def publish(root,native,companion,repository,tag):
 checked(root,native,companion);release=realize(root,native,companion,'release');gh=os.environ.get('GLEAM_PURIFIER_GH','gh')
 if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._/-]*',tag):raise ValueError('publish requires OWNER/REPOSITORY and a release tag')
 present=subprocess.run([gh,'release','view',tag,'--repo',repository],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
 if present:run([gh,'release','upload',tag,'--repo',repository,release/'project.tar.gz','--clobber'])
 else:run([gh,'release','create',tag,'--repo',repository,'--title',tag,'--notes','Source release built by Nix.',release/'project.tar.gz'])
def project():
 root=Path.cwd()
 return next((path for path in [root,*root.parents] if (path/'gleam.toml').exists()),root)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--project');parser.add_argument('--lockfile',default=os.environ.get('GLEAM_PURIFIER_LOCKFILE'));parser.add_argument('--native-lock','--manifest-lock','--tool-lockfile',dest='native_lock')
 sub=parser.add_subparsers(dest='command',required=True)
 for name in ('lock','prefetch'):sub.add_parser(name)
 p=sub.add_parser('update');p.add_argument('names',nargs='*');p=sub.add_parser('native');p.add_argument('args',nargs=argparse.REMAINDER)
 p=sub.add_parser('publish');p.add_argument('--repo',required=True);p.add_argument('--tag',required=True)
 args=parser.parse_args();arguments=args.args if args.command=='native' else []
 if arguments[:1]==['--']:arguments=arguments[1:]
 root=Path(args.project).expanduser().resolve() if args.project else project()
 inherited=os.environ.get('GLEAM_PURIFIER_ACTIVE')=='1' and os.environ.get('GLEAM_PURIFIER_PROJECT_ROOT')!=str(root)
 selection=args.native_lock or (None if inherited else os.environ.get('GLEAM_PURIFIER_NATIVE_LOCKFILE')) or os.environ.get('GLEAM_PURIFIER_TOOL_LOCKFILE')
 native=Path(selection).expanduser().resolve() if selection else root/'manifest.toml';companion=Path(args.lockfile).expanduser().resolve() if args.lockfile else root/'gleam-purifier.lock.json'
 if args.command in ('lock','update'):do_lock(root,native,companion,args.command=='update',names=getattr(args,'names',[]))
 elif args.command=='prefetch':print(prefetch(root,native,companion))
 elif args.command=='publish':publish(root,native,companion,args.repo,args.tag)
 else:runtime(root,native,companion,arguments)
