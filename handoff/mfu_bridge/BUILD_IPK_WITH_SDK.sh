#!/bin/sh
set -eu

# Сборка .ipk пакета `spectr-utmc-bridge` через OpenWrt SDK.
# Использование:
#   OPENWRT_SDK=/path/to/openwrt-sdk-19.07.*-ramips-mt7620_* \
#     ./BUILD_IPK_WITH_SDK.sh

: "${OPENWRT_SDK:?Нужно задать OPENWRT_SDK (путь к каталогу OpenWrt SDK)}"

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PKG_SRC="$DIR/openwrt/package/spectr-utmc-bridge"
PKG_DST="$OPENWRT_SDK/package/spectr-utmc-bridge"

if [ ! -d "$OPENWRT_SDK" ]; then
  echo "OPENWRT_SDK не найден: $OPENWRT_SDK" >&2
  exit 2
fi

mkdir -p "$OPENWRT_SDK/package"
rm -rf "$PKG_DST"
cp -a "$PKG_SRC" "$PKG_DST"

# Сборка
( cd "$OPENWRT_SDK" && make package/spectr-utmc-bridge/compile V=s )

printf "\nСборка завершена. Ищите .ipk в:\n"
find "$OPENWRT_SDK/bin/packages" -name 'spectr-utmc-bridge_*.ipk' -print 2>/dev/null || true
