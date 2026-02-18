# Sintez MFU Bridge (Spectr-ITS <-> SINTEZ UTMC)

Репозиторий с кодом и артефактами, чтобы поставить **МФУ (OpenWrt) между АСУДД "СПЕКТР" и контроллером "Синтез"**.

Задача: логика, которая в текущем контуре реализована "нодой" на стороне АСУДД (команды Spectr), должна выполняться на МФУ в виде сервиса/пакета `.ipk`.

ЖМ (жёлтое мигание) здесь не самоцель, а один из режимов управления, который должен работать надежно и предсказуемо.

## Цели

1. Реализовать на МФУ C++ сервис, который говорит в сторону АСУДД протоколом Spectr (команды `SET_*`/`GET_*`, ответы `>O.K.`, `>NOT_EXEC`, и т.п.).
2. Транслировать команды в управление контроллером Синтез через UTMC/SNMP, включая устойчивую логику ЖМ:
   - подтверждение по `utcReplyFR`,
   - удержание `utcControlFF=1`,
   - корректный выход из ЖМ при смене режима/команде.
3. Упаковать в `.ipk` для OpenWrt и обеспечить:
   - конфиг в `/etc/...`,
   - автозапуск через `procd`,
   - логирование в `logread`,
   - минимальные конфликты с другими пакетами/сетевыми настройками на МФУ.

## Что уже сделано

1. C++ bridge (Spectr stream client + SNMP):
   - код: `spectr_utmc/spectr_utmc_cpp/`
   - бинарник: `spectr_utmc/spectr_utmc_cpp/build/spectr_utmc_cpp`
2. C++ тестовая утилита (в т.ч. сценарий ЖМ по SSH+локальному SNMP на контроллере):
   - `spectr_utmc/spectr_utmc_cpp/build/test_controller`
   - команда `ssh_yf_for` (ЖМ на N секунд -> возврат в штатный режим)
3. Сценарные тесты/снятие логов (bash+python):
   - `tools/dk_capture.sh`, `tools/yf_scripted_test.sh`, `tools/yf_make_report.py`
   - результаты: `spectr_utmc/controller_snapshot/experiments/...`
4. Зафиксировано, где логика управления живет в установленной АСУДД (RoadCenter):
   - `docs/ASUDD_NODE_DISCOVERY.md`
5. Добавлена заготовка OpenWrt-пакета:
   - `openwrt/package/spectr-utmc-bridge/`
   - `openwrt/README.md`

## Наблюдаемая логика ЖМ (по тестам)

На данном контроллере ЖМ стабильно включается/держится по схеме:

1. `operationMode=3` (UTC Control)
2. (пере)посылать `utcControlFF=1` до подтверждения `utcReplyFR != 0`
3. при активном ЖМ периодически повторять `utcControlFF=1`
4. возврат в штатный режим: `utcControlLO=0`, `utcControlFF=0`, `operationMode=1`

OID (ключевые):
- `operationMode`: `1.3.6.1.4.1.13267.3.2.4.1`
- `utcControlFF`: `1.3.6.1.4.1.13267.3.2.4.2.1.20`
- `utcControlLO`: `1.3.6.1.4.1.13267.3.2.4.2.1.11`
- `utcReplyFR`: `1.3.6.1.4.1.13267.3.2.5.1.1.36`

## Быстрый старт (Linux, локально)

Сборка:
```bash
cd spectr_utmc/spectr_utmc_cpp
cmake -S . -B build
cmake --build build -j
```

Тест ЖМ на 30 секунд средствами C++ (SSH на контроллер):
```bash
spectr_utmc/spectr_utmc_cpp/build/test_controller \
  ssh_yf_for 192.168.75.150 UTMC 30 voicelink 120 2 /tmp/dk_pass
```

## Конфигурация bridge

Пример: `spectr_utmc/spectr_utmc_cpp/config.json`

Добавлены параметры ЖМ:
- `yf.confirmTimeoutSec`
- `yf.keepPeriodMs`
- `yf.maxHoldSec` (0 = держать до другой команды)

## OpenWrt / .ipk

Заготовка пакета: `openwrt/package/spectr-utmc-bridge/` (init + config + Makefile).

Инструкция сборки/установки: `openwrt/README.md`.

## Структура репозитория

- `spectr_utmc/spectr_utmc_cpp/` C++ bridge + утилиты тестирования SNMP
- `tools/` сценарные тесты и сбор логов
- `spectr_utmc/controller_snapshot/` снимки и эксперименты
- `docs/` заметки по обнаружению логики в АСУДД
- `openwrt/` заготовка `.ipk` для МФУ
  - дампы/снимки состояния контроллера и результаты экспериментов.

## План работ (задачи)

1. MFU/OpenWrt:
   - кросс-сборка `spectr_utmc_cpp` под OpenWrt (toolchain/SDK),
   - упаковка в пакет (opkg) или единый бинарник,
   - автозапуск через `procd`, логирование в `logread`.
2. Прокси вместо JS-ноды:
   - поднять на МФУ сервис (TCP/HTTP) для приема команд АСУДД,
   - реализовать мэппинг команд АСУДД -> действия контроллера,
   - обеспечить подтверждение результата (по `utcReplyFR` и др.) и таймауты.
3. Надежность:
   - ретраи, reconnection, rate limit,
   - watchdog/healthcheck,
   - аккуратное поведение при `Ctrl+C`/сигналах (обязательный возврат в штатный режим при прерывании).
4. Безопасность:
   - убрать пароли/секреты из репозитория, хранить в конфиге/секрет-хранилище,
   - ротация тестовых учетных данных при публикации наружу.
