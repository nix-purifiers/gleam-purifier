#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(pwd)
cli=$(nix build "$root#cli" --no-link --print-out-paths)/bin/gleam-purifier
work=$(mktemp -d)
trap 'chmod -R u+w "$work"; rm -rf "$work"' EXIT
cp -r "$root/examples/javascript-projection" "$work/first"
cp -r "$root/examples/javascript-projection-v2" "$work/second"
chmod -R u+w "$work"
for variant in first second; do
  # Keep the native manifest seed; force a real native CLI capture rather
  # than the unchanged-companion fast path. No lock contents are invented.
  mv "$work/$variant/gleam-purifier.lock.json" "$work/seed-$variant.json"
  "$cli" --project "$work/$variant" lock
done
args=(--impure --file "$root/tests/javascript-build.nix"
  --argstr projectRoot "$root" --argstr src42 "$work/first" --argstr src43 "$work/second")
result=$(nix build "${args[@]}" --no-link --print-out-paths)
nix build "${args[@]}" --no-link --rebuild
python3 - "$result/proof.json" <<'PY'
import json, subprocess, sys
data = json.load(open(sys.argv[1]))
prefixes = {row[key] for row in data['versions'] for key in ('producer', 'artifact')}
for prefix in sorted(prefixes):
    drv = subprocess.check_output(['nix-store', '-q', '--deriver', prefix], text=True).strip()
    subprocess.run(['nix', 'build', '--no-link', '--rebuild', drv + '^*'], check=True)
PY
negative=(--impure --file "$root/tests/javascript-negative.nix"
  --argstr projectRoot "$root" --argstr src "$work/first")
for module in absent opaque_probe escape_probe; do
  if nix build "${negative[@]}" --argstr module "$module" --no-link > "$work/$module.log" 2>&1; then
    echo "unexpected JavaScript projection accepted: $module" >&2; exit 1
  fi
done
grep -qF 'selected module is absent from the native package interface' "$work/absent.log"
grep -qF 'unsupported-dynamic-import' "$work/opaque_probe.log"
grep -qF 'native module graph path escapes the runtime output' "$work/escape_probe.log"
if nix build "${negative[@]}" --argstr module answer --argstr version 9.9.9 --no-link > "$work/version.log" 2>&1; then
  echo 'WebJar accepted a non-native package version' >&2; exit 1
fi
grep -qF 'WebJar version differs from the native Gleam package version' "$work/version.log"
echo "javascript-projections.sh: fresh capture, exact modules/resources/WebJars and rejection controls passed ($result)"
