"""Inspect / patch the GFx movie inside a Witcher 3 .redswf (CR2W file holding a CSwfResource).

Used by stl.ps1 (build ui); runs only at build time, never shipped with the mod.
Why it exists, what it does and how it is checked: docs/cr2w_swf.md

    python -I tools/lib/cr2w_swf.py info    <file.redswf>
    python -I tools/lib/cr2w_swf.py verify  <file.redswf>
    python -I tools/lib/cr2w_swf.py extract <file.redswf> <out.gfx>
    python -I tools/lib/cr2w_swf.py patch   <in.redswf> <new.gfx> <out.redswf>

A .redswf is a CR2W container: export 0 is the CSwfResource, whose data holds the
compressed GFx movie ("CFX", preceded by its length); the following exports are the
CSwfTexture images, left untouched. 'patch' swaps the movie, shifts the following
exports and recomputes every size and CRC (standard CRC32: per export data, per table,
and for the header + table directory, computed with the crc field set to 0xDEADBEEF).
"""
import struct
import sys
import zlib

HEADER = struct.Struct("<4sIIQIIII")  # magic, version, flags, timestamp, build, fileSize, bufferSize, crc
TABLE = struct.Struct("<III")         # offset, count, crc
EXPORT = struct.Struct("<HHIIIII")    # class, flags, parent, dataSize, dataOffset, template, crc
TABLES = 10
HEADER_BLOCK = HEADER.size + 4 + TABLES * TABLE.size  # header + chunk count + table directory = 160
EXPORTS_TABLE = 4
ENTRY_SIZES = {0: 1, 1: 8, 2: 8, 3: 16, 4: 24, 5: 24, 6: 24}  # bytes per entry (table 0 counts bytes)


def crc(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def header_crc(buf, hdr):
    head = bytearray(buf[:HEADER_BLOCK])
    HEADER.pack_into(head, 0, *(hdr[:7] + [0xDEADBEEF]))
    return crc(bytes(head))


def parse(buf):
    if buf[:4] != b"CR2W":
        raise SystemExit("not a CR2W file")
    hdr = list(HEADER.unpack_from(buf, 0))
    num_chunks = struct.unpack_from("<I", buf, HEADER.size)[0]
    tables = [list(TABLE.unpack_from(buf, HEADER.size + 4 + i * TABLE.size)) for i in range(TABLES)]
    off, count, _ = tables[EXPORTS_TABLE]
    exports = [list(EXPORT.unpack_from(buf, off + i * EXPORT.size)) for i in range(count)]
    return hdr, num_chunks, tables, exports


def table_bytes(buf, i, tables):
    off, count, _ = tables[i]
    return buf[off:off + count * ENTRY_SIZES.get(i, 0)]


def find_gfx(buf, export):
    """Offset of the compressed movie and its length inside the CSwfResource export."""
    start, end = export[4], export[4] + export[3]
    for sig in (b"CFX", b"GFX"):
        pos = buf.find(sig, start + 4, end)
        if pos > 0:
            length = struct.unpack_from("<I", buf, pos - 4)[0]
            if pos + length <= end:
                return pos, length
    raise SystemExit("no GFx movie found in the CSwfResource export")


def problems(buf):
    """Every size or CRC that does not match (empty list = valid file)."""
    hdr, _, tables, exports = parse(buf)
    found = []
    if hdr[5] != len(buf):
        found.append("fileSize %d != file length %d" % (hdr[5], len(buf)))
    if hdr[7] != header_crc(buf, hdr):
        found.append("header crc mismatch")
    for i, (_, count, c) in enumerate(tables):
        if count and c != crc(table_bytes(buf, i, tables)):
            found.append("table %d crc mismatch" % i)
    for i, e in enumerate(exports):
        if e[6] != crc(buf[e[4]:e[4] + e[3]]):
            found.append("export %d crc mismatch" % i)
    return found


def info(path):
    buf = open(path, "rb").read()
    hdr, chunks, tables, exports = parse(buf)
    print("version", hdr[1], "fileSize", hdr[5], "bufferSize", hdr[6], "crc %08x" % hdr[7], "chunks", chunks)
    for i, (off, count, c) in enumerate(tables):
        if count:
            print("table %d off=%d count=%d crc=%08x" % (i, off, count, c))
    for i, e in enumerate(exports):
        print("export %2d class=%d size=%d offset=%d crc=%08x" % (i, e[0], e[3], e[4], e[6]))
    pos, length = find_gfx(buf, exports[0])
    print("gfx at", pos, "length", length)
    print("valid" if not problems(buf) else "INVALID: " + ", ".join(problems(buf)))


def verify(path):
    found = problems(open(path, "rb").read())
    if found:
        raise SystemExit("invalid redswf: " + ", ".join(found))
    print("redswf ok")


def extract(src, out):
    buf = open(src, "rb").read()
    _, _, _, exports = parse(buf)
    pos, length = find_gfx(buf, exports[0])
    open(out, "wb").write(buf[pos:pos + length])
    print("extracted gfx: %d bytes" % length)


def patch(src, gfx_path, out):
    buf = bytearray(open(src, "rb").read())
    gfx = open(gfx_path, "rb").read()
    hdr, _, tables, exports = parse(buf)
    pos, length = find_gfx(buf, exports[0])
    delta = len(gfx) - length

    buf[pos:pos + length] = gfx
    struct.pack_into("<I", buf, pos - 4, len(gfx))

    exports[0][3] += delta
    for e in exports[1:]:
        if e[4] > pos:
            e[4] += delta
    for e in exports:
        e[6] = crc(bytes(buf[e[4]:e[4] + e[3]]))
    off = tables[EXPORTS_TABLE][0]
    for i, e in enumerate(exports):
        EXPORT.pack_into(buf, off + i * EXPORT.size, *e)
    for i in range(TABLES):
        if tables[i][1]:
            tables[i][2] = crc(bytes(table_bytes(buf, i, tables)))
            TABLE.pack_into(buf, HEADER.size + 4 + i * TABLE.size, *tables[i])

    hdr[5] += delta
    hdr[6] += delta
    hdr[7] = header_crc(buf, hdr)
    HEADER.pack_into(buf, 0, *hdr)

    found = problems(bytes(buf))
    if found:
        raise SystemExit("patched redswf would be invalid: " + ", ".join(found))
    open(out, "wb").write(buf)
    print("patched: gfx %d -> %d bytes, file %d bytes" % (length, len(gfx), len(buf)))


if __name__ == "__main__":
    commands = {"info": (info, 1), "verify": (verify, 1), "extract": (extract, 2), "patch": (patch, 3)}
    if len(sys.argv) < 2 or sys.argv[1] not in commands or len(sys.argv) - 2 != commands[sys.argv[1]][1]:
        raise SystemExit(__doc__)
    commands[sys.argv[1]][0](*sys.argv[2:])
