# Lazy Action — ROM Builder (LineageOS 20 / Android 13)

给 **优学派 P709 / U60（k71v1_64_bsp）** 构建 ROM 用的 GitHub Actions 仓库。
（recovery 的 Action 在另一个仓库：`Lazy_Action-Recoverys-Builder`）

目标：**LineageOS 20（Android 13）** —— 本机（MT6771 / Linux 4.4）内核世代的天花板，
之后再"中国厂商式魔改"出 AviumUI 功能 + MD3E 风格界面。

---

## ⚠️ 先读：磁盘现实（务必看）

LineageOS 20（A13）全量源码 ~70GB + 编译产物 ~50GB ≈ **120GB**。

| runner | 可用磁盘 | 能否编 LOS20 |
|---|---|---|
| GitHub **托管** (ubuntu-24.04) | ~14GB（`maximize-build-space` 清理后 ~60–70GB）| **基本不能**（大概率 ENOSPC）|
| GitHub **付费大 runner** | 150GB+ | 可以（收费）|
| **self-hosted**（自己的 Linux / 免费云 VM）| 你说了算（≥200GB）| **可以（推荐）**|

> 本 workflow 已内置 `easimon/maximize-build-space`（抢回磁盘）+ `--depth=1` 浅同步，
> 让托管 runner 尽量多挤出空间——**但 LOS20 仍很可能不够**。若只想先验证流程，
> 可把 `BUILD_TARGET` 设为 `systemimage`（产物更小），或先用 `SYNC_ONLY=1` 看同步能不能过。

### 没有自己的机器怎么办（三个可行方向）

| 方案 | 说明 | 代价 |
|---|---|---|
| **A. 免费云 VM 当 self-hosted runner**（推荐）| 如 Oracle Cloud 免费 ARM（4核/24GB/200GB 盘）。**你仍然在 GitHub Actions 界面点"Run workflow"**，只是任务跑在这台云机上。一次配置，长期用。 | 需注册云账号 + 一次性装 runner |
| **B. 付费 GitHub 大 runner** | Settings → Actions → Larger runners，磁盘 150GB+ | 花钱 |
| **C. 不编 ROM，改"GSI 魔改"** | 下载现成 A13 GSI（本机实测能跑）→ 托管 runner 里解包/改/重打包（几 GB，托管完全够） | 只能做应用/主题/overlay 级魔改，动不了 framework 深层 |


---

## 一、self-hosted runner 怎么搭（推荐）

1. 在 GitHub 仓库 → Settings → Actions → Runners → New self-hosted runner →
   按提示在**你的 Linux 机器**上安装并启动（`./run.sh`）。
2. 该机器需要：
   - Ubuntu 20.04/22.04/24.04（或 WSL2）
   - 磁盘 **≥ 200 GB 可用**（源码+产物），内存 **≥16 GB**（不足则开 8~16GB swap）
   - 网络能访问 github.com / android.googlesource.com
3. 首次构建前，建议先跑一次 **`SYNC_ONLY=1`**（只同步源码），把源码拉全，
   再跑正式构建（源码会留在 runner 上复用）。

---

## 二、vendor blobs（必须解决）

ROM 需要厂商专有文件（HAL、相机、射频…）。本机原厂镜像是 ext4 全分区回读：
- `system.bin`（6.44GB）、`vendor.bin`（856MB）

**流程**：
```bash
# 在 Linux 上解开(需要 root/loop 或 7z)
sudo mkdir -p dump && cd dump
sudo mount -o loop,ro /path/system.bin system
sudo mount -o loop,ro /path/vendor.bin vendor
# 生成 blobs 到 vendor/youxuepai/k71v1_64_bsp
cd lineage
./device/youxuepai/k71v1_64_bsp/extract-files.sh /path/dump
```
然后把 `vendor/youxuepai/k71v1_64_bsp` 推成一个单独的 **blobs 仓库**，
在 workflow 的 `VENDOR_TREE_URL` 里填它。
> 注：`proprietary-files.txt` 目前是参考树(Unihertz Atom LXL)的起步清单，
> **必须用本机 dump 重生成/校正**。

---

## 三、用法

Actions → **LineageOS 20 [ROM]** → Run workflow：

| 输入 | 说明 |
|---|---|
| `RUNNER` | `self-hosted`（默认/推荐）或 `ubuntu-24.04` |
| `MANIFEST_URL` / `MANIFEST_BRANCH` | ROM 源码（默认 LineageOS `lineage-20.0`）|
| `DEVICE_TREE_URL` / `..._BRANCH` / `DEVICE_PATH` | 设备树（默认我们新建的 `_rom` 仓库）|
| `VENDOR_TREE_URL` / `VENDOR_PATH` | blobs 仓库（有就填）|
| `LUNCH` / `BUILD_VARIANT` | 默认 `lineage_k71v1_64_bsp-userdebug` |
| `BUILD_TARGET` | `bacon`=整包；也可 `systemimage` / `bootimage` |
| `CCACHE` | 1=开启（self-hosted 上有奇效）|
| `SYNC_ONLY` | 1=只同步源码不构建 |

产物上传到本仓库的 Release（tag `rom-<run_id>`）。

---

## 四、构建产物怎么刷

本机**无 AVB**、`boot`/`recovery` 各 32MB、**非动态分区**：

```bash
fastboot -S 128M flash system  <system.img>
fastboot -S 128M flash vendor  <vendor.img>
fastboot -S 128M flash boot    <boot.img>
# 清 data(首次换 ROM 必须)
fastboot -w
```

> ⚠️ `boot.img` 必须是"**v1 头 + 内核(尾部带 110572B MTK DTB)** + A13 ramdisk"，
> 否则 MTK lk 会死循环（详见 recovery 交接文档）。
> 设备树 `prebuilt/kernel` 已带尾部 DTB，`BOARD_BOOT_HEADER_VERSION := 1`。

---

## 五、M1 常见卡点（按经验）

1. **VNDK**：vendor 是 Android 9(VNDK 28) → 需正确设置 VNDK（GSI 13 能跑说明可行）。
2. **proprietary 清单**：按本机 dump 重生成，别照抄 Atom。
3. **sepolicy**：先 permissive 起来，再逐条收紧（看 `dmesg | grep avc`）。
4. **FBE/metadata**：`fstab.mt6771` 加密参数按原厂 policy 校正。
5. **HAL**：MTK 相机/音频/传感器 HAL 要能被 A13 调用。
6. **首次同步慢/大**：用 `SYNC_ONLY=1` 分两次跑。
