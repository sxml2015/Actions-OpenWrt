#!/bin/bash
#============================================================
# sxml2015
# 2026-10-18 2512
#https://github.com/HoldOnBro/Actions-OpenWrt
#https://github.com/breakings/OpenWrt
#============================================================
# 2026-10-16 改造：
#   1) 所有第三方源码克隆块受 aarch64/Lede2512/thirdparty.cfg 的 block 开关控制，
#      不用哪个就把 thirdparty.cfg 里对应的 on 改成 off，能省时间、少踩坑。
#   2) 新增第三方插件：写进 thirdparty.cfg 的 repo 行，本脚本会自动调用克隆。
#   3) 特殊处理（如 OpenClash 的 po2lmo 编译）放在 thirdparty.sh 里。
#   原始版本备份：2512diy-part2.sh.bak-*
#============================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${GITHUB_WORKSPACE:-$(cd "$HERE/../.." && pwd)}"
if [ -f "$HERE/../scripts/tp_lib.sh" ]; then
    # shellcheck source=/dev/null
    . "$HERE/../scripts/tp_lib.sh"
else
    echo "[part2] !! 找不到 tp_lib.sh，第三方克隆开关一律按 on 处理"
    tp_block() { return 0; }
    tp_block_state() { echo on; }
fi

echo "=============================================================="
echo " 2512diy-part2.sh  第三方插件开关（on = 克隆）"
echo "=============================================================="
for b in smartdns kenzok8-small helloworld passwall-packages passwall passwall2 \
         lua-maxminddb amlogic mosdns ddns-go openclash vim; do
    printf '   %-18s %s\n' "$b" "$(tp_block_state "$b")"
done
echo "=============================================================="

#移除不用软件包
# luci-app-dockerman：在使用中（新版 Docker LuCI 界面），不能删源码，否则 .config 里 =y 也编不出来。
#                     luci-app-docker（老版 Python 界面）已由 plugins.cfg 关掉。
#rm -rf package/lean/luci-app-wrtbwmon
rm -rf feeds/packages/net/smartdns
rm -rf feeds/luci/applications/luci-app-smartdns
#rm -fr feeds/luci/themes/luci-theme-design
rm -rf feeds/luci/applications/luci-app-ddns-go
rm -rf feeds/packages/net/ddns-go
#重新编译时没有旧的或不必要的文件干扰 #staging_dir：编译生成的文件和依赖库 #build_dir：软件包的源代码和编译生成的文件
rm -rf staging_dir build_dir
rm -rf feeds/packages/net/shadowsocks-libev

# 设置ttyd免帐号登录
sed -i 's/\/bin\/login/\/bin\/login -f root/' feeds/packages/utils/ttyd/files/ttyd.config

#克隆 pymumu 仓库 smartdns 20260405
# 克隆LEDE分支的luci界面（适配旧版）
if tp_block smartdns; then
  echo "[part2] 克隆 smartdns"
  # 1. 添加 SmartDNS 核心程序（pymumu/openwrt-smartdns）
  git clone --depth=1 https://github.com/pymumu/openwrt-smartdns.git feeds/packages/net/smartdns
  # 2. 添加 SmartDNS LuCI 界面（使用 lede 分支，兼容 coolsnowwolf/lede）
  git clone --depth=1 -b lede https://github.com/pymumu/luci-app-smartdns.git feeds/luci/applications/luci-app-smartdns
else
  echo "[part2] smartdns 已关闭，跳过"
fi

if tp_block kenzok8-small; then
  echo "[part2] 克隆 kenzok8/small"
  # 克隆 kenzok8 small仓库
  git clone --depth=1 https://github.com/kenzok8/small.git small-package
  #cp -rf small-package/gost package/gost
  #cp -rf small-package/luci-app-gost package/luci-app-gost
  #cp -rf small-package/sagernet-core package/sagernet-core
  #cp -rf small-package/v2ray-geodata package/v2ray-geodata
  cp -rf small-package/brook package/brook
  cp -rf small-package/ssocks package/ssocks
  cp -rf small-package/pdnsd-alt package/pdnsd-alt
  cp -rf small-package/trojan-go package/trojan-go
  cp -rf small-package/dns2tcp package/dns2tcp
  # cp -rf small-package/v2ray-geoview package/v2ray-geoview
  rm -rf small-package
