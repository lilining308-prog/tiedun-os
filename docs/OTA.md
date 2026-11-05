# 铁盾 OS OTA 发布体系

> 对应改动清单 1.0.2.4：内置更新器「铁盾系统更新」+ 本机 OTA 服务端。

## 组成

| 件 | 位置 | 说明 |
|----|------|------|
| 更新器 | `packages/apps/TiedunUpdater/` | 检查更新 / 断点续传 / SHA-256 / Recovery 刷入 / 本地包安装 |
| OTA 服务端 | `scripts/tiedun-ota-server.py` | 本机 HTTP 服务：`update.json` 元数据 + 刷机包 |
| 发布目录 | 任意目录（默认 `./ota-root`） | `update.json` + `lineage-24.x-*-UNOFFICIAL-dipper.zip` |

## 协议

更新器请求 `ro.tiedun.ota_url`（缺省 `http://192.168.31.67:8000/update.json`），
服务端返回：

```json
{
  "version": "1.0.2.5",
  "url": "http://192.168.31.67:8000/lineage-24.x-UNOFFICIAL-dipper.zip",
  "sha256": "<64位小写十六进制>",
  "size": 1234567890,
  "changelog": "1. 修复…\n2. 新增…"
}
```

- `url` 支持 HTTP Range（断点续传依赖 206 响应）。
- 下载完成后更新器校验 `sha256`，不一致即删除并提示。

## 发布一个新版本

```bash
# 1. 编译产物 out/target/product/dipper/lineage-24.x-*-UNOFFICIAL-dipper.zip
# 2. 放入发布目录并生成元数据
python3 scripts/tiedun-ota-server.py --gen \
    --root ./ota-root \
    --zip out/target/product/dipper/lineage-24.x-UNOFFICIAL-dipper.zip \
    --version 1.0.2.5 --changelog "修复 WiFi"
# 3. 起服务(默认 0.0.0.0:8000)
python3 scripts/tiedun-ota-server.py --root ./ota-root --port 8000
```

设备端把 `ro.tiedun.ota_url` 指到该服务（或用默认地址），打开
「铁盾系统更新」→ 检查更新即可。

## 签名与安全

- 发布包为 testkey 签名（构建默认）；Recovery 安装要求包可被设备接受。
- SHA-256 防传输损坏；如需防篡改可后续在 `update.json` 加签名字段（迭代项）。
