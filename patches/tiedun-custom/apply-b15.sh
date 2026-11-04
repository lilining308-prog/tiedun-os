#!/bin/bash
# 铁盾OS B15 施工脚本: 铁盾之盾(com.lilining.lockescape) Android 权限全量预授权
# 背景: 用户拍板 —— 不逐项深查, 全部权限都给。三层实现:
#   ① default-permissions.xml: 运行时权限预授权(product/etc/default-permissions/)
#   ② tiedun-priv/service.sh 开机块: manifest 全部可授权限 pm grant + 所有 AppOps allow
#      (悬浮窗/后台/通知/开机自启全覆盖) + 电池优化白名单
#   ③ 无障碍第三档通道预启用(com.lilining.lockescape.EscapeAccessibilityService)
# 注: Root(KSU白名单) 与 Shizuku(API_V23 自动授权) 已由 B3 覆盖, 本脚本只补其余。
# 用法: bash apply-b15.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
D="$SRC/device/xiaomi/dipper"
[ -d "$D/tiedun-priv" ] || { echo "tiedun-priv 未找到: $D"; exit 1; }

python3 - "$D" <<'PYEOF'
import io, os, sys
D = sys.argv[1]

# ── 1) service.sh 追加 ③ 权限全量预授权块 ──
p = D + "/tiedun-priv/service.sh"
s = io.open(p, encoding="utf-8").read()
if "B15" in s:
    print("service.sh 已施工, 跳过")
else:
    anchor = 'log "===== boot service done ====="'
    assert anchor in s, "service.sh anchor"
    block = (
        "\n# \u2500\u2500 \u2462 Android \u6743\u9650\u5168\u91cf\u9884\u6388\u6743 (\u94c1\u76feOS B15: \u7528\u6237\u8981\u6c42\u5168\u7ed9, \u4e0d\u9010\u9879\u6df1\u67e5) \u2500\u2500\n"
        "(\n"
        "  i=0\n"
        "  while [ $i -lt 90 ]; do\n"
        "    [ \"$(getprop sys.boot_completed)\" = \"1\" ] && break\n"
        "    sleep 2\n"
        "    i=$((i+1))\n"
        "  done\n"
        "  sleep 5\n"
        "  PKG=com.lilining.lockescape\n"
        "  # (a) manifest \u58f0\u660e\u7684\u6240\u6709\u53ef\u6388\u8fd0\u884c\u65f6\u6743\u9650 \u2192 pm grant\n"
        "  for P in $(dumpsys package $PKG 2>/dev/null | grep -oE \"android\\.permission\\.[A-Z_0-9]+|moe\\.shizuku\\.manager\\.permission\\.API_V23\" | sort -u); do\n"
        "    pm grant $PKG $P 2>/dev/null\n"
        "  done\n"
        "  log \"manifest \u6743\u9650 pm grant \u5b8c\u6210\"\n"
        "  # (b) \u6240\u6709 AppOps \u2192 allow(\u60ac\u6d6e\u7a97/\u540e\u53f0/\u901a\u77e5/\u5f00\u673a\u81ea\u542f\u7b49\u5168\u8986\u76d6)\n"
        "  for OP in $(appops get $PKG 2>/dev/null | sed -n 's/^ *\\([A-Za-z_0-9]*\\):.*/\\1/p' | sort -u); do\n"
        "    appops set $PKG $OP allow 2>/dev/null\n"
        "  done\n"
        "  log \"appops \u5168\u91cf allow \u5b8c\u6210\"\n"
        "  # (c) \u7535\u6c60\u4f18\u5316\u767d\u540d\u5355 + \u65e0\u969c\u788d\u7b2c\u4e09\u6863\u901a\u9053\n"
        "  dumpsys deviceidle whitelist +$PKG >/dev/null 2>&1 && log \"\u7535\u6c60\u4f18\u5316\u767d\u540d\u5355 ok\"\n"
        "  SVC=\"$PKG/com.lilining.lockescape.EscapeAccessibilityService\"\n"
        "  CUR=$(settings get secure enabled_accessibility_services 2>/dev/null)\n"
        "  case \"$CUR\" in\n"
        "    *$PKG*) log \"\u65e0\u969c\u788d\u5df2\u542f\u7528, \u8df3\u8fc7\" ;;\n"
        "    *)\n"
        "      if [ -n \"$CUR\" ] && [ \"$CUR\" != \"null\" ]; then\n"
        "        settings put secure enabled_accessibility_services \"$CUR:$SVC\" 2>/dev/null\n"
        "      else\n"
        "        settings put secure enabled_accessibility_services \"$SVC\" 2>/dev/null\n"
        "      fi\n"
        "      settings put secure accessibility_enabled 1 2>/dev/null\n"
        "      log \"\u65e0\u969c\u788d\u7b2c\u4e09\u6863\u9884\u542f\u7528: $SVC\" ;;\n"
        "  esac\n"
        ") &\n\n"
    )
    s = s.replace(anchor, block + anchor, 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print("service.sh 已注入权限块")

# ── 2) default-permissions.xml ──
os.makedirs(D + "/permissions", exist_ok=True)
p = D + "/permissions/lockescape-default-permissions.xml"
xml = (
    "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
    "<!--\n"
    "     \u94c1\u76feOS B15: \u94c1\u76fe\u4e4b\u76fe(com.lilining.lockescape) \u8fd0\u884c\u65f6\u6743\u9650\u9884\u6388\u6743\n"
    "     (\u5168\u91cf: manifest \u58f0\u660e\u7684\u53ef\u6388\u6743\u9879\u5168\u90e8\u9884\u6388; \u7279\u6b8a\u6743\u9650/AppOps/\u65e0\u969c\u788d\u7531\n"
    "      tiedun-priv/service.sh \u5f00\u673a\u5168\u91cf\u6388\u4e88)\n"
    "-->\n"
    "<exceptions>\n"
    "    <exception package=\"com.lilining.lockescape\">\n"
    "        <permission name=\"android.permission.POST_NOTIFICATIONS\" fixed=\"false\"/>\n"
    "    </exception>\n"
    "</exceptions>\n"
)
io.open(p, "w", encoding="utf-8").write(xml)
print("default-permissions.xml 已写入")

# ── 3) device.mk ──
p = D + "/device.mk"
s = io.open(p, encoding="utf-8").read()
if "lockescape-default-permissions" in s:
    print("device.mk 已施工, 跳过")
else:
    anchor = "    $(LOCAL_PATH)/tiedun-priv/service.sh:$(TARGET_COPY_OUT_PRODUCT)/etc/tiedun/service.sh \\"
    assert anchor in s, "device.mk anchor"
    add = anchor + "\n    $(LOCAL_PATH)/permissions/lockescape-default-permissions.xml:$(TARGET_COPY_OUT_PRODUCT)/etc/default-permissions/lockescape-default-permissions.xml \\"
    s = s.replace(anchor, add, 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print("device.mk 已加拷贝行")
PYEOF

echo "== B15 完成 =="
