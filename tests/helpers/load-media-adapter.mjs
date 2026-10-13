import { readFileSync } from 'node:fs';
import ts from 'typescript';

let sequence = 0;
export async function loadMediaAdapter({ avSession, audio, MusicVolumeBridge }) {
  const key = `__mediaAdapterTest${++sequence}`;
  globalThis[key] = { avSession, audio, MusicVolumeBridge };
  const native = `const {avSession,audio,MusicVolumeBridge}=globalThis[${JSON.stringify(key)}];export {avSession,audio,MusicVolumeBridge};`;
  const kitUrl = `data:text/javascript;base64,${Buffer.from(native).toString('base64')}`;
  const errorUrl = 'data:text/javascript;base64,' + Buffer.from(
    'export class WatchChannelError extends Error { constructor(message,code) { super(message);this.code=code; } }').toString('base64');
  const source = readFileSync(new URL('../../entry/src/main/ets/platform/PhoneMediaAdapter.ets', import.meta.url), 'utf8');
  let code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText;
  code = code.replaceAll("'@kit.AVSessionKit'", JSON.stringify(kitUrl)).replaceAll("'@kit.AudioKit'", JSON.stringify(kitUrl))
    .replaceAll("'../core/WearableServices'", JSON.stringify(new URL('../../.cloud-build/out/WearableServices.js', import.meta.url).href))
    .replaceAll("'../core/PhoneMedia'", JSON.stringify(new URL('../../.cloud-build/out/PhoneMedia.js', import.meta.url).href))
    .replaceAll("'./MusicVolumeBridge'", JSON.stringify(kitUrl))
    .replaceAll("'./WatchChannelProbe'", JSON.stringify(errorUrl));
  try {
    const loaded = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
    return loaded.HarmonyPhoneMediaAdapter;
  } finally { delete globalThis[key]; }
}
