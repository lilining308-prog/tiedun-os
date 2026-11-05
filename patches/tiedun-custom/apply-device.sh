#!/bin/bash
# 铁盾OS B1/B2/B3/B4/B6/B9/B10/B11 施工脚本(幂等, 可重复执行)
# 用法: [PREBUILTS_DIR=.. BOOTANIM_DIR=..] bash apply-device.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PREBUILTS="${PREBUILTS_DIR:-/mnt/build/buildspace/rom-build/prebuilts}"
BA_DIR="${BOOTANIM_DIR:-/mnt/data/dipper-android17/bootanimation}"
D="$SRC/device/xiaomi/dipper"

echo "== B1: WiFi captive portal 补丁并入 overlay =="
mkdir -p "$D/overlay/packages/modules/Connectivity/NetworkStack/res/values"
cp "$HERE/../wifi-captive-portal/overlay/packages/modules/Connectivity/NetworkStack/res/values/config.xml" \
   "$D/overlay/packages/modules/Connectivity/NetworkStack/res/values/config.xml"

echo "== B2: 预装三件套(铁盾之盾/Shizuku/FOSS Browser/Lawnchair) =="
mkdir -p "$D/tiedun-apk"
cp "$PREBUILTS/tiedun-shield-v3.0-adb.apk" "$D/tiedun-apk/TieDunShield.apk"
cp "$PREBUILTS/shizuku-v13.6.0.apk"       "$D/tiedun-apk/Shizuku.apk"
cp "$PREBUILTS/foss-browser.apk"          "$D/tiedun-apk/FossBrowser.apk"
cp "$PREBUILTS/lawnchair-15.0.0-beta3.apk" "$D/tiedun-apk/Lawnchair.apk"
cp "$PREBUILTS/KernelSU-Next-Manager-v3.4.2.apk" "$D/tiedun-apk/KernelSUNextManager.apk"
cat > "$D/tiedun-apk/Android.bp" <<'BPEOF'
// 铁盾OS B2/B11: 预装件(product 系统应用)
android_app_import {
    name: "TieDunShield",
    apk: "TieDunShield.apk",
    presigned: true,
    product_specific: true,
    dex_preopt: { enabled: false },
}

android_app_import {
    name: "Shizuku",
    apk: "Shizuku.apk",
    presigned: true,
    product_specific: true,
    dex_preopt: { enabled: false },
}

android_app_import {
    name: "FossBrowser",
    apk: "FossBrowser.apk",
    presigned: true,
    product_specific: true,
    dex_preopt: { enabled: false },
}

android_app_import {
    name: "Lawnchair",
    apk: "Lawnchair.apk",
    presigned: true,
    product_specific: true,
    dex_preopt: { enabled: false },
}

android_app_import {
    name: "KernelSUNextManager",
    apk: "KernelSUNextManager.apk",
    presigned: true,
    product_specific: true,
    dex_preopt: { enabled: false },
}
BPEOF

echo "== B3: tiedun-priv KSU 通道 =="
mkdir -p "$D/tiedun-priv"
cp "$HERE/tiedun-priv/tiedun-priv.rc"                "$D/tiedun-priv/"
cp "$HERE/../../ksu-module/tiedun-priv/module.prop"  "$D/tiedun-priv/"
cp "$HERE/../../ksu-module/tiedun-priv/service.sh"   "$D/tiedun-priv/"
cp "$HERE/../../ksu-module/tiedun-priv/tiedun-ksu-grant" "$D/tiedun-priv/"
cp "$HERE/../../ksu-module/tiedun-priv.zip"          "$D/tiedun-priv/"

echo "== B4: 开机动画/关机动画 =="
mkdir -p "$D/tiedun-media"
cp "$BA_DIR/bootanimation.zip"     "$D/tiedun-media/bootanimation.zip"
cp "$BA_DIR/shutdownanimation.zip" "$D/tiedun-media/shutdownanimation.zip"

