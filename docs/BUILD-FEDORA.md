# 在 Fedora（移动硬盘）上用容器编译 ROM

> 适用：你只有周末能用、用移动硬盘启动的 Fedora、没有银行卡。
> 目标 ROM：**LineageOS 20 / Android 13**。

---

## 0. 为什么要用容器（重要）

AOSP/LineageOS **官方只支持 Ubuntu LTS**，Fedora **不受支持**：
- `envsetup.sh` / build 系统会做发行版检查；
- Fedora 没有 `libncurses5`、`python2`（LOS20 构建链仍需要）、部分 32 位库命名不同。

**解法**：Fedora 只当宿主，**用 Podman/Docker 跑 `ubuntu:20.04` 容器**，在容器里编译。
源码与 ccache 放在**移动硬盘**上（bind mount 进容器），容器可随时销毁、状态不丢。

```
Fedora(宿主, 移动硬盘)  ──bind mount──▶  ubuntu:20.04 容器(编译)  ──▶ out/*.zip
        ▲                                        │
        └──────── 源码 ~70GB + ccache 50GB 都放硬盘 ──┘
```

---

## 1. 磁盘预算（移动硬盘要留多少）

| 项 | 大小 | 放哪 |
|---|---|---|
| LineageOS 20 源码 | **~70 GB** | 移动硬盘 |
| 编译产物 `out/` | **~40 GB** | 移动硬盘 |
| ccache | **~50 GB**（可调小到 20GB）| 移动硬盘 |
| 容器镜像 | ~3 GB | 系统盘即可 |

**建议移动硬盘预留 ≥ 200 GB 可用**。脚本会先检查。

---

## 2. 一次性准备（第一个周末）

```bash
# --- Fedora 上装 podman（Fedora 自带，通常已有）---
sudo dnf install -y podman git

# --- 确认移动硬盘挂载点（假设 /run/media/$USER/EXT）---
df -h | grep -i media           # 找到你的硬盘挂载点
export ROM_HD=/run/media/$USER/EXT      # 改成你的实际路径

# --- 在硬盘上建工作目录 ---
mkdir -p "$ROM_HD/lineage" "$ROM_HD/ccache"

# --- 取本仓库里的脚本 ---
git clone https://github.com/mmbsmm-git/Lazy_Action-ROM-Builder
cd Lazy_Action-ROM-Builder/local
```

> Fedora 默认 SELinux enforcing，容器挂载可能被拒：脚本已用
> `--security-opt label=disable` 规避（也可以临时 `sudo setenforce 0`）。

---

## 3. 用法

脚本 `rom.sh` 有三个子命令：

```bash
export ROM_HD=/run/media/$USER/EXT      # 移动硬盘挂载点
export ROM_DEVICE_TREE=~ /path/to/android_device_youxuepai_k71v1_64_bsp_rom

# ① 建编译镜像（只做一次，~10 分钟）
./rom.sh image

# ② 同步源码（第一次很久：4~10 小时；之后是增量，几分钟）
./rom.sh sync

# ③ 编译（第一次 6~12 小时；有 ccache 后快很多）
./rom.sh build
#   想只出某个镜像更快：
#   ./rom.sh build systemimage    或   ./rom.sh build bootimage

# 进容器手动操作（调试用）
./rom.sh shell
```

产物在：`$ROM_HD/lineage/out/target/product/k71v1_64_bsp/`

---

## 4. 周末时间怎么安排（现实的节拍）

| 周末 | 做什么 | 时长 |
|---|---|---|
| 第 1 个 | `image` + `sync`（源码下全）| 4~10h（可挂着跑）|
| 第 2 个 | 首次 `build`（大概率报错，出来一个修一个）| 6~12h |
| 第 3+ 个 | 修错 → 重编（有 ccache，通常 1~3h/次）| 逐步逼近 |

> 关键：**源码和 ccache 留在硬盘上**，不要在周末之间重下/重编。

---

## 5. 常见坑

1. **`python2` 缺失**：容器里已装（`python2.7` + `python-is-python2`）。
2. **SELinux 挂载被拒**：脚本用 `label=disable`；仍不行就 `sudo setenforce 0`（重启恢复）。
3. **内存 16GB 偏紧**：脚本会开 swap 建议值；也可把 `-j` 降到 `$(nproc)`。
4. **git-lfs**：LOS20 部分仓库用 LFS，脚本已 `git lfs install`。
5. **同步中断**：`repo sync` 可重复执行，会续传。
6. **磁盘又满了**：清 `out/` 重编（源码别删）；或 `ccache -C` 清缓存。

---

## 6. 产物怎么刷到手机

本机**无 AVB**，`system`/`vendor`/`boot` 直接刷（见 ROM 设备树 README）：

```bash
fastboot -S 128M flash system  out/.../system.img
fastboot -S 128M flash vendor  out/.../vendor.img
fastboot -S 128M flash boot    out/.../boot.img
fastboot -w        # 换 ROM 首次必须清 data
```

> `boot.img` 必须带"尾部 DTB 的内核 + v1 头"，设备树 `prebuilt/kernel` 已就绪。
