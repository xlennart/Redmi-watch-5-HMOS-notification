import { zlib } from '@kit.BasicServicesKit';
import { FitnessLogEntry } from '../core/MiFitnessArchive';

export async function unpackFitnessEntry(entry: FitnessLogEntry): Promise<Uint8Array> {
  if (entry.method === 0) return entry.bytes;
  const output = new ArrayBuffer(entry.size + 1);
  const stream: zlib.ZStream = { nextIn: entry.bytes.buffer as ArrayBuffer,
    availableIn: entry.bytes.length, nextOut: output, availableOut: output.byteLength };
  const zip = await zlib.createZip();
  if (await zip.inflateInit2(stream, -15) !== zlib.ReturnStatus.OK) throw new Error('INVALID_ARCHIVE');
  try {
    const result = await zip.inflate(stream, zlib.CompressFlushMode.FINISH);
    const progress = await zip.getZStream();
    if (result !== zlib.ReturnStatus.STREAM_END || progress.totalOut !== entry.size ||
        progress.totalIn !== entry.bytes.length) throw new Error('INVALID_ARCHIVE');
    return new Uint8Array(output, 0, entry.size);
  } finally {
    await zip.inflateEnd({});
  }
}
