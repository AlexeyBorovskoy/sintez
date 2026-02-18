# ЖМ Scripted Test Report
- Report time: `2026-02-18T11:34:23.836893`
- Run dir: `spectr_utmc/controller_snapshot/experiments/2026-02-18_112947_yf_scripted_test`
- Capture base dir: `spectr_utmc/controller_snapshot/experiments/2026-02-18_112947_yf_scripted_test/extracted/tmp/dk_capture_20260218_112456`

## Конфигурация
```text
run_dir=/tmp/yf_scripted_test_20260218_112456
controller_ip=192.168.75.150
ssh_user=voicelink
community=UTMC
yf_enable_timeout_sec=120
yf_set_period_sec=2
yf_hold_sec=60
between_sec=120
```
## Спецификации и OID
- `operationMode`: `1.3.6.1.4.1.13267.3.2.4.1`
- `utcControlFF` (SetAF): `1.3.6.1.4.1.13267.3.2.4.2.1.20` (на этом ДК выглядит как write-only: GET может отвечать `No Such Object`, но SET работает)
- `utcControlLO`: `1.3.6.1.4.1.13267.3.2.4.2.1.11` (аналогично)
- `utcReplyFR`: `1.3.6.1.4.1.13267.3.2.5.1.1.36`
- `utcReplyGn`: `1.3.6.1.4.1.13267.3.2.5.1.1.3`

## Наблюдаемая логика (по тесту)
- Включение ЖМ требует перевода `operationMode=3`, после чего нужно (пере)посылать `utcControlFF=1` до подтверждения по `utcReplyFR`.
- Для удержания ЖМ (на этом ДК) применялось периодическое подтверждение `utcControlFF=1`.
- Возврат в штатную программу: `utcControlLO=0`, `utcControlFF=0`, `operationMode=1`.

