#!/bin/bash
#=============================================================
# sxml2015
# 2026-10-06 2512
# part1：**只做 git 克隆插件，移除 feeds update/install**，避免被 yml 步骤二次 update 覆盖修复补丁
#=============================================================
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
# Lisence: MIT
# Author: P3TERX
# Blog: https://p3terx.com
#=============================================================
#原
# Uncomment a feed source
#sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default
# Add a feed source
#sed -i '$a src-git lienol https://github.com/Lienol/openwrt-package' feeds.conf.default

#==============================================================================
# 2026-11-06 FileBrowser：独立 feed 接线（必须排在 luci feed 之前）
#------------------------------------------------------------------------------
# 插件源码在单独仓库，固件项目这边只加一行 feed 源：
#   https://github.com/sxml2015/Actions-OpenWrt-FileBrowser
# 该 feed 提供两个包：
#   · luci-app-filebrowser  界面 + UCI 配置 + procd 启动脚本（LUCI_PKGARCH:=all）
#   · filebrowser-bin       官方 arm64 预编译二进制 -> /usr/bin/filebrowser
#
# 为什么必须放第一行：coolsnowwolf/luci 的 openwrt-25.12 分支自带一个同名包
# luci-app-filebrowser（stokito 的 JS 版文件管理器，菜单也是 NAS -> File Browser）。
# scripts/feeds 对同名源包是「feeds.conf 里先出现者胜」，后出现的静默跳过。
# 追加到末尾时，装进固件的就是上游那个包，本插件连链接都不会建。
#
# 编不编进固件仍由 plugins.cfg 的三个 on 决定。改插件只动插件仓库。
# 时机要求：必须早于 feeds update —— 本脚本正是在 update 之前执行。
#==============================================================================
FB_FEED_LINE='src-git filebrowser https://github.com/sxml2015/Actions-OpenWrt-FileBrowser.git'
FB_CONF=feeds.conf.default
if [ -f feeds.conf ]; then
    FB_CONF=feeds.conf
fi

if [ -f "$FB_CONF" ]; then
    # 先删掉历史遗留的同名行（之前追加在末尾的那一行）
    grep -v -E '^[[:space:]]*src-git[[:space:]]+filebrowser[[:space:]]' \
        "$FB_CONF" > "$FB_CONF.fbtmp" 2>/dev/null
    # 再放到最前面
    printf '%s\n' "$FB_FEED_LINE" > "$FB_CONF"
    cat "$FB_CONF.fbtmp" >> "$FB_CONF"
    rm -f "$FB_CONF.fbtmp"
    echo "[part1] 已把 FileBrowser feed 放在 $FB_CONF 第一行（需早于 luci feed）"
    head -n 2 "$FB_CONF"
else
    echo "[part1] !! 找不到 $FB_CONF，FileBrowser 将不会进固件"
fi

#==============================================================================
# 2026-11-12 首次开机行为（写进 base-files 的 uci-defaults，随固件生效）
#------------------------------------------------------------------------------
# 为什么用 uci-defaults：/etc/uci-defaults 由 /etc/init.d/boot 在 S10 执行，
# 早于 S95/S99 的服务启动；脚本执行完自动删除，每次刷机后重跑一次。
# 文件必须 chmod 755 —— 不可执行的文件不会被 run。
#
# 1) zz-disable-autostart：FileBrowser 与 Syncthing 默认不启动。
#    这两个包的 postinst 会在打包时自动 enable（生成 /etc/rc.d/S* 链接），
#    所以要在首次开机显式 disable；需要时到 LuCI「系统 → 启动项」里手动开启。
#
# 2) zz-carbon-default：默认主题固定为 Carbon。
#    各主题包的 30_luci-theme-* 按字母序执行，design / material 排在 carbon
#    之后，会把 luci.main.mediaurlbase 改回自己。
#    用 zz- 前缀（排在数字和字母之后），确保在所有包自带的 uci-defaults 之后收尾。
#==============================================================================
UD=package/base-files/files/etc/uci-defaults
mkdir -p "$UD"

cat > "$UD/zz-disable-autostart" <<'EOF'
#!/bin/sh
[ -x /etc/init.d/filebrowser ] && /etc/init.d/filebrowser disable
[ -x /etc/init.d/syncthing ] && /etc/init.d/syncthing disable
exit 0
EOF
chmod 755 "$UD/zz-disable-autostart"

cat > "$UD/zz-carbon-default" <<'EOF'
#!/bin/sh
uci -q set luci.themes.Carbon='/luci-static/carbon'
uci -q set luci.main.mediaurlbase='/luci-static/carbon'
uci commit luci
exit 0
EOF
chmod 755 "$UD/zz-carbon-default"

echo "[part1] uci-defaults 已写入：zz-disable-autostart、zz-carbon-default"
ls -l "$UD" 2>/dev/null | tail -n 4
