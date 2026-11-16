#!/bin/bash
# 铁盾OS A7 施工脚本: sepolicy 老类型名兼容(23.2设备树 vs 24.0平台)
# 背景: 24.0 device/qcom/sepolicy_vndr 把 QTI 老类型加 vendor_ 前缀/更名
#   (cnd→vendor_cnd, camera_prop→exported_camera_prop, qcom_ims_prop→vendor_ims_prop,
#    device_latency→vendor_latency_device, sysfs_*→vendor_sysfs_* ...),
#   本设备树(lineage-23.2 血统)仍引用旧名 → checkpolicy "not declared / unknown type"。
# 修法: ①00-tiedun-legacy-compat.te 用 typealias 旧名→新名(声明先于使用, 文件名 00- 排序最前)
#      ②hal_bluetooth_qti.te / mm-pp-daemon.te 两条死规则注释(24.0 无等价类型且本树无标签)
# 用法: bash apply-a7.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
A7="$HERE/a7"
D="$SRC/device/xiaomi/sdm845-common/sepolicy/vendor"
[ -d "$D" ] || { echo "sepolicy 目录未找到: $D"; exit 1; }

echo "== A7: compat 别名文件 =="
cp "$A7/00-tiedun-legacy-compat.te" "$D/"

python3 - "$D" <<'PYEOF'
import sys, io
D = sys.argv[1]
edits = [
    ("hal_bluetooth_qti.te",
     "r_dir_file(hal_bluetooth_qti, vendor_convergence_data_file)",
     "# TieDun A7: 24.0 已无 hal_bluetooth_qti 类型(qcom树未迁移), 本树亦无标签, 死规则注释\n# r_dir_file(hal_bluetooth_qti, vendor_convergence_data_file)"),
    ("mm-pp-daemon.te",
     "get_prop(mm-pp-daemon, vendor_dpps_prop)",
     "# TieDun A7: 24.0 已无 mm-pp-daemon 类型(qcom树未迁移), 本树亦无标签, 死规则注释\n# get_prop(mm-pp-daemon, vendor_dpps_prop)"),
]
for fn, old, new in edits:
    p = D + "/" + fn
    s = io.open(p, encoding="utf-8").read()
    if "TieDun A7" in s:
        print(fn, "已施工, 跳过")
        continue
    assert old in s, fn
    s = s.replace(old, new, 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print(fn, "已注释死规则")

# camera_prop → exported_camera_prop 直接改名(plat public 类型不能做别名, versioned policy 会拒)
for fn in ("appdomain.te", "property_contexts"):
    p = D + "/" + fn
    s = io.open(p, encoding="utf-8").read()
    if "exported_camera_prop" in s:
        print(fn, "已改名, 跳过")
        continue
    n = s.count("camera_prop")
    if n:
        s = s.replace("camera_prop", "exported_camera_prop")
        io.open(p, "w", encoding="utf-8").write(s)
        print(fn, "已改名 x%d" % n)
PYEOF

echo "== A7 完成 =="
