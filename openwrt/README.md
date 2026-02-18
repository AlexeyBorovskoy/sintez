# OpenWrt Package: spectr-utmc-bridge

Target MFU from dump:
- OpenWrt 19.07.x
- `ramips/mt7620`
- `mipsel_24kc`

## What This Is

An OpenWrt `.ipk` package definition that builds and installs the C++ Spectr-to-UTMC bridge:

- binary: `/usr/sbin/spectr-utmc-bridge`
- config: `/etc/spectr-utmc/config.json`
- init (procd): `/etc/init.d/spectr-utmc-bridge`

## Build (SDK)

1. Download the OpenWrt SDK matching your MFU firmware (`19.07.x`, `ramips/mt7620`, `mipsel_24kc`).
2. Put this package into the SDK tree:
   - copy `openwrt/package/spectr-utmc-bridge` into `SDK/package/spectr-utmc-bridge`
3. In SDK, enable required feeds/packages (netsnmp runtime):
   - package depends on `libnetsnmp` and `libstdcpp`.
4. Build:

```sh
make package/spectr-utmc-bridge/compile V=s
```

Result `.ipk` will appear under `bin/packages/mipsel_24kc/.../`.

## Install (MFU)

```sh
opkg install /tmp/spectr-utmc-bridge_*.ipk
/etc/init.d/spectr-utmc-bridge enable
/etc/init.d/spectr-utmc-bridge start
logread -f
```

## Configure

Edit:
- `/etc/spectr-utmc/config.json`

Restart:
- `/etc/init.d/spectr-utmc-bridge restart`

