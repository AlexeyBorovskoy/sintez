# Поиск “ноды” в установленной АСУДД (RoadCenter / Spectr)

Заметка фиксирует, где в установленной на этой рабочей станции АСУДД находится логика “ноды” (скрипты Spectr), и какие команды/протокол она использует.

## Точка входа

- Запуск GUI АСУДД: `/usr/bin/roadcenter` (Debian-пакет `roadcenter-core`)
- Desktop launcher: `/usr/share/applications/roadcenter.desktop`

## Скрипты плагина Spectr (UI / keepalive)

Плагин Spectr установлен Debian-пакетом `roadcenter-plugin-spectr` и содержит Python-скрипты:

- `/usr/share/roadcenter/scripts/spectr/submenu.py`
  - выставляет в UI команды контроллера, включая `SET_YF` (ЖМ), `SET_OS`, `SET_LOCAL`, `SET_PHASE`, `GET_STAT` и т.д.
- `/usr/share/roadcenter/scripts/spectr/keepalive.py`
  - реализует периодическую переотправку (keepalive) отдельных управляющих команд.

Наблюдаемое поведение keepalive (по `keepalive.py`):

- Отслеживаемые команды: `SET_PROG`, `SET_PHASE`, `SET_YF`, `SET_OS`
- После успешного ответа команда сохраняется в таблице по объекту и может быть переотправлена позднее.
- Таймаут (задержка перед переотправкой): `60s`
- Период проверки: `10s` (по умолчанию)
- Условия переотправки для `SET_YF`:
  - `obj.controlSource == 3` (источник управления = АСУДД)
  - `(obj.controlAlgorithm == 0 or 255) and obj.keyRegime == 2`

## Набор команд протокола (Spectr)

Словарь команд, используемых АСУДД, присутствует в вспомогательной библиотеке:

- `/lib/x86_64-linux-gnu/libqt5qspectrhlp.so.1`

Частичный список команд, извлеченный из строк библиотеки:

- SET: `SET_LOCAL`, `SET_PHASE`, `SET_PROG`, `SET_GROUP`, `SET_YF`, `SET_OS`, `SET_START`,
  `SET_DATE`, `SET_TIME`, `SET_CONFIG`, `SET_VERB`, `SET_EVENT`, `SET_TOUT`, `SET_DPROG`,
  `SET_DDMAP`, `SET_DSDY`, `SET_TDTIME`, `SET_VPU`, `SET_EVTCFG`, `SET_QUERY`, `SET_PASSKY`,
  `SET_STRAT`, `SET_ASTATE`, `SET_APSTATE`, `SET_DEFAULT`, `SET_ADEFAULT`
- GET: `GET_STAT`, `GET_REFER`, `GET_GROUP`, `GET_SENS`, `GET_SWITCH`, `GET_TDET`, `GET_DATE`,
  `GET_JRNL`, `GET_CONFIG`, `GET_TWP`, `GET_DEVICE`, `GET_CLIST`, `GET_VPU`, `GET_QUERY`,
  `GET_PASSDB`, `GET_PASSKY`, `GET_POWER`, `GET_STATE`, `GET_DPROG`, `GET_CONFIG_HASH`, `GET_CONFIG_SIZE`

Ответы включают: `>O.K.`, `>OFF_LINE`, `>BAD_CHECK`, `>UNINDENT`, `>BROKEN`, `>TOO_LONG`, `>BAD_DATA`, `>BAD_PARAM`, `>NOT_EXEC <code>`.

## Влияние на МФУ-мост

Чтобы заменить JS-ноду на стороне АСУДД на C++ сервис на МФУ, сервис на МФУ должен:

1. Говорить тем же словарем команд Spectr и отвечать теми же кодами ошибок.
2. Реализовать рабочее подмножество команд (минимум: `GET_STAT`, `GET_REFER`, `SET_PHASE`, `SET_YF`, `SET_OS`, `SET_LOCAL`, `SET_START`, `SET_EVENT`).
3. Для остальных команд отвечать детерминированно как “команда известна, но не поддерживается” (`>NOT_EXEC 4`), а не `>UNINDENT`.
4. Обеспечить надежность ЖМ:
   - подтверждение включения по `utcReplyFR`,
   - периодическая переотправка `utcControlFF=1` во время активного ЖМ,
   - останов переотправки при приходе другой управляющей команды (например `SET_LOCAL`, `SET_OS`, `SET_PHASE`).
