import {readFileSync, writeFileSync, readdirSync, existsSync} from 'fs';
import {join, dirname} from 'path';
import {fileURLToPath} from 'url';

const here = dirname(fileURLToPath(import.meta.url));
const fixDir = join(here, '..', 'fixtures');

// Display order = README gallery order; first match wins.
const order = ['menu','audit','disk','network','memory','ports','battery','backup',
  'upgrade','docker','git','xcode','certs','ssh','env','startup','trash','fonts','history','help','version'];

const cmdFor = {
  audit: 'rcc audit --deep', upgrade: 'rcc upgrade --dry-run',
  version: 'rcc --version', menu: 'rcc',
};

const files = new Set(readdirSync(fixDir).filter((f) => f.endsWith('.txt')));
const ids = order.filter((id) => files.has(id + '.txt'));

const data = ids.map((id) => {
  let lines = readFileSync(join(fixDir, id + '.txt'), 'utf8').replace(/\s+$/, '').split('\n');
  while (lines.length && lines[0].trim() === '') lines.shift();
  return {id, cmd: cmdFor[id] || ('rcc ' + id), lines};
});

writeFileSync(join(here, '..', 'src', 'data.json'), JSON.stringify(data, null, 2));
console.log('wrote data.json:', data.length, 'compositions ->', data.map((d) => d.id).join(', '));
