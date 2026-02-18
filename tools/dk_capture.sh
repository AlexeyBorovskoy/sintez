#!/usr/bin/env bash
set -euo pipefail

# Read-only capture helper for SINTEZ UTMC controller troubleshooting.
# It only reads logs/status and starts/stops read-only background tailers.

DK_IP="${DK_IP:-192.168.75.150}"
DK_USER="${DK_USER:-voicelink}"
DK_PASS="${DK_PASS:-}"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o IdentitiesOnly=yes
  -o PreferredAuthentications=password
  -o PubkeyAuthentication=no
  -o ConnectTimeout=5
)

die() { echo "error: $*" >&2; exit 1; }

need_pass() {
  [[ -n "${DK_PASS}" ]] || die "DK_PASS is required (export DK_PASS=... before running)"
}

sshc() {
  need_pass
  # Note: sshpass -p exposes password in process list briefly. Keep calls short.
  sshpass -p "${DK_PASS}" ssh "${SSH_OPTS[@]}" "${DK_USER}@${DK_IP}" "$@"
}

now_ts() { date +%Y%m%d_%H%M%S; }

cmd="${1:-}"
shift || true

case "${cmd}" in
  start)
    local_dir="${1:-/tmp/dk_capture_$(now_ts)}"
    mkdir -p "${local_dir}"

    ts="$(now_ts)"
    remote_dir="/tmp/dk_capture_${ts}"

    cat >"${local_dir}/meta.txt" <<EOF
local_time_start=$(date -Iseconds)
dk_ip=${DK_IP}
dk_user=${DK_USER}
remote_dir=${remote_dir}
EOF

    sshc "set -e
      d='${remote_dir}'
      mkdir -p \"\$d\"
      echo \"\$d\" > /tmp/dk_capture_current

      {
        echo \"controller_time_start=\$(date -Iseconds)\"
        echo \"uptime=\$(uptime -p 2>/dev/null || uptime)\"
        echo
        echo \"### ss -lun\"
        ss -lun || true
        echo
        echo \"### snmp sysUpTime (community UTMC)\"
        snmpget -v1 -c UTMC -t 1 -r 0 -Oqv ${DK_IP} 1.3.6.1.2.1.1.3.0 2>&1 || true
        echo
        echo \"### resident config (head)\"
        ls -l /home/voicelink/rtc/resident/config 2>/dev/null || true
        sed -n '1,200p' /home/voicelink/rtc/resident/config 2>/dev/null || true
        echo
        echo \"### spectr_utmc recent (last 15 min)\"
        journalctl -u spectr_utmc --since \"15 min ago\" --no-pager -o short-iso 2>&1 || true
        echo
        echo \"### resident full.log tail\"
        tail -n 400 /home/voicelink/rtc/resident/full.log 2>/dev/null || true
      } >\"\$d/baseline.txt\" 2>&1

      # Live follow: UTMC bridge service + resident logs.
      nohup sh -c 'journalctl -fu spectr_utmc -o short-iso' >\"\$d/spectr_utmc_follow.log\" 2>&1 & echo \$! >\"\$d/pid_spectr_utmc_follow\"
      nohup sh -c 'tail -n0 -F /home/voicelink/rtc/resident/full.log /home/voicelink/rtc/resident/info.log /home/voicelink/rtc/resident/error.log 2>/dev/null' >\"\$d/resident_follow.log\" 2>&1 & echo \$! >\"\$d/pid_resident_follow\"

      # SNMP poll (read-only). We poll the few OIDs that are stable in this setup.
      nohup bash -lc '
        getv() { snmpget -v1 -c UTMC -t 1 -r 0 -Oqv ${DK_IP} \"\$1\" 2>/dev/null || echo \"?\"; }
        while :; do
          ts=\$(date -Iseconds)
          sys=\$(getv 1.3.6.1.2.1.1.3.0)
          mode=\$(getv 1.3.6.1.4.1.13267.3.2.4.1)
          fr=\$(getv 1.3.6.1.4.1.13267.3.2.5.1.1.36)
          gn=\$(getv 1.3.6.1.4.1.13267.3.2.5.1.1.3)
          # timing / cycle-related OIDs
          stageLen=\$(getv 1.3.6.1.4.1.13267.3.2.5.1.1.4)
          stageCounter=\$(getv 1.3.6.1.4.1.13267.3.2.5.1.1.5)
          transition=\$(getv 1.3.6.1.4.1.13267.3.2.5.1.1.7)
          printf \"%s sysUpTime=%s mode=%s fr=%s gn=%s stageLen=%s stageCounter=%s transition=%s\\n\" \"\$ts\" \"\$sys\" \"\$mode\" \"\$fr\" \"\$gn\" \"\$stageLen\" \"\$stageCounter\" \"\$transition\"
          sleep 0.2
        done
      ' >\"\$d/snmp_poll.log\" 2>&1 & echo \$! >\"\$d/pid_snmp_poll\"

      echo \"started_remote_dir=\$d\"
      ls -l \"\$d\""

    echo "started: local_dir=${local_dir}"
    echo "remote_dir=${remote_dir}"
    ;;

  stop)
    # Stop background tailers/pollers started by `start`.
    sshc "set -e
      d=\$(cat /tmp/dk_capture_current 2>/dev/null || true)
      if [ -z \"\$d\" ] || [ ! -d \"\$d\" ]; then
        echo \"no_active_session\"
        exit 0
      fi
      for p in pid_spectr_utmc_follow pid_resident_follow pid_snmp_poll; do
        if [ -f \"\$d/\$p\" ]; then
          pid=\$(cat \"\$d/\$p\" 2>/dev/null || true)
          if [ -n \"\$pid\" ]; then
            kill \"\$pid\" 2>/dev/null || true
          fi
        fi
      done
      echo \"stopped_remote_dir=\$d\""
    ;;

  pull)
    local_dir="${1:-/tmp/dk_capture_pull_$(now_ts)}"
    mkdir -p "${local_dir}"

    remote_dir="$(sshc "cat /tmp/dk_capture_current 2>/dev/null || true" | tr -d '\r\n')"
    [[ -n "${remote_dir}" ]] || die "no active remote session found (/tmp/dk_capture_current is empty)"

    # Fetch a tarball with all captured data.
    tarball="${local_dir}/capture.tgz"
    sshc "set -e; cd /; tar -czf - \"${remote_dir}\"" >"${tarball}"
    echo "pulled: ${tarball}"
    ;;

  status)
    sshc "set -e
      d=\$(cat /tmp/dk_capture_current 2>/dev/null || true)
      echo \"remote_dir=\$d\"
      [ -n \"\$d\" ] && [ -d \"\$d\" ] && ls -lh \"\$d\" || true"
    ;;

  *)
    cat >&2 <<EOF
Usage: DK_PASS=... $0 <start|stop|pull|status> [args]

Environment:
  DK_IP   (default: ${DK_IP})
  DK_USER (default: ${DK_USER})
  DK_PASS (required)

Commands:
  start [local_dir]  - start remote capture session (read-only)
  stop               - stop background pollers/tailers on controller
  pull [local_dir]   - download captured logs into local_dir/capture.tgz
  status             - show current remote session directory and files
EOF
    exit 2
    ;;
esac
