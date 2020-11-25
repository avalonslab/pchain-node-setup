#!/bin/bash

# Script to install a PCHAIN Node onto a
# Debian or Ubuntu system.
#
# Discussion, issues and change requests at:
#   https://t.me/pchainsupernode
#
# Usage: bash <(wget -qO- https://raw.githubusercontent.com/avalonslab/pchain-node-setup/main/install_node.sh)

cat << 'FIG'
  _  __    _     ____   __  __     _
 | |/ /   / \   |  _ \ |  \/  |   / \
 | ' /   / _ \  | |_) || |\/| |  / _ \
 | . \  / ___ \ |  _ < | |  | | / ___ \
 |_|\_\/_/   \_\|_| \_\|_|  |_|/_/   \_\

0xe0546c3cac301ff456b2ab2b586bdf15a772be75
FIG

logfile="install_node.sh.log"
pchain_dir="${HOME}/pchain"
data_dir="${HOME}/.pchain"
chain_id="pchain"
rpc_port="6969"
rpc_url="http://localhost:${rpc_port}/${chain_id}"
snapshot="https://pchainblockdata.s3-us-west-2.amazonaws.com/blockData.tar.gz"
node_repo="https://github.com/avalonslab/pchain-node-setup"
node_repo_dir="${HOME}/$(basename ${node_repo})"

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  exit "${code}"
}
trap 'error ${LINENO}' ERR

if [[ "$(whoami)" != "root" ]]; then
  echo
  echo "Please login as 'root' user, the script will now be terminated."
  exit 1
fi

# Create a new user account and add it to necessary groups
echo "Current username is 'root'"
echo "For security reasons it is highly recommended to create an additional user to operate your node."
echo "The node itself will still run under the 'root' user."
echo "Which user do you want to use? A new user will be created if it does not exist."

read -p "Username: " new_username </dev/tty
echo "Please choose a strong password!"
read -sp "Password: " new_password </dev/tty
echo
read -sp "Confirm Password: " confirm_password </dev/tty
echo

if [[ "${new_username}" = "root" ]]; then
  echo "Please use another user than 'root', the script will now be terminated."
  exit 1
fi

if [[ "${new_password}" != "${confirm_password}" ]]; then
  echo "Your password does not match, the script will now be terminated."
  exit 1
fi

if ! id "${new_username}" > /dev/null 2>&1; then
  echo "Creating user '$new_username'"
  useradd -m -p $(openssl passwd -1 ${new_password}) -s /bin/bash -G sudo "${new_username}" >> $logfile 2>&1
fi

echo "Adding user '${new_username}' to the 'sudo' group"
usermod -aG sudo "${new_username}" >> $logfile 2>&1
echo "Adding user '${new_username}' to the 'systemd-journal' group"
usermod -aG systemd-journal "${new_username}" >> "${logfile}" 2>&1

# Disable root SSH
while true; do
  echo "Deactivating the SSH login for your 'root' user adds another security layer and is highly recommended."
  read -p "Do you want to deactivate the 'root' SSH login? (y/n)" i </dev/tty
  case $i in
    [Yy]*) disable_rootssh="true"; break;;
    [Nn]*) disable_rootssh="false"; break;;
  esac
done

if [[ "${disable_rootssh}" == "true" ]]; then
  awk '$1=="PermitRootLogin"{foundLine=1; print "PermitRootLogin no"} $1!="PermitRootLogin"{print $0} END{if(foundLine!=1) print "permitRootLogin no"}' "/etc/ssh/sshd_config" > "/etc/ssh/sshd_config.tmp"
  mv "/etc/ssh/sshd_config.tmp" "/etc/ssh/sshd_config"
  service ssh reload
fi

while true; do
  read -p "Do you wish to setup a childchain as well? (y/n)" i </dev/tty
  case $i in
    [Yy]*) setup_childchain="true"; break;;
    [Nn]*) setup_childchain="false"; break;;
  esac
done

if [[ "${setup_childchain}" == "true" ]]; then
  snapshot="https://pchainblockdata.s3-us-west-2.amazonaws.com/blockDataWithChild.tar.gz"
  child_arg="--childChain=child_0"
fi

# System Upgrade
echo "System Upgrade, please wait..."
apt update -y >> "${logfile}" 2>&1
apt upgrade -y >> "${logfile}" 2>&1

# Dependencies
if [[ ! -x "$(command -v jq)" ]]; then
  echo "'jq' not found > installing"
  apt install jq -y >> "${logfile}" 2>&1
fi

if [[ ! -x "$(command -v git)" ]]; then
  echo "'git' not found > installing"
  apt install git -y >> "${logfile}" 2>&1
fi

if [[ ! -x "$(command -v ufw)" ]]; then
  echo "'ufw' not found > installing"
  apt install ufw >> "${logfile}" 2>&1
fi

if [[ ! -d "/etc/fail2ban" ]]; then
  echo "'fail2ban' not found > installing"
  apt install fail2ban -y >> "${logfile}" 2>&1
  echo "Start 'fail2ban'"
  service fail2ban start >> "${logfile}" 2>&1
fi

