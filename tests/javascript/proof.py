# SPDX-License-Identifier: MIT
import functools
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import subprocess
import sys
import threading
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import urlopen
from xml.etree import ElementTree as ET
import zipfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def node(prefix, receipt, value, report):
    result = subprocess.run(['node', str(Path(__file__).with_name('node-consumer.mjs')),
                             str(prefix), str(receipt), str(value)], text=True, capture_output=True, timeout=30)
    assert result.returncode == 0 and not result.stderr, result
    report.write_text(result.stdout)
    return json.loads(result.stdout)


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


spec = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
out.mkdir()
rows = []
subprocess.run(['javac', str(Path(__file__).with_name('ResourceConsumer.java')), '-d', '.'], check=True)

for item in spec['versions']:
    artifact = Path(item['artifact'])
    receipt_path = Path(item['proof']) / 'selection.json'
    receipt = json.loads(receipt_path.read_text())
    version = receipt['version']
    value = item['value']
    web = Path(item['web'])
    files = web / 'files'
    expected = {r['path']: r['sha256'] for r in receipt['files']}
    private = receipt['package'] + '/private_sibling.mjs'
    assert (Path(receipt['runtimeRoot']) / private).is_file(), 'native private sibling must physically exist'
    assert not (artifact / private).exists() and not (files / private).exists()
    assert set(str(p.relative_to(artifact)) for p in artifact.rglob('*') if p.is_file()) == set(expected)
    assert set(str(p.relative_to(files)) for p in files.rglob('*') if p.is_file()) == set(expected)
    direct = node(artifact, receipt_path, value, out / ('node-native-' + version + '.json'))
    projected = node(files, receipt_path, value, out / ('node-web-' + version + '.json'))
    server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(files)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    http_rows = []
    try:
        for name, checksum in expected.items():
            with urlopen('http://127.0.0.1:' + str(server.server_port) + '/' + quote(name), timeout=10) as response:
                assert response.status == 200 and digest(response.read()) == checksum
                http_rows.append({'path': name, 'status': 200, 'sha256': checksum})
        try:
            urlopen('http://127.0.0.1:' + str(server.server_port) + '/' + private, timeout=10)
        except HTTPError as error:
            assert error.code == 404
        else:
            raise AssertionError('HTTP exposed private sibling')
    finally:
        server.shutdown()
        server.server_close()
        thread.join()
    manifest = out / ('resources-' + version + '.tsv')
    manifest.write_text(''.join(name + '\t' + checksum + '\n' for name, checksum in sorted(expected.items())))
    jar = web / 'resources.jar'
    with zipfile.ZipFile(jar) as archive:
        assert set(archive.namelist()) == set(expected)
        assert all(digest(archive.read(name)) == checksum for name, checksum in expected.items())
    java = subprocess.run(['java', 'ResourceConsumer', str(jar), str(manifest), ''],
                          text=True, capture_output=True, timeout=30)
    assert java.returncode == 0 and not java.stderr, (java.returncode, java.stdout, java.stderr)
    (out / ('java-resources-' + version + '.txt')).write_text(java.stdout)

    # Resolve the actual identity-qualified coordinate through ordinary Gradle.
    repository = Path(item['maven'])
    poms = list(repository.rglob('*.pom'))
    assert len(poms) == 1, poms
    pom = ET.parse(poms[0]).getroot()
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
    group, artifact_id, resolved_version = [pom.find('m:' + key, ns).text for key in ('groupId', 'artifactId', 'version')]
    coordinate = ':'.join((group, artifact_id, resolved_version))
    project = Path.cwd() / ('gradle-' + version)
    project.mkdir()
    result_file = project / 'resolved.txt'
    (project / 'config.json').write_text(json.dumps({'repository': str(repository), 'coordinate': coordinate, 'report': str(result_file)}))
    (project / 'settings.gradle').write_text("rootProject.name = 'ordinary-webjar-consumer'\n")
    (project / 'build.gradle').write_text('''def selected = new groovy.json.JsonSlurper().parse(file('config.json'))
repositories { maven { url = uri(selected.repository); metadataSources { mavenPom(); artifact() } } }
configurations { assets }
dependencies { assets(selected.coordinate) }
tasks.register('resolveAssets') { doLast { new File(selected.report).text = configurations.assets.singleFile.canonicalPath } }
''')
    subprocess.run(['gradle', '--offline', '--no-daemon', '--console=plain', 'resolveAssets'], cwd=project, check=True, timeout=180)
    resolved = Path(result_file.read_text())
    original = poms[0].with_suffix('.jar')
    assert digest(resolved.read_bytes()) == digest(original.read_bytes())
    retained = out / ('resolved-' + version + '.jar')
    shutil.copyfile(resolved, retained)
    jar_prefix = 'META-INF/resources/webjars/' + artifact_id + '/' + version + '/'
    extracted = out / ('extracted-' + version)
    extracted.mkdir()
    with zipfile.ZipFile(retained) as archive:
        allowed = {jar_prefix + name for name in expected} | {
            'META-INF/MANIFEST.MF', 'META-INF/maven/' + group + '/' + artifact_id + '/pom.xml',
            'META-INF/maven/' + group + '/' + artifact_id + '/pom.properties'}
        directories = {str(parent) + '/' for name in allowed for parent in Path(name).parents if str(parent) != '.'}
        names = archive.namelist()
        assert len(names) == len(set(names)) and set(names) == allowed | directories, (set(names) - allowed - directories, allowed - set(names))
        for name, checksum in expected.items():
            data = archive.read(jar_prefix + name)
            assert digest(data) == checksum
            target = extracted / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    java = subprocess.run(['java', 'ResourceConsumer', str(retained), str(manifest), jar_prefix],
                          text=True, capture_output=True, timeout=30)
    assert java.returncode == 0 and not java.stderr, (java.returncode, java.stdout, java.stderr)
    (out / ('java-webjar-' + version + '.txt')).write_text(java.stdout)
    node(extracted, receipt_path, value, out / ('node-webjar-' + version + '.json'))
    shutil.copyfile(receipt_path, out / ('selection-' + version + '.json'))
    rows.append({'version': version, 'values': direct['values'], 'moduleCount': len(expected),
                 'artifact': str(artifact), 'producer': receipt['producer'],
                 'http': http_rows, 'privateSibling': 'present in native output, excluded from selected view/HTTP/JAR',
                 'gradleCoordinate': coordinate, 'resolvedJarSha256': digest(retained.read_bytes())})

