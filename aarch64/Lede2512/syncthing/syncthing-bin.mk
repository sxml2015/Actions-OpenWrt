# ---- ST-OFFICIAL-BIN ----
# Syncthing 官方预编译二进制包 Makefile（覆盖 feeds 版）。
#
# 由 2512diy-part2.sh 在 ./scripts/feeds install -a 之后覆盖到
#   feeds/packages/utils/syncthing/Makefile
# 原文件会先备份为 Makefile.feed.bak。
#
# 与原 Makefile 的差别：
#   · 不编 Go 源码，直接下载官方 linux-arm64 tar.gz，取其 syncthing 二进制；
#     顺带省掉 golang/host 构建（约 8~15 分钟）。
#   · opkg 里版本号是真实的 2.x，LuCI「软件包」页不再显示 1.24.0。
#   · 不再构建 stdiscosrv / strelaysrv 两个包（本仓库基线里两个都是
#     "is not set"，plugins.cfg 也没有它们，删掉不会造成依赖缺失）。
#
# 为什么需要这个覆盖：
#   feeds 里的 1.24.0 是 go1.27.1 编的，带 Go 1.26+ 的 crypto/tls 会话票据
#   缺陷，会持续 panic 重启；官方 v2 只发 tar.gz、没有 ipk，所以原来只能
#   刷完机手动跑 syncthing-upgrade.sh 去替换 /usr/bin/syncthing。
#
# 版本号与 SHA256 由脚本用 sed 注入（@ST_VER@ / @ST_SHA256@），
# 要升版本只改 2512diy-part2.sh 里的 ST_VER / ST_SHA256 两处。
#
# 注意：官方二进制只适用于 aarch64，PKGARCH 已锁定 aarch64_generic。
#       换到 x86/armv7 目标时不能复用本文件。

include $(TOPDIR)/rules.mk

PKG_NAME:=syncthing
PKG_VERSION:=@ST_VER@
PKG_RELEASE:=1

PKG_SOURCE:=syncthing-linux-arm64-v$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/syncthing/syncthing/releases/download/v$(PKG_VERSION)
PKG_HASH:=@ST_SHA256@

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)
PKGARCH:=aarch64_generic

PKG_LICENSE:=MPL-2.0
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/syncthing
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Continuous file synchronization program (official prebuilt)
  URL:=https://syncthing.net
  DEPENDS:=
  USERID:=syncthing=499:syncthing=499
endef

define Package/syncthing/description
  Syncthing replaces proprietary sync and cloud services with something
  open, trustworthy and decentralized. Your data is your data alone and
  you deserve to choose where it is stored, if it is shared with some
  third party and how it's transmitted over the Internet.

  This package installs the official prebuilt linux-arm64 binary instead of
  building from source, so the version tracks upstream 2.x while the feeds
  package is still 1.24.0.
endef

define Package/syncthing/conffiles
/etc/config/syncthing
/etc/syncthing
endef

# 官方 tar.gz 内层目录是 syncthing-linux-arm64-v<ver>/，strip 掉这一层，
# 让 $(PKG_BUILD_DIR)/syncthing 正好是二进制。
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR) --strip-components=1
endef

define Build/Compile
	# 无源码，二进制已由 Build/Prepare 解出
endef

define Package/syncthing/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/syncthing $(1)/usr/bin/syncthing

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(CURDIR)/files/syncthing.conf $(1)/etc/config/syncthing

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(CURDIR)/files/syncthing.init $(1)/etc/init.d/syncthing

	$(INSTALL_DIR) $(1)/etc/sysctl.d
	-$(INSTALL_BIN) $(CURDIR)/files/syncthing-sysctl.conf $(1)/etc/sysctl.d/90-syncthing-inotify.conf
endef

$(eval $(call BuildPackage,syncthing))
