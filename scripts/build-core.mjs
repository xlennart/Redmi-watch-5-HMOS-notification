import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = fileURLToPath(new URL('../', import.meta.url));
const dest = `${root}.cloud-build`;
rmSync(dest, { recursive: true, force: true });
mkdirSync(`${dest}/src`, { recursive: true });
// Mechanical extension mapping only: tests exercise the application's actual core.
const modules = ['ProbeStats', 'WearableCandidates', 'MiFitnessCredentials', 'MiFitnessArchive', 'MiFitnessCloud', 'WearableData', 'WearableServices', 'NotificationRelay', 'WatchWire', 'WatchProtocol', 'WatchIcon', 'AppState'];
for (const name of modules) {
  const core = readFileSync(`${root}entry/src/main/ets/core/${name}.ets`, 'utf8');
  writeFileSync(`${dest}/src/${name}.ts`, core.replace(/from '\.\/([A-Za-z]+)'/g, "from './$1.js'"));
}
execFileSync(process.execPath, [
  `${root}node_modules/typescript/bin/tsc`, ...modules.map(name => `${dest}/src/${name}.ts`),
  '--strict', '--target', 'ES2022', '--module', 'ES2022', '--outDir', `${dest}/out`,
  '--noEmitOnError', '--skipLibCheck'
], { stdio: 'inherit', cwd: root });
console.log('Shared core compiled with TypeScript; this is not an ArkTS/SDK build.');
