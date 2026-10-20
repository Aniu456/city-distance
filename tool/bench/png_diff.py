"""比较两组 PNG 预览的像素差异：python3 png_diff.py 基准目录 新目录。"""
import struct, sys, zlib, os

def read(path):
    data = open(path, 'rb').read()
    pos, chunks = 8, []
    width = height = 0
    while pos < len(data):
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b'IHDR':
            width, height, depth, color = struct.unpack('>IIBB', body[:10])
            assert depth == 8 and color == 6, (depth, color)
        elif kind == b'IDAT':
            chunks.append(body)
        pos += 12 + length
    raw = zlib.decompress(b''.join(chunks))
    stride = width * 4
    rows, prev = [], bytearray(stride)
    for y in range(height):
        f = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        rows.append(bytes(line)); prev = line
    return width, height, b''.join(rows)

base, new = sys.argv[1], sys.argv[2]
for name in sorted(os.listdir(base)):
    other = os.path.join(new, name)
    if not name.endswith('.png') or not os.path.exists(other):
        continue
    w1, h1, a = read(os.path.join(base, name)); w2, h2, b = read(other)
    if (w1, h1) != (w2, h2):
        print(f'{name}: size differs'); continue
    changed = maxd = 0
    for i in range(0, len(a), 4):
        d = max(abs(a[i + k] - b[i + k]) for k in range(4))
        if d:
            changed += 1; maxd = max(maxd, d)
    print(f'{name}: {changed} px changed ({changed * 100 / (w1 * h1):.3f}%), max channel diff {maxd}')
