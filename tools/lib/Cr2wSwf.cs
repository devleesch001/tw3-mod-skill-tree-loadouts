// Reads / patches the GFx movie inside a Witcher 3 .redswf (CR2W file holding a CSwfResource).
// Loaded by tools/lib/redswf.ps1 with Add-Type.
//
// Layout used (all little-endian):
//   header   0..35  magic "CR2W", version, flags, timestamp(8), build, fileSize@24, bufferSize@28, crc@32
//   chunks   36     number of chunks
//   tables   40..159  10 x { offset, count, crc } ; table 4 = exports
//   export   24 bytes { class u16, flags u16, parent, dataSize@8, dataOffset@12, template, crc@20 }
// Export 0 is the CSwfResource; its data holds the compressed movie ("CFX", preceded by its
// length). The following exports are the CSwfTexture objects, left untouched.
// CRCs are standard CRC32: per export data, per table, and for the header + table directory
// (160 bytes) computed with the crc field set to 0xDEADBEEF.
using System;
using System.Text;

public static class Cr2wSwf
{
    const int TablesOffset = 40;
    const int TableCount = 10;
    const int HeaderSize = TablesOffset + TableCount * 12;
    const int ExportsTable = 4;
    const int ExportSize = 24;
    static readonly int[] EntrySizes = { 1, 8, 8, 16, 24, 24, 24, 0, 0, 0 };

    static uint[] crcTable;

    public static uint Crc32(byte[] data, int offset, int length)
    {
        if (crcTable == null)
        {
            crcTable = new uint[256];
            for (uint i = 0; i < 256; i++)
            {
                uint c = i;
                for (int k = 0; k < 8; k++)
                    c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                crcTable[i] = c;
            }
        }
        uint crc = 0xFFFFFFFFu;
        for (int i = offset; i < offset + length; i++)
            crc = crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFFu;
    }

    static uint U32(byte[] b, int o) { return BitConverter.ToUInt32(b, o); }

    static void SetU32(byte[] b, int o, uint v)
    {
        b[o] = (byte)v; b[o + 1] = (byte)(v >> 8); b[o + 2] = (byte)(v >> 16); b[o + 3] = (byte)(v >> 24);
    }

    static int TableOffset(byte[] b, int t) { return (int)U32(b, TablesOffset + t * 12); }
    static int TableEntries(byte[] b, int t) { return (int)U32(b, TablesOffset + t * 12 + 4); }
    static int ExportEntry(byte[] b, int i) { return TableOffset(b, ExportsTable) + i * ExportSize; }

    static void CheckMagic(byte[] b)
    {
        if (b.Length < HeaderSize || Encoding.ASCII.GetString(b, 0, 4) != "CR2W")
            throw new InvalidOperationException("not a CR2W file");
    }

    static uint HeaderCrc(byte[] b)
    {
        byte[] head = new byte[HeaderSize];
        Array.Copy(b, head, HeaderSize);
        SetU32(head, 32, 0xDEADBEEFu);
        return Crc32(head, 0, HeaderSize);
    }

    // offset and length of the compressed movie inside export 0
    static void FindGfx(byte[] b, out int pos, out int length)
    {
        int e = ExportEntry(b, 0);
        int start = (int)U32(b, e + 12);
        int end = start + (int)U32(b, e + 8);
        foreach (string sig in new[] { "CFX", "GFX" })
        {
            byte[] s = Encoding.ASCII.GetBytes(sig);
            for (int p = start + 4; p + 3 <= end; p++)
            {
                if (b[p] == s[0] && b[p + 1] == s[1] && b[p + 2] == s[2])
                {
                    int len = (int)U32(b, p - 4);
                    if (len > 8 && p + len <= end) { pos = p; length = len; return; }
                }
            }
        }
        throw new InvalidOperationException("no GFx movie found in the CSwfResource export");
    }

    public static byte[] ExtractGfx(byte[] b)
    {
        int pos, length;
        CheckMagic(b);
        FindGfx(b, out pos, out length);
        byte[] gfx = new byte[length];
        Array.Copy(b, pos, gfx, 0, length);
        return gfx;
    }

    public static byte[] Patch(byte[] src, byte[] gfx)
    {
        int pos, length;
        CheckMagic(src);
        FindGfx(src, out pos, out length);
        int delta = gfx.Length - length;

        byte[] b = new byte[src.Length + delta];
        Array.Copy(src, 0, b, 0, pos);
        Array.Copy(gfx, 0, b, pos, gfx.Length);
        Array.Copy(src, pos + length, b, pos + gfx.Length, src.Length - pos - length);
        SetU32(b, pos - 4, (uint)gfx.Length);

        int exports = TableEntries(b, ExportsTable);
        for (int i = 0; i < exports; i++)
        {
            int e = ExportEntry(b, i);
            if (i == 0)
                SetU32(b, e + 8, (uint)((int)U32(b, e + 8) + delta));
            else if ((int)U32(b, e + 12) > pos)
                SetU32(b, e + 12, (uint)((int)U32(b, e + 12) + delta));
        }
        for (int i = 0; i < exports; i++)
        {
            int e = ExportEntry(b, i);
            SetU32(b, e + 20, Crc32(b, (int)U32(b, e + 12), (int)U32(b, e + 8)));
        }
        for (int t = 0; t < TableCount; t++)
        {
            int count = TableEntries(b, t);
            if (count > 0)
                SetU32(b, TablesOffset + t * 12 + 8, Crc32(b, TableOffset(b, t), count * EntrySizes[t]));
        }
        SetU32(b, 24, (uint)((int)U32(b, 24) + delta));
        SetU32(b, 28, (uint)((int)U32(b, 28) + delta));
        SetU32(b, 32, HeaderCrc(b));
        return b;
    }

    // "" when every CRC and size checks out, otherwise the first problem found
    public static string Verify(byte[] b)
    {
        CheckMagic(b);
        if (U32(b, 24) != b.Length) return "fileSize does not match the file length";
        if (U32(b, 32) != HeaderCrc(b)) return "header crc mismatch";
        for (int t = 0; t < TableCount; t++)
        {
            int count = TableEntries(b, t);
            if (count > 0 && U32(b, TablesOffset + t * 12 + 8) != Crc32(b, TableOffset(b, t), count * EntrySizes[t]))
                return "table " + t + " crc mismatch";
        }
        int exports = TableEntries(b, ExportsTable);
        for (int i = 0; i < exports; i++)
        {
            int e = ExportEntry(b, i);
            if (U32(b, e + 20) != Crc32(b, (int)U32(b, e + 12), (int)U32(b, e + 8)))
                return "export " + i + " crc mismatch";
        }
        return "";
    }
}