else
  echo "[part2] kenzok8-small 已关闭，跳过"
fi

if tp_block helloworld; then
  echo "[part2] 克隆 fw876/helloworld"
  # 克隆 fw876 仓库
  git clone --depth=1 -b main https://github.com/fw876/helloworld.git
  #cp -rf helloworld/luci-app-ssr-plus package/luci-app-ssr-plus
  cp -rf helloworld/xray-core package/xray-core
  #cp -rf helloworld/xray-plugin package/xray-plugin
  # cp -rf helloworld/shadowsocks-libev package/shadowsocks-libev
  cp -rf helloworld/shadowsocks-rust package/shadowsocks-rust
  #cp -rf helloworld/shadowsocksr-libev package/shadowsocksr-libev
  cp -rf helloworld/v2ray-plugin package/v2ray-plugin
  cp -rf helloworld/v2ray-core package/v2ray-core
  #cp -rf helloworld/v2ray-geodata package/v2ray-geodata
  cp -rf helloworld/trojan package/trojan
  #cp -rf helloworld/sagernet-core package/sagernet-core
  cp -rf helloworld/microsocks package/microsocks
  cp -rf helloworld/redsocks2 package/redsocks2
  cp -rf helloworld/ipt2socks package/ipt2socks
  cp -rf helloworld/dns2socks package/dns2socks
  cp -rf helloworld/lua-neturl package/lua-neturl
  cp -rf helloworld/gn package/gn
  cp -rf helloworld/shadow-tls package/shadow-tls
  cp -rf helloworld/tuic-client package/tuic-client
  cp -rf helloworld/naiveproxy package/naiveproxy
  rm -rf helloworld
else
  echo "[part2] helloworld 已关闭，跳过"
fi

# 克隆 sbwml 仓库 shadowsocksr-libev 问题 20251021
#命令中的 -b v5 的意思是指定要克隆的分支（branch）为 v5
#命令中的--depth=1 只复制仓库最新的1个提交历史
# git clone --depth=1 -b v5 https://github.com/sbwml/openwrt_helloworld.git
# cp -rf openwrt_helloworld/shadowsocksr-libev package/shadowsocksr-libev

#------------------------------------------------------------------------------
# 从上游仓库复制子目录到 package/
# 上游删掉或改名某个目录时（例如 openwrt-passwall-packages 已移除 trojan-plus），
# 原来的 cp -rf 会刷一行
#   cp: cannot stat 'openwrt-passwall-packages/trojan-plus': No such file or directory
# 虽不致命，但会混在日志里干扰排查。改为先判断存在性，缺了只提示、不报错。
#------------------------------------------------------------------------------
tp_cp() {
  if [ -d "$1" ]; then
    cp -rf "$1" "$2"
  else
    echo "[part2] 跳过 $(basename "$1")：上游仓库里已没有这个目录"
  fi
}

if tp_block passwall-packages; then
  echo "[part2] 克隆 openwrt-passwall-packages"
  # 克隆openwrt-passwall仓库
  git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git
  #tp_cp openwrt-passwall-packages/brook package/brook
  #tp_cp openwrt-passwall-packages/ssocks package/ssocks
  tp_cp openwrt-passwall-packages/simple-obfs package/simple-obfs
  #tp_cp openwrt-passwall-packages/pdnsd-alt package/pdnsd-alt
  tp_cp openwrt-passwall-packages/chinadns-ng package/chinadns-ng
  tp_cp openwrt-passwall-packages/tcping package/tcping
  #tp_cp openwrt-passwall-packages/trojan-go package/trojan-go
  tp_cp openwrt-passwall-packages/trojan-plus package/trojan-plus
  tp_cp openwrt-passwall-packages/hysteria package/hysteria
  #tp_cp openwrt-passwall-packages/dns2tcp package/dns2tcp
  tp_cp openwrt-passwall-packages/sing-box package/sing-box
  tp_cp openwrt-passwall-packages/v2ray-geodata package/v2ray-geodata
  tp_cp openwrt-passwall-packages/xray-plugin package/xray-plugin
  tp_cp openwrt-passwall-packages/shadowsocksr-libev package/shadowsocksr-libev
  rm -rf openwrt-passwall-packages
