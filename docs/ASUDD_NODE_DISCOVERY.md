# ASUDD Node Discovery (RoadCenter / Spectr)

This note records where the "node" logic lives in the installed ASUDD on this workstation and what protocol/commands it uses.

## Entry Point

- ASUDD GUI starts from: `/usr/bin/roadcenter` (Debian package `roadcenter-core`)
- Desktop launcher: `/usr/share/applications/roadcenter.desktop`

## Spectr Plugin Scripts (UI/Keepalive)

The Spectr plugin is installed via Debian package `roadcenter-plugin-spectr` and includes Python scripts:

- `/usr/share/roadcenter/scripts/spectr/submenu.py`
  - exposes controller commands in UI, including `SET_YF` (ЖМ), `SET_OS`, `SET_LOCAL`, `SET_PHASE`, `GET_STAT`, etc.
- `/usr/share/roadcenter/scripts/spectr/keepalive.py`
  - implements periodic re-send (keepalive) for selected control commands.

Keepalive behavior (from `keepalive.py`):

- Tracks commands: `SET_PROG`, `SET_PHASE`, `SET_YF`, `SET_OS`
- After a successful command response it keeps the command in a table per object and may re-send it later.
- Timeout (re-send delay): `60s`
- Check period: `10s` (default)
- Re-send conditions for `SET_YF`:
  - `obj.controlSource == 3` (АСУДД is control source)
  - `(obj.controlAlgorithm == 0 or 255) and obj.keyRegime == 2`

## Protocol Command Set (Spectr protocol)

The command vocabulary used by ASUDD is present in the helper library:

- `/lib/x86_64-linux-gnu/libqt5qspectrhlp.so.1`

Command list discovered from library strings (partial):

- SET: `SET_LOCAL`, `SET_PHASE`, `SET_PROG`, `SET_GROUP`, `SET_YF`, `SET_OS`, `SET_START`,
  `SET_DATE`, `SET_TIME`, `SET_CONFIG`, `SET_VERB`, `SET_EVENT`, `SET_TOUT`, `SET_DPROG`,
  `SET_DDMAP`, `SET_DSDY`, `SET_TDTIME`, `SET_VPU`, `SET_EVTCFG`, `SET_QUERY`, `SET_PASSKY`,
  `SET_STRAT`, `SET_ASTATE`, `SET_APSTATE`, `SET_DEFAULT`, `SET_ADEFAULT`
- GET: `GET_STAT`, `GET_REFER`, `GET_GROUP`, `GET_SENS`, `GET_SWITCH`, `GET_TDET`, `GET_DATE`,
  `GET_JRNL`, `GET_CONFIG`, `GET_TWP`, `GET_DEVICE`, `GET_CLIST`, `GET_VPU`, `GET_QUERY`,
  `GET_PASSDB`, `GET_PASSKY`, `GET_POWER`, `GET_STATE`, `GET_DPROG`, `GET_CONFIG_HASH`, `GET_CONFIG_SIZE`

Responses include: `>O.K.`, `>OFF_LINE`, `>BAD_CHECK`, `>UNINDENT`, `>BROKEN`, `>TOO_LONG`, `>BAD_DATA`, `>BAD_PARAM`, `>NOT_EXEC <code>`.

## Impact On MFU Bridge

To replace the JS-node on the ASUDD side with a C++ bridge on the MFU, the MFU service must:

1. Speak the same Spectr command vocabulary and reply with the same error codes.
2. Implement the subset used in production (at minimum: `GET_STAT`, `GET_REFER`, `SET_PHASE`, `SET_YF`, `SET_OS`, `SET_LOCAL`, `SET_START`, `SET_EVENT`).
3. For the remaining commands, reply deterministically as "known but unsupported" (`>NOT_EXEC 4`) instead of `>UNINDENT`.
4. Keep Yellow Flashing reliable:
   - confirm by `utcReplyFR`
   - reassert `utcControlFF=1` periodically while ЖМ is active
   - stop reassert when a different control command is issued (e.g. `SET_LOCAL`, `SET_OS`, `SET_PHASE`).

