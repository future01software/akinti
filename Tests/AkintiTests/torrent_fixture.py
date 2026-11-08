# Testler için yerel torrent ortamı (internet gerekmez):
#  - <out>/seed/akinti-test.bin  : paylaşılacak 2 MB'lık dosya
#  - <out>/test.torrent           : tracker'ı bu betik olan .torrent dosyası
#  - tracker                       : her duyuruya tek eş olarak 127.0.0.1:<seeder_port> döndürür
# Kullanım: python3 torrent_fixture.py <out> <seeder_port>  ->  <out>/fixture.json yazar ve tracker'ı çalıştırır
import hashlib, http.server, json, os, struct, sys

out, seeder_port = sys.argv[1], int(sys.argv[2])

def bencode(v):
    if isinstance(v, int): return b"i%de" % v
    if isinstance(v, str): v = v.encode()
    if isinstance(v, bytes): return b"%d:%s" % (len(v), v)
    if isinstance(v, list): return b"l" + b"".join(bencode(x) for x in v) + b"e"
    if isinstance(v, dict): return b"d" + b"".join(bencode(k) + bencode(v[k]) for k in sorted(v)) + b"e"
    raise TypeError(v)

class Tracker(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        body = bencode({"interval": 5, "peers": bytes([127, 0, 0, 1]) + struct.pack(">H", seeder_port)})
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Tracker)
tracker = "http://127.0.0.1:%d/announce" % server.server_port

os.makedirs(os.path.join(out, "seed"), exist_ok=True)
data = bytes((i * 7 + (i >> 8)) % 256 for i in range(2 * 1024 * 1024))
with open(os.path.join(out, "seed", "akinti-test.bin"), "wb") as f: f.write(data)
piece = 64 * 1024
info = {"name": "akinti-test.bin", "length": len(data), "piece length": piece,
        "pieces": b"".join(hashlib.sha1(data[i:i + piece]).digest() for i in range(0, len(data), piece))}
with open(os.path.join(out, "test.torrent"), "wb") as f: f.write(bencode({"announce": tracker, "info": info}))
with open(os.path.join(out, "fixture.json.tmp"), "w") as f:
    json.dump({"infohash": hashlib.sha1(bencode(info)).hexdigest(), "tracker": tracker}, f)
os.rename(os.path.join(out, "fixture.json.tmp"), os.path.join(out, "fixture.json"))
server.serve_forever()
