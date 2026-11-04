#!/bin/bash
# 铁盾OS A9 施工脚本: 内核 UAPI 导出 pre-4.12 老 ION ABI(23.2 CAF HAL 依赖)
# 背景: lineage-23.2-caf-sdm845 血统的 display/media HAL(gr_ion_alloc/EGLImageWrapper/
#   omx vdec/venc/mm_jpeg_ionbuf 等10处) 使用 pre-4.12 handle 式 ION ABI:
#   ion_allocation_data{len,align,heap_id_mask,flags,handle} + ION_IOC_ALLOC/MAP/FREE/IMPORT
#   + ion_flush_data/ion_custom_data/ION_IOC_CLEAN_*_CACHES 等。
#   4.19 内核 uapi/ion.h 只导出新 ABI(fd 式) 且 msm_ion.h 丢了 #include "ion.h" → 全部炸。
#   内核 CONFIG_ION_LEGACY 完整实现老 ABI(ion_legacy.h + ion-ioctl.c, handle 内部即 fd,
#   ION_OLD_IOC_ALLOC/MAP/SHARE/FREE/IMPORT 全有) → 导出声明即语义无损。
# 修法: ①uapi/ion.h 用 #ifdef __KERNEL__ 分叉: 内核看新 ABI(ion-ioctl.c 依赖),
#        用户态看老 ABI(struct size_t len/align...; ioctl 号自动= ION_OLD_IOC_ALLOC,
#        32位20B 走 compat_ion.c, 64位32B 走原生); 再补老结构体/ioctl/缓存命令声明。
#      ②uapi/msm_ion.h 恢复 #include "ion.h"(QTI 原版 include 链)。
#      ③camera_prop 同批处理: 00-tiedun-legacy-compat.te 撤销
#        "typealias exported_camera_prop alias camera_prop"(plat public 类型禁止
#        typealiasactual, versioned policy 报错), 改为 appdomain.te/property_contexts
#        源文件直接改名 exported_camera_prop(apply-a7 一并施工)。
# 用法: bash apply-a9.sh <源码树根>
set -euo pipefail
SRC="${1:-/mnt/build/buildspace/android/lineage-24.0}"
K="$SRC/kernel/xiaomi/sdm845_419/drivers/staging/android/uapi"
[ -f "$K/ion.h" ] || { echo "uapi/ion.h 未找到: $K"; exit 1; }

python3 - "$K" <<'PYEOF'
import sys, io
K = sys.argv[1]

# 1) ion.h
p = K + "/ion.h"
s = io.open(p, encoding="utf-8").read()
if "TieDun A9" in s:
    print("ion.h 已施工, 跳过")
