# C++ Code Review Notes (For External Engineer)

Scope reviewed:
- `spectr_utmc/spectr_utmc_cpp/src/*.cpp`
- `spectr_utmc/spectr_utmc_cpp/include/*.h`

## Key Findings And Fixes Applied

1. `TcpClient` data race on `sendQueue_`
- Previous code checked `sendQueue_.empty()` without holding `sendMutex_`.
- Fixed by taking the mutex before checking emptiness (prevents UB under C++ memory model).

2. `ConfigLoader::load` did not reset output object
- If `ConfigLoader::load()` is called multiple times on the same `Config` instance, old values could accumulate.
- Fixed by resetting `config` at function start and clearing `objects`.
- Removed duplicated `No objects configured` check.

3. `object_manager.h` header self-sufficiency
- Header used `std::thread` but did not include `<thread>`.
- Fixed by adding the include.

4. `main.cpp` unused variable
- Removed unused `targetId` variable.

## Behavioral Notes

- The bridge currently acts as a Spectr stream client (connects out to `its.host:its.port`).
- Yellow Flashing (`SET_YF`) is implemented with keepalive logic:
  - reasserts `utcControlFF=1` periodically while active
  - tries to confirm by `utcReplyFR` within `yf.confirmTimeoutSec`
  - keepalive is stopped when other control commands are issued (`SET_LOCAL`, `SET_OS`, `SET_PHASE`, `SET_START`)

## Known Gaps / Follow-Ups

- OpenWrt packaging is a skeleton: you must build in the correct SDK and validate `libnetsnmp` package naming for OpenWrt 19.07 feeds.
- `ConfigLoader` is a minimal JSON parser; for production, consider switching to a real JSON library or UCI-based config.

