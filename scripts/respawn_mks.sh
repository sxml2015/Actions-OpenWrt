#!/bin/bash

cd /opt/openwrt_packit
cp make.env makeplus.env

#兼容历史：早期下载脚本没做 URL 解码，会把资产名里的 "+" 存成 "%2B"
for f in /opt/kernel/*%2B*; do
    [ -e "$f" ] || continue
    nf="${f//%2B/+}"
    mv -f "$f" "$nf" && echo "[respawn] 修正文件名: $(basename "$nf")"
done

#sync the kernel version
#  -printf '%f' 只输出文件名，避免 awk 依赖目录层级（用相对路径时 $2..$6 会错位）
KV=$(find /opt/kernel/ -name "boot*+o.tar.gz" -printf '%f\n' | head -1 | awk -F '[-.]' '{print $2"."$3"."$4"-"$5"-"$6}')
KPPV=$(find /opt/kernel/ -name "boot*+.tar.gz" -printf '%f\n' | head -1 | awk -F '[-.]' '{print $2"."$3"."$4"-"$5"-"$6}')

if [ -z "$KV" ] || [ -z "$KPPV" ]; then
    echo "!! 无法从 /opt/kernel 解析内核版本号，停止打包"
    echo "   KV='$KV'   KPPV='$KPPV'"
    echo "   期望文件名形如 boot-6.12.113-flippy-95+o.tar.gz / boot-6.18.57-flippy-95+.tar.gz"
    echo "   实际目录内容："
    ls -la /opt/kernel 2>/dev/null || echo "   （目录不存在）"
    exit 1
fi
echo "[respawn] KERNEL_VERSION(basic)=$KV  KERNEL_VERSION(plus)=$KPPV"
#KPV=$(find /opt/kernel/ -name "boot-5\.16*+.tar.gz" | awk -F '[-.]' '{print $2"."$3"."$4"-"$5"-"$6}')
#KPPV=$(find /opt/kernel/ -name "boot-5\.19*+.tar.gz" | awk -F '[-.]' '{print $2"."$3"."$4"-"$5"-"$6}')
sed -i "s/^    KERNEL_VERSION.*/    KERNEL_VERSION=\"$KV\"/" make.env
#sed -i "s/^    KERNEL_VERSION.*/    KERNEL_VERSION=\"$KPV\"/" makeplus.env
sed -i "s/^    KERNEL_VERSION.*/    KERNEL_VERSION=\"$KPPV\"/" makeplus.env

