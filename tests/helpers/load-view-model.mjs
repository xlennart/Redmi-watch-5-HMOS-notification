import { readFileSync } from 'node:fs';
import ts from 'typescript';

let sequence = 0;
export async function loadViewModel(dependencies) {
  const key = `__viewModelTest${++sequence}`;
  globalThis[key] = dependencies;
  const source = readFileSync(new URL('../../entry/src/main/ets/platform/AppViewModel.ets', import.meta.url), 'utf8');
  let code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText;
  const names = new Set();
  for (const match of code.matchAll(/import \{([^}]+)\} from '([^']+)';/g)) {
    if (match[2] === '../core/AppState') continue;
    for (const name of match[1].split(',')) names.add(name.trim());
  }
  const stub = [...names].map(name => `export const ${name}=globalThis[${JSON.stringify(key)}][${JSON.stringify(name)}];`).join('\n');
  const kitUrl = `data:text/javascript;base64,${Buffer.from(stub).toString('base64')}`;
  code = code.replace(/from '([^']+)';/g, (_, path) => 'from ' + JSON.stringify(path === '../core/AppState' ?
    new URL('../../.cloud-build/out/AppState.js', import.meta.url).href : kitUrl) + ';');
  try { return (await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`)).AppViewModel; }
  finally { delete globalThis[key]; }
}