# Firewall Configuration
echo "Configure Firewall"
ufw allow ssh/tcp >> "${logfile}" 2>&1
ufw limit ssh/tcp >> "${logfile}" 2>&1
ufw allow 30308/tcp >> "${logfile}" 2>&1
ufw allow 30308/udp >> "${logfile}" 2>&1
ufw logging on >> "${logfile}" 2>&1
ufw --force enable >> "${logfile}" 2>&1

# Install newest available PCHAIN version
version_info="$(curl --silent -X POST -H "Content-Type:application/json" https://api.pchain.org/getLastVersion)"
state="$(echo ${version_info} | jq --raw-output .result)"
if [[ "${state}" != "success" ]]; then
  echo "Cannot fetch version info from 'https://api.pchain.org/getLastVersion' > exiting"
  exit 1
fi

latest_version="$(echo ${version_info} | jq --raw-output .data[0].v)"
url="$(echo ${version_info} | jq --raw-output '.data[0].url')"
filename_tar="$(basename ${url})"
filename="${filename_tar%.*}"
filename="${filename%.*}"

if [[ -f "/tmp/${filename_tar}" ]]; then
  rm "/tmp/${filename_tar}"
fi

echo "Downloading PCHAIN ${latest_version}"
wget -q --show-progress "${url}" -P "/tmp/"

echo "Extracting '/tmp/${filename_tar}' to '/tmp/${filename}'"
tar -xzf "/tmp/${filename_tar}" -C "/tmp/" >> "${logfile}" 2>&1
mkdir -p "${pchain_dir}/bin"
echo "Copy '/tmp/${filename}/pchain' to '${pchain_dir}/bin/'"
cp "/tmp/${filename}/pchain" "${pchain_dir}/bin/"

# Set version file for automatic updates
echo "${latest_version}" > "${pchain_dir}/version"

echo "export PATH=${PATH}:${pchain_dir}/bin" >> "${HOME}/.profile"
source "${HOME}/.profile"

# Blockchain Snapshot
snapshot_tar="$(basename $snapshot)"
if [[ -f "/tmp/${snapshot_tar}" ]]; then
  echo "'/tmp/${snapshot_tar}' exists > deleting"
  rm "/tmp/${snapshot_tar}"
fi

echo "Downloading snapshot from '${snapshot}'"
wget -q --show-progress "${snapshot}" -P "/tmp/"
echo "Extracting '/tmp/${snapshot_tar}' to '${data_dir}'"
tar -C "${HOME}" -xzf "/tmp/${snapshot_tar}" >> "${logfile}" 2>&1

# Systemd Setup
echo "Configure '/etc/systemd/system/pchain.service'"
cat << EOF > /etc/systemd/system/pchain.service
[Unit]
Description=PCHAIN Node

[Service]
User=root
KillMode=process
KillSignal=SIGINT
WorkingDirectory=${pchain_dir}
ExecStart=${pchain_dir}/bin/pchain \
--datadir ${data_dir} \
--rpc \
--rpcapi=eth,web3,admin,tdm,miner,personal,chain,txpool,del \
--rpcport ${rpc_port} \
--gcmode=full \
--verbosity 2 \
--bootnodes enode://5d867a49995ce5939324ce110d9e21c5396ca919002ea2063735ea164fc3401cb5ffb74b976406807929c8e179bf00fe9b3df4f3d680691bcc463a115735741d@13.49.131.60:30308,enode://cddbf23fdcda09dfb7d160b998da2807cc4d5138881bba6206bdbd5e4c30f70af412d023693cfdc51fce9d150aaac694e3d408623a8ccc0c226c8f55c9410a6f@15.207.188.58:30308,enode://8b1234cf208657da6a67ce2a38cf1c1fb7e8b41220ccecb8775bc60b11e6f329214624b8485b1cdb9ae5c13ff405dd4d9226391edac9e45f536a0add4df1ad6a@52.25.235.47:30308 \
${child_arg}
Restart=always
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

# Enable Node
systemctl daemon-reload
systemctl enable pchain.service >> "${logfile}" 2>&1

echo "Start pchain.service"
systemctl start pchain.service >> "${logfile}" 2>&1

# Cloning pchain-node-setup repository
git clone "${node_repo}" "${node_repo_dir}" >> "${logfile}" 2>&1
chmod +x "${node_repo_dir}/"*.sh >> "${logfile}" 2>&1

# Health Monitor & Automatic Update Crontab Configuration
echo "Create and import health monitor & automatic update crontab"
echo "*/3 * * * * ${node_repo_dir}/health_monitor.sh >> /var/log/pchain_monitor.log 2>&1" >> "/tmp/newCrontab"
echo "*/11 * * * * ${node_repo_dir}/automatic_update.sh >> /var/log/pchain_monitor.log 2>&1" >> "/tmp/newCrontab"
crontab -u root "/tmp/newCrontab" >> "${logfile}" 2>&1
rm "/tmp/newCrontab" >> "${logfile}" 2>&1

echo
echo "##### Installation completed! #####"
echo "If you have found this tutorial useful, please consider delegating some of your votes to the KARMA validator node: 0xe0546c3cac301ff456b2ab2b586bdf15a772be75"
echo
echo "Type 'cat ${logfile}' to view the install log file."
echo "Type 'journalctl -f -u pchain' to view the log file of your node."
echo "Type 'cat /var/log/pchain_monitor.log' to view the health monitor log file."
