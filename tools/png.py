"""Minimal pure-python PNG reader/writer (8-bit RGBA/RGB/gray+alpha)."""
import struct, zlib


def _chunks(data):
    pos = 8
    while pos < len(data):
        (ln,) = struct.unpack(">I", data[pos : pos + 4])
        typ = data[pos + 4 : pos + 8]
        yield typ, data[pos + 8 : pos + 8 + ln]
        pos += 12 + ln


def read(path):
    data = open(path, "rb").read()
    idat = b""
    plte = None
    trns = None
    w = h = bd = ct = None
    for typ, body in _chunks(data):
        if typ == b"IHDR":
            w, h, bd, ct, comp, filt, inter = struct.unpack(">IIBBBBB", body)
            assert bd == 8 and inter == 0, (bd, inter)
        elif typ == b"IDAT":
            idat += body
        elif typ == b"PLTE":
            plte = body
        elif typ == b"tRNS":
            trns = body
    raw = zlib.decompress(idat)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    stride = w * channels
    out = bytearray(h * stride)
    pos = 0
    prev = bytearray(stride)
    for y in range(h):
        f = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride : (y + 1) * stride] = line
        prev = line
    # convert to RGBA
    rgba = bytearray(w * h * 4)
    for i in range(w * h):
        if ct == 6:
            r, g, b, a = out[i * 4 : i * 4 + 4]
        elif ct == 2:
            r, g, b = out[i * 3 : i * 3 + 3]
            a = 255
        elif ct == 0:
            r = g = b = out[i]
            a = 255
        elif ct == 4:
            r = g = b = out[i * 2]
            a = out[i * 2 + 1]
        elif ct == 3:
            p = out[i]
            r, g, b = plte[p * 3 : p * 3 + 3]
            a = trns[p] if trns and p < len(trns) else 255
        rgba[i * 4 : i * 4 + 4] = bytes((r, g, b, a))
    return w, h, rgba


def write(path, w, h, rgba):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw += rgba[y * stride : (y + 1) * stride]
    comp = zlib.compress(bytes(raw), 9)
    def chunk(typ, body):
        c = struct.pack(">I", len(body)) + typ + body
        return c + struct.pack(">I", zlib.crc32(typ + body) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", comp)
    png += chunk(b"IEND", b"")
    open(path, "wb").write(png)


def crop(src, sx, sy, sw, sh):
    w, h, rgba = src
    out = bytearray(sw * sh * 4)
    for y in range(sh):
        for x in range(sw):
            si = ((sy + y) * w + (sx + x)) * 4
            di = (y * sw + x) * 4
            out[di : di + 4] = rgba[si : si + 4]
    return sw, sh, out
