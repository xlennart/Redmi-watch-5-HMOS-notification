import { util } from '@kit.ArkTS';
import { unpackFitnessEntry } from './FitnessZipCodec';
import { fitnessArchiveEntries, FitnessLogEntry, logCrc32 } from '../core/MiFitnessArchive';
import { DeviceCredential, readMiFitnessLog } from '../core/MiFitnessCredentials';

@Concurrent
export async function decodeMiFitnessExport(buffer: ArrayBuffer): Promise<DeviceCredential[]> {
  const bytes = new Uint8Array(buffer);
  let entries: FitnessLogEntry[] = [];
  try {
    const decoder = util.TextDecoder.create('utf-8', { fatal: false });
    if (bytes[0] !== 0x50 || bytes[1] !== 0x4b) return readMiFitnessLog(decoder.decodeToString(bytes));
    entries = fitnessArchiveEntries(bytes);
    const found: DeviceCredential[] = [];
    for (let i = 0; i < entries.length; i++) {
      const content = await unpackFitnessEntry(entries[i]);
      try {
        if (content.length !== entries[i].size || logCrc32(content) !== entries[i].crc) throw new Error('INVALID_ARCHIVE');
        const records = readMiFitnessLog(decoder.decodeToString(content));
        for (let j = 0; j < records.length; j++) {
          const existing = found.findIndex(item => item.address === records[j].address);
          if (existing >= 0) found[existing] = records[j];
          else found.push(records[j]);
        }
      } finally {
        content.fill(0);
      }
    }
    return found;
  } finally {
    for (let i = 0; i < entries.length; i++) entries[i].bytes.fill(0);
    bytes.fill(0);
  }
}
