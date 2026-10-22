"""Inspect / patch the GFx stream inside a Witcher 3 .redswf (CR2W CSwfResource).

    python -I tools/cr2w_swf.py info    <file.redswf>
    python -I tools/cr2w_swf.py extract <file.redswf> <out.gfx>
    python -I tools/cr2w_swf.py patch   <in.redswf> <new.gfx> <out.redswf>

The .redswf holds one CSwfResource export (whose DataBuffer is the compressed
GFx movie, "CFX" signature) followed by CSwfTexture exports. 'patch' swaps the
GFx bytes, shifts the following exports and recomputes sizes and CRCs.
"""
import struct
import sys
import zlib

HEADER = struct.Struct("<4sIIQIIII")  # magic, version, flags, timestamp, build, fileSize, bufferSize, crc
TABLE = struct.Struct("<III")         # offset, count, crc
EXPORT = struct.Struct("<HHIIIII")    # class, flags, parent, dataSize, dataOffset, template, crc
EXPORTS_TABLE = 4
EXPORT_SIZES = {0: 1, 1: 8, 2: 8, 3: 16, 4: 24, 5: 24, 6: 24}  # bytes per entry, table 0 counts bytes


def crc(data):
    return zlib.crc32(data) & 0xFFFFFFFF


def header_crc(buf, hdr):
    """CRC32 of header + table directory (160 bytes) with the crc field set to 0xDEADBEEF."""
    head = bytearray(buf[:HEADER.size + 4 + 10 * TABLE.size])
    HEADER.pack_into(head, 0, *(hdr[:7] + [0xDEADBEEF]))
    return crc(bytes(head))


def parse(buf):
    hdr = list(HEADER.unpack_from(buf, 0))
    num_chunks = struct.unpack_from("<I", buf, HEADER.size)[0]
    tables = [list(TABLE.unpack_from(buf, HEADER.size + 4 + i * TABLE.size)) for i in range(10)]
    off, count, _ = tables[EXPORTS_TABLE]
    exports = [list(EXPORT.unpack_from(buf, off + i * EXPORT.size)) for i in range(count)]
    return hdr, num_chunks, tables, exports


def table_bytes(buf, i, tables):
    off, count, _ = tables[i]
    return buf[off:off + count * EXPORT_SIZES.get(i, 0)]


def find_gfx(buf, export):
    """Offset of the CFX/GFX stream and its compressed length inside an export."""
    start, end = export[4], export[4] + export[3]
    for sig in (b"CFX", b"GFX"):
        pos = buf.find(sig, start, end)
        if pos > 4:
            length = struct.unpack_from("<I", buf, pos - 4)[0]
            if pos + length <= end:
                return pos, length
    raise SystemExit("no GFx stream found in the first export")


def info(path):
    buf = open(path, "rb").read()
    hdr, chunks, tables, exports = parse(buf)
    print("version", hdr[1], "fileSize", hdr[5], "bufferSize", hdr[6], "crc %08x" % hdr[7],
          "recomputed %08x" % header_crc(buf, hdr), "chunks", chunks)
    for i, (off, count, c) in enumerate(tables):
        if count:
            data = table_bytes(buf, i, tables)
            print("table %d off=%d count=%d crc=%08x recomputed=%08x" % (i, off, count, c, crc(data)))
    for i, e in enumerate(exports):
        data = buf[e[4]:e[4] + e[3]]
        print("export %2d class=%d size=%d offset=%d crc=%08x recomputed=%08x" % (i, e[0], e[3], e[4], e[6], crc(data)))
    pos, length = find_gfx(buf, exports[0])
    print("gfx at", pos, "length", length)


def extract(src, out):
    buf = open(src, "rb").read()
    _, _, _, exports = parse(buf)
    pos, length = find_gfx(buf, exports[0])
    open(out, "wb").write(buf[pos:pos + length])
    print("extracted gfx: %d bytes" % length)


def patch(src, gfx_path, out):
    buf = bytearray(open(src, "rb").read())
    gfx = open(gfx_path, "rb").read()
    hdr, chunks, tables, exports = parse(buf)
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
    for i in range(10):
        if tables[i][1]:
            tables[i][2] = crc(bytes(table_bytes(buf, i, tables)))
            TABLE.pack_into(buf, HEADER.size + 4 + i * TABLE.size, *tables[i])

    hdr[5] += delta
    hdr[6] += delta
    hdr[7] = header_crc(buf, hdr)
    HEADER.pack_into(buf, 0, *hdr)
    open(out, "wb").write(buf)
    print("patched: gfx %d -> %d bytes, file %d bytes" % (length, len(gfx), len(buf)))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "info":
        info(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "extract":
        extract(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 5 and sys.argv[1] == "patch":
        patch(sys.argv[2], sys.argv[3], sys.argv[4])
    else:
        raise SystemExit(__doc__)
