include $(TOPDIR)/rules.mk

LUCI_TITLE:=Starfail Multi-Interface Failover
LUCI_DEPENDS:=+starfaild +luci-compat
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-starfail
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Starfail Team <starfail@example.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
