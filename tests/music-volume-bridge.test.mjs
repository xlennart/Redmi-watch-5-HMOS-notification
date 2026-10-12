import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import ts from 'typescript';
const errorUrl='data:text/javascript;base64,'+Buffer.from('export class WatchChannelError extends Error { constructor(stage,code){super(stage);this.code=code;} }').toString('base64');
const source=readFileSync(new URL('../entry/src/main/ets/platform/MusicVolumeBridge.ets',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText.replaceAll("'./WatchChannelProbe'",JSON.stringify(errorUrl));
const {MusicVolumeBridge}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
test('background and unbound pages cannot silently request system volume changes',()=>{
  const levels=[];const unbind=MusicVolumeBridge.bind(level=>levels.push(level));
  MusicVolumeBridge.setForeground(false);
  assert.throws(()=>MusicVolumeBridge.request(6),error=>error.code===-66);
  assert.deepEqual(levels,[]);
  MusicVolumeBridge.setForeground(true);MusicVolumeBridge.request(6);assert.deepEqual(levels,[6]);
  unbind();assert.throws(()=>MusicVolumeBridge.request(7),error=>error.code===-66);
});
