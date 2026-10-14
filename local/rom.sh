#!/usr/bin/env bash
# ============================================================================
# rom.sh — 在 Fedora(或任意 Linux) 上用 Podman/Docker 容器编译 LineageOS 20
#
# 用法:
#   export ROM_HD=/run/media/$USER/EXT        # 移动硬盘挂载点(源码/ccache 放这)
#   ./rom.sh image                            # 建编译镜像(只做一次, ~10min)
#   ./rom.sh sync                             # 同步源码(首次 4~10h, 之后增量)
#   ./rom.sh build [systemimage|bootimage|bacon]   # 编译(默认 bacon)
#   ./rom.sh shell                            # 进容器手动调试
#
# 可用环境变量覆盖:
#   ROM_HD ROM_CCACHE_SIZE ROM_MANIFEST_URL ROM_MANIFEST_BRANCH
#   ROM_DEVICE_TREE_URL ROM_DEVICE_TREE_BRANCH ROM_DEVICE_PATH ROM_DEVICE_NAME
#   ROM_VENDOR_TREE_URL ROM_VENDOR_PATH ROM_LUNCH ROM_VARIANT ROM_JOBS
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROM_HD="${ROM_HD:-$HOME/romwork}"
LINEAGE_DIR="${ROM_HD}/lineage"
CCACHE_DIR="${ROM_HD}/ccache"
CCACHE_SIZE="${ROM_CCACHE_SIZE:-50G}"

IMAGE_NAME="${ROM_IMAGE_NAME:-los20-builder:latest}"
BASE_IMAGE="${ROM_BASE_IMAGE:-ubuntu:20.04}"

MANIFEST_URL="${ROM_MANIFEST_URL:-https://github.com/LineageOS/android.git}"
MANIFEST_BRANCH="${ROM_MANIFEST_BRANCH:-lineage-20.0}"
DEVICE_TREE_URL="${ROM_DEVICE_TREE_URL:-https://github.com/mmbsmm-git/android_device_youxuepai_k71v1_64_bsp_rom.git}"
DEVICE_TREE_BRANCH="${ROM_DEVICE_TREE_BRANCH:-main}"
DEVICE_PATH="${ROM_DEVICE_PATH:-device/youxuepai/k71v1_64_bsp}"
DEVICE_NAME="${ROM_DEVICE_NAME:-k71v1_64_bsp}"
VENDOR_TREE_URL="${ROM_VENDOR_TREE_URL:-}"
VENDOR_TREE_BRANCH="${ROM_VENDOR_TREE_BRANCH:-main}"
VENDOR_PATH="${ROM_VENDOR_PATH:-vendor/youxuepai}"
LUNCH="${ROM_LUNCH:-lineage_k71v1_64_bsp}"
VARIANT="${ROM_VARIANT:-userdebug}"
JOBS="${ROM_JOBS:-$(nproc 2>/dev/null || echo 4)}"

# --- 选容器引擎 ---
ENGINE="$(command -v podman || command -v docker || true)"
if [ -z "$ENGINE" ]; then
  echo "[错误] 没找到 podman 或 docker。Fedora 上: sudo dnf install -y podman"
  exit 1
fi

# --- 挂载参数(SELinux 兼容) ---
MOUNTS=(
  -v "${LINEAGE_DIR}:/lineage"
  -v "${CCACHE_DIR}:/ccache"
  -v "${SCRIPT_DIR}:/scripts:ro"
)
SECOPT=()
if [ "$(basename "$ENGINE")" = "podman" ]; then
  SECOPT=(--security-opt label=disable)
fi

need_dirs() {
  mkdir -p "$LINEAGE_DIR" "$CCACHE_DIR"
}

check_space() {
  local avail
  avail=$(df --output=avail -BG "$ROM_HD" | tail -1 | tr -dc '0-9')
  echo "[磁盘] $ROM_HD 可用 ${avail}GB (建议 >= 200GB)"
  if [ "${avail:-0}" -lt 120 ]; then
    echo "[警告] 可用空间偏小，源码+产物可能不够(建议 200GB)。"
  fi
}

cmd_image() {
  echo "[构建编译镜像] $IMAGE_NAME  (基于 $BASE_IMAGE)"
  "$ENGINE" build -t "$IMAGE_NAME" -f "${SCRIPT_DIR}/Dockerfile" "$SCRIPT_DIR"
  echo "[完成] 镜像: $IMAGE_NAME"
}

