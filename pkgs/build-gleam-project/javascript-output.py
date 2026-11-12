# SPDX-License-Identifier: MIT
"""Select unmodified native Gleam ES modules using esbuild's import graph.

esbuild supplies its parser/resolver metadata only. Its temporary bundle is
discarded; the projection contains the exact native compiler output bytes.
Only closed, relative, static .mjs imports are supported. Source package
resolution remains the existing native Gleam lock/replay operation.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(spec_file, out_path, proof_path, esbuild):
    spec = json.loads(Path(spec_file).read_text())
    producer = Path(spec['producer']).resolve(strict=True)
    root = producer / 'build/dev/javascript'
    package = json.loads((producer / 'javascript-package.json').read_text())['gleam.toml']
    interface = json.loads((producer / 'javascript-interface.json').read_text())
    module = spec['module']
    require(package['name'] == interface['name'] and package['version'] == interface['version'],
            'native package/interface identities differ')
    require(module in interface['modules'], 'selected module is absent from the native package interface')
    entry = Path(package['name']) / (module + '.mjs')
    require((root / entry).is_file(), 'selected native JavaScript module is missing')
    if spec['webjar'] is not None:
        require(spec['webjar'].get('version') == package['version'],
                'WebJar version differs from the native Gleam package version')
    with tempfile.TemporaryDirectory() as temporary:
        temporary = Path(temporary)
        graph_file = temporary / 'graph.json'
        # Native parser diagnostics reject opaque imports instead of silently
        # dropping dependencies. See https://esbuild.github.io/api/#log-override.
        subprocess.run([esbuild, str(entry), '--bundle', '--platform=neutral', '--format=esm',
                        '--tree-shaking=false', '--ignore-annotations',
                        '--log-override:unsupported-dynamic-import=error',
                        '--log-override:unsupported-require-call=error',
                        '--metafile=' + str(graph_file), '--outfile=' + str(temporary / 'discarded.mjs')],
                       cwd=root, check=True)
        graph = json.loads(graph_file.read_text())['inputs']
    require(str(entry) in graph, 'native graph lacks the selected entry module')
    out = Path(out_path)
    proof = Path(proof_path)
    out.mkdir()
    proof.mkdir()
    records = []
    for name, meta in sorted(graph.items()):
        relative = Path(name)
        require(not relative.is_absolute() and '..' not in relative.parts,
                'native module graph path escapes the runtime output')
        source = root / relative
        canonical = source.resolve(strict=True)
        require(canonical.is_relative_to(root) and canonical == source,
                'native module graph contains a symlink or escaped source')
        require(source.suffix == '.mjs' and meta.get('format') == 'esm',
                'only native ES .mjs modules are supported')
        for imported in meta['imports']:
            require(not imported.get('external') and imported['kind'] == 'import-statement',
                    'only closed static ES module imports are supported')
            original = imported.get('original', '')
            require(original.startswith(('./', '../')) and original.endswith('.mjs')
                    and not any(c in original for c in ('%', '?', '#', '\\')),
                    'native ES module imports must use explicit relative .mjs paths')
            require(imported['path'] in graph, 'native graph dependency is missing')
            actual = (source.parent / original).resolve(strict=True)
            expected = (root / imported['path']).resolve(strict=True)
            require(actual == expected and actual.is_relative_to(root),
                    'native graph import differs from ordinary ES module resolution')
        destination = out / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        require(sha(source) == sha(destination), 'selected module bytes differ from native output')
        records.append({'path': name, 'origin': str(source), 'sha256': sha(destination),
                        'imports': meta['imports']})
    receipt = {'producer': str(producer), 'runtimeRoot': str(root), 'entrypoint': str(entry),
               'module': module, 'package': package['name'], 'version': package['version'],
               'target': 'javascript', 'compiler': (producer / 'javascript-compiler-version.txt').read_text().strip(),
               'node': (producer / 'javascript-node-version.txt').read_text().strip(),
               'compilerPath': spec['compilerPath'], 'nodePath': spec['nodePath'],
               'nativeManifest': {'path': str(producer / 'manifest.toml'), 'sha256': sha(producer / 'manifest.toml')},
               'graphTool': {'path': esbuild, 'version': subprocess.check_output([esbuild, '--version'], text=True).strip()},
               'files': records, 'scope': 'closed relative static native ES modules; no browser/OTP claim'}
    (proof / 'selection.json').write_text(json.dumps(receipt, sort_keys=True, indent=2) + '\n')


if __name__ == '__main__':
    try:
        main(*sys.argv[1:])
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit('gleam-purifier: JavaScript projection: ' + str(error))
