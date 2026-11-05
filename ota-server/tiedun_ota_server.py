#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
铁盾OS OTA 服务端 v2.1 —— SPDX-License-Identifier: GPL-3.0
架构(用户拍板 2026-11-03):
  · 公网只读端  :8848  —— 经内网穿透(Tailscale Funnel)对外; 设备更新器只从这查/下载
  · 内网管理端  :8849  —— 仅局域网(不进穿透); 密码登录; 上传/推送/撤销更新包
  · 发布模型    : 上传→待推送(staged) → 推送(pushed, 48h 窗口) → 到期删文件
                  推送四件套: 点击推送(立即) / 设置定时推送(到点自动生效) /
                  立马推送(定时提前生效·已推送续期) / 撤回推送(下架保留包)
  · 设备上报    : 更新器检查更新时自动上报 机型/版本/设备ID, 管理台统计装机名单
  · 限流        : 同一时刻仅一台设备下载(排队), 单台限速 config.rate_limit_mbps MB/s
  · 签名        : 更新包由专属 OTA 密钥签名(打包脚本签), 设备端钉扎校验
JSON 兼容 LineageOS Updater v2; 下载 URL 跟随访问入口(公网给公网/内网给内网)。
用法: python3 tiedun_ota_server.py [--config /mnt/data/tiedun-ota/config.json]
"""
import argparse
import base64
import hashlib
import html
import json
import os
import re
import shutil
import threading
import time
import urllib.parse
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULTS = {
    "port": 8848,
    "admin_port": 8849,
    "host": "0.0.0.0",
    "packages_dir": "/mnt/data/tiedun-ota/packages",
    "registry_file": "/mnt/data/tiedun-ota/registry.json",
    "public_base_url": "auto",
    "devices": ["dipper"],
    "version": "24.0",
    "type": "UNOFFICIAL",
    "admin_user": "admin",
    "admin_password": "2012722",
    "rate_limit_mbps": 20,
    "publish_window_hours": 48,
    "max_queue_wait_minutes": 30,
}

_registry_lock = threading.Lock()
_registry = {}
_download_slot = threading.Lock()   # 串行下载: 同一时刻仅一台设备

_devices_lock = threading.Lock()
_devices = {}

# 代号 → 机型名(更新器未上报 model 时兜底标注)
MODEL_NAMES = {"dipper": "小米8"}


def log(msg):
    print("[%s] %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg), flush=True)


# ────────────────────────────── 注册表 ──────────────────────────────
def registry_path(cfg):
    return cfg["registry_file"]


def load_registry(cfg):
    global _registry
    try:
        with open(registry_path(cfg), "r", encoding="utf-8") as f:
            _registry = json.load(f)
    except Exception:
        _registry = {}


def save_registry(cfg):
    p = registry_path(cfg)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(_registry, f, ensure_ascii=False, indent=1)
    os.replace(tmp, p)


# ────────────────────────────── 设备上报 ──────────────────────────────
def devices_path(cfg):
    return os.path.join(os.path.dirname(registry_path(cfg)), "devices.json")


def load_devices(cfg):
    global _devices
    try:
        with open(devices_path(cfg), "r", encoding="utf-8") as f:
            _devices = json.load(f)
    except Exception:
        _devices = {}


def save_devices(cfg):
    p = devices_path(cfg)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(_devices, f, ensure_ascii=False, indent=1)
    os.replace(tmp, p)


def touch_device(cfg, params, ua, ip, kind, url_device=""):
    """记录设备上报(检查/下载)。params=查询参数 dict(list 值)。
    无 did 的旧版更新器按 IP 兜底入列, 机型用代号标注。"""
    def g(k, d=""):
        v = (params.get(k) or [""])[0].strip()
        return v or d
    did = g("did") or ("ip:" + ip)
    now = int(time.time())
    with _devices_lock:
        d = _devices.get(did)
        if not d:
            d = {"id": did, "model": "", "codename": "", "version": "",
                 "ua": "", "ip": ip, "first_seen": now, "last_seen": now,
                 "checks": 0, "downloads": 0}
            _devices[did] = d
            log("发现新设备: %s 机型=%s 代号=%s" % (did[:16], g("model", "-"),
                                              g("codename", url_device or "-")))
        d["model"] = g("model", d.get("model", ""))
        d["codename"] = g("codename", d.get("codename", "") or url_device)
        d["version"] = g("version", d.get("version", ""))
        if ua:
            d["ua"] = ua[:120]
        d["ip"] = ip
        d["last_seen"] = now
        if kind == "check":
            d["checks"] += 1
        elif kind == "download":
            d["downloads"] += 1
        save_devices(cfg)
    return did


def device_label(d):
    return d.get("model") or MODEL_NAMES.get(d.get("codename", ""), "") \
        or d.get("codename", "") or "未知"


def scan_new(cfg):
    """扫描 packages_dir 里未登记的 zip → staged(待推送)"""
    zdir = cfg["packages_dir"]
    os.makedirs(zdir, exist_ok=True)
    changed = False
    for name in sorted(os.listdir(zdir)):
        if not name.lower().endswith(".zip"):
            continue
        with _registry_lock:
            if name in _registry:
                continue
        st = os.stat(os.path.join(zdir, name))
        ent = {
            "name": name,
            "size": st.st_size,
            "mtime": int(st.st_mtime),
            "sha256": "",
            "datetime": 0,
            "os_patch_level": "",
            "status": "staged",
            "uploaded_at": int(time.time()),
            "pushed_at": 0,
            "scheduled_at": 0,
            "expires_at": 0,
        }
        with _registry_lock:
            _registry[name] = ent
        changed = True
        log("发现新包(待推送): %s (%d MB)" % (name, st.st_size >> 20))
    return changed


def ensure_meta(cfg, name):
    """补算 sha256 / 构建时间(推送时强制)"""
    with _registry_lock:
        ent = _registry.get(name)
    if not ent:
        return None
    path = os.path.join(cfg["packages_dir"], name)
    if not os.path.isfile(path):
        return None
    if not ent["sha256"] or not ent["datetime"]:
        log("计算元数据: %s" % name)
        h = hashlib.sha256()
        with open(path, "rb") as f:
            while True:
                b = f.read(1 << 20)
                if not b:
                    break
                h.update(b)
        ent["sha256"] = h.hexdigest()
        meta = {}
        try:
            with zipfile.ZipFile(path) as z:
                for n in ("META-INF/com/android/metadata", "META-INF/com/android/metadata.txt"):
                    if n in z.namelist():
                        for line in z.read(n).decode("utf-8", "replace").splitlines():
                            if "=" in line:
                                k, v = line.split("=", 1)
                                meta[k.strip()] = v.strip()
                        break
        except Exception as e:
            log("metadata 读取失败 %s: %s" % (name, e))
        try:
            ent["datetime"] = int(meta.get("post-timestamp", "0"))
        except Exception:
            ent["datetime"] = 0
        if ent["datetime"] <= 0:
            ent["datetime"] = int(os.stat(path).st_mtime)
        ent["os_patch_level"] = meta.get("post-security-patch-level", "")
        with _registry_lock:
            save_registry(cfg)
    return ent


def do_push(cfg, name):
    """推送: 立即公网可见, 开始 48h 窗口"""
    ent = ensure_meta(cfg, name)
    if not ent:
        return False
    now = time.time()
    with _registry_lock:
        ent["status"] = "pushed"
        ent["pushed_at"] = int(now)
        ent["scheduled_at"] = 0
        ent["expires_at"] = int(now + cfg.get("publish_window_hours", 48) * 3600)
        save_registry(cfg)
    return True


def promote_scheduled(cfg):
    """定时推送: 到点自动转为推送中"""
    now = time.time()
    with _registry_lock:
        names = [n for n, e in _registry.items()
                 if e["status"] == "scheduled" and e.get("scheduled_at", 0)
                 and now >= e["scheduled_at"]]
    for name in names:
        if do_push(cfg, name):
            log("定时推送生效: %s" % name)


def sweep(cfg):
    """48h 到期自动撤包并删文件"""
    now = time.time()
    with _registry_lock:
        names = [n for n, e in _registry.items()
                 if e["status"] == "pushed" and e["expires_at"] and now > e["expires_at"]]
    for name in names:
        path = os.path.join(cfg["packages_dir"], name)
        try:
            os.remove(path)
        except OSError:
            pass
        with _registry_lock:
            _registry[name]["status"] = "expired"
            save_registry(cfg)
        log("到期撤包并删除: %s" % name)


def sweep_loop(cfg):
    while True:
        time.sleep(60)
        try:
            scan_new(cfg)
            promote_scheduled(cfg)
            sweep(cfg)
        except Exception as e:
            log("sweep 异常: %s" % e)


# ────────────────────────────── 公网只读端 ──────────────────────────────
def base_url(cfg, handler):
    if cfg.get("public_base_url", "auto") != "auto":
        return cfg["public_base_url"].rstrip("/")
    proto = handler.headers.get("X-Forwarded-Proto", "http")
    host = handler.headers.get("Host", "127.0.0.1")
    return "%s://%s" % (proto, host)


class PublicHandler(BaseHTTPRequestHandler):
    server_version = "TieDunOta/2.1"
    cfg = None

    def log_message(self, fmt, *args):
        log("[public] %s %s" % (self.address_string(), fmt % args))

    def _send(self, code, body, ctype="text/plain; charset=utf-8", head_only=False, extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        if head_only:
            return
        try:
            self.wfile.write(body)
        except Exception:
            pass

    def do_HEAD(self):
        self.do_GET(head_only=True)

    def do_GET(self, head_only=False):
        cfg = self.cfg
        try:
            path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
            if path == "/health":
                return self._send(200, "ok", head_only=head_only)
            if path in ("/", "/index.html"):
                return self._index(head_only)
            m = re.match(r"^/api/v2/devices/([^/]+)/builds/?$", path) or \
                re.match(r"^/api/v1/([^/]+)/([^/]+)/?$", path)
            if m:
                return self._builds(m.group(1), head_only)
            m = re.match(r"^/files/(.+)$", path)
            if m:
                return self._serve_file(m.group(1), head_only)
            self._send(404, "not found")
        except BrokenPipeError:
            pass
        except Exception as e:
            log("public 异常: %s" % e)
            try:
                self._send(500, "internal error")
            except Exception:
                pass

    def _live_entries(self):
        now = time.time()
        with _registry_lock:
            items = [dict(e) for e in _registry.values()
                     if e["status"] == "pushed" and e["expires_at"] > now]
        items.sort(key=lambda e: e["datetime"], reverse=True)
        return items

    def _builds(self, device, head_only):
        cfg = self.cfg
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        # 设备上报: 更新检查即上报(机型/版本/设备ID), 管理台统计装机
        did = touch_device(cfg, q, self.headers.get("User-Agent", ""),
                           self.client_address[0], "check", device)
        out = []
        if device in cfg.get("devices", ["dipper"]):
            bu = base_url(cfg, self)
            for e in self._live_entries():
                furl = "%s/files/%s" % (bu, urllib.parse.quote(e["name"]))
                if q.get("did"):
                    furl += "?did=" + urllib.parse.quote(did)
                ent = {
                    "datetime": e["datetime"],
                    "files": [{
                        "filename": e["name"],
                        "sha256": e["sha256"],
                        "size": e["size"],
                        "url": furl,
                    }],
                    "type": cfg.get("type", "UNOFFICIAL"),
                    "version": cfg.get("version", "24.0"),
                }
                if e.get("os_patch_level"):
                    ent["files"][0]["os_patch_level"] = e["os_patch_level"]
                out.append(ent)
        self._send(200, json.dumps(out, ensure_ascii=False),
                   "application/json; charset=utf-8", head_only=head_only,
                   extra={"Cache-Control": "no-cache"})

    def _serve_file(self, name, head_only):
        cfg = self.cfg
        name = os.path.basename(name)
        with _registry_lock:
            ent = _registry.get(name)
        now = time.time()
        if not ent or ent["status"] != "pushed" or ent["expires_at"] <= now:
            return self._send(404, "no such package")
        path = os.path.join(cfg["packages_dir"], name)
        if not os.path.isfile(path):
            return self._send(404, "no such package")
        size = os.stat(path).st_size
        # 设备上报: 下载归档到设备名下
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        if q.get("did") or q.get("model"):
            touch_device(cfg, q, self.headers.get("User-Agent", ""),
                         self.client_address[0], "download")
        rng = self.headers.get("Range")
        start, end = 0, size - 1
        code = 200
        if rng:
            m = re.match(r"bytes=(\d*)-(\d*)$", rng.strip())
            if m and (m.group(1) or m.group(2)):
                if m.group(1):
                    start = int(m.group(1))
                if m.group(2):
                    end = min(int(m.group(2)), size - 1)
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", "bytes */%d" % size)
                    self.end_headers()
                    return
                code = 206
        length = end - start + 1

        # ── 限流+串行: 排队等下载槽(一台更完另一台再更) ──
        max_wait = cfg.get("max_queue_wait_minutes", 30) * 60
        got = _download_slot.acquire(timeout=max_wait)
        if not got:
            return self._send(503, "server busy, retry later",
                              extra={"Retry-After": "300"})
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(length))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Disposition",
                             'attachment; filename="%s"' % name)
            if code == 206:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
            self.end_headers()
            if head_only:
                return
            # 令牌桶限速 rate_limit_mbps MB/s
            rate = float(cfg.get("rate_limit_mbps", 20)) * 1024 * 1024
            chunk = 256 * 1024
            sent = 0.0
            t0 = time.time()
            with open(path, "rb") as f:
                f.seek(start)
                left = length
                while left > 0:
                    b = f.read(min(chunk, left))
                    if not b:
                        break
                    self.wfile.write(b)
                    left -= len(b)
                    sent += len(b)
                    due = sent / rate - (time.time() - t0)
                    if due > 0:
                        time.sleep(due)
        except (BrokenPipeError, ConnectionResetError):
            log("下载中断: %s" % name)
        finally:
            _download_slot.release()

    def _index(self, head_only):
        cfg = self.cfg
        rows = []
        for e in self._live_entries():
            left = int((e["expires_at"] - time.time()) / 3600)
            rows.append(
                "<tr><td>%s</td><td>%s</td><td>%d MB</td><td>剩 %dh</td>"
                "<td><a href=\"%s\">下载</a></td><td><code>%s…</code></td></tr>" % (
                    html.escape(cfg.get("version", "24.0")),
                    time.strftime("%Y-%m-%d %H:%M", time.localtime(e["datetime"])),
                    e["size"] >> 20, max(left, 0),
                    html.escape(base_url(cfg, self) + "/files/" + urllib.parse.quote(e["name"])),
                    html.escape(e["sha256"][:16])))
        body = """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>铁盾OS 更新服务</title><style>body{font-family:sans-serif;background:#1C1C1E;
color:#eee;margin:2em}a{color:#7fb3ff}td,th{padding:.5em 1em;border-bottom:1px solid #444}
table{border-collapse:collapse}code{color:#9c9}</style></head><body>
<h1>铁盾 OS · 系统更新</h1><p>当前提供 %d 个可下载版本（48 小时窗口内有效）</p>
<table><tr><th>版本</th><th>构建时间</th><th>大小</th><th>剩余</th><th>包</th><th>SHA-256</th></tr>
%s</table></body></html>""" % (len(rows), "\n".join(rows))
        self._send(200, body, "text/html; charset=utf-8", head_only=head_only)


# ────────────────────────────── 内网管理端 ──────────────────────────────
class AdminHandler(BaseHTTPRequestHandler):
    server_version = "TieDunOtaAdmin/2.1"
    cfg = None

    def log_message(self, fmt, *args):
        log("[admin] %s %s" % (self.address_string(), fmt % args))

    def _authed(self):
        cfg = self.cfg
        h = self.headers.get("Authorization", "")
        if h.startswith("Basic "):
            try:
                u, p = base64.b64decode(h[6:]).decode("utf-8").split(":", 1)
                if u == cfg.get("admin_user", "admin") and p == cfg.get("admin_password", ""):
                    return True
            except Exception:
                pass
        self.send_response(401)
        self.send_header("WWW-Authenticate", 'Basic realm="TieDun OTA Admin"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except Exception:
            pass

    def do_GET(self):
        if not self._authed():
            return
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        if path == "/admin/list":
            scan_new(self.cfg)
            with _registry_lock:
                items = sorted(_registry.values(), key=lambda e: e["uploaded_at"], reverse=True)
            return self._send(200, json.dumps(items, ensure_ascii=False),
                              "application/json; charset=utf-8")
        if path == "/admin/devices":
            with _devices_lock:
                items = sorted(_devices.values(),
                               key=lambda d: d.get("last_seen", 0), reverse=True)
            return self._send(200, json.dumps(items, ensure_ascii=False),
                              "application/json; charset=utf-8")
        return self._send(200, ADMIN_PAGE, "text/html; charset=utf-8")

    def do_POST(self):
        if not self._authed():
            return
        cfg = self.cfg
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = os.path.basename(q.get("name", [""])[0])
        act = urllib.parse.urlparse(self.path).path
        if not name or name not in _registry:
            return self._send(400, "bad name")
        if act == "/admin/push":          # 点击推送: 立即公网可见
            if do_push(cfg, name):
                log("点击推送: %s (48h 窗口开始)" % name)
                return self._send(200, "pushed")
            return self._send(404, "no such package")
        if act == "/admin/pushnow":       # 立马推送: 定时提前生效 / 已推送续期
            ent = _registry.get(name)
            if ent and ent["status"] == "pushed":
                now = time.time()
                with _registry_lock:
                    ent["expires_at"] = int(now + cfg.get("publish_window_hours", 48) * 3600)
                    save_registry(cfg)
                log("立马推送(窗口续期): %s" % name)
                return self._send(200, "renewed")
            if do_push(cfg, name):
                log("立马推送(定时提前): %s" % name)
                return self._send(200, "pushed")
            return self._send(404, "no such package")
        if act == "/admin/schedule":      # 设置定时推送
            try:
                at = int(q.get("at", ["0"])[0])
            except Exception:
                at = 0
            if at <= int(time.time()):
                return self._send(400, "bad time")
            ent = ensure_meta(cfg, name)
            if not ent:
                return self._send(404, "no such package")
            with _registry_lock:
                ent["status"] = "scheduled"
                ent["scheduled_at"] = at
                save_registry(cfg)
            log("定时推送设置: %s @ %s" % (name, time.strftime("%m-%d %H:%M", time.localtime(at))))
            return self._send(200, "scheduled")
        if act == "/admin/revoke":        # 撤回推送: 下架但保留包, 可再推
            with _registry_lock:
                ent = _registry.get(name)
                if ent:
                    ent["status"] = "staged"
                    ent["scheduled_at"] = 0
                    ent["pushed_at"] = 0
                    ent["expires_at"] = 0
                    save_registry(cfg)
            log("撤回推送: %s" % name)
            return self._send(200, "revoked")
        if act == "/admin/cleanup":       # 删除: 彻底删包
            try:
                os.remove(os.path.join(cfg["packages_dir"], name))
            except OSError:
                pass
            with _registry_lock:
                _registry[name]["status"] = "deleted"
                _registry[name]["scheduled_at"] = 0
                save_registry(cfg)
            log("删除: %s" % name)
            return self._send(200, "deleted")
        return self._send(404, "bad action")

    def do_PUT(self):
        if not self._authed():
            return
        cfg = self.cfg
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = os.path.basename(q.get("name", [""])[0])
        if not name.lower().endswith(".zip"):
            return self._send(400, "only .zip")
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return self._send(400, "empty")
        dest = os.path.join(cfg["packages_dir"], name)
        os.makedirs(cfg["packages_dir"], exist_ok=True)
        tmp = dest + ".part"
        remaining = length
        with open(tmp, "wb") as f:
            while remaining > 0:
                b = self.rfile.read(min(1 << 20, remaining))
                if not b:
                    break
                f.write(b)
                remaining -= len(b)
        if remaining > 0:
            os.remove(tmp)
            return self._send(400, "short upload")
        os.replace(tmp, dest)
        log("上传: %s (%d MB)" % (name, length >> 20))
        scan_new(cfg)
        return self._send(200, "uploaded")


ADMIN_PAGE = """<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">
<title>铁盾OS OTA 管理</title><style>
body{font-family:sans-serif;background:#111;color:#eee;margin:2em}
button{margin-left:.5em;padding:.4em 1em;cursor:pointer}
table{border-collapse:collapse;margin-top:1em}td,th{padding:.5em 1em;border-bottom:1px solid #333}
.staged{color:#fc6}.scheduled{color:#6af}.pushed{color:#6f6}
.expired,.revoked,.deleted{color:#888}
#up{margin-top:1.5em;padding:1em;border:1px dashed #555;border-radius:8px}
#dev{margin-top:1.5em;padding:1em;border:1px solid #363;border-radius:8px}
h2{margin-top:1.6em;font-size:1.05em}
.badge{background:#2a2;color:#fff;border-radius:10px;padding:.1em .6em;font-size:.85em}
</style></head><body>
<h1>铁盾 OS · OTA 管理台</h1>
<p>推送四件套：<b>点击推送</b>＝立即公网可见(48h 窗口) ｜ <b>设置定时推送</b>＝到点自动生效 ｜
<b>立马推送</b>＝定时提前生效 / 已推送续期 ｜ <b>撤回推送</b>＝下架保留包可再推</p>
<div id="dev"><h2>  已检测设备 <span class="badge" id="devsum">…</span></h2>
<table id="devtbl"><tr><th>机型</th><th>代号</th><th>当前版本</th><th>设备ID</th>
<th>首次在线</th><th>最后在线</th><th>检查</th><th>下载</th><th>IP</th></tr></table>
<p style="color:#888">更新器开机 / 每6h / 手动检查时自动上报(机型·版本·设备ID)，首次联网即入列。</p></div>
<div id="up"><input type="file" id="file" accept=".zip">
<button onclick="upload()">上传</button><span id="upmsg"></span></div>
<table id="tbl"><tr><th>包</th><th>大小</th><th>状态</th><th>推送/定时</th><th>剩余</th><th>操作</th></tr></table>
<script>
const NAMES={'dipper':'小米8'};
const ts=v=>v?new Date(v*1000).toLocaleString():'-';
const ST={staged:'待推送',scheduled:'已定时',pushed:'推送中',revoked:'已撤回',expired:'已过期',deleted:'已删除'};
async function refreshDevices(){
  const list=await (await fetch('/admin/devices')).json();
  const t=document.getElementById('devtbl');
  t.innerHTML='<tr><th>机型</th><th>代号</th><th>当前版本</th><th>设备ID</th><th>首次在线</th><th>最后在线</th><th>检查</th><th>下载</th><th>IP</th></tr>';
  const models={};
  for(const d of list){
    const model=d.model||NAMES[d.codename]||d.codename||'未知';
    models[model]=(models[model]||0)+1;
    t.innerHTML+='<tr><td>'+model+'</td><td>'+(d.codename||'-')+'</td><td>'+(d.version||'-')+
      '</td><td><code>'+(d.id||'').slice(0,16)+'</code></td><td>'+ts(d.first_seen)+
      '</td><td>'+ts(d.last_seen)+'</td><td>'+d.checks+'</td><td>'+d.downloads+
      '</td><td>'+(d.ip||'-')+'</td></tr>';
  }
  const sum=Object.entries(models).map(([k,v])=>k+' ×'+v).join('，');
  document.getElementById('devsum').textContent='已检测到 '+list.length+' 台 · '+(sum||'暂无');
}
async function refresh(){
  const r=await fetch('/admin/list'); const list=await r.json();
  const t=document.getElementById('tbl');
  t.innerHTML='<tr><th>包</th><th>大小</th><th>状态</th><th>推送/定时</th><th>剩余</th><th>操作</th></tr>';
  for(const e of list){
    const left=e.expires_at?Math.max(0,Math.round((e.expires_at-Date.now()/1000)/3600)):'-';
    const when=(e.status==='scheduled'&&e.scheduled_at)?('定 '+ts(e.scheduled_at)):
               (e.pushed_at?('推 '+ts(e.pushed_at)):'-');
    let ops='';
    if(e.status==='staged'){
      ops='<button onclick="act(\\'push\\',\\''+e.name+'\\')">点击推送</button>'+
          '<button onclick="schedulePush(\\''+e.name+'\\')">设置定时推送</button>'+
          '<button onclick="act(\\'cleanup\\',\\''+e.name+'\\')">删除</button>';
    }
    if(e.status==='scheduled'){
      ops='<button onclick="act(\\'pushnow\\',\\''+e.name+'\\')">立马推送</button>'+
          '<button onclick="act(\\'revoke\\',\\''+e.name+'\\')">撤回推送</button>'+
          '<button onclick="act(\\'cleanup\\',\\''+e.name+'\\')">删除</button>';
    }
    if(e.status==='pushed'){
      ops='<button onclick="act(\\'pushnow\\',\\''+e.name+'\\')">立马推送(续期)</button>'+
          '<button onclick="act(\\'revoke\\',\\''+e.name+'\\')">撤回推送</button>';
    }
    if(e.status==='revoked'||e.status==='expired'||e.status==='deleted'){
      ops='<button onclick="act(\\'cleanup\\',\\''+e.name+'\\')">删除</button>';
    }
    t.innerHTML+='<tr><td>'+e.name+'</td><td>'+(e.size>>20)+' MB</td><td class="'+e.status+'">'+
      (ST[e.status]||e.status)+'</td><td>'+when+'</td><td>'+left+'h</td><td>'+ops+'</td></tr>';
  }
}
async function act(a,name){
  await fetch('/admin/'+a+'?name='+encodeURIComponent(name),{method:'POST'});
  refresh();
}
async function schedulePush(name){
  const d=new Date(Date.now()+3600000),p=n=>String(n).padStart(2,'0');
  const def=d.getFullYear()+'-'+p(d.getMonth()+1)+'-'+p(d.getDate())+'T'+p(d.getHours())+':'+p(d.getMinutes());
  const s=prompt('定时推送生效时间 (例 2026-11-05T20:00):',def);
  if(!s)return;
  const at=Math.floor(new Date(s).getTime()/1000);
  if(isNaN(at)){alert('时间格式不对');return;}
  await fetch('/admin/schedule?name='+encodeURIComponent(name)+'&at='+at,{method:'POST'});
  refresh();
}
async function upload(){
  const f=document.getElementById('file').files[0];
  if(!f)return;
  document.getElementById('upmsg').textContent=' 上传中…(大包需几秒到几十秒)';
  const r=await fetch('/admin/upload?name='+encodeURIComponent(f.name),{method:'PUT',body:f});
  document.getElementById('upmsg').textContent=r.ok?' ✅ 上传完成, 可点推送':' ❌ 失败';
  refresh();
}
refresh();refreshDevices();setInterval(()=>{refresh();refreshDevices();},5000);
</script></body></html>"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config", default="/mnt/data/tiedun-ota/config.json")
    args = ap.parse_args()
    cfg = dict(DEFAULTS)
    try:
        with open(args.config, "r", encoding="utf-8") as f:
            cfg.update(json.load(f))
    except Exception as e:
        log("config 加载失败(%s), 用默认" % e)
    load_registry(cfg)
    load_devices(cfg)
    scan_new(cfg)
    sweep(cfg)
    threading.Thread(target=sweep_loop, args=(cfg,), daemon=True).start()

    PublicHandler.cfg = cfg
    AdminHandler.cfg = cfg
    pub = ThreadingHTTPServer((cfg["host"], int(cfg["port"])), PublicHandler)
    adm = ThreadingHTTPServer((cfg["host"], int(cfg["admin_port"])), AdminHandler)
    threading.Thread(target=adm.serve_forever, daemon=True).start()
    log("OTA 公网端 :%s  |  管理端 :%s  |  限速 %s MB/s 串行  |  窗口 %sh  |  包目录 %s"
        % (cfg["port"], cfg["admin_port"], cfg["rate_limit_mbps"],
           cfg["publish_window_hours"], cfg["packages_dir"]))
    try:
        pub.serve_forever()
    except KeyboardInterrupt:
        log("bye")


if __name__ == "__main__":
    main()
