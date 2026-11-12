"""Converts an RGBA PNG to the uncompressed 32-bit TGA that WoW loads as a
texture. Standard library only (no Pillow).

  python png_to_tga.py badge.png ../NpcSonar/Media/sonar_search.tga
"""
import struct
import sys
import zlib


def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if (depth, colour, interlace) != (8, 6, 0):
                raise ValueError(f"{path}: need 8-bit non-interlaced RGBA, got depth={depth} colour={colour}")
        elif kind == b"IDAT":
            idat += chunk
        pos += 12 + length

    raw = zlib.decompress(idat)
    bpp, stride = 4, width * 4
    rows, prev = [], bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        kind, line = raw[start], bytearray(raw[start + 1:start + 1 + stride])
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if kind == 1:
                line[x] = (line[x] + a) & 255
            elif kind == 2:
                line[x] = (line[x] + b) & 255
            elif kind == 3:
                line[x] = (line[x] + (a + b) // 2) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(line)
        prev = line
    return width, height, rows


def write_tga(path, width, height, rows):
    # Type 2 (uncompressed true-colour), 32 bpp, descriptor 0x08 = bottom-left
    # origin with 8 alpha bits, so rows are written bottom-up. Bottom-left is
    # the TGA default and what every WoW client reads; the top-left flag is
    # not honoured everywhere.
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x08)
    body = bytearray()
    for line in reversed(rows):
        for x in range(0, len(line), 4):
            r, g, b, a = line[x:x + 4]
            body += bytes((b, g, r, a))
    open(path, "wb").write(header + body)


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    w, h, px = read_png(src)
    write_tga(dst, w, h, px)
    print(f"wrote {dst} ({w}x{h})")
