#!/bin/bash

#
# psx-pi-smbshare setup script
#
# *What it does*
# This script will install and configure an smb share at /share
# It will also compile ps3netsrv from source to allow operability with PS3/Multiman
# It also configures the pi ethernet port to act as dhcp server for connected devices and allows those connections to route through wifi on wlan0
# Finally, XLink Kai is installed for online play.
#
# *More about the network configuration*
# This configuration provides an ethernet connected PS2 or PS3 a low-latency connection to the smb share running on the raspberry pi
# The configuration also allows for outbound access from the PS2 or PS3 if wifi is configured on the pi
# This setup should work fine out the box with OPL and multiman
# Per default configuration, the smbserver is accessible on 192.168.2.1


USER=`whoami`

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Make sure we're not root otherwise the paths will be wrong
if [ $USER = "root" ]; then
  echo "Do not run this script as root or with sudo"
  exit 1
fi

if whiptail --yesno "Would you like to enable ps3netsrv for PS3 support? (SMB is enabled either way for PS2 support etc.)" 8 55; then
  PS3NETSRV=true
else
  PS3NETSRV=false
fi

if whiptail --yesno "Would you like to share wifi over ethernet, for devices without wifi? (Ethernet will no longer work for providing the pi an internet connection)" 9 55; then
  ETHROUTE=true
else
  ETHROUTE=false
fi

# Update packages
sudo apt-get -y update
sudo apt-get -y upgrade

# Ensure basic tools are present
sudo apt-get -y install screen wget git curl coreutils iptables hostapd

# Install and configure Samba
sudo apt-get install -y samba samba-common-bin
sed -i "s/userplaceholder/${USER}/g" ${SCRIPT_DIR}/samba-init.sh
chmod 755 ${SCRIPT_DIR}/samba-init.sh
sudo cp ${SCRIPT_DIR}/samba-init.sh /usr/local/bin
sudo mkdir -m 1777 /share

# Install ps3netsrv if PS3NETSRV is true
if [ "$PS3NETSRV" = true ]; then
  sudo rm /usr/local/bin/ps3netsrv++
  sudo apt-get install -y git gcc
  git clone https://github.com/dirkvdb/ps3netsrv--.git
  cd ps3netsrv--
  git submodule update --init
  make CXX=g++
  sudo cp ps3netsrv++ /usr/local/bin
fi

if [ "$ETHROUTE" = true ]; then
  # Install wifi-to-eth route settings
  sudo apt-get install -y dnsmasq
  bash ${SCRIPT_DIR}/setup-shared-eth-route.sh
fi

# Install USB automount settings
bash ${SCRIPT_DIR}/setup-automount-usb.sh

# Not a bad idea to reboot
sudo reboot
