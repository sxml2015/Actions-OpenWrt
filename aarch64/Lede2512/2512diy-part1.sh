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
# 2026-11-05 FileBrowser：独立 feed 接线
#------------------------------------------------------------------------------
# 插件源码已拆到单独仓库，固件项目这边只加一行 feed 源：
#   https://github.com/sxml2015/Actions-OpenWrt-FileBrowser
# 该 feed 提供两个包：
#   · luci-app-filebrowser  界面 + UCI 配置 + procd 启动脚本（LUCI_PKGARCH:=all）
#   · filebrowser-bin       官方 arm64 预编译二进制 -> /usr/bin/filebrowser
#
# 这里只负责「让源码进源码树」，编不编进固件仍由 plugins.cfg 的三个 on 决定。
# 时机要求：必须早于 feeds update —— 本脚本正是在 update 之前执行。
# 改插件（默认值/启动逻辑/升版本）只动插件仓库，本文件不用改。
#==============================================================================
FB_FEED_LINE='src-git filebrowser https://github.com/sxml2015/Actions-OpenWrt-FileBrowser.git'
FB_CONF=feeds.conf.default
if [ -f feeds.conf ]; then
    FB_CONF=feeds.conf
fi

if grep -q '^src-git filebrowser ' "$FB_CONF" 2>/dev/null; then
    echo "[part1] FileBrowser feed 已存在（$FB_CONF），跳过"
else
    echo "$FB_FEED_LINE" >> "$FB_CONF" \
        && echo "[part1] 已添加 FileBrowser feed -> $FB_CONF" \
        || echo "[part1] !! 写入 $FB_CONF 失败，FileBrowser 将不会进固件"
fi
