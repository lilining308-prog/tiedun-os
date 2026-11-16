#!/bin/bash
# 铁盾OS 通用点火脚本(替代构建农场私有 02-build.sh): envsetup + lunch + mka bacon
# 用法: bash tiedun-build.sh <源码树根> [jobs]
set -euo pipefail
SRC="${1:?用法: bash tiedun-build.sh <源码树根> [jobs]}"
JOBS="${2:-$(nproc)}"
cd "$SRC"
source build/envsetup.sh
lunch lineage_dipper-cp2a-userdebug
mka bacon -j"$JOBS" || { echo "== $JOBS 并发失败(OOM?), JOBS=2 重试 =="; mka bacon -j2; }
