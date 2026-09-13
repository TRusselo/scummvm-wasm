// build/emulatorjs/test/make-fixtures.mjs
// Regenerates test fixtures. Run: node build/emulatorjs/test/make-fixtures.mjs
import { mkdirSync, writeFileSync, rmSync } from "node:fs";
import { deflateRawSync, crc32 } from "node:zlib";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = join(dirname(fileURLToPath(import.meta.url)), "fixtures");

// Minimal zip writer. Not general purpose -- it exists to produce exactly the
// shapes the reader must cope with, including malformed ones.
function u16(n) { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; }
function u32(n) { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); return b; }
function u64(n) { const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(n)); return b; }

// entries: [{ name, data: Buffer, store?: bool, crcOverride?: number }]
// opts: { zip64?: bool, comment?: string }
function makeZip(entries, opts = {}) {
  const locals = [];
  const centrals = [];
  let offset = 0;

  for (const e of entries) {
    const isDir = e.name.endsWith("/");
    const raw = isDir ? Buffer.alloc(0) : e.data;
    const store = isDir || e.store === true;
    const comp = store ? raw : deflateRawSync(raw);
    const crc = e.crcOverride !== undefined ? e.crcOverride : crc32(raw);
    const nameBuf = Buffer.from(e.name, "utf8");

    const needed = opts.zip64 ? 45 : 20;  // zip64 requires >= 4.5
    const local = Buffer.concat([
      u32(0x04034b50), u16(needed), u16(0), u16(store ? 0 : 8),
      u16(0), u16(0), u32(crc), u32(comp.length), u32(raw.length),
      u16(nameBuf.length), u16(0), nameBuf, comp,
    ]);
    locals.push(local);

    // Zip64 marks the 32-bit fields saturated and moves the real values into
    // the extra field. Exercised by the zip64 fixture even though the file is
    // small -- the reader must follow the pointer, not guess from size.
    const extra = opts.zip64
      ? Buffer.concat([u16(0x0001), u16(24), u64(raw.length), u64(comp.length), u64(offset)])
      : Buffer.alloc(0);

    centrals.push(Buffer.concat([
      u32(0x02014b50), u16(20), u16(needed), u16(0), u16(store ? 0 : 8),
      u16(0), u16(0), u32(crc),
      u32(opts.zip64 ? 0xFFFFFFFF : comp.length),
      u32(opts.zip64 ? 0xFFFFFFFF : raw.length),
      u16(nameBuf.length), u16(extra.length), u16(0), u16(0), u16(0), u32(0),
      u32(opts.zip64 ? 0xFFFFFFFF : offset),
      nameBuf, extra,
    ]));
    offset += local.length;
  }

  const cd = Buffer.concat(centrals);
  const cdOffset = offset;
  const parts = [Buffer.concat(locals), cd];

  if (opts.zip64) {
    parts.push(Buffer.concat([
      u32(0x06064b50), u64(44), u16(45), u16(45), u32(0), u32(0),
      u64(entries.length), u64(entries.length), u64(cd.length), u64(cdOffset),
    ]));
    parts.push(Buffer.concat([
      u32(0x07064b50), u32(0), u64(cdOffset + cd.length), u32(1),
    ]));
  }

  const comment = Buffer.from(opts.comment || "", "utf8");
  parts.push(Buffer.concat([
    u32(0x06054b50), u16(0), u16(0),
    u16(opts.zip64 ? 0xFFFF : entries.length),
    u16(opts.zip64 ? 0xFFFF : entries.length),
    u32(opts.zip64 ? 0xFFFFFFFF : cd.length),
    u32(opts.zip64 ? 0xFFFFFFFF : cdOffset),
    u16(comment.length), comment,
  ]));

  return Buffer.concat(parts);
}

const HELLO = Buffer.from("hello world\n", "utf8");
// Deliberately compressible, and big enough that deflate actually shrinks it.
const BIG = Buffer.from("A".repeat(200000), "utf8");

rmSync(DIR, { recursive: true, force: true });
mkdirSync(DIR, { recursive: true });

const write = (name, buf) => { writeFileSync(join(DIR, name), buf); console.log(`  ${name}  ${buf.length} bytes`); };

console.log("fixtures:");

// 1. plain deflate, two files
write("deflate.zip", makeZip([
  { name: "hello.txt", data: HELLO },
  { name: "big.txt", data: BIG },
]));

// 2. stored (method 0), no compression
write("stored.zip", makeZip([{ name: "hello.txt", data: HELLO, store: true }]));

// 3. explicit directory entries -- the ENOTDIR class of bug
write("dirs.zip", makeZip([
  { name: "sub/", data: Buffer.alloc(0) },
  { name: "sub/nested/", data: Buffer.alloc(0) },
  { name: "sub/nested/hello.txt", data: HELLO },
]));

// 4. zip64 -- 32-bit fields saturated, real values in the extra field
write("zip64.zip", makeZip([{ name: "hello.txt", data: HELLO }], { zip64: true }));

// 5. a trailing comment, so the EOCD is not at the very end
write("comment.zip", makeZip([{ name: "hello.txt", data: HELLO }], { comment: "x".repeat(300) }));

// 6. truncated -- last 100 bytes lopped off, so no EOCD survives
const good = makeZip([{ name: "hello.txt", data: HELLO }]);
write("truncated.zip", good.subarray(0, good.length - 100));

// 7. wrong CRC recorded for an otherwise valid entry
write("badcrc.zip", makeZip([{ name: "hello.txt", data: HELLO, crcOverride: 0x12345678 }]));

// 8. not a zip at all
write("notazip.bin", Buffer.from("this is not a zip file", "utf8"));

console.log("done ->", DIR);
