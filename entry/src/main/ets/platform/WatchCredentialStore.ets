import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { DeviceCredential } from '../core/MiFitnessCredentials';

export class WatchCredentialStore {
  private alias(): Uint8Array {
    return new util.TextEncoder().encodeInto('wrist-notifications.watch.v1');
  }

  async present(): Promise<boolean> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    try {
      return (await asset.query(query)).length > 0;
    } catch (error) {
      if ((error as BusinessError).code === 24000002) return false;
      throw new Error('CREDENTIAL_STORE_UNAVAILABLE');
    }
  }

  async save(credential: DeviceCredential): Promise<void> {
    const bytes = new util.TextEncoder().encodeInto(JSON.stringify(credential));
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.alias());
    attributes.set(asset.Tag.SECRET, bytes);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attributes);
    } finally {
      bytes.fill(0);
    }
  }

  // Plaintext is available only to the app's in-memory handshake, never exported or rendered.
  async readForHandshake(): Promise<DeviceCredential> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const records = await asset.query(query);
    if (records.length !== 1) throw new Error('CREDENTIAL_NOT_FOUND');
    const secret = records[0].get(asset.Tag.SECRET) as Uint8Array;
    if (!secret || secret.length > 4096) throw new Error('CREDENTIAL_INVALID');
    try {
      const credential = JSON.parse(util.TextDecoder.create('utf-8').decodeToString(secret)) as DeviceCredential;
      if (!/^redmi\s+watch\s+5(?:\s+[0-9a-f]{4})?$/i.test(credential.name) || !/^[0-9a-f]{32}$/i.test(credential.authKey)) {
        throw new Error('CREDENTIAL_INVALID');
      }
      return credential;
    } finally { secret.fill(0); }
  }

  async remove(): Promise<void> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.alias());
    try {
      await asset.remove(query);
    } catch (error) {
      if ((error as BusinessError).code !== 24000002) throw new Error('CREDENTIAL_STORE_UNAVAILABLE');
    }
  }
}
