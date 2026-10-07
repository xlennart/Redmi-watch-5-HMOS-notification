import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';
import JSON5 from 'json5';
import { configuration } from './configure-probe.mjs';

// Use one separator for both filesystem paths and map keys on Windows and POSIX.
const root = fileURLToPath(new URL('../', import.meta.url)).replaceAll('\\', '/');
function walk(path) {
  return readdirSync(path, { withFileTypes: true }).flatMap(item => {
    if (['.git', '.local', 'local-feedback', 'node_modules', '.cloud-build', '.hvigor', 'oh_modules', 'build'].includes(item.name)) return [];
    return item.isDirectory() ? walk(`${path}/${item.name}`) : [`${path}/${item.name}`];
  });
}
const files = walk(root.replace(/\/$/, ''));
const parsed = new Map();
for (const file of files.filter(p => /\.(json|json5)$/.test(p))) {
  parsed.set(file, JSON5.parse(readFileSync(file, 'utf8')));
}
const read = path => parsed.get(`${root}${path}`);
const module = read('entry/src/main/module.json5').module;
const modeSource = readFileSync(`${root}entry/src/main/ets/config/ProbeMode.ets`, 'utf8');
const enabled = modeSource.includes('= true;');
const expected = configuration(enabled ? 'notifications' : 'baseline');
assert.deepEqual(module, JSON.parse(expected.manifest).module, 'Manifest must match selected mode');
assert.equal(modeSource.replaceAll('\r\n', '\n'), expected.modeSource,
  'Mode flag must match generated configuration');
for (const ability of [...module.abilities, ...(module.extensionAbilities ?? [])]) {
  assert.ok(existsSync(`${root}entry/src/main/${ability.srcEntry}`), `Missing ${ability.srcEntry}`);
}
const resources = {
  string: new Set(), color: new Set(), media: new Set(), profile: new Set()
};
for (const file of files.filter(p => /\/resources\/base\//.test(p))) {
  if (/\/element\//.test(file)) {
    for (const kind of ['string', 'color']) {
      for (const item of parsed.get(file)?.[kind] ?? []) resources[kind].add(item.name);
    }
  } else {
    const match = file.match(/\/(media|profile)\/([^/]+)\.[^.]+$/);
    if (match) resources[match[1]].add(match[2]);
  }
}
for (const file of files.filter(p => /\.(json|json5|ets)$/.test(p))) {
  const text = readFileSync(file, 'utf8');
  for (const match of text.matchAll(/\$(string|color|media|profile):([A-Za-z0-9_]+)/g)) {
    assert.ok(resources[match[1]].has(match[2]), `Missing resource ${match[0]} in ${file}`);
  }
}
const profile = read('build-profile.json5');
assert.equal(profile.app.products[0].targetSdkVersion, '26.0.0');
assert.equal(profile.app.products[0].compatibleSdkVersion, '26.0.0');
assert.equal(read('oh-package.json5').modelVersion, read('hvigor/hvigor-config.json5').modelVersion);
const pages = read('entry/src/main/resources/base/profile/main_pages.json').src;
for (const page of pages) assert.ok(existsSync(`${root}entry/src/main/ets/${page}.ets`));
console.log(`Project integrity passed: ${parsed.size} JSON/JSON5 files, resource references and ${enabled ? 'notifications' : 'baseline'} mode.`);
console.log('ArkTS compilation, ACL signing and device behavior are not validated by this check.');
