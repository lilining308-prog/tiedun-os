# 铁盾 OS 构建说明（BUILDING）

## 环境
- 16 核 / 30G 内存 + 16G swap / 250G+ 磁盘（ext4）
- Ubuntu 22.04/24.04，OpenJDK 17，repo 工具
- 网络：AOSP 走清华 TUNA 镜像（系统级 insteadOf），GitHub 走代理

## 1. 源码配方（16 仓库）
`manifests/dipper.xml`（本地 manifest）给出全部仓库/分支：
- 平台: LineageOS lineage-24.0（1255 仓库）
- 设备树: LineageOS/android_device_xiaomi_{dipper,sdm845-common}@lineage-23.2
- 内核: sdm845-419/android_kernel_xiaomi_sdm845_419@perf（+ KernelSU-Next 集成）
- blobs: TheMuppets proprietary_vendor_xiaomi_{dipper,sdm845-common}@lineage-22.2
- HAL: hardware/xiaomi@lineage-24.0、qcom-caf-sdm845@lineage-23.2-caf-sdm845

同步:
```bash
repo init -u https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/platform/manifest \
  -b lineage-24.0 --git-lfs
cp manifests/dipper.xml .repo/local_manifests/
repo sync -c -j8
```

## 2. 补丁应用（patches/ 三类）
1. `patches/build-adaptation/` — 让 24.0 平台 + 23.2 设备树编译通过的适配
   （libheif 补齐、跨命名空间撞名改 _vendor+stem、wfd 依赖清空、
    非CAF display 树移除、device_framework_matrix 补回、内核指向 4.19 树等）
2. `patches/wifi-captive-portal/` — captive portal 验证地址改国内节点（B1）
   并入 `device/xiaomi/dipper/overlay/`
3. `patches/tiedun-custom/` — 铁盾定制（关于页/鸣谢/属性/预装/装卸策略等 B 系列）

## 3. 内核（tiedun-os-kernel 仓, GPL-2.0）
- 基底: perf 分支尖端（4.19.325-CIP 血统）
- 集成: KernelSU-Next 12759 + SUSFS（perf-ksu_next 分支增量, 70 文件）
- defconfig: `vendor/sdm845-perf_defconfig` + `vendor/xiaomi/sdm845-common.config`
  + `vendor/xiaomi/dipper.config` + KSU fragment（BoardConfig TARGET_KERNEL_CONFIG）

## 4. 编译
```bash
source build/envsetup.sh
lunch lineage_dipper-cp2a-userdebug   # 安卓17版本段 cp2a, 三段式
mka bacon -j14                        # OOM 时 JOBS=2 重跑
```
产物: `out/target/product/dipper/lineage-24.x-*-UNOFFICIAL-dipper.zip`
（testkey 签名, 可直接 fastboot/recovery 刷入）

## 5. 网络配置（国内环境）
```bash
sudo git config --system url."https://mirrors.tuna.tsinghua.edu.cn/git/AOSP/".insteadOf "https://android.googlesource.com/"
sudo git config --system http."https://mirrors.tuna.tsinghua.edu.cn/".proxy ""
sudo git config --system https."https://mirrors.tuna.tsinghua.edu.cn/".proxy ""
export REPO_URL=https://mirrors.tuna.tsinghua.edu.cn/git/git-repo
# GitHub 流量: http_proxy=127.0.0.1:10808, no_proxy 含 mirrors.tuna.tsinghua.edu.cn
```
