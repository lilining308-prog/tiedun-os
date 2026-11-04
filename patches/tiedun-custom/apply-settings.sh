#!/bin/bash
# 铁盾OS B5 施工脚本: 关于页(hero+六行+鸣谢) 并入 packages/apps/Settings
# 用法: bash apply-settings.sh <源码树根> [<本补丁目录>]
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
HERE="$(cd "$(dirname "$0")" && pwd)/settings"
S="$SRC/packages/apps/Settings"
[ -d "$S" ] || { echo "Settings not found: $S"; exit 1; }

echo "== 1/6 新文件落位 =="
cp "$HERE/tiedun_about_hero.xml"      "$S/res/layout/"
cp "$HERE/tiedun_hero_gradient.xml"   "$S/res/drawable/"
cp "$HERE/tiedun_credits.xml"         "$S/res/xml/"
cp "$HERE/TieDunStaticInfoController.java" "$S/src/com/android/settings/deviceinfo/tiedun/" 2>/dev/null || {
    mkdir -p "$S/src/com/android/settings/deviceinfo/tiedun"
    cp "$HERE/TieDunStaticInfoController.java" "$S/src/com/android/settings/deviceinfo/tiedun/"
    cp "$HERE/TieDunCreditsFragment.java"      "$S/src/com/android/settings/deviceinfo/tiedun/"
}
cp "$HERE/TieDunCreditsFragment.java" "$S/src/com/android/settings/deviceinfo/tiedun/"
cp "$HERE/my_device_info.xml"         "$S/res/xml/"     # 整文件覆盖(定稿图纸)

echo "== 2/6 字符串合并 =="
python3 - "$S" "$HERE" <<'PYEOF'
import re, sys
S, HERE = sys.argv[1], sys.argv[2]
def merge(snippet, target):
    if "tiedun_hero_title" in open(target, encoding="utf-8").read():
        print("strings already merged ->", target)
        return
    body = open(snippet, encoding="utf-8").read()
    items = re.findall(r'(    <string name="tiedun_[^"]+">.*?</string>)', body, re.S)
    txt = open(target, encoding="utf-8").read()
    add = "\n    <!-- TieDun OS B5 -->\n" + "\n".join(items) + "\n"
    txt = txt.replace("</resources>", add + "</resources>", 1)
    open(target, "w").write(txt)
    print("merged", len(items), "strings ->", target)
merge(HERE + "/strings-tiedun-default.xml", S + "/res/values/strings.xml")
merge(HERE + "/strings-tiedun-zh.xml", S + "/res/values-zh-rCN/strings.xml")
PYEOF

echo "== 3/6 MyDeviceInfoFragment: hero 头部绑定调整 =="
python3 - "$S" <<'PYEOF'
import sys
p = sys.argv[1] + "/src/com/android/settings/deviceinfo/aboutphone/MyDeviceInfoFragment.java"
s = open(p, encoding="utf-8").read()
if "TieDunCredentialGate" in s or "铁盾OS B5" in s:
    print("MyDeviceInfoFragment already patched")
    raise SystemExit(0)
old = """        final View headerView = headerPreference.findViewById(R.id.entity_header);
        final Activity context = getActivity();"""
new = """        final View headerView = headerPreference.findViewById(R.id.entity_header);
        // 铁盾OS B5: hero 头图自带静态文案(TieDun OS 1.0.2.4 / Android 17), 跳过 EntityHeader 绑定
        if (headerView == null) {
            return;
        }
        final Activity context = getActivity();"""
assert old in s, "MyDeviceInfoFragment anchor not found"
s = s.replace(old, new, 1)
open(p, "w").write(s)
print("MyDeviceInfoFragment patched")
PYEOF

echo "== 4/6 SettingsGateway: 注册鸣谢 Fragment =="
python3 - "$S" <<'PYEOF'
import sys
p = sys.argv[1] + "/src/com/android/settings/core/gateway/SettingsGateway.java"
s = open(p, encoding="utf-8").read()
if "TieDunCreditsFragment" in s:
    print("SettingsGateway already patched")
    raise SystemExit(0)
anchor = "import com.android.settings.deviceinfo.aboutphone.MyDeviceInfoFragment;"
assert anchor in s
s = s.replace(anchor, anchor + "\nimport com.android.settings.deviceinfo.tiedun.TieDunCreditsFragment;", 1)
anchor2 = "            MyDeviceInfoFragment.class.getName(),"
assert anchor2 in s
s = s.replace(anchor2, anchor2 + "\n            TieDunCreditsFragment.class.getName(),", 1)
open(p, "w").write(s)
print("SettingsGateway patched")
PYEOF

echo "== 5/6 AndroidManifest: SubSettings 可承载(无需新 Activity, 沿用通用入口) =="
echo "   (鸣谢页经 Preference android:fragment 由 SubSettings 承载, 无需 manifest 改动)"

echo "== 6/6 完成 =="
echo "B5 关于页施工完成。编译后自检: 设置→关于手机 应见黑渐变 hero + 六行 + 鸣谢。"
