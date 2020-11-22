#!/bin/bash

# Script to update a PCHAIN Node automatically
#
# Discussion, issues and change requests at:
#   https://t.me/pchainsupernode

pchain_dir="${HOME}/pchain"
chain_id="pchain"

version_info="$(curl --silent -X POST -H "Content-Type:application/json" https://api.pchain.org/getLastVersion)"
state="$(echo ${version_info} | jq --raw-output '.result')"

log() {
  echo "[$(date --rfc-3339=seconds)] [Automatic Update] $*"
}

echo
if [[ "${state}" != "success" ]]; then
  log "Cannot fetch version info from 'https://api.pchain.org/getLastVersion' > exiting"
  exit 1
fi

latest_version="$(echo ${version_info} | jq --raw-output '.data[0].v')"
if [[ ! -e "${pchain_dir}/version" ]]; then
  echo "0.0.00" > "${pchain_dir}/version"
fi

local_version="$(cat "$pchain_dir/version")"
log "Local version is ${local_version}, latest version is ${latest_version}"

url="$(echo ${version_info} | jq --raw-output '.data[0].url')"

if [[ "${latest_version}" > "${local_version}" ]]; then # Lexicographical comparison intended
  log "Start update from version ${local_version} to ${latest_version}"
  url="$(echo ${version_info} | jq --raw-output '.data[0].url')"
  filename_tar="$(basename ${url})"
  filename="${filename_tar%.*}"
  filename="${filename%.*}"

  log "Stop pchain.service"
  if ! systemctl stop pchain.service; then
    log "Cannot stop pchain.service > exiting"
    exit 1
  fi

  log "Cleaning log directories"
  rm -R "${pchain_dir}/log/"* "${pchain_dir}/bin/log/"* "${HOME}/log/"* 2>/dev/null

  log "Downloading ${url}"
  if ! wget -q "${url}" -P "/tmp/"; then
    log "Error downloading '${url}' > exiting"
    exit 1
  fi

  log "Extracting '/tmp/${filename_tar}'"
  if ! tar -xzf "/tmp/${filename_tar}" -C "/tmp/"; then
    log "Error extracting '/tmp/${filename_tar}' > exiting"
    exit 1
  fi

  log "Update PCHAIN binary"
  if ! mv "/tmp/${filename}/pchain" "${pchain_dir}/bin/"; then
    log "Error moving '/tmp/${filename}/pchain' to '${pchain_dir}/bin/' > exiting"
    exit 1
  fi

  rm "/tmp/${filename_tar}"
  rm -R "/tmp/${filename}"

  log "Update finished, starting pchain.service now"
  if ! systemctl start pchain.service; then
    "Error starting pchain.service"
  fi

  echo "${latest_version}" > "${pchain_dir}/version"
fi