## Сценарий
```text
[2026-02-18T11:24:56+03:00] START capture
started_remote_dir=/tmp/dk_capture_20260218_112456
total 72
-rw-r--r-- 1 voicelink voicelink 55957 Feb 18 11:44 baseline.txt
-rw-r--r-- 1 voicelink voicelink     6 Feb 18 11:44 pid_resident_follow
-rw-r--r-- 1 voicelink voicelink     6 Feb 18 11:44 pid_snmp_poll
-rw-r--r-- 1 voicelink voicelink     6 Feb 18 11:44 pid_spectr_utmc_follow
-rw-r--r-- 1 voicelink voicelink   141 Feb 18 11:44 resident_follow.log
-rw-r--r-- 1 voicelink voicelink     0 Feb 18 11:44 snmp_poll.log
-rw-r--r-- 1 voicelink voicelink     0 Feb 18 11:44 spectr_utmc_follow.log
started: local_dir=/tmp/yf_scripted_test_20260218_112456
remote_dir=/tmp/dk_capture_20260218_112456
[2026-02-18T11:24:57+03:00] Baseline: mode/fr/gn
mode=1
fr=0
gn="01 00 "
[2026-02-18T11:24:58+03:00] STEP 1: enable YF
[2026-02-18T11:25:01+03:00] fr=0
[2026-02-18T11:25:04+03:00] fr=0
[2026-02-18T11:25:08+03:00] fr=0
[2026-02-18T11:25:12+03:00] fr=0
[2026-02-18T11:25:16+03:00] fr=0
[2026-02-18T11:25:20+03:00] fr=1
[2026-02-18T11:25:20+03:00] CONFIRMED: utcReplyFR=1
[2026-02-18T11:25:20+03:00] STEP 1: hold YF 60s (keep asserting FF=1)
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
[2026-02-18T11:26:21+03:00] STEP 2: restore normal
mode=1 fr=0
[2026-02-18T11:26:23+03:00] STEP 3: wait 120s
[2026-02-18T11:28:23+03:00] STEP 4: enable YF again
[2026-02-18T11:28:26+03:00] fr=0
[2026-02-18T11:28:30+03:00] fr=0
[2026-02-18T11:28:34+03:00] fr=0
[2026-02-18T11:28:37+03:00] fr=0
[2026-02-18T11:28:41+03:00] fr=1
[2026-02-18T11:28:41+03:00] CONFIRMED: utcReplyFR=1
[2026-02-18T11:28:41+03:00] STEP 4: hold YF 60s (keep asserting FF=1)
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
ff_keep_1
[2026-02-18T11:29:43+03:00] STEP 5: restore normal
mode=1 fr=0
[2026-02-18T11:29:45+03:00] STOP capture + pull
stopped_remote_dir=/tmp/dk_capture_20260218_112456
tar: Removing leading `/' from member names
pulled: /tmp/yf_scripted_test_20260218_112456/capture.tgz
```
## Выполненные команды (фактические)
```text
[2026-02-18T11:24:57+03:00] ssh bash -lc: set -euo pipefail; echo mode=$(snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.1); echo fr=$(snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36); echo gn=$(snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.3)
[2026-02-18T11:24:58+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.1 i 3 >/dev/null; echo mode_set_3
[2026-02-18T11:24:59+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:25:00+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:25:03+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:25:04+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:25:06+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:25:07+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:25:10+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:25:11+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:25:14+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:25:15+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:25:18+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:25:19+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:25:20+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:23+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:26+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:29+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:32+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:34+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:37+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:40+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:43+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:46+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:49+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:52+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:55+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:25:58+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:01+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:04+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:07+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:10+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:13+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:15+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:18+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:26:21+03:00] ssh bash -lc: set -euo pipefail
snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1   1.3.6.1.4.1.13267.3.2.4.2.1.11 i 0   1.3.6.1.4.1.13267.3.2.4.2.1.20 i 0   1.3.6.1.4.1.13267.3.2.4.1 i 1 >/dev/null
sleep 1
echo mode=$(snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.1 2>/dev/null || echo '?')      fr=$(snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?')
[2026-02-18T11:28:23+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.1 i 3 >/dev/null; echo mode_set_3
[2026-02-18T11:28:24+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:28:25+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:28:28+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:28:29+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:28:32+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:28:33+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:28:36+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:28:36+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:28:39+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_set_1
[2026-02-18T11:28:40+03:00] ssh bash -lc: set -euo pipefail; snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?'
[2026-02-18T11:28:41+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:28:44+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:28:47+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:28:50+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:28:53+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:28:56+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:28:59+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:02+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:05+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:08+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:11+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:13+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:16+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:19+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:22+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:25+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:28+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:31+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:34+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:37+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:40+03:00] ssh bash -lc: set -euo pipefail; snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.2.1.20 i 1 >/dev/null; echo ff_keep_1
[2026-02-18T11:29:43+03:00] ssh bash -lc: set -euo pipefail
snmpset -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1   1.3.6.1.4.1.13267.3.2.4.2.1.11 i 0   1.3.6.1.4.1.13267.3.2.4.2.1.20 i 0   1.3.6.1.4.1.13267.3.2.4.1 i 1 >/dev/null
sleep 1
echo mode=$(snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.4.1 2>/dev/null || echo '?')      fr=$(snmpget -v1 -c "$COMM" -t 2 -r 1 -Oqv 127.0.0.1 1.3.6.1.4.1.13267.3.2.5.1.1.36 2>/dev/null || echo '?')
```
## Результат (подтверждение ЖМ)
- Подтверждения по сценарию (локальное время запуска):
  - `2026-02-18T11:25:20+03:00` -> `utcReplyFR=1`
  - `2026-02-18T11:28:41+03:00` -> `utcReplyFR=1`
- Окно `fr=1` по `snmp_poll.log` (время контроллера):
  - first: `2026-02-18T11:44:57+03:00`
  - last : `2026-02-18T11:49:03+03:00`
  - duration_s: `246.0`
- Примечание: таймстампы `snmp_poll.log`/`resident_follow.log` идут по часам контроллера и могут отличаться от локального времени запуска сценария.

## Ключевые строки логов

### spectr_utmc_follow.log: #SET_YF
```text
not found
```

### spectr_utmc_follow.log: >O.K.
```text
not found
```

### resident_follow.log: Remote mode
```text
18-02-2026 11:44:50;;0x101a;;Remote mode is launched using the {0} protocol.;;UTMC
18-02-2026 11:44:50;;0x101a;;Remote mode is launched using the {0} protocol.;;UTMC
18-02-2026 11:48:12;;0x101a;;Remote mode is launched using the {0} protocol.;;UTMC
18-02-2026 11:48:12;;0x101a;;Remote mode is launched using the {0} protocol.;;UTMC
```

### resident_follow.log: Flashing yellow
```text
18-02-2026 11:44:56;;0x101f;;Flashing yellow.;;
18-02-2026 11:44:56;;0x101f;;Flashing yellow.;;
18-02-2026 11:48:18;;0x101f;;Flashing yellow.;;
18-02-2026 11:48:18;;0x101f;;Flashing yellow.;;
```
