import { registerHooks } from 'node:module';
import { readFileSync, realpathSync } from 'node:fs';
import { resolve, relative } from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const [prefixArg, receiptArg, countArg] = process.argv.slice(2);
const prefix = realpathSync(prefixArg), count = Number(countArg);
const receipt = JSON.parse(readFileSync(receiptArg));
assert.equal(process.version, receipt.node, "consumer Node SDK differs from producer");
const loaded = new Map();
const hooks = registerHooks({resolve(specifier, context, next) {
  const result = next(specifier, context);
  if (result.url.startsWith('file:')) {
    const actual = realpathSync(fileURLToPath(result.url));
    assert(actual.startsWith(prefix + '/'), 'ordinary Node resolved outside selected closure: ' + actual);
    const bytes = readFileSync(actual);
    loaded.set(relative(prefix, actual), {origin: actual, sha256: createHash('sha256').update(bytes).digest('hex')});
  }
  return result;
}});
const module = await import(pathToFileURL(resolve(prefix, receipt.entrypoint)).href);
assert.deepEqual([module.answer(0), module.answer(1)], [count, count+1]);
hooks.deregister();
assert.deepEqual([...loaded.keys()].sort(), receipt.files.map(r => r.path).sort());
for (const row of receipt.files) {
  const observed = loaded.get(row.path);
  assert.equal(observed.sha256, row.sha256, 'loaded module bytes differ from native selection: ' + row.path);
  assert.equal(createHash('sha256').update(readFileSync(row.origin)).digest('hex'), row.sha256);
}
console.log(JSON.stringify({values: [count, count+1], node: process.version, entrypoint: receipt.entrypoint, loaded: Object.fromEntries(loaded)}));
