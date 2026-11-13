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
# 2026-11-13 Syncthing：注册 ucitrack，让「服务 → Syncthing」保存后自动重启
#------------------------------------------------------------------------------
# 背景（服务启停与 LuCI 启动项耦合）：
#   · LuCI「系统 → 启动项」列的是 /etc/rc.d/S* 链接，`init.d disable` 会删链接
#     → 页面里那一行直接消失，再从界面开不回来。所以任何情况下都不要用
#     disable 来实现「默认不启动」—— 要用 uci 里的 enabled / enable。
#   · 但光有开关不够：LuCI 保存配置后不会自动重启服务。
#     FileBrowser 插件自带 ucitrack（见插件仓库 root/etc/uci-defaults），
#     feeds 里的 luci-app-syncthing 不保证有，这里补一个，两边行为一致。
#   · 这样「在服务页勾选 / 取消 → 保存」就等于一次完整的启停动作，
#     完全不依赖启动项页面，也不再需要动 rc.d 链接。
#
# 时机：/etc/uci-defaults 由 /etc/init.d/boot 在 S10 执行，早于 S90/S99 的服务启动。
# 幂等：先 delete 再 add，重复执行结果一致。
#==============================================================================
UD=package/base-files/files/etc/uci-defaults
mkdir -p "$UD"

cat > "$UD/zz-syncthing-ucitrack" <<'EOF'
#!/bin/sh
uci -q batch <<-EOT >/dev/null
delete ucitrack.@syncthing[-1]
add ucitrack syncthing
set ucitrack.@syncthing[-1].init=syncthing
commit ucitrack
EOT
rm -f /tmp/luci-indexcache
exit 0
EOF
chmod 755 "$UD/zz-syncthing-ucitrack"

echo "[part1] 已写入 uci-defaults：zz-syncthing-ucitrack"
ls -l "$UD" 2>/dev/null | tail -n 3

