#!/usr/bin/env python3
# 铁盾OS 本机 OTA 服务端(GPL-3.0) — 见 docs/OTA.md
#   生成元数据: python3 tiedun-ota-server.py --gen --root DIR --zip FILE --version V [--changelog TEXT]
#   启动服务:   python3 tiedun-ota-server.py --root DIR [--port 8000]
import argparse, hashlib, http.server, json, os, shutil, sys

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def gen(args):
    os.makedirs(args.root, exist_ok=True)
    dst = os.path.join(args.root, os.path.basename(args.zip))
    if os.path.abspath(args.zip) != os.path.abspath(dst):
        shutil.copy2(args.zip, dst)
    meta = {
        "version": args.version,
        "url": "{}/{}".format(args.url_base.rstrip("/"), os.path.basename(dst)),
        "sha256": sha256(dst),
        "size": os.path.getsize(dst),
        "changelog": args.changelog or "",
    }
    with open(os.path.join(args.root, "update.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print(json.dumps(meta, ensure_ascii=False, indent=2))

class Handler(http.server.SimpleHTTPRequestHandler):
    # 支持 Range(断点续传)
    def send_head(self):
        rng = self.headers.get("Range")
        if not rng or not rng.startswith("bytes="):
            return super().send_head()
        path = self.translate_path(self.path)
        if not os.path.isfile(path):
            return super().send_head()
        start, end = rng[6:].split("-", 1)
        size = os.path.getsize(path)
        start = int(start) if start else 0
        end = int(end) if end else size - 1
        end = min(end, size - 1)
        f = open(path, "rb")
        f.seek(start)
        self.send_response(206)
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Content-Range", "bytes {}-{}/{}".format(start, end, size))
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        return _Slice(f, end - start + 1)

class _Slice:
    def __init__(self, f, remain):
        self.f, self.remain = f, remain
    def read(self, n=-1):
        if self.remain <= 0:
            return b""
        if n < 0 or n > self.remain:
            n = self.remain
        data = self.f.read(n)
        self.remain -= len(data)
        return data
    def close(self):
        self.f.close()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--root", default="./ota-root")
    p.add_argument("--port", type=int, default=8000)
    p.add_argument("--gen", action="store_true")
    p.add_argument("--zip")
    p.add_argument("--version")
    p.add_argument("--changelog", default="")
    p.add_argument("--url-base", default="")
    args = p.parse_args()
    if args.gen:
        if not (args.zip and args.version):
            sys.exit("--gen 需要 --zip 与 --version")
        if not args.url_base:
            args.url_base = "http://127.0.0.1:{}".format(args.port)
        return gen(args)
    os.chdir(args.root)
    httpd = http.server.ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    print("OTA 服务: http://0.0.0.0:{}/  (root={})".format(args.port, args.root))
    httpd.serve_forever()

if __name__ == "__main__":
    main()
