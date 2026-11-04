#!/bin/bash
# 铁盾OS A8 施工脚本: 内核 UAPI 恢复 ION_SECURE 兼容别名
# 背景: QTI 原版 drivers/staging/android/uapi/msm_ion.h 带有
#   "Deprecated! Please use the corresponding ION_FLAG_*" 兼容别名块:
#       #define ION_SECURE ION_FLAG_SECURE
#   msm-4.19 重基时该块丢失; 而 display/media HAL(lineage-23.2-caf-sdm845, gr_allocator.cpp
#   与 omx_vdec/omx_video) 仍用旧名 ION_SECURE → "use of undeclared identifier 'ION_SECURE'"。
# 修法: 在内核 UAPI msm_ion.h 的 ION_FLAG_SECURE 定义后恢复 QTI 原样别名(值=bit31, 语义一致)。
# 影响面: 所有 <linux/msm_ion.h> 消费者(gralloc/media/未来模块)一次修齐。
# 用法: bash apply-a8.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
F="$SRC/kernel/xiaomi/sdm845_419/drivers/staging/android/uapi/msm_ion.h"
[ -f "$F" ] || { echo "msm_ion.h 未找到: $F"; exit 1; }

python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
if "ION_SECURE ION_FLAG_SECURE" in s:
    print("A8 已施工, 跳过")
    raise SystemExit(0)
anchor = "#define ION_FLAG_SECURE"
idx = s.index(anchor)
idx = s.index("\n", idx) + 1
add = (
    "\n/*\n"
    " * TieDun A8: \u6062\u590d QTI \u539f\u7248 \"Deprecated! Please use the corresponding\n"
    " * ION_FLAG_*\" \u517c\u5bb9\u522b\u540d(msm-4.19 \u91cd\u57fa\u65f6\u4e22\u5931). display/media HAL\n"
    " * (lineage-23.2-caf-sdm845) \u4ecd\u7528\u65e7\u540d ION_SECURE. \u539f\u6587\u51fa\u5904: QTI kernel/msm\n"
    " * drivers/staging/android/uapi/msm_ion.h\n"
    " */\n"
    "#ifndef ION_SECURE\n"
    "#define ION_SECURE ION_FLAG_SECURE\n"
    "#endif\n"
)
io.open(p, "w", encoding="utf-8").write(s[:idx] + add + s[idx:])
print("msm_ion.h 已补 ION_SECURE 别名")
PYEOF

echo "== A8 完成 =="