echo "== B11: 风格层(壁纸overlay/Roboto字体) =="
mkdir -p "$D/tiedun-overlay/res/drawable-nodpi"
cp "$HERE/tiedun-overlay/Android.bp"          "$D/tiedun-overlay/"
cp "$HERE/tiedun-overlay/AndroidManifest.xml" "$D/tiedun-overlay/"
cp "$HERE/../../assets/tiedun_wallpaper.png"  "$D/tiedun-overlay/res/drawable-nodpi/default_wallpaper.png"
mkdir -p "$D/tiedun-media/fonts"
cp "$HERE/../../assets/fonts/"Roboto-*.ttf "$D/tiedun-media/fonts/"

echo "== B8: 性能档位 init 触发器 =="
mkdir -p "$D/tiedun-perf"
cp "$HERE/tiedun-perf/tiedun-perf.rc" "$D/tiedun-perf/"
mkdir -p "$D/sepolicy/private"
grep -q "persist.tiedun.perf_mode" "$D/sepolicy/private/property_contexts" 2>/dev/null || \
    echo "persist.tiedun.perf_mode u:object_r:system_prop:s0" >> "$D/sepolicy/private/property_contexts"

echo "== device.mk 幂等注入(B2/B3/B4/B6/B8/B10/B11) =="
python3 - "$D" <<'PYEOF'
import sys
p = sys.argv[1] + "/device.mk"
s = open(p, encoding="utf-8").read()
if "TieDunFrameworkOverlay" in s:
    print("  device.mk 已注入, 跳过")
    raise SystemExit(0)
anchor = "# Audio\nPRODUCT_COPY_FILES +="
assert anchor in s, "device.mk anchor not found"
add = """# ===== 铁盾OS 定制(需求冻结定稿) =====
# B4: 开机动画(黑底纯文字无logo) + 关机动画
PRODUCT_COPY_FILES += \\
    $(LOCAL_PATH)/tiedun-media/bootanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/bootanimation.zip \\
    $(LOCAL_PATH)/tiedun-media/shutdownanimation.zip:$(TARGET_COPY_OUT_PRODUCT)/media/shutdownanimation.zip

# B3: tiedun-priv KSU 通道(KSU白名单预置/Shizuku root拉起开机自启自动授权)
PRODUCT_COPY_FILES += \\
    $(LOCAL_PATH)/tiedun-priv/tiedun-priv.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/tiedun-priv.rc \\
    $(LOCAL_PATH)/tiedun-priv/module.prop:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/module.prop \\
    $(LOCAL_PATH)/tiedun-priv/service.sh:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/service.sh \\
    $(LOCAL_PATH)/tiedun-priv/tiedun-ksu-grant:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/tiedun-ksu-grant \\
    $(LOCAL_PATH)/tiedun-priv/tiedun-priv.zip:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/tiedun-priv.zip

# B8: 性能档位(均衡/性能/省电) init 调频触发器
PRODUCT_COPY_FILES += \\
    $(LOCAL_PATH)/tiedun-perf/tiedun-perf.rc:$(TARGET_COPY_OUT_PRODUCT)/etc/init/tiedun-perf.rc

# B2: 预装件 + B11: Lawnchair 默认桌面
PRODUCT_PACKAGES += \\
    TieDunShield \\
    Shizuku \\
    FossBrowser \\
    Lawnchair \\
    KernelSUNextManager

# B11: 风格层独立overlay(默认壁纸) + Roboto 字体
PRODUCT_PACKAGES += \\
    TieDunFrameworkOverlay

PRODUCT_COPY_FILES += \\
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Regular.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Regular.ttf \\
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Medium.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Medium.ttf \\
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Bold.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Bold.ttf \\
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Light.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Light.ttf \\
    $(LOCAL_PATH)/tiedun-media/fonts/Roboto-Italic.ttf:$(TARGET_COPY_OUT_PRODUCT)/fonts/Roboto-Italic.ttf

# B10: 简中默认 -- zh-CN 占 ProductLocales 头位(gen_build_prop 取[0]生成 ro.product.locale;
#      不能在 SYSTEM_DEFAULT_PROPERTIES 重复写, gen_build_prop 强制唯一)
PRODUCT_LOCALES := zh_CN $(PRODUCT_LOCALES)

# B6+B10: 时区走 make 列表(无空格安全); 版本属性值含空格的走 system.prop(脚本下方写入)
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \\
    persist.sys.timezone=Asia/Shanghai

""" + anchor
s = s.replace(anchor, add, 1)
open(p, "w").write(s)
print("  device.mk 注入完成")