else
  echo "[part2] passwall-packages 已关闭，跳过"
fi

if tp_block passwall; then
  echo "[part2] 克隆 luci-app-passwall"
  #passwall
  git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git
  cp -rf openwrt-passwall/luci-app-passwall package/luci-app-passwall
  rm -rf openwrt-passwall
else
  echo "[part2] passwall 已关闭，跳过"
fi

if tp_block passwall2; then
  echo "[part2] 克隆 luci-app-passwall2"
  #passwall2
  git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2.git
  cp -rf openwrt-passwall2/luci-app-passwall2 package/luci-app-passwall2
  rm -rf openwrt-passwall2
else
  echo "[part2] passwall2 已关闭，跳过"
fi

if tp_block lua-maxminddb; then
  echo "[part2] 克隆 lua-maxminddb"
  #解析
  git clone --depth=1 https://github.com/jerrykuku/lua-maxminddb.git package/lua-maxminddb
  rm -rf lua-maxminddb
else
  echo "[part2] lua-maxminddb 已关闭，跳过"
fi

if tp_block amlogic; then
  echo "[part2] 克隆 luci-app-amlogic"
  #添加晶晨宝盒
  git clone --depth=1 https://github.com/ophub/luci-app-amlogic.git
  cp -rf luci-app-amlogic/luci-app-amlogic package/luci-app-amlogic
  rm -rf luci-app-amlogic
  #修改晶晨宝盒默认配置
  # 1.设置OpenWrt 文件的下载仓库
  sed -i "s|https.*/OpenWrt|https://github.com/sxml/Actions-OpenWrt|g" package/luci-app-amlogic/root/etc/config/amlogic
  # 2.设置 Releases 里 Tags 的关键字（按设备区分，由工作流传入 AML_TAG_KEYWORD）
  if [ -n "$AML_TAG_KEYWORD" ]; then
    sed -i "s|option github_releases_tag '.*'|option github_releases_tag '$AML_TAG_KEYWORD'|" package/luci-app-amlogic/root/etc/config/amlogic
    sed -i "s|^github_releases_tag=.*|github_releases_tag='$AML_TAG_KEYWORD'|" package/luci-app-amlogic/root/etc/config/amlogic
    sed -i "s|ARMv8|$AML_TAG_KEYWORD|g" package/luci-app-amlogic/root/etc/config/amlogic
    echo "[part2] 晶晨宝盒 Releases 关键字 → $AML_TAG_KEYWORD"
  else
    sed -i "s|ARMv8|ARMv8|g" package/luci-app-amlogic/root/etc/config/amlogic
  fi
  # 3.设置 Releases 里 OpenWrt 文件的后缀
  sed -i "s|.img.gz|.img.gz|g" package/luci-app-amlogic/root/etc/config/amlogic
  # 4.设置 OpenWrt 内核的下载路径
  #sed -i "s|opt/kernel|BuildARMv8|g" package/luci-app-amlogic/root/etc/config/amlogic
  sed -i "s|http.*/library|https://github.com/breakings/OpenWrt/tree/main/opt/kernel|g" package/luci-app-amlogic/root/etc/config/amlogic
else
  echo "[part2] amlogic 已关闭，跳过"
fi

# themes 主题
# git clone --depth=1 https://github.com/sxml/luci-theme-design.git package/luci-theme-design
# git clone --depth=1 https://github.com/sxml/luci-app-design-config.git package/luci-app-design-config
# rm -rf luci-theme-design
# rm -rf luci-app-design-config

if tp_block mosdns; then
  echo "[part2] 克隆 mosdns"
  #mosdns
  rm -rf feeds/packages/net/mosdns
  rm -rf feeds/luci/applications/luci-app-mosdns
  #命令中的 -b v5-lua 的意思是指定要克隆的分支（branch）为 v5-lua
  git clone -b v5-lua https://github.com/sbwml/luci-app-mosdns package/luci-app-mosdns
  git clone -b v5-lua https://github.com/sbwml/luci-app-mosdns package/mosdns
  rm -rf luci-app-mosdns
  rm -rf mosdns
