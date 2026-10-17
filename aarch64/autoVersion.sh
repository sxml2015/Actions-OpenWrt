#!/bin/bash
#=============================================================================
# autoVersion.sh —— 把 LEDE 源码里的版本号写进 openwrt_packit 打包用的 whoami
#
# 2026-10-16 改造：原来把仓库绝对路径写死成
#   /home/runner/work/Actions-OpenWrt/Actions-OpenWrt/scripts/whoami
# 仓库改名或换 runner 路径就会失效，现在改为优先使用 GITHUB_WORKSPACE。
#=============================================================================

WS="${GITHUB_WORKSPACE:-}"
if [ -z "$WS" ]; then
    # 不在 Actions 里跑时，用本脚本往上两级推算仓库根
    WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

SRC_CONFIG="$WS/openwrt/package/lean/default-settings/files/zzz-default-settings"
[ -f "$SRC_CONFIG" ] || SRC_CONFIG="/workdir/openwrt/package/lean/default-settings/files/zzz-default-settings"

OpVersion=$(grep -Po "DISTRIB_REVISION=\'\K[^\']*" "$SRC_CONFIG" 2>/dev/null)

echo "版本号: $OpVersion"
echo "仓库根: $WS"

if [ -z "$OpVersion" ]; then
    echo "!! 未能从 $SRC_CONFIG 读取版本号，放弃改写 whoami"
    exit 0
fi

if [ -f "$WS/scripts/whoami" ]; then
    sed -i "s/OPENWRT_VER=.*/OPENWRT_VER=\"$OpVersion\"/" "$WS/scripts/whoami"
    echo "已更新 $WS/scripts/whoami"
else
    echo "!! 找不到 $WS/scripts/whoami"
fi
