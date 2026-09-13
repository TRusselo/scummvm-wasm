import { writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { deflateRawSync, crc32 } from "node:zlib";

const DIR = join(dirname(fileURLToPath(import.meta.url)), "fixtures");
mkdirSync(DIR, { recursive: true });

const u16 = (n) => { const b = Buffer.alloc(2); b.writeUInt16LE(n); return b; };
const u32 = (n) => { const b = Buffer.alloc(4); b.writeUInt32LE(n >>> 0); return b; };

const COUNT = 40;
const SIZE = 8 * 1048576;
const locals = [], centrals = [];
let offset = 0;

for (let i = 0; i < COUNT; i++) {
  // Pseudo-random so deflate cannot collapse it to nothing, deterministic so
  // the test is reproducible.
  const raw = Buffer.alloc(SIZE);
  for (let j = 0; j < SIZE; j += 4) raw.writeUInt32LE((j * 2654435761 + i) >>> 0, j);
  const comp = deflateRawSync(raw);
  const crc = crc32(raw);
  const name = Buffer.from(`file${String(i).padStart(2, "0")}.bin`, "utf8");

  const local = Buffer.concat([
    u32(0x04034b50), u16(20), u16(0), u16(8), u16(0), u16(0),
    u32(crc), u32(comp.length), u32(raw.length), u16(name.length), u16(0), name, comp,
  ]);
  locals.push(local);
  centrals.push(Buffer.concat([
    u32(0x02014b50), u16(20), u16(20), u16(0), u16(8), u16(0), u16(0),
    u32(crc), u32(comp.length), u32(raw.length),
    u16(name.length), u16(0), u16(0), u16(0), u16(0), u32(0), u32(offset), name,
  ]));
  offset += local.length;
}

const cd = Buffer.concat(centrals);
const out = Buffer.concat([
  Buffer.concat(locals), cd,
  Buffer.concat([u32(0x06054b50), u16(0), u16(0), u16(COUNT), u16(COUNT), u32(cd.length), u32(offset), u16(0)]),
]);
writeFileSync(join(DIR, "big-many.zip"), out);
console.log(`big-many.zip ${(out.length / 1048576).toFixed(1)} MB, ${COUNT} entries`);
