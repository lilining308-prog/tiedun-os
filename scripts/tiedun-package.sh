#!/bin/bash
# 铁盾OS B14: 出包归档(算力机 out/ -> 树莓派 U盘 交付目录)
# 用法: bash tiedun-package.sh   (在树莓派执行, 编译完成后)
set -euo pipefail
T67=ubuntu@192.168.31.67
OUT=/mnt/build/buildspace/android/lineage-24.0/out/target/product/dipper
DEST=/mnt/data/dipper-android17/release/delivery-1.0.2.4
DEST2="/mnt/data/小米8铁盾os/刷机包"
mkdir -p "$DEST"

echo "== 取包 =="
ssh $T67 "ls -la $OUT/*.zip 2>/dev/null | tail -5"
rsync -a --include='*.zip' --include='*.img' --exclude='*' \
    $T67:$OUT/ "$DEST/" 2>/dev/null || true

echo "== 生成包校验 =="
cd "$DEST" && for f in *.zip *.img; do
    [ -f "$f" ] && sha256sum "$f"
done > SHA256SUMS 2>/dev/null || true

echo "== 重打源码/内核归档 + 许可证断言 =="
REPO="$(cd "$(dirname "$0")/.." && pwd)"
bash "$REPO/scripts/tiedun-repack-src.sh"

echo "== 主仓源码同步到 U盘(含全部施工脚本) =="
mkdir -p "/mnt/data/小米8铁盾os/源码/tiedun-os-main"
rsync -a "$REPO/" "/mnt/data/小米8铁盾os/源码/tiedun-os-main/"

echo "== 交付目录结构 =="
cat > "$DEST/交付清单.md" <<'EOF'
# 铁盾 OS 1.0.2.4 交付清单

## 产物
- lineage-24.x-*-UNOFFICIAL-dipper.zip — 刷机包（testkey 签名，可直接刷）
- SHA256SUMS — 校验

## 随包文档（tiedun-os 仓 docs/）
- FLASHING.md — 刷机指南与验证清单
- CHANGELOG.md / KNOWN-ISSUES.md / BUILDING.md
- README.md / LICENSE / NOTICE / THIRD_PARTY_NOTICES.md

## 源码（GPL 合规）
- tiedun-os-kernel/tiedun-kernel-4.19.325-ksu.tar.gz — 内核完整源码（GPL-2.0，含 KernelSU-Next）
- tiedun-os/ — 主仓源码/补丁/脚本/素材（GPL-3.0）

## 脚本
- ksu-module/tiedun-priv.zip — KSU 模块（白名单预置 + Shizuku root 通道）
- scripts/tiedun-deploy.sh — 构建一键总控
EOF

echo "== 完成: $DEST =="
ls -la "$DEST"
