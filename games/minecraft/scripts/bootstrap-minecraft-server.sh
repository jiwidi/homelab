#!/usr/bin/env bash
set -Eeuo pipefail

bootstrap_started_at="$(date +%s)"

log() {
  local now elapsed
  now="$(date +%s)"
  elapsed=$(( now - bootstrap_started_at ))
  echo "[minecraft-server][+${elapsed}s] $*"
}

is_true() {
  [[ "${1:-}" =~ ^([Tt][Rr][Uu][Ee]|[Yy][Ee][Ss]|1)$ ]]
}

metadata_file="${MINECRAFT_SERVER_METADATA_FILE:-/opt/minecraft-bootstrap/all-the-mods-9.env}"

if [[ ! -f "${metadata_file}" ]]; then
  echo "[minecraft-server] Missing metadata file at ${metadata_file}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${metadata_file}"

pack_name="${ALL_THE_MODS_9_NAME:?missing pack name}"
pack_slug="${ALL_THE_MODS_9_SLUG:?missing pack slug}"
pack_version="${ALL_THE_MODS_9_VERSION:?missing pack version}"
server_pack_file="${ALL_THE_MODS_9_SERVER_PACK_FILE:?missing server pack file name}"
server_pack_root_dir="${ALL_THE_MODS_9_SERVER_PACK_ROOT_DIR:?missing server pack root dir}"
server_pack_url="${ALL_THE_MODS_9_SERVER_PACK_URL:?missing server pack url}"
server_pack_sha256="${ALL_THE_MODS_9_SERVER_PACK_SHA256:?missing server pack sha256}"
forge_installer_file="${ALL_THE_MODS_9_FORGE_INSTALLER_FILE:?missing forge installer file name}"
forge_installer_url="${ALL_THE_MODS_9_FORGE_INSTALLER_URL:?missing forge installer url}"
forge_installer_sha256="${ALL_THE_MODS_9_FORGE_INSTALLER_SHA256:?missing forge installer sha256}"

cache_root="${MINECRAFT_SERVER_CACHE_ROOT:-/cache}"
cache_dir="${cache_root}/${pack_slug}/${pack_version}"
cache_server_dir="${cache_dir}/server"
cache_source_dir="${cache_dir}/source"
cache_ready_file="${cache_dir}/.ready"
cache_metadata_file="${cache_dir}/metadata.env"
data_dir="${MINECRAFT_SERVER_DATA_DIR:-/data/server}"
legacy_data_dir="/data/Server-Files-1.1.1"
server_port="${MINECRAFT_SERVER_PORT:-42424}"
backup_enabled="${MINECRAFT_SERVER_BACKUP_ENABLED:-${ATM9_BACKUP_ENABLED:-true}}"
min_memory="${MINECRAFT_SERVER_MIN_MEMORY:-${ATM9_MIN_MEMORY:-}}"
max_memory="${MINECRAFT_SERVER_MAX_MEMORY:-${ATM9_MAX_MEMORY:-}}"
online_mode="${MINECRAFT_SERVER_ONLINE_MODE:-true}"
prevent_proxy_connections="${MINECRAFT_SERVER_PREVENT_PROXY_CONNECTIONS:-true}"
enable_rcon="${MINECRAFT_SERVER_ENABLE_RCON:-false}"
enable_query="${MINECRAFT_SERVER_ENABLE_QUERY:-false}"
enforce_secure_profile="${MINECRAFT_SERVER_ENFORCE_SECURE_PROFILE:-true}"
whitelist_enabled="${MINECRAFT_SERVER_WHITELIST_ENABLED:-false}"
rate_limit="${MINECRAFT_SERVER_RATE_LIMIT:-0}"

verify_sha256() {
  local expected_sha256="$1"
  local file_path="$2"
  local description="$3"
  local actual_sha256

  actual_sha256="$(sha256sum "${file_path}" | awk '{ print $1 }')"
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    echo "[minecraft-server] ${description} checksum mismatch: expected ${expected_sha256}, got ${actual_sha256}" >&2
    exit 1
  fi

  log "Verified ${description} checksum"
}

download_file() {
  local url="$1"
  local destination="$2"
  local description="$3"
  local expected_sha256="${4:-}"

  mkdir -p "$(dirname "${destination}")"
  log "Downloading ${description}"
  curl -fL --retry 5 --retry-delay 5 --retry-all-errors -o "${destination}" "${url}"
  if [[ -n "${expected_sha256}" ]]; then
    verify_sha256 "${expected_sha256}" "${destination}" "${description}"
  fi
}