cmd_sync() {
  need_dirs; check_space
  echo "[同步源码] $MANIFEST_URL @ $MANIFEST_BRANCH  ->  $LINEAGE_DIR"
  "$ENGINE" run --rm -i "${SECOPT[@]}" "${MOUNTS[@]}" \
    -e MANIFEST_URL="$MANIFEST_URL" -e MANIFEST_BRANCH="$MANIFEST_BRANCH" \
    -e JOBS="$JOBS" \
    "$IMAGE_NAME" bash -lc '
      set -e
      cd /lineage
      if [ ! -d .repo ]; then
        repo init --depth=1 -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" --no-clone-bundle
      else
        echo "已有 .repo，跳过 init（增量同步）"
      fi
      repo sync -c -j"$JOBS" --force-sync --no-clone-bundle --no-tags
      echo "=== SYNC DONE ==="
      du -sh /lineage || true
    '
}

cmd_build() {
  local target="${1:-bacon}"
  need_dirs
  "$ENGINE" run --rm -i "${SECOPT[@]}" "${MOUNTS[@]}" \
    -e DEVICE_TREE_URL="$DEVICE_TREE_URL" -e DEVICE_TREE_BRANCH="$DEVICE_TREE_BRANCH" \
    -e DEVICE_PATH="$DEVICE_PATH" -e DEVICE_NAME="$DEVICE_NAME" \
    -e VENDOR_TREE_URL="$VENDOR_TREE_URL" -e VENDOR_TREE_BRANCH="$VENDOR_TREE_BRANCH" \
    -e VENDOR_PATH="$VENDOR_PATH" \
    -e LUNCH="$LUNCH" -e VARIANT="$VARIANT" -e JOBS="$JOBS" \
    -e CCACHE_SIZE="$CCACHE_SIZE" -e BUILD_TARGET="$target" \
    "$IMAGE_NAME" bash -lc '
      set -e
      cd /lineage
      [ -d .repo ] || { echo "[错误] 还没同步源码，请先 ./rom.sh sync"; exit 1; }

      # 设备树
      if [ ! -d "$DEVICE_PATH/.git" ]; then
        rm -rf "$DEVICE_PATH"
        git clone "$DEVICE_TREE_URL" -b "$DEVICE_TREE_BRANCH" "$DEVICE_PATH"
      fi
      # vendor blobs(可选)
      if [ -n "$VENDOR_TREE_URL" ] && [ ! -d "$VENDOR_PATH/$DEVICE_NAME/.git" ]; then
        mkdir -p "$VENDOR_PATH"
        git clone "$VENDOR_TREE_URL" -b "$VENDOR_TREE_BRANCH" "$VENDOR_PATH/$DEVICE_NAME"
      fi

      # ccache
      export USE_CCACHE=1
      export CCACHE_DIR=/ccache
      export CCACHE_EXEC="$(command -v ccache)"
      ccache -M "$CCACHE_SIZE"
      ccache -s || true

      export LC_ALL=C
      source build/envsetup.sh
      lunch "$LUNCH-$VARIANT"
      echo "=== mka $BUILD_TARGET (jobs=$JOBS) ==="
      mka "$BUILD_TARGET" -j"$JOBS"
      echo "=== BUILD DONE ==="
      ls -la "out/target/product/$DEVICE_NAME/" || true
      ccache -s || true
    '
}

cmd_extract() {
  need_dirs
  local dump="${ROM_DUMP:-}"
  if [ -z "$dump" ]; then
    echo "[错误] 需要指定挂载了原厂 system/vendor 的目录:"
    echo "        sudo ./local\extract-from-images.sh /path/system.bin /path/vendor.bin /mnt/p709dump"
    echo "        ROM_DUMP=/mnt/p709dump ./rom.sh extract"
    exit 1
  fi
  "$ENGINE" run --rm -it "${SECOPT[@]}" "${MOUNTS[@]}" -v "${dump}:/dump:ro" \
    -e DEVICE_PATH="$DEVICE_PATH" -e DEVICE_NAME="$DEVICE_NAME" \
    "$IMAGE_NAME" bash -lc '
      set -e
      cd /lineage
      [ -d "$DEVICE_PATH" ] || { echo "[错误] 设备树不在 $DEVICE_PATH（先跑 ./rom.sh sync 并克隆设备树）"; exit 1; }
      cd "$DEVICE_PATH"
      chmod +x ./extract-files.sh ./setup-makefiles.sh || true
      ./extract-files.sh /dump
      echo "=== EXTRACT DONE ==="
      echo "blobs 已生成到 /lineage/vendor/youxuepai/$DEVICE_NAME"
    '
}

cmd_shell() {
  need_dirs
  echo "[进入容器] 源码目录 /lineage, ccache /ccache"
  "$ENGINE" run --rm -it "${SECOPT[@]}" "${MOUNTS[@]}" "$IMAGE_NAME" bash
}

case "${1:-}" in
  image)   cmd_image ;;
  sync)    cmd_sync ;;
  build)   shift || true; cmd_build "${1:-bacon}" ;;
  extract) cmd_extract ;;
  shell)   cmd_shell ;;
  *) sed -n '2,22p' "$0"; exit 1 ;;
esac
