import test from 'node:test';
import assert from 'node:assert/strict';
import { watchMusicStateCommand, parseWatchMusicCommand, watchMusicVolumeDirection } from '../.cloud-build/out/WatchMusic.js';
import { joinBytes, protoInt, protoBytes, readProto, fieldInt, fieldBytes } from '../.cloud-build/out/WatchProtocol.js';

const music = (subtype, key = null, volume = null) => joinBytes([
  protoInt(1, 18), protoInt(2, subtype), ...(key === null ? [] : [protoBytes(20, protoBytes(2,
    joinBytes([protoInt(1, key), ...(volume === null ? [] : [protoInt(2, volume)])])))])]);
const parse = data => parseWatchMusicCommand(readProto(data));
const state = changes => ({ state: 'playing', track: Buffer.from('曲目 🎵'), artist: Buffer.from('Artist'),
  positionSeconds: 60, durationSeconds: 180, volumePercent: 55, ...changes });

test('Xiaomi music state wire fields are type 18/1 and Command field 20, not Huami', () => {
  const command = readProto(watchMusicStateCommand(state()));
  assert.equal(fieldInt(command, 1), 18); assert.equal(fieldInt(command, 2), 1);
  const body = readProto(fieldBytes(command, 20)); const info = readProto(fieldBytes(body, 1));
  assert.deepEqual(info.map(f => f.id), [1, 2, 4, 5, 6, 7]);
  assert.equal(fieldInt(info, 1), 1); assert.equal(fieldInt(info, 2), 55);
  assert.equal(Buffer.from(fieldBytes(info, 4)).toString(), '曲目 🎵');
  assert.equal(Buffer.from(fieldBytes(info, 5)).toString(), 'Artist');
  assert.equal(fieldInt(info, 6), 60); assert.equal(fieldInt(info, 7), 180);
});

test('paused, empty session and duration boundary clear or bound the state', () => {
  const info = changes => readProto(fieldBytes(readProto(fieldBytes(readProto(watchMusicStateCommand(state(changes))), 20)), 1));
  assert.equal(fieldInt(info({state: 'paused'}), 1), 2);
  assert.deepEqual(info({state: 'none'}).map(f => [f.id, f.integer]), [[1, 0], [2, 55]]);
  assert.equal(fieldInt(info({positionSeconds: 200}), 6), 180);
  assert.equal(fieldInt(info({durationSeconds: 0, positionSeconds: 200}), 6), 200);
  assert.equal(fieldInt(info({durationSeconds: 0xffffffff, positionSeconds: 0xffffffff}), 7), 0xffffffff);
});

test('state rejects non-finite, fractional, negative and out of range values and invalid UTF8', () => {
  for (const value of [NaN, Infinity, -1, 0.1, 101]) assert.throws(() => watchMusicStateCommand(state({volumePercent: value})), /INTEGER/);
  for (const value of [NaN, Infinity, -1, 0.1, 0x100000000]) assert.throws(() => watchMusicStateCommand(state({durationSeconds: value})), /INTEGER/);
  assert.throws(() => watchMusicStateCommand(state({state: 'unknown'})), /STATE/);
  for (const track of [new Uint8Array(513).fill(65), Buffer.from([0]), Buffer.from([0xc0, 0x80]),
    Buffer.from([0xed, 0xa0, 0x80]), Buffer.from([0xf4, 0x90, 0x80, 0x80]), Buffer.from([0xe3, 0x81]), Buffer.from([0x80])]) {
    assert.throws(() => watchMusicStateCommand(state({track})), /TEXT/);
  }
  const track = new Uint8Array(512).fill(65); const original = track.slice();
  watchMusicStateCommand(state({track})); assert.deepEqual(track, original);
});

test('Xiaomi keys map only known actions and volume carries a percentage', () => {
  assert.equal(parse(music(0)).action, 'request');
  for (const [key, action] of [[0,'play'],[1,'pause'],[3,'previous'],[4,'next']]) assert.equal(parse(music(2,key)).action, action);
  for (const volume of [0, 50, 100]) {
    const result = parse(music(2,5,volume)); assert.equal(result.action, 'volume'); assert.equal(result.volumePercent, volume);
  }
  for (const key of [2,6,255]) assert.equal(parse(music(2,key)).action, 'unsupported');
  for (const subtype of [1,3,4,255]) assert.equal(parse(music(subtype,0)).action, 'unsupported');
});

test('unknown domain, malformed nesting, duplicates and unbounded bodies never dispatch', () => {
  const invalid = [joinBytes([protoInt(1,7),protoInt(2,2)]), music(2), music(0,0), music(2,5), music(2,5,101),
    joinBytes([music(2,0), protoInt(1,18)]), joinBytes([protoInt(1,18),protoInt(2,2),protoBytes(20,new Uint8Array([10,127,1]))]),
    joinBytes([protoInt(1,18),protoInt(2,2),protoBytes(20,new Uint8Array(1025))])];
  for (const key of [joinBytes([protoInt(1,0),protoInt(1,1)]),joinBytes([protoInt(1,5),protoInt(2,0),protoInt(2,100)]),
    protoBytes(1, Buffer.from('0')), protoBytes(1,new Uint8Array()), new Uint8Array(129)]) {
    invalid.push(joinBytes([protoInt(1,18),protoInt(2,2),protoBytes(20,protoBytes(2,key))]));
  }
  for (const command of invalid) assert.equal(parse(command).action, 'unsupported');
  const fields = readProto(music(2,0)); const saved = fields.map(f => f.bytes.slice());
  assert.equal(parseWatchMusicCommand(fields).action, 'play');
  fields.forEach((f,i) => assert.deepEqual(f.bytes,saved[i]));
});

test('volume endpoints and equal target avoid an inverted change; unknown percentages reject', () => {
  assert.equal(watchMusicVolumeDirection(100,50),1); assert.equal(watchMusicVolumeDirection(0,50),-1);
  assert.equal(watchMusicVolumeDirection(100,100),0); assert.equal(watchMusicVolumeDirection(0,0),0);
  assert.equal(watchMusicVolumeDirection(40,50),-1); assert.equal(watchMusicVolumeDirection(60,50),1);
  for (const value of [-1,101,NaN,Infinity,0.5]) assert.throws(() => watchMusicVolumeDirection(value,50), /VOLUME/);
});
