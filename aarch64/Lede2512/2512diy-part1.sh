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

#==============================================================================
# 【临时】2026-11-13 回退 host 工具链，绕过 gettext host 编译失败
#------------------------------------------------------------------------------
# 现象（run 2026-11-13 夜）：编译走到 host 工具链阶段时
#   staging_dir/host/share/gnulib/gnulib-tool.py: *** patch file
#   lib/exitfail.h didn't apply cleanly
#   ERROR: package/libs/gettext-full [host] failed to build.
#   这是内容不匹配，确定性失败，重跑无效（不是偶发、也不是竞争条件）。
#
# 原因：上游 2026-11-13 06:44 UTC 的 bed88351（restore native macOS
#   cross-compilation）把 tools/gnulib 从 stable-202401 升到 stable-202507，
#   同时把 coreutils 升到 9.6、elfutils 升到 0.196。gettext-0.22.5 的 host
#   构建在 autogen 阶段调用新版 gnulib-tool，它自带的 lib/exitfail.h 本地
#   补丁对新版 gnulib 打不上，于是整包失败。
#
# 做法：把这三个 tools 目录整体回退到 bed88351 的父提交 80122fea
#   （即 2026-09 的状态：gnulib stable-202401 / coreutils 9.5 / elfutils 0.195）。
#   不用整树 checkout，上游其它更新照常获取；三者出自同一提交，互相配套，
#   不会出现版本错配。
#
# 为什么先 rm -rf 再 checkout：git checkout <旧提交> -- <目录> 只把旧文件写回，
#   **不会删除**新提交里新增的文件（例如新版 patch），残留文件照样会影响
#   编译。先删目录再取，才能保证内容与旧提交完全一致。
#
# 【上游修好后怎么撤】只改这两处，不涉及别的东西：
#   1) 删掉本文件 ">>> TMP-PIN 开始" 到 "<<< TMP-PIN 结束" 之间的全部内容
#   2) 删掉 .github/workflows/Lede2512_FOL.yml 里名为「上游修复自检」的那一步
#      （那步只是打印提示，留着也无害，删掉更干净）
#   3) 推送后编一次：gettext host 能过 = 上游真的修好了
#
# 【怎么知道上游修好了】不用记日期、不用记哈希。本钉子已登记在
#   aarch64/Lede2512/upstream-pins.conf（名字 gettext-host-gnulib），
#   每次编译的「上游修补自检」步骤会打印结论，两行看完就行：
#     【结论】全部未修复，所有钉子继续保留，本次不用做任何事
#     【结论】有钉子对应的上游位置被改动了，按上面「处理」那一行做即可
#   该结论也写在 Actions 运行页的 Summary 表格里，不必翻日志。
#   将来若为别的上游问题再打钉子，同样往那个登记表加一行即可，不必改脚本。
#==============================================================================
# >>> TMP-PIN 开始（上游修复后整段删除）
HOST_TOOLS_PIN=80122feac964889bc69b62420cedfefaaf701eb0
HOST_TOOLS_DIRS="tools/gnulib tools/coreutils tools/elfutils"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "[part1] !! 当前目录不是 git 仓库，无法回退 host 工具（gettext 会编不过）"
    exit 1
fi

echo "[part1] 回退 host 工具到 ${HOST_TOOLS_PIN}（绕过 gettext host 编译失败）"
for d in $HOST_TOOLS_DIRS; do
    if ! git cat-file -e "${HOST_TOOLS_PIN}:${d}" 2>/dev/null; then
        echo "[part1] !! ${HOST_TOOLS_PIN} 里找不到 ${d}，无法回退"
        exit 1
    fi
    rm -rf "$d"
    if ! git checkout "$HOST_TOOLS_PIN" -- "$d"; then
        echo "[part1] !! 回退 ${d} 失败"
        exit 1
    fi
    echo "[part1]   ${d} 已回退到 $(git show -s --format='%h %cd' --date=short "$HOST_TOOLS_PIN")"
done
echo "[part1]   gnulib 版本行：$(grep -m1 -E 'PKG_SOURCE_VERSION|PKG_VERSION' tools/gnulib/Makefile 2>/dev/null | tr -d ' ')"
# <<< TMP-PIN 结束

