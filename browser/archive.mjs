// Small, bounded ZIP transport. Report semantics and SHA-256 checks stay in MoonBit.
export const ZIP_LIMITS = Object.freeze({ bytes: 64 * 1024 * 1024, entryBytes: 16 * 1024 * 1024, entries: 128 });
const encoder = new TextEncoder();
const decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
const fail = detail => { throw new Error(`报告 ZIP 无法读取：${detail}`); };
function text(bytes) {
  try { return decoder.decode(bytes); } catch { fail("文件内容或名称不是有效 UTF-8。"); }
}

const crcTable = Uint32Array.from({ length: 256 }, (_, byte) => {
  let crc = byte;
  for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (crc & 1 ? 0xedb88320 : 0);
  return crc;
});
export function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = (crc >>> 8) ^ crcTable[(crc ^ byte) & 255];
  return (crc ^ 0xffffffff) >>> 0;
}

function safeName(name) {
  const segments = name.replace(/\/$/, "").split("/");
  if (!name || /[\\:\x00-\x1f\x7f]/.test(name) || segments.some(s => !s || s === "." || s === ".." ||
      /[. ]$/.test(s) || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(s))) fail("文件路径不受支持。");
  return name.normalize("NFC").toLowerCase();
}

function uniqueName(name, seen) {
  const key = safeName(name);
  if (seen.has(key)) fail("存在重复文件路径。");
  seen.add(key);
}

export function writeZip(files) {
  if (!files.length || files.length > ZIP_LIMITS.entries) fail("文件数量超出限制。");
  const entries = [], seen = new Set();
  let offset = 0, total = 0;
  for (const file of files) {
    uniqueName(file.name, seen);
    if (file.name.endsWith("/") || typeof file.content !== "string") fail("导出文件无效。");
    const name = encoder.encode(file.name), data = encoder.encode(file.content);
    total += data.length;
    if (name.length > 65535 || data.length > ZIP_LIMITS.entryBytes || total > ZIP_LIMITS.bytes) fail("内容大小超出限制。");
    entries.push({ name, data, crc: crc32(data), offset });
    offset += 30 + name.length + data.length;
  }
  const central = offset;
  const size = central + entries.reduce((n, e) => n + 46 + e.name.length, 0) + 22;
  if (size > ZIP_LIMITS.bytes) fail("归档大小超出限制。");
  const bytes = new Uint8Array(size), view = new DataView(bytes.buffer);
  const u16 = (at, value) => view.setUint16(at, value, true);
  const u32 = (at, value) => view.setUint32(at, value, true);
  for (const e of entries) {
    let p = e.offset;
    u32(p, 0x04034b50); u16(p + 4, 20); u16(p + 6, 0x800); u16(p + 12, 33);
    u32(p + 14, e.crc); u32(p + 18, e.data.length); u32(p + 22, e.data.length); u16(p + 26, e.name.length);
    bytes.set(e.name, p + 30); bytes.set(e.data, p + 30 + e.name.length);
    p = offset;
    u32(p, 0x02014b50); u16(p + 4, 20); u16(p + 6, 20); u16(p + 8, 0x800); u16(p + 14, 33);
    u32(p + 16, e.crc); u32(p + 20, e.data.length); u32(p + 24, e.data.length); u16(p + 28, e.name.length);
    u32(p + 42, e.offset); bytes.set(e.name, p + 46); offset += 46 + e.name.length;
  }
  u32(offset, 0x06054b50); u16(offset + 8, entries.length); u16(offset + 10, entries.length);
  u32(offset + 12, offset - central); u32(offset + 16, central);
  return bytes;
}

async function inflate(data, expected) {
  let stream;
  try { stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw")); }
  catch { fail("此浏览器不支持 DEFLATE 解压，请使用未压缩 ZIP。"); }
  const reader = stream.getReader(), chunks = [];
  let length = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      length += value.length;
      if (length > expected || length > ZIP_LIMITS.entryBytes) { await reader.cancel(); fail("解压内容超出声明大小。"); }
      chunks.push(value);
    }
  } catch { await reader.cancel().catch(() => {}); fail("压缩内容损坏或解压大小不一致。"); }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return result;
}

