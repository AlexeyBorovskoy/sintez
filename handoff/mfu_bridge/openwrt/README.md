# OpenWrt пакет: `spectr-utmc-bridge`

Целевая платформа МФУ (по дампу):
- OpenWrt 19.07.x
- `ramips/mt7620`
- `mipsel_24kc`

## Что это

OpenWrt пакет `.ipk`, который собирает и устанавливает C++ мост Spectr-ITS <-> UTMC:

- бинарник: `/usr/sbin/spectr-utmc-bridge`
- конфиг: `/etc/spectr-utmc/config.json`
- init (procd): `/etc/init.d/spectr-utmc-bridge`

Этот handoff-комплект **можно собирать без интернета**: в пакете лежит локальный tarball с исходниками:
- `openwrt/package/spectr-utmc-bridge/src/`

## Сборка (OpenWrt SDK)

1. Скачайте OpenWrt SDK, соответствующий прошивке МФУ (`19.07.x`, `ramips/mt7620`, `mipsel_24kc`).
2. В корне комплекта выполните:

```sh
OPENWRT_SDK=/path/to/openwrt-sdk-19.07.*-ramips-mt7620_* \
  ./BUILD_IPK_WITH_SDK.sh
```

Готовый `.ipk` появится в `SDK/bin/packages/mipsel_24kc/.../`.

## Установка (на МФУ)

```sh
opkg install /tmp/spectr-utmc-bridge_*.ipk
/etc/init.d/spectr-utmc-bridge enable
/etc/init.d/spectr-utmc-bridge start
logread -f
```

## Настройка

Правка конфига:
- `/etc/spectr-utmc/config.json`

Перезапуск:
- `/etc/init.d/spectr-utmc-bridge restart`