else
  echo "[part2] mosdns 已关闭，跳过"
fi

if tp_block ddns-go; then
  echo "[part2] 克隆 ddns-go"
  #添加ddns-go 动态域名解析
  #git clone --depth=1 https://github.com/sirpdboy/luci-app-ddns-go.git package/ddns-go
  git clone --depth=1 -b lua https://github.com/sirpdboy/luci-app-ddns-go.git
  cp -rf luci-app-ddns-go/ddns-go package/ddns-go
  cp -rf luci-app-ddns-go/luci-app-ddns-go package/luci-app-ddns-go
  rm -rf luci-app-ddns-go
  rm -rf ddns-go
else
  echo "[part2] ddns-go 已关闭，跳过"
fi

if tp_block openclash; then
  echo "[part2] 克隆 OpenClash（po2lmo 编译在 thirdparty.sh 里做）"
  #小猫
  git clone --depth=1 https://github.com/vernesong/OpenClash.git
  cp -rf OpenClash/luci-app-openclash package/luci-app-openclash
  rm -rf OpenClash
else
  echo "[part2] openclash 已关闭，跳过"
fi

# #libcryptopp 编译问题
# # 在 Makefile 中显式指定编译器
# sed -i '/include $(INCLUDE_DIR)\/package.mk/a TARGET_CC:=aarch64-openwrt-linux-musl-gcc\nTARGET_CXX:=aarch64-openwrt-linux-musl-g++' package/lean/libcryptopp/Makefile
# # 清理 libcryptopp 的缓存
# make package/lean/libcryptopp/clean

#202607 vim报错
if tp_block vim; then
  echo "[part2] 替换 vim 为 openwrt-18.06 版本"
  rm -rf feeds/packages/utils/vim
  git clone https://github.com/openwrt/packages.git --depth=1 -b openwrt-18.06 feeds-tmp
  # 修正：原脚本从 feeds-t 复制（该目录并不存在），改为从实际克隆目录 feeds-tmp 复制
  cp -r feeds-tmp/utils/vim feeds/packages/utils/
  rm -rf feeds-tmp
else
  echo "[part2] vim 替换已关闭，跳过"
fi

#修改makefile
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/include\ \.\.\/\.\.\/luci\.mk/include \$(TOPDIR)\/feeds\/luci\/luci\.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/include\ \.\.\/\.\.\/lang\/golang\/golang\-package\.mk/include \$(TOPDIR)\/feeds\/packages\/lang\/golang\/golang\-package\.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=\@GHREPO/PKG_SOURCE_URL:=https:\/\/github\.com/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -i sed -i 's/PKG_SOURCE_URL:=\@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload\.github\.com/g' {}

#------------------------------------------------------------------------------
# 新增第三方插件源（thirdparty.cfg 里的 repo 行）
#------------------------------------------------------------------------------
if [ -f "$HERE/../scripts/clone_thirdparty.sh" ]; then
    bash "$HERE/../scripts/clone_thirdparty.sh" || echo "[part2] !! clone_thirdparty.sh 返回非 0"
fi

#------------------------------------------------------------------------------
# 第三方插件特殊处理（thirdparty.sh）
#------------------------------------------------------------------------------
if [ -f "$HERE/thirdparty.sh" ]; then
    bash "$HERE/thirdparty.sh" || echo "[part2] !! thirdparty.sh 返回非 0"
fi

./scripts/feeds update -a
./scripts/feeds install -a