for F in *.sh ; do cp $F ${F%.sh}_basic.sh && cp $F ${F%.sh}_plus.sh;done
#find ./* -maxdepth 1 -path "*_plus.sh" | xargs -i sed -i 's/make\.env/makeplus\.env/g' {}
find ./* -maxdepth 1 -path "*_plus.sh" | xargs -i sed -i 's/make\.env/makeplus\.env/g' {}
#统一用FOL打包
#find ./*_basic.sh ./*_plus.sh ./*_plusplus.sh -maxdepth 1 -path "*" | xargs -i sed -i 's/OP_ROOT_TGZ=\"openwrt/OP_ROOT_TGZ=\"F-openwrt/g' {}
#find ./*_basic.sh ./*_plus.sh ./*_plusplus.sh -maxdepth 1 -path "*" | xargs -i sed -i 's/TGT_IMG=\"\${WORK_DIR}\/openwrt/TGT_IMG=\"\${WORK_DIR}\/F-openwrt/g' {}

#旧内核新内核分开打包
#12以后内核无法使用SFE，使用仅含FOL的固件进行打包
#find ./*_plusplus.sh -maxdepth 1 -path "*" | xargs -i sed -i 's/OP_ROOT_TGZ=\"openwrt/OP_ROOT_TGZ=\"F-openwrt/g' {}
#find ./*_plusplus.sh -maxdepth 1 -path "*" | xargs -i sed -i '/^TGT_IMG.*img\"$/s/\.img/\_FOL\.img/g' {}
#所有内核均已支持SFE，使用含SFE和FOL的固件进行打包
#find ./*_basic.sh ./*_plus.sh -maxdepth 1 -path "*" | xargs -i sed -i 's/OP_ROOT_TGZ=\"openwrt/OP_ROOT_TGZ=\"SF-openwrt/g' {}
#find ./*_basic.sh ./*_plus.sh -maxdepth 1 -path "*" | xargs -i sed -i '/^TGT_IMG.*img\"$/s/\.img/\_FOL\+SFE\.img/g' {}

# ---------------------------------------------------------------------------
# N1 分区参数：完全使用上游默认值，不做任何覆盖（2026.11.07 定案）
#
# 最终分区布局不是 mk 脚本直接写进镜像的：
#   mk_s905d_n1.sh 只做两个分区（p1 boot + p2 rootfs），并把
#   "${SKIP_MB} ${BOOT_MB} ${ROOTFS_MB}" 写进镜像里的 /etc/part_size；
#   设备首次开机时 /etc/first_run.sh（来自 packit 的 files/first_run.sh）
#   用磁盘剩余空间现场补出：
#     p3 = ROOTFS_MB      btrfs  MMC_ROOTFS2   ← luci-app-amlogic 在线升级的 A/B 备用根
#     p4 = 全部剩余空间    btrfs  MMC_SHARED    ← /mnt/mmcblk2p4，docker 与升级 img 都在这里
#   所以 ROOTFS_MB 一变，镜像大小、p2、p3 三处同时跟着变，p4 只剩剩余部分。
#
# 为什么不再改 ROOTFS_MB：
#   1) 上游默认 1280 已比设备当前的 960 大 320 MB，足够缓解 opkg 空间紧张；
#   2) 保持上游值则 p4 约 4.06 GB，最接近设备现状（4.47 GB），其他分区改动最小；
#   3) 改大（1536/2048）会把 p4 压到 3.55 / 2.5 GB，而 luci-app-amlogic 在线升级
#      需要把 .img.gz 解压成 .img 放在 p4，峰值约 2R + 1.1 GB，p4 不足 3 GB 就升不动。
#   4) 不覆盖上游，还能跟随上游更新，本仓库零维护。
#
#   注意：分区表只在首次开机时生成，必须全新刷机才生效；就地升级不改分区。
#   这里仅做只读检查：打印实际取值，并在上游把默认值调得过大时告警。
# ---------------------------------------------------------------------------
for mk in mk_s905d_n1_basic.sh mk_s905d_n1_plus.sh; do
    [ -f "$mk" ] || continue
    MB=$(sed -n 's/^ROOTFS_MB=\([0-9]*\).*/\1/p' "$mk" | head -n1)
    if [ -z "$MB" ]; then
        echo "!! $mk 里找不到 ROOTFS_MB=，上游可能改了变量名，请人工确认分区参数"
        continue
    fi
    echo "[respawn] $mk -> ROOTFS_MB=$MB  $(grep -m1 '^BOOT_MB=' "$mk")  $(grep -m1 '^SKIP_MB=' "$mk")"
    if [ "$MB" -gt 1536 ]; then
        echo "!! ROOTFS_MB=$MB 偏大：p4 会小于 3 GB，luci-app-amlogic 在线升级可能因空间不足失败"
    fi
done

# 校验上游仍按「2 分区 + 首启扩分区」的方式工作，避免上游改结构后静默失效
if [ -f files/first_run.sh ] && grep -q '^FIRSTRUN_SCRIPT=' mk_s905d_n1.sh; then
    echo "[respawn] 首启分区脚本在位：files/first_run.sh（p3/p4 由设备首次开机创建）"
else
    echo "!! 未找到 files/first_run.sh 或 FIRSTRUN_SCRIPT 定义，设备可能不会自动创建 p3/p4"
fi

echo "mk_files respawned."
