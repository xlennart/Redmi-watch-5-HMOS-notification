import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';

test('volume requests require the real foreground music panel and stop when the panel or owner disappears', async () => {
  const errorUrl = 'data:text/javascript;base64,' + Buffer.from(
    'export class WatchChannelError extends Error { constructor(message,code) {super(message);this.code=code;} }').toString('base64');
  const source = readFileSync(new URL('../entry/src/main/ets/platform/MusicVolumeBridge.ets', import.meta.url), 'utf8');
  const code = ts.transpileModule(source, {compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText
    .replaceAll("'./WatchChannelProbe'", JSON.stringify(errorUrl));
  const {MusicVolumeBridge: Bridge} = await import('data:text/javascript;base64,' + Buffer.from(code).toString('base64'));
  const levels=[]; const release=Bridge.bind(level=>levels.push(level));
  Bridge.setForeground(true);
  assert.throws(()=>Bridge.request(3), error=>error.code===-66);
  Bridge.setPanelVisible(true); Bridge.request(4);
  assert.deepEqual(levels,[4]);
  Bridge.setForeground(false); assert.throws(()=>Bridge.request(5), error=>error.code===-66);
  Bridge.setForeground(true); Bridge.setPanelVisible(false);
  assert.throws(()=>Bridge.request(5), error=>error.code===-66);
  Bridge.setPanelVisible(true); release();
  assert.throws(()=>Bridge.request(5), error=>error.code===-66);
  assert.deepEqual(levels,[4]);
});
