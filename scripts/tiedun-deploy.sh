#!/bin/bash
# 铁盾OS 一键总控(在算力机执行): 内核换装(KSU合并树) + 全部补丁落地 + 点火编译
# 前置: 树莓派已把 release/prebuilts/bootanimation 同步到 TIEDUN_ROOT
# 用法: [TIEDUN_ROOT=/mnt/build/buildspace/rom-build/tiedun] bash tiedun-deploy.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
TIEDUN_ROOT="${TIEDUN_ROOT:-/mnt/build/buildspace/rom-build/tiedun}"
RELEASE="$TIEDUN_ROOT/tiedun-os"
KERNEL_TGZ="$TIEDUN_ROOT/tiedun-os-kernel/tiedun-kernel-4.19.325-ksu.tar.gz"
# GitHub 流量走树莓派代理(反向隧道), 清华镜像直连
export http_proxy=http://127.0.0.1:10808 https_proxy=http://127.0.0.1:10808
export no_proxy=mirrors.tuna.tsinghua.edu.cn,127.0.0.1,localhost

echo "===== 1/5 内核换装(perf尖端+KernelSU-Next合并树) ====="
if [ ! -f "$SRC/kernel/xiaomi/sdm845_419/drivers/kernelsu/Makefile" ]; then
    echo "  替换 kernel/xiaomi/sdm845_419 ..."
    rm -rf "$SRC/kernel/xiaomi/sdm845_419.new"
    mkdir -p "$SRC/kernel/xiaomi/sdm845_419.new"
    tar xzf "$KERNEL_TGZ" -C "$SRC/kernel/xiaomi/sdm845_419.new" --strip-components=1
    rm -rf "$SRC/kernel/xiaomi/sdm845_419.old"
    [ -d "$SRC/kernel/xiaomi/sdm845_419" ] && mv "$SRC/kernel/xiaomi/sdm845_419" "$SRC/kernel/xiaomi/sdm845_419.old"
    mv "$SRC/kernel/xiaomi/sdm845_419.new" "$SRC/kernel/xiaomi/sdm845_419"
    grep -m1 "^VERSION" "$SRC/kernel/xiaomi/sdm845_419/Makefile"
    grep -m1 "KSU_VERSION :=" "$SRC/kernel/xiaomi/sdm845_419/drivers/kernelsu/Makefile"
else
    echo "  KSU 内核树已在位, 跳过"
fi

echo "===== 2/5 BoardConfig 内核配置(KSU fragment 并入) ====="
python3 - "$SRC" <<'PYEOF'
import sys
p = sys.argv[1] + "/device/xiaomi/sdm845-common/BoardConfigCommon.mk"
s = open(p, encoding="utf-8").read()
old = "TARGET_KERNEL_CONFIG := vendor/sdm845-perf_defconfig vendor/xiaomi/sdm845-common.config"
new = old + " vendor/extras/ksu.config"
if "vendor/extras/ksu.config" in s:
    print("  ksu.config 已在配置中")
elif old in s:
    s = s.replace(old, new, 1)
    open(p, "w").write(s)
    print("  TARGET_KERNEL_CONFIG += vendor/extras/ksu.config")
else:
    raise SystemExit("  BoardConfig 锚点失配, 手动检查")
PYEOF

echo "===== 2.6/5 A3: 禁用 CAF 源码音频 HAL(与 stock blob 撞名 audio.primary.sdm845, 血统=stock) ====="
python3 - "$SRC" <<'PYEOF'
import sys
p = sys.argv[1] + "/hardware/qcom-caf/sdm845/audio/hal/Android.bp"
s = open(p, encoding="utf-8").read()
anchor = 'target_board_platform_cc_library_shared {\n    name: "audio.primary.qcom",'
if "tiedun-disable" in s:
    print("  已禁用, 跳过")
elif anchor in s:
    s = s.replace(anchor, anchor + '\n    enabled: false, // tiedun-disable: stock blob 血统, 与预编译 audio.primary.sdm845 撞名', 1)
    open(p, "w").write(s)
    print("  CAF audio HAL disabled")
else:
    print("  !! 锚点失配(模块结构或有变化), 跳过(如打包报冲突再手动处理)")
PYEOF

echo "===== 3/5 B1/B2/B3/B4/B6/B9/B10/B11 设备树施工 ====="
PREBUILTS_DIR="$TIEDUN_ROOT/prebuilts" \
BOOTANIM_DIR="$TIEDUN_ROOT/bootanimation" \
bash "$RELEASE/patches/tiedun-custom/apply-device.sh" "$SRC"

echo "===== 3.6/5 B9 高通相机 Snap(优先, 缺则 Aperture 兜底) ====="
if [ ! -d "$SRC/packages/apps/Snap" ]; then
    echo "  拉取 LineageOS Snap(lineage-23.2)..."
    (cd "$SRC/packages/apps" && git clone --depth 1 -b lineage-23.2 \
        https://github.com/LineageOS/android_packages_apps_Snap Snap >/dev/null 2>&1) \
        && echo "  Snap 已就位(编译不过则自动回退 Aperture)" \
        || echo "  Snap 拉取失败, 使用 Aperture 兜底"
fi

echo "===== 4/5 B5 关于页施工 ====="
bash "$RELEASE/patches/tiedun-custom/apply-settings.sh" "$SRC"

echo "===== 4.5/5 B7 装卸策略施工 ====="
bash "$RELEASE/patches/tiedun-custom/apply-b7.sh" "$SRC"

echo "===== 4.55/5 A6-A11 平台适配 ====="
bash "$RELEASE/patches/tiedun-custom/apply-a6.sh" "$SRC"
bash "$RELEASE/patches/tiedun-custom/apply-a7.sh" "$SRC"
bash "$RELEASE/patches/tiedun-custom/apply-a8.sh" "$SRC"
bash "$RELEASE/patches/tiedun-custom/apply-a9.sh" "$SRC"
bash "$RELEASE/patches/tiedun-custom/apply-a10.sh" "$SRC"
bash "$RELEASE/patches/tiedun-custom/apply-a11.sh" "$SRC"

echo "===== 4.57/5 B15 铁盾之盾权限全量预授权 ====="
bash "$RELEASE/patches/tiedun-custom/apply-b15.sh" "$SRC"

echo "===== 4.6/5 B8 性能档位施工 ====="
bash "$RELEASE/patches/tiedun-custom/apply-b8.sh" "$SRC"

echo "===== 5/5 点火 ====="
(setsid nohup bash /mnt/build/buildspace/rom-build/scripts/02-build.sh "$SRC" > /mnt/build/buildspace/logs/build-auto.log 2>&1 &)
sleep 3
pgrep -f "[0]2-build" >/dev/null && echo "编译已点火: /mnt/build/buildspace/logs/build-auto.log"
