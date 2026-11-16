#!/bin/bash
# 铁盾OS build-adaptation 施工脚本: 24.0 平台 + 23.2 设备树编译适配(A 系列)
# 把主仓归档的「AOSP/Lineage 树内全部被修改文件」(与 tiedun-modified-aosp-src.tar.gz
# 同源)覆盖进 repo sync 出来的源码树。幂等: 重复执行安全。
#
# 覆盖内容 = scripts/tiedun-repack-src.sh 的 modified-src 清单:
#   - libheif 补齐 / 跨命名空间撞名改 _vendor+stem / wfd 依赖清空
#     (vendor/xiaomi/*/Android.bp、*-vendor.mk)
#   - device_framework_matrix 补回 / protobuf_vendorcompat 撞名排除
#     (vendor/lineage/config/*)
#   - 内核指向 4.19 树 + ksu.config / B 系列设备树终态
#     (device/xiaomi/*)
#   - PackageInstaller 装卸策略、Settings 关于页、CAF audio HAL 禁用
#
# 用法: bash apply-build-adaptation.sh <源码树根>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"   # 主仓根
SRC="${1:-}"
[ -n "$SRC" ] || { echo "用法: bash apply-build-adaptation.sh <源码树根>"; exit 1; }
[ -d "$SRC/build" ] && [ -d "$SRC/device" ] || { echo "不是安卓源码树根: $SRC"; exit 1; }

copy_dir() {
    local rel="$1"
    [ -d "$ROOT/$rel" ] || { echo "!! 归档缺失: $ROOT/$rel"; exit 1; }
    mkdir -p "$SRC/$rel"
    cp -a "$ROOT/$rel/." "$SRC/$rel/"
    echo "  [目录] $rel"
}
copy_file() {
    local rel="$1"
    [ -f "$ROOT/$rel" ] || { echo "!! 归档缺失: $ROOT/$rel"; exit 1; }
    mkdir -p "$SRC/$(dirname "$rel")"
    cp -a "$ROOT/$rel" "$SRC/$rel"
    echo "  [文件] $rel"
}

echo "== build-adaptation: 归档修改件覆盖进 $SRC =="

# 1) 设备树整树(最终态: BoardConfig 内核指向 4.19 + ksu.config、device.mk 注入、sepolicy 等)
copy_dir device/xiaomi/dipper
copy_dir device/xiaomi/sdm845-common

# 2) PackageInstaller 装卸策略(B7 改动的 res/src 整树)
copy_dir frameworks/base/packages/PackageInstaller/res
copy_dir frameworks/base/packages/PackageInstaller/src

# 3) CAF audio HAL(禁用与 stock blob 撞名的源码模块)
copy_dir hardware/qcom-caf/sdm845/audio/hal

# 4) Settings 关于页/鸣谢页(B5 改动件)
copy_file packages/apps/Settings/res/drawable/tiedun_hero_gradient.xml
copy_file packages/apps/Settings/res/layout/tiedun_about_hero.xml
copy_file packages/apps/Settings/res/values/strings.xml
copy_file packages/apps/Settings/res/values-zh-rCN/strings.xml
copy_file packages/apps/Settings/res/xml/my_device_info.xml
copy_file packages/apps/Settings/res/xml/tiedun_credits.xml
copy_file packages/apps/Settings/src/com/android/settings/deviceinfo/aboutphone/MyDeviceInfoFragment.java
copy_file packages/apps/Settings/src/com/android/settings/core/gateway/SettingsGateway.java
copy_dir packages/apps/Settings/src/com/android/settings/deviceinfo/tiedun

# 5) vendor/lineage 配置(protobuf_vendorcompat 撞名排除 + device_framework_matrix 补回)
copy_file vendor/lineage/config/common.mk
copy_file vendor/lineage/config/device_framework_matrix.xml

# 6) vendor/xiaomi 生成件(_vendor+stem 撞名改名、wfd 依赖清空、libheif 模块)
copy_file vendor/xiaomi/dipper/Android.bp
copy_file vendor/xiaomi/dipper/dipper-vendor.mk
copy_file vendor/xiaomi/sdm845-common/Android.bp
copy_file vendor/xiaomi/sdm845-common/sdm845-common-vendor.mk

# 7) 内置更新器源码(声明.md 承诺的自研 GPL-3.0 件, 不在 repack 清单内)
copy_dir packages/apps/TiedunUpdater

echo "== 完成。提示: 内核侧别忘了 bash kernel/…/patches/apply-a18-dts.sh =="