#==============================================================================
# 2026-10-17 修复：python 包的 wheel 文件名大小写不确定 → installer 找不到文件
#------------------------------------------------------------------------------
# 两次不同的失败，同一个根因：
#   FileNotFoundError: .../pypi/itsdangerous-2.1.2//openwrt-build/-2.1.2-*.whl   （名字整个空了）
#   FileNotFoundError: .../pypi/PyYAML-6.0.1//openwrt-build/pyyaml-6.0.1-*.whl    （大小写不符）
#
# 根因：python3-package.mk / python3-host-build.mk 的 install 配方写死了
#         "$(PYTHON3_PKG_BUILD_DIR)"/openwrt-build/$(PYTHON3_PKG_WHEEL_NAME)-$(PYTHON3_PKG_WHEEL_VERSION)-*.whl
#       而 PYTHON3_PKG_WHEEL_NAME 的默认值是
#         $(subst -,_,$(if $(PYPI_SOURCE_NAME),$(PYPI_SOURCE_NAME),$(PKG_NAME)))
#       ——只把 '-' 换成 '_'，【不做小写化】。
#       可实产 wheel 的名字取决于包自己的元数据：
#         · 带 pyproject.toml [project] 的（Cython 3.x）→ 规范化成小写 cython-3.0.10-*.whl
#         · 只有 setup.py 的（PyYAML 6.0.1）         → 原样保留大写 PyYAML-6.0.1-*.whl
#       Linux 区分大小写，所以「一律改小写」和「一律不改」都必然误伤一部分包。
#
#       历史教训：曾按「PYPI 名含大写就改小写」批量覆盖了 21 个包。先挂 itsdangerous，
#       修掉判断逻辑后又在 python-yaml 挂——两次都是这一处。证明"猜名字"这条路走不通。
#
# 方案：不再猜。把两处 install 配方的 glob 从
#         <名字>-<版本>-*.whl   →   *.whl
#       `python -m build --wheel` 每次构建在 openwrt-build/ 下只产出一个 whl，
#       通配必然命中，与大小写、命名规范、包类型都无关。
#       同时清掉历史注入的 PYTHON3_*_WHEEL_NAME 覆盖行（改完通配后它们是死代码）。
#
# 必须在 feeds update/install 之后执行（feeds 更新会覆盖这些 mk 文件）。
#==============================================================================
wheel_glob_fix() {
  _f="$1"
  _var="$2"
  if [ ! -f "$_f" ]; then
    echo "[wheel-glob-fix] 跳过（文件不存在）: $_f"
    return 0
  fi
  if grep -q 'openwrt-build/\*\.whl' "$_f"; then
    echo "[wheel-glob-fix] $(basename "$_f")：已修补过，跳过"
    return 0
  fi
  # 用 [$] [*] [.] 逐字符转义，避开 BRE 元字符歧义
  sed -i "s|openwrt-build/[$](${_var}_WHEEL_NAME)-[$](${_var}_WHEEL_VERSION)-[*][.]whl|openwrt-build/*.whl|" "$_f"
  if grep -q 'openwrt-build/\*\.whl' "$_f"; then
    echo "[wheel-glob-fix] $(basename "$_f")：install glob → openwrt-build/*.whl"
  else
    echo "[wheel-glob-fix] !! $(basename "$_f")：未匹配到预期文本"
    echo "[wheel-glob-fix] !! 上游 mk 结构可能已变，请手工检查 install 配方"
  fi
}
wheel_glob_fix feeds/packages/lang/python/python3-package.mk    PYTHON3_PKG
wheel_glob_fix feeds/packages/lang/python/python3-host-build.mk PYTHON3_HOST

# 清掉历史注入的覆盖行。只删「PKG 与 HOST 两项都存在且值完全相同」的成对行——
# 上游自己写的覆盖一般只有一条，或两条值不同，不会命中。
for _f in feeds/packages/lang/python/*/Makefile; do
  [ -f "$_f" ] || continue
  grep -qE '^PYTHON3_(PKG|HOST)_WHEEL_NAME:=' "$_f" || continue
  _pn=$(sed -n 's/^PYTHON3_PKG_WHEEL_NAME:=\(.*\)$/\1/p' "$_f" | head -n1)
  _hn=$(sed -n 's/^PYTHON3_HOST_WHEEL_NAME:=\(.*\)$/\1/p' "$_f" | head -n1)
  if [ -n "$_pn" ] && [ "$_pn" = "$_hn" ]; then
    sed -i '/^PYTHON3_PKG_WHEEL_NAME:=/d; /^PYTHON3_HOST_WHEEL_NAME:=/d' "$_f"
    echo "[wheel-glob-fix] 清除历史覆盖: $(basename "$(dirname "$_f")") ($_pn)"
  fi
done