cache_is_ready() {
  [[ -f "${cache_ready_file}" ]] \
    && [[ -f "${cache_metadata_file}" ]] \
    && cmp -s "${metadata_file}" "${cache_metadata_file}" \
    && [[ -f "${cache_server_dir}/run.sh" ]] \
    && [[ -f "${cache_server_dir}/user_jvm_args.txt" ]] \
    && [[ -d "${cache_server_dir}/libraries" ]]
}

prepare_cache() {
  local stage_dir stage_cache_dir extract_dir stage_server_dir server_pack_archive

  if cache_is_ready; then
    log "Cache hit at ${cache_dir}"
    return
  fi

  log "Cache miss for ${pack_name} ${pack_version}; preparing ${cache_dir}"
  mkdir -p "${cache_root}" "$(dirname "${cache_dir}")"

  stage_dir="$(mktemp -d "${cache_root}/bootstrap.XXXXXX")"
  stage_cache_dir="${stage_dir}/cache"
  extract_dir="${stage_dir}/extract"
  server_pack_archive="${stage_cache_dir}/source/${server_pack_file}"

  cleanup_stage_dir() {
    rm -rf "${stage_dir}"
  }

  trap cleanup_stage_dir RETURN

  mkdir -p "${stage_cache_dir}/source" "${extract_dir}"
  download_file "${server_pack_url}" "${server_pack_archive}" "${pack_name} ${pack_version} server pack" "${server_pack_sha256}"
  unzip -q "${server_pack_archive}" -d "${extract_dir}"

  stage_server_dir="${extract_dir}/${server_pack_root_dir}"
  if [[ ! -d "${stage_server_dir}" ]]; then
    echo "[minecraft-server] Expected extracted server pack at ${stage_server_dir}" >&2
    exit 1
  fi

  cp -a "${stage_server_dir}" "${stage_cache_dir}/server"
  download_file "${forge_installer_url}" "${stage_cache_dir}/server/${forge_installer_file}" "Forge installer ${forge_installer_file}" "${forge_installer_sha256}"

  (
    cd "${stage_cache_dir}/server"
    chmod +x startserver.sh
    ATM9_INSTALL_ONLY=true ATM9_RESTART=false sh ./startserver.sh
  )

  cp "${metadata_file}" "${stage_cache_dir}/metadata.env"
  touch "${stage_cache_dir}/.ready"

  rm -rf "${cache_dir}"
  mv "${stage_cache_dir}" "${cache_dir}"
  log "Cache preparation complete at ${cache_dir}"
}

