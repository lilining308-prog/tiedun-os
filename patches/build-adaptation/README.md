# build-adaptation — 24.0 平台 + 23.2 设备树编译适配（A 系列）

BUILDING.md 第 2 节承诺的三类补丁之一。本目录把主仓归档的
「AOSP/Lineage 树内全部被修改文件」（与 `tiedun-modified-aosp-src.tar.gz` 同源）
覆盖进 `repo sync` 出来的源码树——这些适配缺一项就编不过去。

## 用法

```bash
# repo sync 之后、lunch 之前
bash patches/build-adaptation/apply-build-adaptation.sh /path/to/lineage-24.0
```

幂等（重复执行安全）。与 `scripts/tiedun-deploy.sh` 兼容：归档已是终态，
deploy 里的锚点施工会自动识别「已施工」并跳过。

## 各项适配与落点（对应 BUILDING.md 描述）

| 适配 | 落点 | 说明 |
|------|------|------|
| libheif 补齐（A2） | `vendor/xiaomi/sdm845-common/Android.bp`、`device/xiaomi/sdm845-common/sdm845.mk` | 24.0 树无 external/libheif，wfd blob 却 DT_NEEDED libheif.so；按原包 system/lib64/libheif.so 原样提取为预编译模块 |
| 跨命名空间撞名改 `_vendor`+stem | `vendor/xiaomi/{dipper,sdm845-common}/Android.bp`、`*-vendor.mk` | 平台与 blob 预编译重名（libOpenCL 等）→ 模块名加 `_vendor` 后缀；`vendor/lineage/config/common.mk` 另以 `PRODUCT_SOURCE_ROOT_DIRS += -prebuilts/misc/protobuf_vendorcompat` 排除 protobuf 撞名 |
| wfd 依赖清空 | `vendor/xiaomi/sdm845-common/Android.bp` | 37 个 wfd 预编译模块的 shared_libs 与 24.0 音频 AIDL 声明冲突（KNOWN-ISSUES #1）→ 清空（不影响运行时加载） |
| 非 CAF display 树移出构建 | `device/xiaomi/sdm845-common/sdm845.mk` 等归档态 | 显示栈只走 `hardware/qcom-caf/sdm845`（清单钦定）；非 CAF 树不进 PRODUCT_PACKAGES，仅保留 soong 命名空间可见性 |
| device_framework_matrix 补回 | `vendor/lineage/config/device_framework_matrix.xml` | 24.0 上游已移除，按 22.2 时代文件补齐（KNOWN-ISSUES #3） |
| 内核指向 4.19 树 | `device/xiaomi/sdm845-common/BoardConfigCommon.mk` | `TARGET_KERNEL_SOURCE := kernel/xiaomi/sdm845_419`；`TARGET_KERNEL_CONFIG` 含 `vendor/extras/ksu.config`（KernelSU fragment） |
| 内置更新器源码 | `packages/apps/TiedunUpdater/` | 声明.md 承诺的自研 GPL-3.0 更新器（超出 repack 清单，设备树已 `PRODUCT_PACKAGES += TiedunUpdater`）；OTA 体系见 `docs/OTA.md` |

覆盖清单与 `scripts/tiedun-repack-src.sh` 的 modified-src 列表一一对应（交付物同源）。

## 注意

- 目录级覆盖是**合并**而非删除：TheMuppets 的 `proprietary/` 二进制等同步下来的
  内容保持原位，只替换归档里有的文件。
- `packages/apps/Settings/res/values/strings.xml` 等为整文件定稿；若 24.0 平台分支
  后续有上游更新，需人工合并（归档代表 1.0.2.4 定稿时点）。
- 设备树目录（`device/xiaomi/*`）为整树终态（含 B 系列注入）；预装 APK 仍由
  `patches/tiedun-custom/apply-device.sh` 从 prebuilts/ 拷入。
