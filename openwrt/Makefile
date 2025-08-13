# OpenWrt Makefile for starfail daemon

include $(TOPDIR)/rules.mk

PKG_NAME:=starfail
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/markus-lassfolk/rutos-starlink-failover.git
PKG_SOURCE_VERSION:=HEAD
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_USE_MIPS16:=0

GO_PKG:=github.com/markus-lassfolk/rutos-starlink-failover
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/starfaild

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/starfail
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Intelligent multi-interface failover daemon
  DESCRIPTION:=Go-based daemon for autonomous multi-interface failover on RutOS/OpenWrt
  URL:=https://github.com/markus-lassfolk/rutos-starlink-failover
  DEPENDS:=+ca-bundle +mwan3 +kmod-mppe
  PKGARCH:=all
endef

define Package/starfail/description
Starfail is an intelligent multi-interface failover daemon designed for
RutOS and OpenWrt routers. It provides predictive failover between
Starlink, cellular, Wi-Fi, and LAN connections with comprehensive
scoring and telemetry.

Features:
- Autonomous member discovery via mwan3 integration
- Predictive failover based on quality metrics
- Starlink API integration for obstruction monitoring
- Cellular signal quality monitoring via ubus
- Configurable via UCI with sane defaults
- JSON structured logging and ubus API
- Minimal resource footprint
endef

define Package/starfail/conffiles
/etc/config/starfail
endef

define Package/starfail/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/starfaild $(1)/usr/sbin/
	
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/starfailctl $(1)/usr/sbin/
	
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/starfail.init $(1)/etc/init.d/starfail
	
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/starfail.config $(1)/etc/config/starfail
	
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_DATA) ./files/99-starfail $(1)/etc/hotplug.d/iface/
endef

define Package/starfail/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/starfail enable
	echo "Starfail daemon installed. Enable and start with:"
	echo "  /etc/init.d/starfail enable"
	echo "  /etc/init.d/starfail start"
	echo ""
	echo "Configure via: /etc/config/starfail"
	echo "CLI usage: starfailctl help"
}
endef

define Package/starfail/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	/etc/init.d/starfail stop
	/etc/init.d/starfail disable
}
endef

$(eval $(call GoBinPackage,starfail))
$(eval $(call BuildPackage,starfail))