else:
    old_struct = (
        "struct ion_allocation_data {\n"
        "\t__u64 len;\n"
        "\t__u32 heap_id_mask;\n"
        "\t__u32 flags;\n"
        "\t__u32 fd;\n"
        "\t__u32 unused;\n"
        "};"
    )
    assert old_struct in s, "ion_allocation_data anchor"
    new_struct = (
        "#ifdef __KERNEL__\n"
        + old_struct + "\n"
        "#else\n"
        "/*\n"
        " * TieDun A9: userspace \u4fa7\u63d0\u4f9b pre-4.12 \u624b\u67c4\u5f0f(handle) \u8001 ABI \u5e03\u5c40,\n"
        " * \u517c\u5bb9 lineage-23.2-caf-sdm845 \u8840\u7edf\u7684 display/media HAL. \u5185\u6838 CONFIG_ION_LEGACY\n"
        " * \u5b8c\u6574\u5b9e\u73b0\u8be5 ABI(handle \u5185\u90e8\u5373 fd), \u8bed\u4e49\u65e0\u635f. size_t \u5b57\u6bb5\u4e0e QTI\n"
        " * \u539f\u7248\u4e00\u81f4(\u517c\u5bb9 %zu \u683c\u5f0f\u4e32\u4e0e compat_ion.c \u7684 32 \u4f4d 20B \u5e03\u5c40).\n"
        " */\n"
        "struct ion_allocation_data {\n"
        "\tsize_t len;\n"
        "\tsize_t align;\n"
        "\t__u32 heap_id_mask;\n"
        "\t__u32 flags;\n"
        "\t__s32 handle;\n"
        "};\n"
        "#endif"
    )
    s = s.replace(old_struct, new_struct, 1)

    tail_anchor = "#endif /* _UAPI_LINUX_ION_H */"
    assert tail_anchor in s
    legacy = (
        "#ifndef __KERNEL__\n"
        "/* TieDun A9: pre-4.12 \u8001 ABI \u517c\u5bb9\u5bfc\u51fa(\u5185\u6838\u5b9e\u73b0\u4e8e ion_legacy.h / ion-ioctl.c,\n"
        " * \u6587\u4ef6\u53c2\u8003 QTI \u65e7\u7248 uapi/ion.h \u4e0e\u5185\u6838 ion_legacy.h) */\n"
        "typedef int ion_user_handle_t;\n"
        "\n"
        "struct ion_fd_data {\n"
        "\tion_user_handle_t handle;\n"
        "\tint fd;\n"
        "};\n"
        "\n"
        "struct ion_handle_data {\n"
        "\tion_user_handle_t handle;\n"
        "};\n"
        "\n"
        "struct ion_flush_data {\n"
        "\tion_user_handle_t handle;\n"
        "\tint fd;\n"
        "\tvoid *vaddr;\n"
        "\tunsigned int offset;\n"
        "\tunsigned int length;\n"
        "};\n"
        "\n"
        "struct ion_custom_data {\n"
        "\tunsigned int cmd;\n"
        "\tunsigned long arg;\n"
        "};\n"
        "\n"
        "#define ION_IOC_FREE\t\t_IOWR(ION_IOC_MAGIC, 1, struct ion_handle_data)\n"
        "#define ION_IOC_MAP\t\t_IOWR(ION_IOC_MAGIC, 2, struct ion_fd_data)\n"
        "#define ION_IOC_CUSTOM\t\t_IOWR(ION_IOC_MAGIC, 3, struct ion_custom_data)\n"
        "#define ION_IOC_SHARE\t\t_IOWR(ION_IOC_MAGIC, 4, struct ion_fd_data)\n"
        "#define ION_IOC_IMPORT\t\t_IOWR(ION_IOC_MAGIC, 5, struct ion_fd_data)\n"
        "\n"
        "/* \u7f13\u5b58\u7ef4\u62a4\u547d\u4ee4(ion_custom_data.cmd): 4.19 \u5185\u6838\u672a\u5b9e\u73b0 ION_IOC_CUSTOM,\n"
        " * \u8c03\u7528\u5c06\u5f97 ENOTTY \u5e76\u7531 dma-buf \u81ea\u52a8\u7ba1\u7406\u7f13\u5b58, \u4ec5\u4e3a\u7f16\u8bd1\u517c\u5bb9\u4fdd\u7559 */\n"
        "enum {\n"
        "\tION_IOC_CLEAN_CACHES = 0,\n"
        "\tION_IOC_INV_CACHES,\n"
        "\tION_IOC_CLEAN_INV_CACHES,\n"
        "};\n"
        "#endif /* !__KERNEL__ */\n"
        "\n"
    )
    s = s.replace(tail_anchor, legacy + tail_anchor, 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print("uapi/ion.h 已补老 ABI")

# 2) msm_ion.h include
p = K + "/msm_ion.h"
s = io.open(p, encoding="utf-8").read()
if '#include "ion.h"' in s:
    print("msm_ion.h include 已就绪")
else:
    anchor = "#include <linux/types.h>"
    assert anchor in s
    s = s.replace(anchor, anchor + "\n#include \"ion.h\"  /* TieDun A9: \u6062\u590d QTI \u539f\u7248 include \u94fe */", 1)
    io.open(p, "w", encoding="utf-8").write(s)
    print("uapi/msm_ion.h include 已恢复")
PYEOF

echo "== A9 完成 =="