# B6 版本属性: 值含空格(TieDun OS / LineageOS 24.0 / 小米 8), make 列表会按空格切词,
# 必须用 prop 文件语法写进 system.prop
sp = sys.argv[1] + "/system.prop"
t = open(sp, encoding="utf-8").read()
if "ro.tiedun.name" not in t:
    t = t.rstrip("\n") + "\n" + """
# 铁盾OS B6: 版本属性六组(值含空格, 用 prop 文件语法 -- make 列行会切词)
ro.tiedun.name=TieDun OS
ro.tiedun.version=1.0.2.4
ro.tiedun.android=17
ro.tiedun.base=LineageOS 24.0
ro.tiedun.kernel=4.19.325
ro.tiedun.author=lilining308
ro.product.marketname=小米 8
"""
    open(sp, "w").write(t)
    print("  system.prop B6 版本属性写入")
else:
    print("  system.prop 已有 B6 属性, 跳过")
PYEOF

echo "== B2/B11: 移除 Jelly/Trebuchet(FOSS Browser/Lawnchair 自动夺标) =="
grep -rln "PRODUCT_PACKAGES" "$SRC/vendor/lineage/config/" 2>/dev/null | grep "\.mk$" | while read -r f; do
    python3 - "$f" <<'PYEOF' || true
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
out, removed = [], 0
for i, ln in enumerate(lines):
    t = ln.strip().rstrip("\\").strip()
    if t in ("Jelly", "Trebuchet"):
        removed += 1
        # 删的是列表末项时, 去掉上一行悬空续行符, 防止吞掉 endif
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if out and out[-1].rstrip().endswith("\\") and not nxt.startswith((" ", "\t")):
            out[-1] = out[-1].rstrip().rstrip("\\").rstrip() + "\n"
        continue
    out.append(ln)
if removed:
    open(p, "w").write("".join(out))
    print("  removed %d Jelly/Trebuchet lines from %s" % (removed, p))
PYEOF
done

echo "== B9: 高通相机 Snap(优先, 缺则 Aperture 兜底) =="
if [ ! -d "$SRC/packages/apps/Snap" ]; then
    (cd "$SRC/packages/apps" && git clone --depth 1 -b lineage-23.2 \
        https://github.com/LineageOS/android_packages_apps_Snap Snap >/dev/null 2>&1) \
        && echo "  Snap 已就位" || echo "  Snap 拉取失败, 用 Aperture 兜底"
fi
if [ -d "$SRC/packages/apps/Snap" ]; then
    python3 - "$D" <<'PYEOF' || true
import sys
p = sys.argv[1] + "/device.mk"
s = open(p, encoding="utf-8").read()
if "PRODUCT_PACKAGES += \\\n    Snap" not in s and "# B9" not in s:
    s = s.replace("# ===== 铁盾OS 定制(需求冻结定稿) =====",
                  "# ===== 铁盾OS 定制(需求冻结定稿) =====\n# B9: 高通相机 Snap 优先(Aperture 兜底)\nPRODUCT_PACKAGES += \\\n    Snap\n", 1)
    open(p, "w").write(s)
    print("  device.mk += Snap")
PYEOF
fi

echo "== 完成 =="
