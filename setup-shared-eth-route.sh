#!/bin/bash

# Share usb Eth with Eth device using NetworkManager and dnsmasq plugin

eth="enx00e04c691055" # usb eth dongle to ps3
wlan="enx00e04c680953" # usb eth dongle to wlan

sudo systemctl stop NetworkManager

# created using
#sudo nmcli con add type ethernet ifname $wlan con-name wlan
#sudo nmcli con add type ethernet ifname $eth con-name ps3-eth
#sudo nmcli con modify ps3-eth ipv4.method shared
#sudo nmcli con up ps3-eth
sudo cat <<EOF | sudo tee /etc/NetworkManager/system-connections/ps3-eth.nmconnection
[connection]
id=ps3-eth
uuid=8664a759-324b-4184-ad42-ce22e5b467ab
type=ethernet
interface-name=${eth}
timestamp=1751488651

[ethernet]

[ipv4]
method=shared

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOF

sudo cat <<EOF | sudo tee /etc/NetworkManager/conf.d/00-use-dnsmasq.conf
# /etc/NetworkManager/conf.d/00-use-dnsmasq.conf
#
# This enabled the dnsmasq plugin.
[main]
dns=dnsmasq
EOF


# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

sudo cat <<'EOF' | sudo tee /etc/sysctl.d/10-forward.conf
net.ipv4.ip_forward=1
EOF

sudo nmcli con up ps3-eth

sudo systemctl restart NetworkManager

echo "Network configuration updated to use NetworkManager with dnsmasq plugin."
