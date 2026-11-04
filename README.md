# 铁盾 OS 1.0.2.4（TieDun OS）

**铁盾 OS** 是基于 LineageOS 24（Android 17）与 4.19 内核的小米 8（dipper）第三方定制系统，
血统基底为社区第三方 UNOFFICIAL 构建 lineage-23.2-20260411-UNOFFICIAL-dipper。
内置 KernelSU（默认激活）、「铁盾之盾」权限通道（Root > Shizuku > 无障碍三档降级），
无 GApps，简体中文默认。

## 源码仓库地址（先看这里）
| 仓库 | 地址 | 内容 | 协议 |
|---|---|---|---|
| **主仓（本仓）** | <https://github.com/lilining308-prog/tiedun-os> | 安卓+上层框架改动、定制补丁、施工脚本、文档、预装 APK | GPL-3.0 |
| **内核仓** | <https://github.com/lilining308-prog/tiedun-os-system-kernel> | 4.19 内核全量源码（含 KernelSU-Next）+ dts 板级源 | GPL-2.0 |

完整编译复现：`manifests/dipper.xml`（16 仓库配方）+ `docs/BUILDING.md`。

📖 **帮助文档（点击直达）**：
- [构建/部署教程（含国内镜像下载地址、网络配置）](docs/BUILDING.md)
- [刷机教程](docs/FLASHING.md) · [更新日志](docs/CHANGELOG.md) · [已知问题](docs/KNOWN-ISSUES.md)
- [OTA 发布体系](docs/) · [开源声明与出处清单](声明.md) · [改动清单](改动清单.md)

## 硬指标
1. Android 17（LineageOS 24.0 底包）
2. 4.19 内核（4.19.325-CIP 系，与原包同源）
3. 修复 WiFi 反复提示「网络异常」（captive portal 验证地址改用国内可达节点）

## 组成
| 构件 | 来源 | 协议 |
|---|---|---|
| 平台源码 | LineageOS 24.0 / AOSP | Apache-2.0 / AOSP License |
| 内核 | sdm845-419/android_kernel_xiaomi_sdm845_419（perf 血统 + KernelSU-Next） | GPL-2.0 |
| 铁盾之盾 | lilining308（com.lilining.lockescape） | GPL-3.0 |
| Shizuku | RikkaApps/Shizuku v13.6.0 | Apache-2.0 |
| FOSS Browser | FOSS Browser（默认浏览器） | GPL-3.0 |
| 界面风格 | Material 3 Expressive（Pixel 风） | Apache-2.0 |

## 仓库
- **tiedun-os**（主仓，GPL-3.0）：本仓。定制补丁、素材、脚本、文档、预装 APK；
  并收录 AOSP/Lineage 树内**全部被修改文件**（`device/` `frameworks/` `packages/` `vendor/` `hardware/`
  五个命名空间，与 `tiedun-modified-aosp-src.tar.gz` 同源）：设备树、上层框架（PackageInstaller
  装卸策略/凭据门、Settings 关于页与鸣谢页）、内置更新器 TiedunUpdater、sepolicy 等。
- **tiedun-os-system-kernel**（内核仓，GPL-2.0）：4.19 内核源码（含 KernelSU-Next 集成）
  <https://github.com/lilining308-prog/tiedun-os-system-kernel>

## 构建
见 docs/BUILDING.md。核心步骤：
1. repo 同步 LineageOS 24.0 + 本地 manifest（manifests/dipper.xml，16 仓库配方）
2. 应用 patches/ 下全部补丁（build-adaptation、wifi-captive-portal、tiedun-custom）
3. `lunch lineage_dipper-cp2a-userdebug && mka bacon`
4. 产物：out/target/product/dipper/lineage-24.x-*-UNOFFICIAL-dipper.zip

## 鸣谢
铁盾 OS 站在这些巨人肩上（完整鸣谢见关于手机 → 鸣谢页 / THIRD_PARTY_NOTICES.md）：
LineageOS 社区 / AOSP / 谷歌 Material 设计团队 ｜ 高通 / Linux 与 CIP /
sdm845-419 与 duckyduckG / 小米（MIUI 机制参考）｜ EdwinMoq / crsvt + Dhina + Hadad /
infrag + bgcngm ｜ KernelSU(tiann) / Shizuku(Rikka) / FOSS Browser / Lawnchair /
Extinguish + Fake-Lock-Screen + Hail

—— 铁盾 OS 由 lilining308 制作 · GitHub / Gitee · lilining308@gmail.com

## 许可
主仓 GPL-3.0（LICENSE）；内核仓 GPL-2.0（聚合并存，NOTICE 公示 KernelSU×内核 许可证行业争议）。
专有件零自托管：blobs 构建时从 TheMuppets 拉取；MIUI 固件仅给官方下载链接。
