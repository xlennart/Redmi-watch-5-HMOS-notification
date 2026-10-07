import test from 'node:test';
import assert from 'node:assert/strict';
import { AppState, DeviceCandidateView, CredentialCandidateView } from '../.cloud-build/out/AppState.js';

test('production UI starts with unknown permissions, no invented device or delivery counters', () => {
  const state = new AppState();
  assert.equal(state.hasDevice, false); assert.equal(state.material, false);
  assert.equal(state.permissionKnown, false); assert.equal(state.relayEnabled, false);
  assert.equal(state.connection, 'unknown'); assert.equal(state.received, 0); assert.equal(state.acknowledged, 0);
  assert.equal(state.confirmationRequired, false); assert.deepEqual(state.sources, []);
});

test('published snapshots cannot mutate the adapter candidate lists or source metadata', () => {
  const current = new AppState();
  current.sources = ['Synthetic source'];
  current.candidates = [new DeviceCandidateView(1000, 'Synthetic watch', false, 'Unknown call connection')];
  current.credentialCandidates = [new CredentialCandidateView(2000, 'Synthetic record · masked suffix')];
  const snapshot = current.copy();
  snapshot.sources.push('Injected'); snapshot.candidates[0].supported = true;
  snapshot.credentialCandidates[0].label = 'Changed';
  assert.equal(current.sources.length, 1); assert.equal(current.candidates[0].supported, false);
  assert.equal(current.credentialCandidates[0].label, 'Synthetic record · masked suffix');
  assert.deepEqual(Object.keys(snapshot.candidates[0]).sort(), ['detail','name','reference','supported']);
  assert.deepEqual(Object.keys(snapshot.credentialCandidates[0]).sort(), ['label','reference']);
});

test('relay intent, permission uncertainty, actual session activity and diagnostic feedback stay independent', () => {
  const current = new AppState();
  current.relayEnabled = true; current.permission = true; current.permissionKnown = false;
  current.sessionBusy = false; current.connection = 'unknown'; current.acknowledged = 7;
  current.diagnosticResult = 'Synthetic transport acknowledgement'; current.confirmationRequired = true;
  current.iconStatus = 'uploaded'; current.pendingKind = 'refresh';
  const snapshot = current.copy();
  assert.equal(snapshot.relayEnabled, true); assert.equal(snapshot.permissionKnown, false);
  assert.equal(snapshot.sessionBusy, false); assert.equal(snapshot.connection, 'unknown');
  assert.equal(snapshot.acknowledged, 7); assert.equal(snapshot.confirmationRequired, true);
  assert.equal(snapshot.iconStatus, 'uploaded'); assert.equal(snapshot.pendingKind, 'refresh');
});
