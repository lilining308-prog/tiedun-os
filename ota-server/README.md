# 铁盾OS OTA 服务端（v2：内网管理台 + 公网分发）

纯 Python3 标准库，零依赖。详见 `docs/OTA.md`（完整手册）。

## 双端结构
| 端口 | 面向 | 功能 |
|---|---|---|
| `:8848` | 公网（经 195 的 Tailscale Funnel 443 口穿透） | 只读：构建列表 JSON（LineageOS v2 兼容）+ 包下载（Range 断点续传） |
| `:8849` | **仅内网**（不进穿透） | 管理台：上传 / 推送 / 撤销（Basic 密码登录） |

## 运行
```bash
setsid nohup python3 /mnt/data/dipper-android17/release/tiedun-os/ota-server/tiedun_ota_server.py \
  --config /mnt/data/tiedun-ota/config.json >> /mnt/data/tiedun-ota/ota.log 2>&1 &
```
开机自启：crontab `@reboot` 已装。停服：`fuser -k 8848/tcp 8849/tcp`。

## 配置（/mnt/data/tiedun-ota/config.json）
| 键 | 说明 |
|---|---|
| admin_user / admin_password | 管理台登录（默认 admin / 2012722） |
| rate_limit_mbps | 单台下载限速（默认 20 MB/s） |
| publish_window_hours | 推送到撤包窗口（默认 48h，到期删文件） |
| max_queue_wait_minutes | 串行排队最长等待（默认 30min，超时 503） |
| packages_dir / registry_file | 包目录 / 登记表 |
| public_base_url | "auto"=下载 URL 跟随访问入口（公网给公网、内网给内网） |

## 发布流程
上传（脚本自动投或管理台手动传）→ 管理台点[推送] → 公网可见（48h 窗口）→ 到期自动撤包删文件。

## 接口
| 路径 | 说明 |
|---|---|
| `GET /api/v2/devices/<device>/builds` | 更新列表 JSON（datetime/files/type/version） |
| `GET /files/<包名>` | 下载（支持 Range；串行+限速） |
| `GET /` `/health` | 索引页 / 健康检查 |
| `GET /admin/…`（:8849，鉴权） | 管理台页面 / list / upload(PUT) / push(POST) / revoke(POST) |
