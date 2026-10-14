#!/usr/bin/env bash
# ============================================================================
# extract-from-images.sh — 在 Linux 宿主上把原厂 system.bin / vendor.bin(ext4)
#   挂载成一个 dump 目录, 供 `./rom.sh extract` 使用(不需要连手机)。
#
# 用法:
#   sudo ./extract-from-images.sh /path/system.bin /path/vendor.bin [挂载点]
#   # 默认挂载点 /mnt/p709dump
#   ROM_DUMP=/mnt/p709dump ./rom.sh extract
#   sudo umount /mnt/p709dump/system /mnt/p709dump/vendor   # 用完卸载
# ============================================================================
set -euo pipefail

SYS="${1:?用法: $0 <system.bin> <vendor.bin> [挂载点]}"
VEN="${2:?缺少 vendor.bin}"
MNT="${3:-/mnt/p709dump}"

if [ "$(id -u)" != "0" ]; then
  echo "[错误] 需要 root（挂载 loop 设备）。请用: sudo $0 $*"
  exit 1
fi

hex4() { od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n'; }

mount_img() {
  local img="$1" dst="$2"
  local m
  m="$(hex4 "$img")"
  if [ "$m" = "3aff26ed" ]; then
    echo "[$img] 检测到 sparse 镜像 -> 转成 raw"
    command -v simg2img >/dev/null 2>&1 || { echo "需要 simg2img（Fedora: sudo dnf install -y android-tools）"; exit 1; }
    simg2img "$img" "${img}.raw"
    img="${img}.raw"
  fi
  mkdir -p "$dst"
  if mountpoint -q "$dst"; then
    echo "[$dst] 已挂载，跳过"
  else
    mount -o loop,ro "$img" "$dst"
    echo "[挂载] $img -> $dst"
  fi
}

mount_img "$SYS" "${MNT}/system"
mount_img "$VEN" "${MNT}/vendor"

echo
echo "=== 完成 ==="
echo "dump 目录 : $MNT"
ls -la "$MNT"
echo
echo "下一步（在容器里跑，见 docs/BUILD-FEDORA.md）:"
echo "  cd Lazy_Action-ROM-Builder/local"
echo "  ROM_DUMP=$MNT ./rom.sh extract"
echo
echo "用完卸载:"
echo "  sudo umount $MNT/system $MNT/vendor"