directory_is_empty() {
  [[ ! -d "${1}" ]] && return 0
  [[ -z "$(find "${1}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]
}

initialize_runtime_data() {
  mkdir -p /data /cache

  if [[ ! -f "${data_dir}/run.sh" && ! -e "${data_dir}" && -f "${legacy_data_dir}/run.sh" && "${data_dir}" != "${legacy_data_dir}" ]]; then
    log "Migrating legacy server data from ${legacy_data_dir} to ${data_dir}"
    mkdir -p "$(dirname "${data_dir}")"
    mv "${legacy_data_dir}" "${data_dir}"
  fi

  if directory_is_empty "${data_dir}"; then
    log "Initializing runtime data in ${data_dir} from cached files"
    if ! mkdir -p "${data_dir}"; then
      echo "[minecraft-server] Cannot create ${data_dir}. Ensure the data volume is writable by the 'minecraft' user or clear the invalid volume contents." >&2
      exit 1
    fi
    cp -a "${cache_server_dir}/." "${data_dir}/"
  else
    log "Skipping runtime initialization because ${data_dir} already contains data"
  fi

  if [[ ! -f "${data_dir}/run.sh" || ! -f "${data_dir}/user_jvm_args.txt" || ! -f "${data_dir}/startserver.sh" ]]; then
    echo "[minecraft-server] Existing data in ${data_dir} does not look like an initialized ${pack_name} server." >&2
    echo "[minecraft-server] Clear the data volume for a fresh boot or copy a valid server tree into ${data_dir}." >&2
    exit 1
  fi
}

ensure_server_properties() {
  if [[ -f "${data_dir}/server.properties" ]]; then
    return
  fi

  cat > "${data_dir}/server.properties" <<'EOF'
allow-flight=true
motd=All the Mods 9
max-tick-time=180000
EOF
}

set_server_property() {
  local key="$1"
  local value="$2"
  local property_file="${data_dir}/server.properties"
  local tmp_file

  tmp_file="$(mktemp /tmp/server-properties.XXXXXX)"

  awk -v key="${key}" -v value="${value}" '
    BEGIN { updated=0 }
    index($0, key "=") == 1 {
      print key "=" value
      updated=1
      next
    }
    { print }
    END {
      if (!updated) {
        print key "=" value
      }
    }
  ' "${property_file}" > "${tmp_file}"

  cat "${tmp_file}" > "${property_file}"
  rm -f "${tmp_file}"
}

set_jvm_argument() {
  local prefix="$1"
  local value="$2"
  local arg_file="${data_dir}/user_jvm_args.txt"
  local tmp_file

  tmp_file="$(mktemp /tmp/user-jvm-args.XXXXXX)"

  awk -v prefix="${prefix}" -v value="${value}" '
    BEGIN { updated=0 }
    index($0, prefix) == 1 {
      print prefix value
      updated=1
      next
    }
    { print }
    END {
      if (!updated) {
        print prefix value
      }
    }
  ' "${arg_file}" > "${tmp_file}"

  cat "${tmp_file}" > "${arg_file}"
  rm -f "${tmp_file}"
}

if [[ ! "${EULA:-FALSE}" =~ ^([Tt][Rr][Uu][Ee]|[Yy][Ee][Ss])$ ]]; then
  echo "[minecraft-server] Set EULA=TRUE to accept the Minecraft EULA." >&2
  exit 1
fi

log "Bootstrap start for ${pack_name} ${pack_version} as $(id -un):$(id -gn)"
prepare_cache
initialize_runtime_data

printf "eula=true\n" > "${data_dir}/eula.txt"
ensure_server_properties

if [[ -n "${min_memory}" ]]; then
  set_jvm_argument "-Xms" "${min_memory}"
fi

if [[ -n "${max_memory}" ]]; then
  set_jvm_argument "-Xmx" "${max_memory}"
fi

set_server_property "online-mode" "${online_mode}"
set_server_property "server-port" "${server_port}"
set_server_property "query.port" "${server_port}"
set_server_property "prevent-proxy-connections" "${prevent_proxy_connections}"
set_server_property "enable-rcon" "${enable_rcon}"
set_server_property "enable-query" "${enable_query}"
set_server_property "enforce-secure-profile" "${enforce_secure_profile}"
set_server_property "white-list" "${whitelist_enabled}"
set_server_property "enforce-whitelist" "${whitelist_enabled}"
set_server_property "rate-limit" "${rate_limit}"

cd "${data_dir}"

console_fifo="/tmp/minecraft-server-console"
server_pid_file="/tmp/minecraft-server.pid"
rm -f "${console_fifo}"
mkfifo "${console_fifo}"
tail -f /dev/null > "${console_fifo}" &
keepalive_pid=$!

cleanup() {
  if [[ -n "${backup_pid:-}" ]]; then
    kill "${backup_pid}" 2>/dev/null || true
    wait "${backup_pid}" 2>/dev/null || true
  fi
  kill "${keepalive_pid}" 2>/dev/null || true
  wait "${keepalive_pid}" 2>/dev/null || true
  rm -f "${console_fifo}"
  rm -f "${server_pid_file}"
}

stop_server() {
  if [[ -n "${backup_pid:-}" ]]; then
    kill "${backup_pid}" 2>/dev/null || true
    wait "${backup_pid}" 2>/dev/null || true
    backup_pid=""
  fi

  if [[ -n "${server_pid:-}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
    log "Forwarding stop command to Minecraft server"
    printf "stop\n" > "${console_fifo}" || true
    wait "${server_pid}" || true
  fi
}

trap cleanup EXIT
trap stop_server SIGTERM SIGINT

run_args=("$@")
if [[ "${#run_args[@]}" -eq 0 ]]; then
  run_args=(nogui)
fi

log "Launching Minecraft server with args: ${run_args[*]}"
bash ./run.sh "${run_args[@]}" < "${console_fifo}" &
server_pid=$!
printf "%s\n" "${server_pid}" > "${server_pid_file}"

if is_true "${backup_enabled}"; then
  /usr/local/bin/minecraft-backup-loop.sh "${data_dir}" "${console_fifo}" "${server_pid}" &
  backup_pid=$!
else
  echo "[minecraft-backup] Disabled"
fi

wait "${server_pid}"
