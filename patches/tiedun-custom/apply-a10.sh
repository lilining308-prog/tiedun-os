#!/bin/bash
# 铁盾OS A10 施工脚本: radio.te 裸 allow → hal_client_domain 客户域声明
# 背景: 24.0 qcom 用 hal_attribute_hwservice(vendor_hal_iwlanservice_qti, ...) /
#   hal_attribute_hwservice(vendor_hal_datafactory_qti, ...) 登记 iwlan/datafactory
#   两类 hwservice, 并生成 neverallow(仅 client/server 属性可 find)。
#   23.2 血统 radio.te 首行的裸 allow radio {hal_datafactory_hwservice hal_iwlan_hwservice}
#   在 precompiled_sepolicy 阶段触发 neverallow 违例(注意: 语法/单编全过, 只在最终
#   secilc 总装时炸, 属"语义级"断裂)。
# 修法: 替换为 hal_client_domain(radio, vendor_hal_iwlanservice_qti) 与
#   hal_client_domain(radio, vendor_hal_datafactory_qti) —— 自动获得 find 权限,
#   与 23.2 意图语义一致(radio 侧访问 iwlan/datafactory 服务), 且满足 neverallow。
# 用法: bash apply-a10.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
F="$SRC/device/xiaomi/sdm845-common/sepolicy/vendor/radio.te"
[ -f "$F" ] || { echo "radio.te 未找到: $F"; exit 1; }

python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "allow radio { hal_datafactory_hwservice hal_iwlan_hwservice }:hwservice_manager find;"
if "TieDun A10" in s:
    print("A10 已施工, 跳过")
elif old in s:
    new = ("# TieDun A10: 24.0 qcom \u7528 hal_attribute_hwservice \u767b\u8bb0\u8fd9\u4e24\u7c7b hwservice \u5e76\u9644 neverallow\n"
           "# (\u4ec5 client/server \u5c5e\u6027\u53ef find), 23.2 \u8840\u7edf\u7684\u88f8 allow \u8fdd\u4f8b. \u6539\u4e3a\u5ba3\u544a radio \u4e3a\u5ba2\u6237\u57df\n"
           "# (\u81ea\u52a8\u83b7\u5f97 find, \u8bed\u4e49\u4e0e 23.2 \u610f\u56fe\u4e00\u81f4: radio \u4fa7\u8bbf\u95ee iwlan/datafactory \u670d\u52a1)\n"
           "hal_client_domain(radio, vendor_hal_iwlanservice_qti)\n"
           "hal_client_domain(radio, vendor_hal_datafactory_qti)")
    s = s.replace(old, new, 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print("radio.te 已改为客户域声明")
else:
    print("!! 锚点失配, 未改动: " + old)
PYEOF

echo "== A10 完成 =="
