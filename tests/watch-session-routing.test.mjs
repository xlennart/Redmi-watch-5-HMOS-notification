import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import ts from 'typescript';
import { joinBytes, protoInt, protoBytes, clearProto, WatchV2Frame } from '../.cloud-build/out/WatchProtocol.js';
import { parseWatchMusicCommand } from '../.cloud-build/out/WatchMusic.js';

// Runs the production routing/cancellation code; only SDK/socket/crypto adapters are substituted.
const directory = new URL('../.cloud-build/session-routing/', import.meta.url);
mkdirSync(directory, { recursive:true });
writeFileSync(new URL('stubs.mjs', directory), `
import crypto from 'node:crypto';
export const socket={sppWriteAsync:async()=>{},sppCloseClientSocket:()=>{}};
export const connection={};
export const util={TextEncoder};
export class WatchChannelError extends Error { constructor(stage,code){super(stage);this.stage=stage;this.code=code;} }
export class WatchCredentialStore {}
export const cryptoFramework={
  CryptoMode:{ENCRYPT_MODE:1,DECRYPT_MODE:2},
  createSymKeyGenerator:()=>({convertKey:async({data})=>({data,clearMem(){}})}),
  createCipher:()=>({async init(mode,key,params){this.mode=mode;this.key=key.data;this.iv=params.iv.data;},
    async doFinal({data}){const cipher=this.mode===1?crypto.createCipheriv('aes-128-ctr',this.key,this.iv):crypto.createDecipheriv('aes-128-ctr',this.key,this.iv);
      return {data:new Uint8Array(Buffer.concat([cipher.update(data),cipher.final()]))};}})
};
`);
const source = readFileSync(new URL('../entry/src/main/ets/platform/WatchTestSession.ets', import.meta.url),'utf8')
  .replace(/from '@kit\.[^']+'/g,"from './stubs.mjs'")
  .replace(/from '\.\/Watch(?:CredentialStore|ChannelProbe)'/g,"from './stubs.mjs'")
  .replace(/from '\.\.\/core\/([A-Za-z]+)'/g,"from '../out/$1.js'");
writeFileSync(new URL('session.mjs', directory), ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText);
const { WatchTestSession } = await import(new URL('session.mjs',directory).href);
const crypto = await import('node:crypto');
const control = () => joinBytes([protoInt(1,18),protoInt(2,2),protoBytes(20,protoBytes(2,protoInt(1,0)))]);
function frame(sequence, bytes, encrypted=true) {
  const cipher=crypto.createCipheriv('aes-128-ctr',new Uint8Array(16),new Uint8Array(16));
  const payload=encrypted?new Uint8Array(Buffer.concat([cipher.update(bytes),cipher.final()])):bytes;
  return new WatchV2Frame(3,sequence,joinBytes([new Uint8Array([1,encrypted?2:1]),payload]));
}
function session() {
  const instance=new WatchTestSession(); instance.deadline=Number.MAX_SAFE_INTEGER; instance.keyMaterial=new Uint8Array(64); return instance;
}
test('media routing ignores cleartext controls and suppresses retransmission of an encrypted command',async()=>{
  const instance=session(); const command=control();
  const plain=await instance.applicationReply(frame(1,command,false)); assert.deepEqual(plain,[]);
  const first=await instance.applicationReply(frame(2,command)); assert.equal(parseWatchMusicCommand(first).action,'play'); clearProto(first);
  const duplicate=await instance.applicationReply(frame(2,command)); assert.deepEqual(duplicate,[]);
  const next=await instance.applicationReply(frame(3,command)); assert.equal(parseWatchMusicCommand(next).action,'play'); clearProto(next);
  command.fill(0); instance.cancel();
});
test('a media command arriving during icon preparation survives clearing the notification response',async()=>{
  const instance=session();
  instance.queue=[frame(1,control()),frame(2,joinBytes([protoInt(1,22),protoInt(2,0),protoBytes(24,protoBytes(2,protoInt(1,0)))]))];
  const reply=await instance.iconMassReply(1000); assert.equal(reply[0],8); reply.fill(0);
  const deferred=await instance.nextApplication(); assert.equal(parseWatchMusicCommand(deferred).action,'play'); clearProto(deferred);
  assert.equal(instance.deferred.length,0); instance.cancel();
});
test('cancellation wakes an idle receiver and prevents a late media dispatch',async()=>{
  const instance=session();
  const pending=instance.nextApplication(2000); instance.cancel();
  await assert.rejects(pending,error=>error.code===-21);
});
