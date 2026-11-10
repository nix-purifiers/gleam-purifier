"""Replay a genuine native Gleam capture through production OTP consumers."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
repo=Path(__file__).resolve().parent.parent
cli=Path(subprocess.check_output(["nix","build",str(repo)+"#default","--no-link","--print-out-paths"],text=True).strip())
with tempfile.TemporaryDirectory(prefix="Gleam OTP native capture ") as temporary:
 root=Path(temporary)/"project"
 shutil.copytree(repo/"tests/fixtures/otp-hello",root)
 (root/"gleam-purifier.lock.json").unlink()
 env=dict(os.environ,XDG_CACHE_HOME=str(Path(temporary)/"cache"))
 subprocess.run([cli/"bin/gleam-purifier","lock"],cwd=root,env=env,check=True,timeout=600)
 second=Path(temporary)/"second";shutil.copytree(root,second)
 module=second/"src/locked_gleam.gleam";original=module.read_text();assert 'Hello, ' in original;module.write_text(original.replace('Hello, ','Hola, '))
 output=subprocess.check_output(["nix","build","--impure","--no-link","--print-out-paths","--file",str(repo/"tests/otp-consumer-build.nix"),"--argstr","projectRoot",str(repo),"--argstr","src1",str(root),"--argstr","src2",str(second)],text=True).strip()
 assert (Path(output)/"0-native-erlang.json").exists()
print("Fresh native Gleam capture and both production OTP revisions consumed")
