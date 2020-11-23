# PCHAIN Node Setup for Debian and Ubuntu systems

### Install a Node
Log as 'root' user and execute the following command:
```
bash <(wget -qO- https://raw.githubusercontent.com/avalonslab/pchain-node-setup/main/install_node.sh)
```
### Maintenance
#### View Log File
```
journalctl -f -u pchain.service
```
#### View Health Monitor Log File
```
cat /var/log/pchain_monitor.log
```
#### Resync Node
```
~/pchain-node-setup/resync_node.sh
```
