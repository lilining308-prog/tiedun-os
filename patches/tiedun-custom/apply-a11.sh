#!/bin/bash
# 铁盾OS A11 施工脚本: ro.product.locale 格式归一(BCP-47 连字符)
# 背景: ①PRODUCT_LOCALES 的项会原样进入 aapt 的 -c 配置(product_config.mk 直接拼接,
#    make 侧无格式转换), aapt 只认下划线格式(zh_CN), 连字符(zh-CN)报
#    "invalid config 'zh-CN' for -c option" → PRODUCT_LOCALES 必须写下划线。
#    ②ro.product.locale 由 gen_build_prop 取 ProductLocales[0] 原样输出, 生态惯例是
#    BCP-47 连字符(zh-CN/en-US), 于是归一化: 输出前把 _ 换成 -。
# 修法: gen_build_prop.py 第273行 ProductLocales[0].replace("_","-")。
# 配套: device.mk 的 PRODUCT_LOCALES := zh_CN $(PRODUCT_LOCALES)(apply-device.sh 已含)。
# 用法: bash apply-a11.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
F="$SRC/build/soong/scripts/gen_build_prop.py"
[ -f "$F" ] || { echo "gen_build_prop.py 未找到: $F"; exit 1; }

python3 - "$F" <<'PYEOF'
import sys, io
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
if "TieDun A11" in s:
    print("A11 已施工, 跳过")
    raise SystemExit(0)
target = 'print(f"ro.product.locale={config[\'ProductLocales\'][0]}")'
assert target in s, "gen_build_prop anchor"
repl = ('# TieDun A11: ro.product.locale \u7edf\u4e00\u4e3a BCP-47 \u8fde\u5b57\u7b26\u683c\u5f0f(ProductLocales \u4e3a aapt \u5b58\u4e0b\u5212\u7ebf\u683c\u5f0f)\n'
        '    print(f"ro.product.locale={config[\'ProductLocales\'][0].replace(\'_\', \'-\')}")')
s = s.replace('    ' + target, repl, 1)
io.open(p, "w", encoding="utf-8").write(s)
print("gen_build_prop.py 已归一化 ro.product.locale 格式")
PYEOF

echo "== A11 完成 =="
