#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path
from typing import Iterable


def read_text(p: Path) -> str:
    return p.read_text(errors="replace") if p.exists() else ""


def find_fr1_window(snmp_poll: Path) -> tuple[str | None, str | None, float | None]:
    first = None
    last = None
    for ln in read_text(snmp_poll).splitlines():
        if " fr=1 " not in ln:
            continue
        ts = ln.split(" ", 1)[0]
        try:
            t = dt.datetime.fromisoformat(ts)
        except Exception:
            continue
        if first is None:
            first = t
        last = t
    if first and last:
        return first.isoformat(), last.isoformat(), (last - first).total_seconds()
    return None, None, None


def tail_matches(lines: Iterable[str], needle: str, limit: int) -> list[str]:
    out: list[str] = []
    for ln in lines:
        if needle in ln:
            out.append(ln)
    return out[-limit:]


def parse_scenario_confirmations(scenario_text: str) -> list[tuple[str, str]]:
    """
    Extract CONFIRMED lines emitted by tools/yf_scripted_test.sh.
    Example:
      [2026-02-18T11:25:20+03:00] CONFIRMED: utcReplyFR=1
    Returns list of (timestamp, fr_value).
    """
    out: list[tuple[str, str]] = []
    for ln in scenario_text.splitlines():
        if "CONFIRMED: utcReplyFR=" not in ln:
            continue
        ts = ""
        if ln.startswith("[") and "]" in ln:
            ts = ln[1 : ln.index("]")]
        fr = ln.split("CONFIRMED: utcReplyFR=", 1)[1].strip()
        out.append((ts or "unknown_ts", fr))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--base-dir", required=False, default="")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    base_dir = Path(args.base_dir) if args.base_dir else None
    out = Path(args.out)

    meta_local = read_text(run_dir / "meta_local.txt")
    scenario = read_text(run_dir / "scenario.log")
    commands = read_text(run_dir / "commands.log")

    snmp_poll = base_dir / "snmp_poll.log" if base_dir else Path()
    utmc_follow = base_dir / "spectr_utmc_follow.log" if base_dir else Path()
    resident_follow = base_dir / "resident_follow.log" if base_dir else Path()

    fr1_first, fr1_last, fr1_dur = find_fr1_window(snmp_poll) if base_dir else (None, None, None)
    scenario_confirms = parse_scenario_confirmations(scenario)

    utmc_lines = read_text(utmc_follow).splitlines() if base_dir else []
    resident_lines = read_text(resident_follow).splitlines() if base_dir else []

    set_yf_lines = tail_matches(utmc_lines, "#SET_YF", 20)
    ok_lines = tail_matches(utmc_lines, ">O.K.", 20)
    remote_mode_lines = tail_matches(resident_lines, "Remote mode is launched", 10)
    flashing_lines = tail_matches(resident_lines, "Flashing yellow", 10)

    out.parent.mkdir(parents=True, exist_ok=True)

    md = []
    md.append("# ЖМ Scripted Test Report\n")
    md.append(f"- Report time: `{dt.datetime.now().isoformat()}`\n")
    md.append(f"- Run dir: `{run_dir}`\n")
    if base_dir:
        md.append(f"- Capture base dir: `{base_dir}`\n")
    md.append("\n## Конфигурация\n")
    md.append("```text\n")
    md.append(meta_local.strip() + "\n")
    md.append("```\n")

    md.append("## Спецификации и OID\n")
    md.append("- `operationMode`: `1.3.6.1.4.1.13267.3.2.4.1`\n")
    md.append("- `utcControlFF` (SetAF): `1.3.6.1.4.1.13267.3.2.4.2.1.20` (на этом ДК выглядит как write-only: GET может отвечать `No Such Object`, но SET работает)\n")
    md.append("- `utcControlLO`: `1.3.6.1.4.1.13267.3.2.4.2.1.11` (аналогично)\n")
    md.append("- `utcReplyFR`: `1.3.6.1.4.1.13267.3.2.5.1.1.36`\n")
    md.append("- `utcReplyGn`: `1.3.6.1.4.1.13267.3.2.5.1.1.3`\n")

    md.append("\n## Наблюдаемая логика (по тесту)\n")
    md.append("- Включение ЖМ требует перевода `operationMode=3`, после чего нужно (пере)посылать `utcControlFF=1` до подтверждения по `utcReplyFR`.\n")
    md.append("- Для удержания ЖМ (на этом ДК) применялось периодическое подтверждение `utcControlFF=1`.\n")
    md.append("- Возврат в штатную программу: `utcControlLO=0`, `utcControlFF=0`, `operationMode=1`.\n")

    md.append("\n## Сценарий\n")
    md.append("```text\n")
    md.append(scenario.strip() + "\n")
    md.append("```\n")

    md.append("## Выполненные команды (фактические)\n")
    md.append("```text\n")
    md.append(commands.strip() + "\n")
    md.append("```\n")

    md.append("## Результат (подтверждение ЖМ)\n")
    if scenario_confirms:
        md.append("- Подтверждения по сценарию (локальное время запуска):\n")
        for ts, fr in scenario_confirms:
            md.append(f"  - `{ts}` -> `utcReplyFR={fr}`\n")
    else:
        md.append("- Подтверждения по сценарию: `not found`\n")

    md.append("- Окно `fr=1` по `snmp_poll.log` (время контроллера):\n")
    md.append(f"  - first: `{fr1_first or 'n/a'}`\n")
    md.append(f"  - last : `{fr1_last or 'n/a'}`\n")
    md.append(f"  - duration_s: `{fr1_dur if fr1_dur is not None else 'n/a'}`\n")
    md.append("- Примечание: таймстампы `snmp_poll.log`/`resident_follow.log` идут по часам контроллера и могут отличаться от локального времени запуска сценария.\n")

    md.append("\n## Ключевые строки логов\n")
    md.append("\n### spectr_utmc_follow.log: #SET_YF\n")
    md.append("```text\n" + ("\n".join(set_yf_lines) if set_yf_lines else "not found") + "\n```\n")
    md.append("\n### spectr_utmc_follow.log: >O.K.\n")
    md.append("```text\n" + ("\n".join(ok_lines) if ok_lines else "not found") + "\n```\n")
    md.append("\n### resident_follow.log: Remote mode\n")
    md.append("```text\n" + ("\n".join(remote_mode_lines) if remote_mode_lines else "not found") + "\n```\n")
    md.append("\n### resident_follow.log: Flashing yellow\n")
    md.append("```text\n" + ("\n".join(flashing_lines) if flashing_lines else "not found") + "\n```\n")

    out.write_text("".join(md), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
