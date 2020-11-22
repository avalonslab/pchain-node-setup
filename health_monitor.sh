#!/bin/bash

# Script to monitor a PCHAIN Node
#
# Discussion, issues and change requests at:
#   https://t.me/pchainsupernode

data_dir="${HOME}/.pchain"
chain_id="pchain"
rpc_port="6969"
rpc_url="http://localhost:${rpc_port}/${chain_id}"

log() {
  echo "[$(date --rfc-3339=seconds)] $*"
}

restart_service() {
  systemctl daemon-reload

  if systemctl restart pchain.service; then
    log "[pchain.service] Restart successful"
    sleep 20
  else
    log "[pchain.service] Restart failure"
    exit 1
  fi
}
echo

# Is automatic update running?
autoupdate_running="$(ps -ax | grep automatic_update.sh | wc -l)"
if (( autoupdate_running > 1 )); then
  log "[Health Monitor] Automatic Update is running > exiting"
  exit 0
fi

# Checking for BAD BLOCK
badblock_num="$(journalctl -u pchain.service -n 100 | grep "########## BAD BLOCK #########" | wc -l)"
if (( badblock_num > 0 )); then
  log "[Health Monitor] ########## BAD BLOCK ######### detected, please resync your node > exiting"
  exit 1
fi

# Get all chain id's
chain_ids="$(curl --silent -X POST -H "Content-Type:application/json" --data '{"jsonrpc":"2.0","method":"chain_getAllChains","params":[],"id":1}' ${rpc_url} |  jq --raw-output '.result | .[].chain_id')"
chain_ids=(${chain_ids})
if [[ -z "${chain_ids}" ]]; then
  log "[Health Monitor] Cannot fetch all available chains > exiting"
  exit 1
fi

# Chain Monitoring
for chain_id in "${chain_ids[@]}"; do
  if [[ ! -d "${data_dir}/${chain_id}" ]]; then
    continue
  fi

  rpc_url="http://localhost:${rpc_port}/${chain_id}"

  status_code="$(timeout 5m curl --silent --write-out %{http_code} ${rpc_url} --output /dev/null)"
  if (( status_code == 200 )); then
    log "[${chain_id}] HTTP-Status: $status_code OK"
  else
    log "[${chain_id}] HTTP-Status: $status_code ERROR > Restarting the node"
    restart_service
  fi

  sync_status="$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' -H 'content-type: application/json;' ${rpc_url} | jq --raw-output '.result')"
  if [[ -n "${sync_status}" ]] && [[ "${sync_status}" != "false" ]]; then
    currentBlock="$(echo ${sync_status} | jq --raw-output '.currentBlock')"
    highestBlock="$(echo ${sync_status} | jq --raw-output '.highestBlock')"
    log "[${chain_id}] Sync Status: Node is syncing [Block: $((currentBlock))/$((highestBlock))]"
  fi

  current_block_height="$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", true],"id":1}' -H 'content-type:application/json;' ${rpc_url} | jq --raw-output '.result.number')"
  current_block_height_dec="$((current_block_height))"
  if (( current_block_height_dec > 0 )) ; then
    log "[${chain_id}] Current Block Height: ${current_block_height_dec}"

    if [[ -e "${data_dir}/${chain_id}/old_height" ]]; then
      old_height="$(cat ${data_dir}/${chain_id}/old_height)"
    else
      old_height=0
    fi

    if (( current_block_height_dec == old_height )); then
      log "[${chain_id}] Sync Status: Blockchain stuck at block ${current_block_height_dec} > Restarting the node"
      restart_service
    elif (( current_block_height_dec > old_height )); then
      echo "${current_block_height_dec}" > "${data_dir}/${chain_id}/old_height"
    fi
  else
    log "[${chain_id}] Current Block Height: Cannot fetch current block height"
  fi

  peers="$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"admin_peers","params":[],"id":1}' -H 'content-type: application/json;' ${rpc_url} | jq '.result')"
  peers_num="$(echo ${peers} | jq length)"
  if (( peers_num >= 0 )); then
    log "[${chain_id}] Peers: ${peers_num}"
  else
    log "[${chain_id}] Peers: Cannot fetch amount of peers"
  fi

  if [[ ! -e "${data_dir}/${chain_id}/priv_validator.json" ]]; then
    log "[${chain_id}] ${data_dir}/${chain_id}/priv_validator.json does not exist"
  else
    validator_address="$(cat "${data_dir}/${chain_id}/priv_validator.json" | jq --raw-output '.address')"
    log "[${chain_id}] ${data_dir}/${chain_id}/priv_validator.json found [Address: ${validator_address}]"
  fi

  miner_status="$(curl -X POST --silent --data '{"jsonrpc":"2.0","method":"eth_mining","params":[],"id":1}' -H 'content-type: application/json;' ${rpc_url} | jq --raw-output '.result')"
  if [[ "${miner_status}" == "true" ]]; then
    log "[${chain_id}] Miner Status: Is mining"
  else
    log "[${chain_id}] Miner Status: Is NOT mining"
  fi
done

hdd="$(df -Ph | sed s/%//g | awk '{ if($5 > 90 ) print $0;}' | wc -l)"
if (( hdd > 1 )); then
  log "Hard Disc Space: Capacity over 90% > Please expand your storage"
fi