export async function readZip(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  if (bytes.length < 22 || bytes.length > ZIP_LIMITS.bytes) fail("归档大小超出限制或文件不完整。");
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const u16 = p => view.getUint16(p, true), u32 = p => view.getUint32(p, true);
  let end = -1;
  for (let p = bytes.length - 22; p >= Math.max(0, bytes.length - 65557); p--) {
    if (u32(p) === 0x06054b50 && p + 22 + u16(p + 20) === bytes.length) { end = p; break; }
  }
  if (end < 0) fail("缺少 ZIP 结束记录。");
  const count = u16(end + 10), start = u32(end + 16), centralSize = u32(end + 12);
  if (u16(end + 4) || u16(end + 6) || u16(end + 8) !== count || !count || count > ZIP_LIMITS.entries ||
      start + centralSize !== end) fail("不支持分卷、ZIP64 或异常目录。");
  const seen = new Set(), entries = [], regions = [];
  let pos = start, total = 0;
  function extras(begin, length) {
    const stop = begin + length;
    for (let p = begin; p < stop;) {
      if (p + 4 > stop || p + 4 + u16(p + 2) > stop || u16(p) === 1) fail("不支持 ZIP64 或损坏的扩展字段。");
      p += 4 + u16(p + 2);
    }
  }
  for (let i = 0; i < count; i++) {
    if (pos + 46 > end || u32(pos) !== 0x02014b50) fail("目录记录不完整。");
    const flags = u16(pos + 8), method = u16(pos + 10), crc = u32(pos + 16), packed = u32(pos + 20), size = u32(pos + 24);
    const n = u16(pos + 28), x = u16(pos + 30), c = u16(pos + 32), local = u32(pos + 42);
    if (![0, 8].includes(method) || flags & ~(method === 8 ? 0x80e : 0x808) || u16(pos + 34) ||
        ((u32(pos + 38) >>> 16) & 0xf000) === 0xa000 || pos + 46 + n + x + c > end) fail("压缩方式、加密或文件类型不受支持。");
    const nameBytes = bytes.subarray(pos + 46, pos + 46 + n);
    if (!(flags & 0x800) && nameBytes.some(b => b > 127)) fail("文件名须使用 UTF-8 编码。");
    const name = text(nameBytes); uniqueName(name, seen);
    extras(pos + 46 + n, x);
    if (local + 30 > start || u32(local) !== 0x04034b50 || u16(local + 6) !== flags || u16(local + 8) !== method) fail("文件头与目录不一致。");
    const ln = u16(local + 26), lx = u16(local + 28), dataStart = local + 30 + ln + lx;
    if (dataStart + packed > start || ln !== n || !nameBytes.every((b, j) => b === bytes[local + 30 + j]) ||
        (!(flags & 8) && (u32(local + 14) !== crc || u32(local + 18) !== packed || u32(local + 22) !== size))) fail("文件长度或文件头不一致。");
    extras(local + 30 + ln, lx);
    total += size;
    if (size > ZIP_LIMITS.entryBytes || total > ZIP_LIMITS.bytes || (method === 0 && packed !== size)) fail("解压大小超出限制。");
    let dataEnd = dataStart + packed;
    if (flags & 8) {
      if (dataEnd + 12 > start) fail("缺少数据描述记录。");
      const descriptor = u32(dataEnd) === 0x08074b50 ? dataEnd + 4 : dataEnd;
      if (descriptor + 12 > start || u32(descriptor) !== crc || u32(descriptor + 4) !== packed || u32(descriptor + 8) !== size) fail("数据描述记录与目录不一致。");
      dataEnd = descriptor + 12;
    }
    regions.push([local, dataEnd]);
    entries.push({ name, method, crc, size, data: bytes.subarray(dataStart, dataStart + packed) });
    pos += 46 + n + x + c;
  }
  if (pos !== end) fail("目录长度不一致。");
  regions.sort((a, b) => a[0] - b[0]);
  if (regions.some((r, i) => i && r[0] < regions[i - 1][1])) fail("文件数据区域重叠。");
  const files = [];
  for (const e of entries) {
    const data = e.method === 0 ? e.data : await inflate(e.data, e.size);
    if (data.length !== e.size || crc32(data) !== e.crc) fail("文件内容与 CRC 校验不一致。");
    if (e.name.endsWith("/")) { if (data.length) fail("目录包含异常数据。"); continue; }
    files.push({ name: e.name, content: text(data) });
  }
  return files;
}
