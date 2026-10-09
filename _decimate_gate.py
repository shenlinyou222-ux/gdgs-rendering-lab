
import struct, re
src = "assets/hy_cell01_sym2.ply"
dst = "assets/hy_cell01_lod.ply"
data = open(src, "rb").read()
hdr_end = data.find(b"end_header\n") + len(b"end_header\n")
header = data[:hdr_end].decode("latin1")
n = int(re.search(r"element vertex (\d+)", header).group(1))
props = re.findall(r"property (\w+) (\w+)", header)
sizes = {"float":4,"double":8,"uchar":1,"int":4,"uint":4,"short":2,"ushort":2}
names = [p[1] for p in props]
stride = sum(sizes[t] for t, _ in props)
off = {}
o = 0
for t, nm in props:
    off[nm] = o
    o += sizes[t]
body = data[hdr_end:]
assert len(body) >= n * stride, "body short"
K = n // 4
i_op, s0, s1, s2 = off["opacity"], off["scale_0"], off["scale_1"], off["scale_2"]
scores = []
for i in range(n):
    b = i * stride
    op = struct.unpack_from("<f", body, b + i_op)[0]
    a = struct.unpack_from("<f", body, b + s0)[0]
    c = struct.unpack_from("<f", body, b + s1)[0]
    d = struct.unpack_from("<f", body, b + s2)[0]
    scores.append(op * (a + c + d))   # scale 为 log,和即 log 体积
order = sorted(range(n), key=lambda i: scores[i], reverse=True)[:K]
keep = sorted(order)
new_header = header.replace("element vertex " + str(n), "element vertex " + str(K))
out = [new_header.encode("latin1")]
for i in keep:
    out.append(body[i*stride:(i+1)*stride])
open(dst, "wb").write(b"".join(out))
print("decimated", n, "->", K, "bytes", len(b"".join(out)))
