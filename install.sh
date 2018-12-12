#!/bin/bash

#############################
# Script by Veco Developers #
# Veco Core v1.0.0          #
# https://veco.info/        #
#############################

error() {
  local parent_lineno="$1"
  local message="$2"
  local code="${3:-1}"
  echo "Error on or near line ${parent_lineno}; exiting with status ${code}"
  exit "${code}"
}
trap 'error ${LINENO}' ERR

clear

cat <<'FIG'
 .----------------.  .----------------.  .----------------.  .----------------. 
| .--------------. || .--------------. || .--------------. || .--------------. |
| | ____   ____  | || |  _________   | || |     ______   | || |     ____     | |
| ||_  _| |_  _| | || | |_   ___  |  | || |   .' ___  |  | || |   .'    `.   | |
| |  \ \   / /   | || |   | |_  \_|  | || |  / .'   \_|  | || |  /  .--.  \  | |
| |   \ \ / /    | || |   |  _|  _   | || |  | |         | || |  | |    | |  | |
| |    \ ' /     | || |  _| |___/ |  | || |  \ `.___.'\  | || |  \  `--'  /  | |
| |     \_/      | || | |_________|  | || |   `._____.'  | || |   `.____.'   | |
| |              | || |              | || |              | || |              | |
| '--------------' || '--------------' || '--------------' || '--------------' |
 '----------------'  '----------------'  '----------------'  '----------------' 
FIG

# Check for systemd
systemctl --version >/dev/null 2>&1 || { decho "systemd is required. Are you using Ubuntu 16.04?"  >&2; exit 1; }

# Print variable on a screen
decho "Please make sure you double check information before hitting enter!"

read -e -p "Please enter username that will run Veco Core |CaSe SeNsItIvE|: " whoami
if [[ "$whoami" == "" ]]; then
	decho "WARNING: No user entered, exiting!!!"
	exit 3
fi

read -e -p "Server IP Address: " ip
if [[ "$ip" == "" ]]; then
	decho "WARNING: No IP entered, exiting!!!"
	exit 3
fi
read -e -p "Please enter Masternode Private Key (e.g. 3YZEsru3J3kiy9itrLW1EzBt8RsF23s24co82rswUPrPgpJ6r6o # THE KEY YOU GENERATED IN YOUR WALLET EARLIER): " key
if [[ "$key" == "" ]]; then
	decho "WARNING: No Masternode private key entered, exiting!!!"
	exit 3
fi
read -e -p "(Optional) Install Fail2ban? (Recommended) [Y/n]: " install_fail2ban
read -e -p "(Optional) Install UFW and configure ports? (Recommended) [Y/n]: " UFW

# Install swap
decho "Enabling a swap partition..." 

if free | awk '/^Swap:/ {exit !$2}'; then
	echo "Has swap..."
else
	touch /var/swap.img
	chmod 600 /var/swap.img
	dd if=/dev/zero of=/var/swap.img bs=2048 count=1048576
	mkswap /var/swap.img
	swapon /var/swap.img
	echo "/var/swap.img none swap sw 0 0" >> /etc/fstab
fi

# Update package and upgrade Ubuntu
decho "Updating system and installing required packages..."   

apt-get -y update
apt-get -y upgrade

# Install required packages
decho "Installing base packages and dependencies..."

apt-get -y install sudo
apt-get -y install wget
apt-get -y install git
apt-get -y install unzip
apt-get -y install virtualenv
apt-get -y install python-virtualenv
apt-get -y install pwgen

# Install daemon packages
decho "Installing daemon packages and dependencies..."

apt-get -y install software-properties-common libzmq3-dev pwgen
apt-get -y install git libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev libboost-all-dev unzip libminiupnpc-dev python-virtualenv >> $LOG_FILE 2>&1
apt-get -y install build-essential libtool autotools-dev automake pkg-config libssl-dev libevent-dev bsdmainutils

# Add Berkely PPA
decho "Installing bitcoin PPA..."

apt-add-repository -y ppa:bitcoin/bitcoin
apt-get -y update
apt-get -y install libdb4.8-dev libdb4.8++-dev


if [[ ("$install_fail2ban" == "y" || "$install_fail2ban" == "Y" || "$install_fail2ban" == "") ]]; then
	decho "Optional install: Fail2ban"
	cd ~
	apt-get -y install fail2ban
	systemctl enable fail2ban
	systemctl start fail2ban
fi

