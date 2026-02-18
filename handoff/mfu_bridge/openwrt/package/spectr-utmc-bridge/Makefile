include $(TOPDIR)/rules.mk

PKG_NAME:=spectr-utmc-bridge
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

# Сборка без интернета: исходники поставляются внутри handoff-комплекта.
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=file://$(CURDIR)/src
PKG_HASH:=722cb3d350cd6610b56a8b8e74a0d3bef8d179b8d943ecc262ac0f581af071c2

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/spectr-utmc-bridge
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Spectr protocol bridge for SINTEZ UTMC
  DEPENDS:=+libstdcpp +libnetsnmp
endef

define Package/spectr-utmc-bridge/description
  MFU service (OpenWrt) that bridges Spectr command stream (ASUDD side) to SINTEZ UTMC controller via SNMP.
endef

define Package/spectr-utmc-bridge/conffiles
/etc/spectr-utmc/config.json
endef

define Package/spectr-utmc-bridge/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(CMAKE_BINARY_DIR)/spectr_utmc_cpp $(1)/usr/sbin/spectr-utmc-bridge

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/spectr-utmc-bridge $(1)/etc/init.d/spectr-utmc-bridge

	$(INSTALL_DIR) $(1)/etc/spectr-utmc
	$(INSTALL_CONF) ./files/etc/spectr-utmc/config.json $(1)/etc/spectr-utmc/config.json
endef

$(eval $(call BuildPackage,spectr-utmc-bridge))
