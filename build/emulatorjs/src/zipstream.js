// Streaming zip reader. Reads the central directory from the tail of a Blob,
// then extracts entries one at a time so the whole archive is never held in
// memory. Supports stored (0) and deflate (8) entries, including zip64.
//
// No EmulatorJS dependencies by design: it takes a Blob and emits files.

const SIG_EOCD = 0x06054b50;
const SIG_EOCD64 = 0x06064b50;
const SIG_EOCD64_LOC = 0x07064b50;
const SIG_CENTRAL = 0x02014b50;
const EOCD_MIN = 22;
const MAX_COMMENT = 0xFFFF;

async function bytesOf(blob, start, end) {
  return new Uint8Array(await blob.slice(start, end).arrayBuffer());
}

// The EOCD sits at the end, but a trailing comment of up to 64 KB can follow
// it, so scan backwards for the signature rather than assuming a position.
async function findEocd(blob) {
  const scan = Math.min(blob.size, MAX_COMMENT + EOCD_MIN);
  if (scan < EOCD_MIN) throw new Error("zip: file is too small to contain an end of central directory record");
  const base = blob.size - scan;
  const buf = await bytesOf(blob, base, blob.size);
  const dv = new DataView(buf.buffer);
  for (let i = buf.length - EOCD_MIN; i >= 0; i--) {
    if (dv.getUint32(i, true) === SIG_EOCD) return { dv, at: i, base };
  }
  throw new Error("zip: no end of central directory record found (truncated or not a zip archive)");
}

export async function readCentralDirectory(blob) {
  const { dv, at, base } = await findEocd(blob);

  let count = dv.getUint16(at + 10, true);
  let cdSize = dv.getUint32(at + 12, true);
  let cdOffset = dv.getUint32(at + 16, true);

  // Any saturated field means the real values live in the zip64 records.
  if (count === 0xFFFF || cdSize === 0xFFFFFFFF || cdOffset === 0xFFFFFFFF) {
    const locAt = at - 20;
    if (locAt < 0 || dv.getUint32(locAt, true) !== SIG_EOCD64_LOC) {
      throw new Error("zip: archive claims zip64 but its locator record is missing");
    }
    const eocd64At = Number(dv.getBigUint64(locAt + 8, true));
    const head = await bytesOf(blob, eocd64At, eocd64At + 56);
    const hdv = new DataView(head.buffer);
    if (hdv.getUint32(0, true) !== SIG_EOCD64) {
      throw new Error("zip: zip64 locator points at something that is not a zip64 end of central directory record");
    }
    count = Number(hdv.getBigUint64(32, true));
    cdSize = Number(hdv.getBigUint64(40, true));
    cdOffset = Number(hdv.getBigUint64(48, true));
  }

  const cd = await bytesOf(blob, cdOffset, cdOffset + cdSize);

  // blob.slice() silently clamps to the end of the Blob, so a corrupt
  // cdOffset/cdSize can hand back a buffer far shorter than the declared
  // entry count could possibly fit in. Catch that up front rather than
  // letting the loop below run into a raw DataView RangeError. A cdSize that
  // is merely *larger* than the real central directory (and so also gets
  // clamped) is not corrupt — it still contains every real entry — so this
  // checks against the entry count's minimum possible size, not cdSize.
  if (cd.length < count * 46) {
    throw new Error("zip: central directory is truncated or its offset is out of range (archive is corrupt)");
  }

  const cdv = new DataView(cd.buffer);
  const entries = [];
  let p = 0;

  for (let i = 0; i < count; i++) {
    if (p + 46 > cd.length) {
      throw new Error(`zip: central directory entry ${i} is truncated or its offset is out of range (archive is corrupt)`);
    }
    if (cdv.getUint32(p, true) !== SIG_CENTRAL) {
      throw new Error(`zip: central directory entry ${i} has a bad signature`);
    }
    const flags = cdv.getUint16(p + 8, true);
    const method = cdv.getUint16(p + 10, true);
    const crc = cdv.getUint32(p + 16, true);
    let compressedSize = cdv.getUint32(p + 20, true);
    let uncompressedSize = cdv.getUint32(p + 24, true);
    const nameLen = cdv.getUint16(p + 28, true);
    const extraLen = cdv.getUint16(p + 30, true);
    const commentLen = cdv.getUint16(p + 32, true);
    let localOffset = cdv.getUint32(p + 42, true);

    const entryEnd = p + 46 + nameLen + extraLen + commentLen;
    if (entryEnd > cd.length) {
      throw new Error(`zip: central directory entry ${i} is truncated or its offset is out of range (archive is corrupt)`);
    }

    const name = new TextDecoder().decode(cd.subarray(p + 46, p + 46 + nameLen));

    // Zip64 extra field: present values appear in a fixed order, but only for
    // the fields that were saturated above.
    if (extraLen) {
      const exStart = p + 46 + nameLen;
      let q = exStart;
      const exEnd = exStart + extraLen;
      while (q + 4 <= exEnd) {
        const id = cdv.getUint16(q, true);
        const size = cdv.getUint16(q + 2, true);
        if (id === 0x0001) {
          let r = q + 4;
          if (uncompressedSize === 0xFFFFFFFF) { uncompressedSize = Number(cdv.getBigUint64(r, true)); r += 8; }
          if (compressedSize === 0xFFFFFFFF) { compressedSize = Number(cdv.getBigUint64(r, true)); r += 8; }
          if (localOffset === 0xFFFFFFFF) { localOffset = Number(cdv.getBigUint64(r, true)); r += 8; }
          break;
        }
        q += 4 + size;
      }
    }

    entries.push({ name, method, flags, crc, compressedSize, uncompressedSize, localOffset });
    p = entryEnd;
  }

  return entries;
}