if [[ ("$UFW" == "y" || "$UFW" == "Y" || "$UFW" == "") ]]; then
	decho "Optional install: UFW"
	apt-get -y install ufw
	ufw allow ssh/tcp
	ufw allow sftp/tcp
	ufw allow 26919/tcp
	ufw allow 26920/tcp
	ufw default deny incoming
	ufw default allow outgoing
	ufw logging on
	ufw --force enable
fi

decho "Create user $whoami (if necessary)"

# Deactivate trap only for this command
trap '' ERR
getent passwd $whoami > /dev/null 2&>1

if [ $? -ne 0 ]; then
	trap 'error ${LINENO}' ERR
	adduser --disabled-password --gecos "" $whoami
else
	trap 'error ${LINENO}' ERR
fi

# Create veco.conf
decho "Setting up Veco Core..." 

# Generate random passwords
user=`pwgen -s 16 1`
password=`pwgen -s 64 1`

echo 'Creating veco.conf...'
mkdir -p /home/$whoami/.vecocore/
cat << EOF > /home/$whoami/.vecocore/veco.conf
rpcuser=$user
rpcpassword=$password
rpcallowip=127.0.0.1
listen=1
server=1
daemon=1
maxconnections=24
masternode=1
masternodeprivkey=$key
externalip=$ip
addnode=51.15.202.138
addnode=163.172.179.150
addnode=51.15.246.208
addnode=51.158.68.234
addnode=51.15.104.11
addnode=51.15.104.1
addnode=51.15.127.13
addnode=51.15.82.37
EOF
chown -R $whoami:$whoami /home/$whoami

# Install Veco Daemon
echo 'Downloading daemon...'
cd
wget https://github.com/VecoOfficial/Veco/releases/download/v1.0.0/vecoCore-1.0.0-linux64-cli.Ubuntu16.04.tar.gz
tar xvzf vecoCore-1.0.0-linux64-cli.Ubuntu16.04.tar.gz
chmod -R 755 veco
cp veco/vecod /usr/bin/
cp veco/veco-cli /usr/bin/
cp veco/veco-tx /usr/bin/
rm -rf veco

# Run vecod as selected user
sudo -H -u $whoami bash -c 'vecod'

echo 'Veco Core prepared and launched...'

sleep 10

# Setting up sentinel
decho "Setting up sentinel..."

# Install sentinel
echo 'Downloading sentinel...'
git clone https://github.com/VecoOfficial/sentinel.git /home/$whoami/sentinel
chown -R $whoami:$whoami /home/$whoami/sentinel

echo 'Setting up sentinel...'
cd /home/$whoami/sentinel
sudo -H -u $whoami bash -c 'virtualenv ./venv'
sudo -H -u $whoami bash -c './venv/bin/pip install -r requirements.txt'

# Deploy script to keep daemon alive
cat << EOF > /home/$whoami/vecodkeepalive.sh
until vecod; do
    echo "Vecod crashed with error $?.  Restarting.." >&2
    sleep 1
done
EOF

chmod +x /home/$whoami/vecodkeepalive.sh
chown $whoami:$whoami /home/$whoami/vecodkeepalive.sh

# Setup crontab
echo "@reboot sleep 30 && /home/$whoami/vecodkeepalive.sh" >> newCrontab
echo "* * * * * cd /home/$whoami/sentinel && ./venv/bin/python bin/sentinel.py >/dev/null 2>&1" >> newCrontab
crontab -u $whoami newCrontab
rm newCrontab

# Final Masternode instructions
decho "Starting your Masternode"
echo ""
echo "To start your Masternode please follow the steps below:"
echo "1 - In your VPS terminal, use command 'veco-cli mnsync status' and wait for AssetID: to be 999" 
echo "2 - In your wallet, select 'Debug Console' from the Tools menu"
echo "3 - In the Debug Console type the command 'masternode outputs' (these outputs will be used in Masternode Configuration File)" 
echo "4 - In your wallet, select 'Open Masternode Configuration File' from the Tools menu"
echo "5 - Following the example, enter the required details on a new line (without #) and save the file"
echo "6 - In your wallet, click 'Reload Config' from the 'Masternodes' tab"
echo "7 - Select your Masternode and click 'Start alias'"
echo "8 - In your VPS terminal, use command 'veco-cli masternode status' and you should see your Masternode was successfully started"
echo ""
decho "If you have any issues, please get in contact with the Veco Developers on Discord (https://discord.gg/Z7j9mz6)" 


su $whoami
