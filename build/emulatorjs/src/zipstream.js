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
