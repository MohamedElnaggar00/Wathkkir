import sys, zlib, struct
# stdlib PNG decode: prints 1 if the screenshot is mostly the dark ANR-scrim color, else 0
d = open(sys.argv[1], 'rb').read()
pos = 8; w = h = ct = None; idat = b''
while pos < len(d):
    ln = struct.unpack('>I', d[pos:pos+4])[0]; typ = d[pos+4:pos+8]
    if typ == b'IHDR': w, h, bd, ct = struct.unpack('>IIBB', d[pos+8:pos+18])
    elif typ == b'IDAT': idat += d[pos+8:pos+8+ln]
    pos += 12 + ln
raw = zlib.decompress(idat)
ch = 4 if ct == 6 else 3
stride = w * ch
prev = bytearray(stride); p = 0
dark = tot = 0
for y in range(h):
    f = raw[p]; p += 1
    line = bytearray(raw[p:p+stride]); p += stride
    if f == 1:
        for i in range(ch, stride): line[i] = (line[i] + line[i-ch]) & 255
    elif f == 2:
        for i in range(stride): line[i] = (line[i] + prev[i]) & 255
    elif f == 3:
        for i in range(stride): line[i] = (line[i] + ((line[i-ch] if i >= ch else 0) + prev[i]) // 2) & 255
    elif f == 4:
        for i in range(stride):
            a = line[i-ch] if i >= ch else 0; b = prev[i]; c = prev[i-ch] if i >= ch else 0
            q = a + b - c; pa, pb, pc = abs(q-a), abs(q-b), abs(q-c)
            line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255
    if y % 40 == 0:
        for x in range(0, w, 40):
            r, g, b = line[x*ch], line[x*ch+1], line[x*ch+2]
            tot += 1
            if abs(r-51) + abs(g-54) + abs(b-58) < 40: dark += 1
    prev = line
print(1 if dark * 2 > tot else 0)
