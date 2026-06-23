import {readFileSync} from 'fs';
import {execSync} from 'child_process';
import {join, dirname} from 'path';
import {fileURLToPath} from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const data = JSON.parse(readFileSync(join(root, 'src', 'data.json'), 'utf8'));
const outDir = join(root, '..', 'gifs');
const only = process.argv.slice(2);
const targets = only.length ? data.filter((d) => only.includes(d.id)) : data;

for (const d of targets) {
  const out = join(outDir, `rcc-${d.id}.gif`);
  console.log(`\n=== rendering ${d.id} -> ${out} ===`);
  execSync(
    `npx remotion render src/index.ts ${d.id} "${out}" --codec=gif --log=error`,
    {cwd: root, stdio: 'inherit'}
  );
}
console.log('\nALL RENDERED:', targets.length);
