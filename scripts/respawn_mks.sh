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

echo "mk_files respawned."
