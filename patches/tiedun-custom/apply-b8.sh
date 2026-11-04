#!/bin/bash
# 铁盾OS B8 施工脚本: 性能档位(均衡/性能/省电) 并入 XiaomiParts(device/xiaomi/sdm845-common/parts)
# 用法: bash apply-b8.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
B8="$HERE/b8"
PARTS="$SRC/device/xiaomi/sdm845-common/parts"
D="$SRC/device/xiaomi/sdm845-common"
[ -d "$PARTS" ] || { echo "XiaomiParts 未找到: $PARTS"; exit 1; }

echo "== B8: XiaomiParts perf 模块落位 =="
mkdir -p "$PARTS/src/org/lineageos/settings/perf"
cp "$B8/TieDunPerfActivity.java"        "$PARTS/src/org/lineageos/settings/perf/"
cp "$B8/TieDunPerfSettingsFragment.java" "$PARTS/src/org/lineageos/settings/perf/"
cp "$B8/tiedun_perf.xml"                "$PARTS/res/xml/"

python3 - "$PARTS" "$B8" <<'PYEOF'
import sys, os
PARTS, B8 = sys.argv[1], sys.argv[2]

# 1) AndroidManifest: 注册 TieDunPerfActivity(IA_SETTINGS 自动进设置磁贴)
p = PARTS + "/AndroidManifest.xml"
s = open(p, encoding="utf-8").read()
if "TieDunPerfActivity" in s:
    print("B8 已施工, 跳过")
    raise SystemExit(0)
anchor = '''        <service
            android:name=".doze.DozeService"'''
assert anchor in s, "manifest anchor"
add = '''        <activity
            android:name=".perf.TieDunPerfActivity"
            android:exported="false"
            android:label="@string/tiedun_perf_title">
            <intent-filter>
                <action android:name="com.android.settings.action.IA_SETTINGS" />
            </intent-filter>
            <meta-data android:name="com.android.settings.category"
                       android:value="com.android.settings.category.ia.system" />
        </activity>

'''
s = s.replace(anchor, add + anchor, 1)
open(p, "w").write(s)
print("AndroidManifest.xml patched")

# 2) 字符串合并
def merge(target, items):
    txt = open(target, encoding="utf-8").read()
    add = "\n    <!-- TieDun OS B8 -->\n" + "\n".join(items) + "\n"
    txt = txt.replace("</resources>", add + "</resources>", 1)
    open(target, "w").write(txt)

body = open(B8 + "/strings-tiedun-perf.xml", encoding="utf-8").read()
zh_body = body.replace("性能档位", "性能档位")
merge(PARTS + "/res/values/strings.xml", [body.strip()])
zh = PARTS + "/res/values-zh-rCN/strings.xml"
if os.path.exists(zh):
    merge(zh, [body.strip()])
print("strings merged")
PYEOF

echo "== B8: 属性上下文(性能档位属性可写) =="
mkdir -p "$D/sepolicy/private"
grep -q "persist.tiedun.perf_mode" "$D/sepolicy/private/property_contexts" 2>/dev/null || {
    echo "# 铁盾OS B8: 性能档位属性(设置app可写)" >> "$D/sepolicy/private/property_contexts"
    echo "persist.tiedun.perf_mode u:object_r:system_prop:s0" >> "$D/sepolicy/private/property_contexts"
}
# (tiedun-perf.rc 的 PRODUCT_COPY_FILES 已在 apply-device.sh 总块注入)

echo "== B8 完成 =="
