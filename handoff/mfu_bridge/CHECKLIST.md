# MFU Test Checklist

## Preflight

- MFU firmware matches OpenWrt target used for build (19.07.x, `ramips/mt7620`, `mipsel_24kc`)
- Network routes:
  - MFU -> ASUDD Spectr server reachable (`its.host:its.port`)
  - MFU -> Controller reachable (SNMP UDP/161)
- Timeouts and retries understood (SNMP might be lossy on some networks)

## Install

- `opkg install /tmp/spectr-utmc-bridge_*.ipk`
- Config exists: `/etc/spectr-utmc/config.json`
- Service enabled/started:
  - `/etc/init.d/spectr-utmc-bridge enable`
  - `/etc/init.d/spectr-utmc-bridge start`
- Observe logs: `logread -f`

## Functional Tests

- `GET_STAT` returns `>O.K.` (and the STAT payload is consistent)
- `GET_REFER` returns `>O.K.`
- `SET_PHASE <n>` returns `>O.K.` and controller changes phase
- `SET_YF` returns `>O.K.`, and:
  - controller enters Yellow Flashing
  - `utcReplyFR` becomes non-zero
  - YF stays active due to keepalive
- Stop YF by sending another mode-changing command:
  - `SET_LOCAL` (preferred) or `SET_OS`
  - verify keepalive stops and controller state changes accordingly

## Stability

- Restart service:
  - `/etc/init.d/spectr-utmc-bridge restart`
  - verify reconnect to ITS server and continued operation
- Network interruptions:
  - disconnect/reconnect ITS network
  - verify auto reconnect works (no crash, no CPU spin)

