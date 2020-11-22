#!/bin/bash

# Script to resync a PCHAIN Node
#
# Discussion, issues and change requests at:
#   https://t.me/pchainsupernode
#
# Usage: ./resync_node.sh

data_dir="${HOME}/.pchain"
chain_ids=("pchain" "child_0")
snapshot="https://pchainblockdata.s3-us-west-2.amazonaws.com/blockData.tar.gz"
snapshot_child0="https://pchainblockdata.s3-us-west-2.amazonaws.com/blockDataWithChild.tar.gz"
backup_dir="${HOME}/backup"
backup_file="${backup_dir}/$(date +%Y-%m-%d-%H-%M).tar"

log() {
  echo "[$(date --rfc-3339=seconds)] [Resync] $*"
}

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  log "Error on or near line ${parent_lineno}; exiting with status ${code}"
  exit "${code}"
}
trap 'error ${LINENO}' ERR

stop_pchain() {
  pchain_pid="$(pidof pchain)"
  if [[ -z "${pchain_pid}" ]]; then
    log "PCHAIN already stopped"
    return 0
  fi

  if ! systemctl stop pchain.service; then
    return 1
  fi
}

if [[ ! -d "${data_dir}" ]]; then
  log "Cannot find data dir '${data_dir}' > exiting"
  exit 1
fi

if [[ ! -d "${backup_dir}" ]]; then
  mkdir -p "${backup_dir}"
fi

if ! stop_pchain; then
  exit 1
fi

# Backup crontab
if crontab -l > "${backup_dir}/crontab.bak"; then
  log "Backuped crontab to ${backup_dir}/crontab.bak"
  crontab -r
fi

# Backup node config
log "Backup node configuration to '${backup_file}'"
if ! tar -cvf "${backup_file}" $(find ${data_dir} -name "UTC*" -or -name "nodekey" -or -name "priv_validator.json") 2>/dev/null ; then
  log "Error backing up your node config to '${backup_file}' > exiting"
  exit 1
fi

# Blockchain snapshot
snapshot_tar="$(basename ${snapshot})"
if [[ -f "/tmp/${snapshot_tar}" ]]; then
  rm "/tmp/${snapshot_tar}"
fi

log "Downloading snapshot from '${snapshot}'"
if ! wget -q --show-progress "${snapshot}" -P "/tmp/" -o /dev/null; then
  log "Error downloading '${snapshot}'"
fi

log "Extracting '/tmp/${snapshot_tar}' to '/tmp/.pchain'"
if ! tar -C "/tmp/" -xzf "/tmp/${snapshot_tar}"; then
  log "Error extracting '/tmp/${snapshot_tar}'"
fi

log "Stopping PCHAIN again as a precaution"
if ! stop_pchain; then
  log "Cannot stop pchain.service > exiting"
  exit 1
fi

log "Deleting data dir '${data_dir}'"
if ! rm -R "${data_dir}"; then
  log "Cannot delete ${data_dir}"
  exit 1
fi

log "Move '/tmp/.pchain' to '${data_dir}'"
if ! mv "/tmp/.pchain" "${HOME}"; then
  log "Error moving '/tmp/.pchain' to '${HOME}'"
fi

# Restore node config
if ! tar -xvf "${backup_file}" -C "/"; then
  log "Error restoring your node config > exiting"
fi

if ! systemctl start pchain.service; then
  log "Cannot start pchain.service"
fi

# Restore crontab
if [[ -e "${backup_dir}/crontab.bak" ]]; then
  log "Restoring crontab '${backup_dir}/crontab.bak'"
  crontab "${backup_dir}/crontab.bak"
fi