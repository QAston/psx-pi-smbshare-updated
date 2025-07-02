#!/bin/bash

# Share usb Eth with Eth device
#
#
# This script is created to work with Raspbian Stretch
# but it can be used with most of the distributions
# by making few changes.
#
# Make sure you have already installed `dnsmasq`
# Please modify the variables according to your need
# Don't forget to change the name of network interface
# Check them with `ifconfig`

ip_address="192.168.3.1"
netmask="255.255.255.0"
dhcp_range_start="192.168.3.2"
dhcp_range_end="192.168.3.100"
dhcp_time="12h"
eth="enx00e04c691055" # usb eth dongle to ps3
wlan="enx00e04c680953" # usb eth dongle to wlan

sudo systemctl start network-online.target &> /dev/null

# remove rules for all chains, resets settings
sudo iptables -F
# remove all nat table rules
sudo iptables -t nat -F
# The `-A POSTROUTING` option specifies that this rule is being appended to the POSTROUTING chain. The POSTROUTING chain is used to alter packets as they are about to leave the network interface.
# The `-j MASQUERADE` target tells `iptables` to perform masquerading on the packets.
# Masquerading is a form of NAT that allows the source IP address of outgoing packets to be replaced with the IP address of the outgoing interface.
# This is particularly useful in scenarios where the local network is using private IP addresses and needs to communicate with external networks, such as the internet.
# By using this command, the script effectively enables devices on the local network to access external networks while hiding their private IP addresses.
sudo iptables -t nat -A POSTROUTING -o $wlan -j MASQUERADE
# The `-A FORWARD` option specifies that this rule is being appended to the FORWARD chain. The FORWARD chain is used to control the forwarding of packets between different network interfaces.
# -m state --state RELATED,ESTABLISHED: This part of the command uses the state module to match packets based on their connection state. The RELATED state refers to packets that are part of an existing connection (like an FTP data transfer), while ESTABLISHED refers to packets that are part of a connection that has already been established. This means that the rule will allow forwarding of packets that are part of an ongoing session or are related to an existing connection.
# -j ACCEPT: This part of the command specifies the target action for matching packets. In this case, it tells `iptables` to accept the packets that match the criteria defined in the rule.
sudo iptables -A FORWARD -i $wlan -o $eth -m state --state RELATED,ESTABLISHED -j ACCEPT
# The `-A FORWARD` option specifies that this rule is being appended to the FORWARD chain. The FORWARD chain is used to control the forwarding of packets between different network interfaces.
sudo iptables -A FORWARD -i $eth -o $wlan -j ACCEPT

# enable IP forwarding for all interfaces
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

sudo ifconfig $eth $ip_address netmask $netmask

# Remove default route created by dhcpcd
sudo ip route del 0/0 dev $eth &> /dev/null

sudo systemctl stop dnsmasq

sudo rm -rf /etc/dnsmasq.d/*

echo -e "interface=$eth\n\
bind-dynamic\n\
server=1.1.1.1\n\
domain-needed\n\
bogus-priv\n\
dhcp-range=$dhcp_range_start,$dhcp_range_end,$dhcp_time" > /etc/dnsmasq.d/custom-dnsmasq.conf

sudo systemctl start dnsmasq