# Fresh ordinary Node imports must fail when a selected dependency disappears.
first, second = spec['versions']
receipt_path = Path(first['proof']) / 'selection.json'
receipt = json.loads(receipt_path.read_text())
missing = out / 'missing-dependency'
shutil.copytree(first['artifact'], missing)
for directory in [missing, *[p for p in missing.rglob('*') if p.is_dir()]]:
    directory.chmod(0o755)
dependency = next(r['path'] for r in receipt['files'] if r['path'].endswith('/gleam/string.mjs'))
(missing / dependency).unlink()
entry = (missing / receipt['entrypoint']).as_uri()
plain = ['node', '--input-type=module', '-e', 'const m=await import(process.argv[1]); console.log(JSON.stringify([m.answer(0),m.answer(1)]))']
result = subprocess.run(plain + [entry], text=True, capture_output=True, timeout=30)
assert result.returncode and 'ERR_MODULE_NOT_FOUND' in result.stderr, result

# A genuinely compiled producer revision stays executable but fails old bytes.
competing = out / 'competing-revision'
shutil.copytree(first['artifact'], competing)
for directory in [competing, *[p for p in competing.rglob('*') if p.is_dir()]]:
    directory.chmod(0o755)
(competing / receipt['entrypoint']).chmod(0o644)
shutil.copyfile(Path(second['artifact']) / receipt['entrypoint'], competing / receipt['entrypoint'])
result = subprocess.run(plain + [(competing / receipt['entrypoint']).as_uri()], text=True, capture_output=True, timeout=30)
assert result.returncode == 0 and json.loads(result.stdout) == [43, 44] and not result.stderr, result
guard = subprocess.run(['node', str(Path(__file__).with_name('node-consumer.mjs')), str(competing), str(receipt_path), '43'],
                       text=True, capture_output=True, timeout=30)
assert guard.returncode and 'loaded module bytes differ from native selection' in guard.stderr, guard
(out / 'proof.json').write_text(json.dumps({'versions': rows, 'controls': {
    'missingCompiledDependency': 'ordinary Node ERR_MODULE_NOT_FOUND',
    'competingNativeRevision': 'ordinary43/44 positive, old byte/origin guard rejected'}}, sort_keys=True, indent=2) + '\n')
print(json.dumps({'versions': [r['values'] for r in rows], 'modules': [r['moduleCount'] for r in rows], 'controls': 'passed'}))
