import { readdir, readFile, mkdir, cp, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const source = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../public');
const output = path.resolve(source, '../build');
async function files(dir, prefix = '') {
  const result = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const rel = prefix + entry.name;
    if (entry.isDirectory()) result.push(...await files(path.join(dir, entry.name), rel + '/'));
    else result.push(rel);
  }
  return result;
}
const inventory = await files(source);
for (const rel of inventory.filter((name) => name.endsWith('.js'))) {
  execFileSync(process.execPath, ['--check', path.join(source, rel)], { stdio: 'inherit' });
}
const hashes = {};
for (const rel of inventory) hashes[rel] = createHash('sha256').update(await readFile(path.join(source, rel))).digest('hex');
const version = createHash('sha256').update(JSON.stringify(hashes)).digest('hex').slice(0, 16);
await mkdir(output, { recursive: true });
await cp(source, output, { recursive: true });
await writeFile(path.join(output, 'build-info.json'), JSON.stringify({ version, builtAt: new Date().toISOString(), files: hashes }, null, 2));
console.log('Dashboard build complete: ' + inventory.length + ' assets; version ' + version);
