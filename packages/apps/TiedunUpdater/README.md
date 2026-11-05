# TiedunUpdater — 铁盾系统更新（内置更新器，自研 GPL-3.0）

声明.md 承诺的自研更新器源码。功能对齐改动清单 1.0.2.4：
检查更新 / 断点续传下载 / SHA-256 校验 / 自动重启进 Recovery 刷入 / 本地包安装。

## 集成

- `Android.bp`：`android_app`，platform 证书 + privileged（持有 `RECOVERY`
  签名权限以调用 `RecoverySystem.processPackage`）。
- 设备树 `PRODUCT_PACKAGES += TiedunUpdater`（已并入归档 device.mk）。
- 更新源地址：系统属性 `ro.tiedun.ota_url`，缺省 `http://192.168.31.67:8000/update.json`
  （本机 OTA 服务端，协议见 [docs/OTA.md](../../docs/OTA.md)）。

## 说明

1.0.2.4 出包时更新通道走的是 LineageOS 自带 Updater（`vendor/lineage/config/common.mk`
的 `Updater`），本目录补齐声明.md 承诺的自研 GPL-3.0 源码实现；如以本应用为准，
可在 common.mk 移除 `Updater` 条目避免双更新器。

## 许可

GPL-3.0-or-later（见主仓 LICENSE）。
