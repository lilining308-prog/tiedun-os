#!/bin/bash
# 铁盾OS A6 施工脚本: 补齐 Doze 帮助对话框字符串
# 背景: DozeSettingsFragment.showHelp() 引用 R.string.doze_settings_help_title/text,
#       但 24.0 平台 packages/resources/devicesettings(org.lineageos.settings.resources)
#       已从默认 strings.xml 删除这两个字符串(仅剩个别小语种译文残留), 23.2 设备树代码仍在用,
#       导致 XiaomiParts javac 报 cannot find symbol。按 A3 策略本地补齐, 不动平台代码。
# 用法: bash apply-a6.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
A6="$HERE/a6"
PARTS="$SRC/device/xiaomi/sdm845-common/parts"
[ -d "$PARTS" ] || { echo "XiaomiParts 未找到: $PARTS"; exit 1; }

python3 - "$PARTS" "$A6" <<'PYEOF'
import sys, os
PARTS, A6 = sys.argv[1], sys.argv[2]

def merge(target, frag_path, create=False):
    if os.path.exists(target):
        txt = open(target, encoding="utf-8").read()
        if "doze_settings_help_title" in txt:
            return "skip(已施工)"
    elif create:
        txt = '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n</resources>\n'
    else:
        return "missing(文件不存在)"
    frag = open(frag_path, encoding="utf-8").read().strip() + "\n"
    assert txt.count("</resources>") == 1, target
    txt = txt.replace("</resources>", frag + "</resources>", 1)
    open(target, "w").write(txt)
    return "merged"

print("values/strings.xml:", merge(PARTS + "/res/values/strings.xml", A6 + "/doze-help-default.xml"))
os.makedirs(PARTS + "/res/values-zh-rCN", exist_ok=True)
print("values-zh-rCN/strings.xml:", merge(PARTS + "/res/values-zh-rCN/strings.xml", A6 + "/doze-help-zh.xml", create=True))
PYEOF

echo "== A6 完成 =="
