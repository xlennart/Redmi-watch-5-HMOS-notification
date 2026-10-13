import { readFileSync } from 'node:fs';
import ts from 'typescript';

let sequence = 0;
export async function loadIconProvider({ bundleManager, image }) {
  const key = `__iconProviderTest${++sequence}`;
  globalThis[key] = { bundleManager, image };
  const native = `const {bundleManager,image}=globalThis[${JSON.stringify(key)}];export {bundleManager,image};`;
  const kitUrl = `data:text/javascript;base64,${Buffer.from(native).toString('base64')}`;
  const source = readFileSync(new URL('../../entry/src/main/ets/platform/AppNotificationIcon.ets', import.meta.url), 'utf8');
  let code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText;
  code = code.replaceAll("'@kit.AbilityKit'", JSON.stringify(kitUrl)).replaceAll("'@kit.ImageKit'", JSON.stringify(kitUrl))
    .replaceAll("'../core/WatchIcon'", JSON.stringify(new URL('../../.cloud-build/out/WatchIcon.js', import.meta.url).href))
    .replaceAll("'../core/OfflineNotificationIcons'", JSON.stringify(new URL('../../.cloud-build/out/OfflineNotificationIcons.js', import.meta.url).href));
  try { return (await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`)).AppNotificationIcon; }
  finally { delete globalThis[key]; }
}
