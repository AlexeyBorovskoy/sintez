# Handoff: MFU (OpenWrt) Bridge Testing Kit

This folder is prepared for a third-party engineer who will test the solution on a real MFU (OpenWrt).

Goal:
- MFU runs a service that replaces the ASUDD-side "node" logic and bridges Spectr command stream to SINTEZ UTMC controller.

## What To Use In This Repo

1. C++ bridge sources:
- `spectr_utmc/spectr_utmc_cpp/`

Main binary built by CMake:
- `spectr_utmc_cpp` (bridge)
- `test_controller` (diagnostic CLI; optional on MFU)

2. OpenWrt package skeleton (`.ipk`):
- `openwrt/package/spectr-utmc-bridge/`
- `openwrt/README.md`

3. Where the ASUDD "node" logic lives (RoadCenter installation notes):
- `docs/ASUDD_NODE_DISCOVERY.md`

## OpenWrt Target (From MFU Dump)

- OpenWrt: 19.07.x
- Target: `ramips/mt7620`
- Arch: `mipsel_24kc`

## Build And Install (High Level)

1. Build `.ipk` in OpenWrt SDK (matching the MFU firmware target).
2. Install `.ipk` on MFU using `opkg`.
3. Edit config: `/etc/spectr-utmc/config.json`
4. Enable/start service:
```sh
/etc/init.d/spectr-utmc-bridge enable
/etc/init.d/spectr-utmc-bridge start
logread -f
```

## Configuration

Config file installed by package:
- `/etc/spectr-utmc/config.json`

Important keys:
- `its.host`, `its.port` (Spectr server on ASUDD side)
- `community` (UTMC SNMP community)
- `objects[].addr` (controller IP)
- `yf.*` (Yellow Flashing behavior)

## Notes On Yellow Flashing (SET_YF)

Observed reliable behavior for this controller:
1. `operationMode=3`
2. re-send `utcControlFF=1` until confirmed by `utcReplyFR != 0`
3. keep re-sending `utcControlFF=1` periodically while YF is active
4. stop the keepalive when another control command is issued (`SET_LOCAL`, `SET_OS`, `SET_PHASE`, `SET_START`)

## Smoke Tests (Suggested)

1. Connectivity:
- MFU can reach `its.host:its.port` (TCP)
- MFU can reach controller (SNMP UDP/161)

2. Protocol:
- Send `GET_STAT` and verify `>O.K.` response
- Send `SET_YF` and verify:
  - controller enters YF (visual) and `utcReplyFR` becomes non-zero
  - bridge keeps YF active
- Send `SET_LOCAL` (or `SET_OS`) and verify YF keepalive stops and controller returns to expected mode