const SIG_LOCAL = 0x04034b50;
const METHOD_STORE = 0;
const METHOD_DEFLATE = 8;
const FLAG_ENCRYPTED = 0x0001;

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let i = 0; i < 256; i++) {
    let c = i;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    t[i] = c >>> 0;
  }
  return t;
})();

function crc32(bytes) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) c = CRC_TABLE[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

async function inflateRaw(blob, name) {
  try {
    const stream = blob.stream().pipeThrough(new DecompressionStream("deflate-raw"));
    return new Uint8Array(await new Response(stream).arrayBuffer());
  } catch (e) {
    throw new Error(`zip: failed to decompress "${name}": ${e.message}`);
  }
}

export function streamingSupported() {
  return typeof DecompressionStream === "function" && typeof Blob !== "undefined";
}

export async function readZipEntries(blob, onEntry, onProgress) {
  const entries = await readCentralDirectory(blob);

  // Every entry's uncompressed size is in the central directory, so the total
  // is known before a single byte is inflated -- callers can show a real
  // percentage instead of a running byte count that never reaches an end.
  const total = entries.reduce((sum, e) => sum + e.uncompressedSize, 0);
  let written = 0;

  for (const e of entries) {
    if (e.flags & FLAG_ENCRYPTED) {
      throw new Error(`zip: "${e.name}" is encrypted, which is not supported`);
    }

    if (e.name.endsWith("/")) {
      onEntry(e.name, new Uint8Array(0));
      if (onProgress) onProgress(written, total);
      continue;
    }

    if (e.method !== METHOD_STORE && e.method !== METHOD_DEFLATE) {
      throw new Error(`zip: "${e.name}" uses compression method ${e.method}; only stored and deflate are supported`);
    }

    // The central directory's name and extra lengths need not match the local
    // header's, so the data offset must come from the local header itself.
    const head = new Uint8Array(await blob.slice(e.localOffset, e.localOffset + 30).arrayBuffer());
    const hdv = new DataView(head.buffer);
    if (hdv.getUint32(0, true) !== SIG_LOCAL) {
      throw new Error(`zip: "${e.name}" has a bad local header signature`);
    }
    const dataStart = e.localOffset + 30 + hdv.getUint16(26, true) + hdv.getUint16(28, true);
    const slice = blob.slice(dataStart, dataStart + e.compressedSize);

    const bytes = e.method === METHOD_STORE
      ? new Uint8Array(await slice.arrayBuffer())
      : await inflateRaw(slice, e.name);

    if (bytes.length !== e.uncompressedSize) {
      throw new Error(`zip: "${e.name}" unpacked to ${bytes.length} bytes, expected ${e.uncompressedSize}`);
    }
    if (crc32(bytes) !== e.crc) {
      throw new Error(`zip: "${e.name}" failed its CRC check (archive is corrupt)`);
    }

    onEntry(e.name, bytes);
    written += bytes.length;
    if (onProgress) onProgress(written, total);
  }

  return entries.length;
}
