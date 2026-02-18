include $(TOPDIR)/rules.mk

PKG_NAME:=spectr-utmc-bridge
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

# Source: this repo. You can switch URL to your internal GitLab mirror if needed.
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/AlexeyBorovskoy/sintez.git
# Pin to a commit for reproducible builds. Update when needed.
PKG_SOURCE_VERSION:=fd13a2b

PKG_MAINTAINER:=Alexey Borovskoy
PKG_LICENSE:=MIT

# Build only the C++ bridge subdirectory from the repo.
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)/spectr_utmc/spectr_utmc_cpp

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
