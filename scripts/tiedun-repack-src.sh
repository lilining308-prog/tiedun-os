#!/bin/bash
# 铁盾OS B14-补充: 交付 tarball 重打 + 许可证断言
# 保证「源码 / 内核源码」两个归档 = 最终生效树(含 A6-A10、B1-B15 全部改动),
# 且许可证文件一个不丢(红线)。由 tiedun-package.sh 自动调用, 亦可单独跑。
# 用法: bash tiedun-repack-src.sh   (在树莓派执行)
set -euo pipefail
T67=ubuntu@192.168.31.67
SRC=/mnt/build/buildspace/android/lineage-24.0
DEST="/mnt/data/小米8铁盾os"
DESTK="$DEST/内核源码"
DESTS="$DEST/源码"

echo "== 1/3 重打内核 tarball(A8/A9 内核 UAPI 改动必须在内) =="
ssh $T67 "cd $SRC/kernel/xiaomi && tar -czf - --exclude=.git --transform 's,^sdm845_419,tiedun-kernel-4.19.325-ksu,' sdm845_419" \
    > "$DESTK/tiedun-kernel-4.19.325-ksu.tar.gz"
ls -la "$DESTK/tiedun-kernel-4.19.325-ksu.tar.gz"

echo "== 2/3 重打 modified-src tarball(A6-A10/B15 全部树内改动必须在内) =="
ssh $T67 "cd $SRC && tar -czf - \
  device/xiaomi/dipper \
  device/xiaomi/sdm845-common \
  frameworks/base/packages/PackageInstaller/res \
  frameworks/base/packages/PackageInstaller/src \
  hardware/qcom-caf/sdm845/audio/hal \
  packages/apps/Settings/res/drawable/tiedun_hero_gradient.xml \
  packages/apps/Settings/res/layout/tiedun_about_hero.xml \
  packages/apps/Settings/res/values/strings.xml \
  packages/apps/Settings/res/values-zh-rCN/strings.xml \
  packages/apps/Settings/res/xml/my_device_info.xml \
  packages/apps/Settings/res/xml/tiedun_credits.xml \
  packages/apps/Settings/src/com/android/settings/deviceinfo/aboutphone/MyDeviceInfoFragment.java \
  packages/apps/Settings/src/com/android/settings/core/gateway/SettingsGateway.java \
  packages/apps/Settings/src/com/android/settings/deviceinfo/tiedun \
  vendor/lineage/config/common.mk \
  vendor/lineage/config/device_framework_matrix.xml \
  vendor/xiaomi/dipper/Android.bp \
  vendor/xiaomi/dipper/dipper-vendor.mk \
  vendor/xiaomi/sdm845-common/Android.bp \
  vendor/xiaomi/sdm845-common/sdm845-common-vendor.mk" \
    > "$DESTS/tiedun-modified-aosp-src.tar.gz"
ls -la "$DESTS/tiedun-modified-aosp-src.tar.gz"

echo "== 3/3 许可证断言(红线: 千万不能丢, 缺一即失败退出) =="
K="$DESTK/tiedun-kernel-4.19.325-ksu.tar.gz"
tar -tzf "$K" | grep -q "^tiedun-kernel-4.19.325-ksu/COPYING$"          || { echo "!! 内核 COPYING(GPL-2.0) 丢失"; exit 1; }
tar -tzf "$K" | grep -q "tiedun-kernel-4.19.325-ksu/drivers/kernelsu/LICENSE" || { echo "!! KernelSU LICENSE(GPL-3.0) 丢失"; exit 1; }
for f in LICENSE NOTICE THIRD_PARTY_NOTICES.md README.md; do
  [ -f "$DESTS/tiedun-os-main/$f" ] || { echo "!! 主仓 $f 丢失"; exit 1; }
done
for f in LICENSE.GPL-3.0.txt LICENSE.GPL-2.0.txt NOTICE THIRD_PARTY_NOTICES.md 声明.md 改动清单.md; do
  [ -f "$DEST/声明文件/$f" ] || { echo "!! 声明文件/$f 丢失"; exit 1; }
done
[ -f "$DESTK/LICENSE.GPL-2.0.txt" ] || { echo "!! 内核源码目录许可证副本丢失"; exit 1; }
echo "许可证断言全部通过 ✓ (内核COPYING + KernelSU GPL-3 + 主仓GPL-3 + 双许可证全文副本)"
