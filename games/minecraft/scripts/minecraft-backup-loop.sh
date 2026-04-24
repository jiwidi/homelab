#!/usr/bin/env bash
set -Eeuo pipefail

mode="loop"
if [[ "${1:-}" == "loop" || "${1:-}" == "once" ]]; then
  mode="$1"
  shift
fi

data_dir="${1:?data directory is required}"
console_fifo="${2:?console fifo is required}"
server_pid="${3:?server pid is required}"

backup_dir="${MINECRAFT_SERVER_BACKUP_DIR:-${ATM9_BACKUP_DIR:-/data/backups}}"
backup_scope="${MINECRAFT_SERVER_BACKUP_SCOPE:-${ATM9_BACKUP_SCOPE:-world}}"
backup_retention="${MINECRAFT_SERVER_BACKUP_RETENTION:-${ATM9_BACKUP_RETENTION:-8}}"
backup_interval_seconds="${MINECRAFT_SERVER_BACKUP_INTERVAL_SECONDS:-${ATM9_BACKUP_INTERVAL_SECONDS:-21600}}"
backup_quiesce_seconds="${MINECRAFT_SERVER_BACKUP_QUIESCE_SECONDS:-${ATM9_BACKUP_QUIESCE_SECONDS:-5}}"
backup_active=0
sleep_pid=""

server_running() {
  kill -0 "${server_pid}" 2>/dev/null
}

send_console() {
  local command="$1"
  printf "%s\n" "${command}" > "${console_fifo}" || true
}

cleanup_backup_state() {
  if [[ "${backup_active}" -eq 1 ]]; then
    send_console "save-on"
    backup_active=0
  fi
}

cleanup() {
  cleanup_backup_state
  if [[ -n "${sleep_pid}" ]]; then
    kill "${sleep_pid}" 2>/dev/null || true
    wait "${sleep_pid}" 2>/dev/null || true
  fi
}

validate_number() {
  local value="$1"
  local name="$2"
  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    echo "[minecraft-backup] ${name} must be a non-negative integer, got '${value}'" >&2
    exit 1
  fi
}

build_backup_archive() {
  local tmp_path="$1"

  case "${backup_scope}" in
    world)
      local include_paths=()
      local candidate
      for candidate in \
        "world" \
        "server.properties" \
        "ops.json" \
        "whitelist.json" \
        "banned-ips.json" \
        "banned-players.json" \
        "usercache.json"
      do
        if [[ -e "${data_dir}/${candidate}" ]]; then
          include_paths+=("${candidate}")
        fi
      done

      if [[ "${#include_paths[@]}" -eq 0 ]]; then
        echo "[minecraft-backup] Nothing to back up yet in ${data_dir}"
        return 1
      fi

      tar -C "${data_dir}" -czf "${tmp_path}" "${include_paths[@]}"
      ;;
    server)
      tar \
        --exclude="./logs" \
        --exclude="./.mixin.out" \
        --exclude="./local" \
        -C "${data_dir}" \
        -czf "${tmp_path}" \
        .
      ;;
    *)
      echo "[minecraft-backup] Unsupported MINECRAFT_SERVER_BACKUP_SCOPE '${backup_scope}'. Use 'world' or 'server'." >&2
      return 1
      ;;
  esac
}

prune_backups() {
  mapfile -t backups < <(
    find "${backup_dir}" -maxdepth 1 -type f \
      \( -name "minecraft-server-${backup_scope}-*.tar.gz" -o -name "atm9-${backup_scope}-*.tar.gz" \) \
      -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-
  )

  if (( ${#backups[@]} <= backup_retention )); then
    return
  fi

  local prune_count=$(( ${#backups[@]} - backup_retention ))
  local backup_path
  for backup_path in "${backups[@]:0:prune_count}"; do
    rm -f "${backup_path}"
    echo "[minecraft-backup] Pruned ${backup_path}"
  done
}

perform_backup() {
  local timestamp
  local tmp_path
  local final_path
  local status=0

  if ! server_running; then
    echo "[minecraft-backup] Skipping backup because the server process is not running"
    return 1
  fi

  if ! SERVER_HOST=127.0.0.1 mc-health >/dev/null 2>&1; then
    echo "[minecraft-backup] Skipping backup because the server is not ready yet"
    return 1
  fi

  mkdir -p "${backup_dir}"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  tmp_path="${backup_dir}/minecraft-server-${backup_scope}-${timestamp}.tar.gz.tmp"
  final_path="${backup_dir}/minecraft-server-${backup_scope}-${timestamp}.tar.gz"

  echo "[minecraft-backup] Starting ${backup_scope} backup"
  send_console "save-off"
  send_console "save-all flush"
  backup_active=1
  sleep "${backup_quiesce_seconds}"

  if build_backup_archive "${tmp_path}"; then
    mv "${tmp_path}" "${final_path}"
    echo "[minecraft-backup] Wrote ${final_path}"
    prune_backups
  else
    rm -f "${tmp_path}"
    echo "[minecraft-backup] Backup skipped or failed"
    status=1
  fi

  send_console "save-on"
  backup_active=0
  return "${status}"
}

validate_number "${backup_retention}" "MINECRAFT_SERVER_BACKUP_RETENTION"
validate_number "${backup_interval_seconds}" "MINECRAFT_SERVER_BACKUP_INTERVAL_SECONDS"
validate_number "${backup_quiesce_seconds}" "MINECRAFT_SERVER_BACKUP_QUIESCE_SECONDS"

trap 'cleanup; exit 0' TERM INT
trap cleanup EXIT

echo "[minecraft-backup] Enabled: interval=${backup_interval_seconds}s scope=${backup_scope} dir=${backup_dir} retention=${backup_retention}"

if [[ "${mode}" == "once" ]]; then
  perform_backup
  exit $?
fi

while server_running; do
  sleep "${backup_interval_seconds}" &
  sleep_pid=$!
  wait "${sleep_pid}" || break
  sleep_pid=""

  if ! server_running; then
    break
  fi

  perform_backup || true
done
