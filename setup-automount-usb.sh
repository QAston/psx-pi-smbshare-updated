#!/bin/bash

#
# psx-pi-smbshare automout-usb script
#
# *What it does*
# This script configures raspbian to automount any usb storage to /media/sd<xy>
# This allows for use of USB & HDD in addition to Micro-SD
# It also creates a new Samba configuration which exposes the last attached USB drive @ //SMBSHARE/<PARTITION>

USER=`whoami`

# Update packages
#sudo apt-get update

# Install NTFS Read/Write Support and udisks2
sudo apt-get install -y ntfs-3g udisks2

# Add user to disk group
sudo usermod -a -G disk ${USER}

# Create polkit rule
sudo mkdir -p /etc/polkit-1/rules.d/
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d/

# For polkit > 105
sudo cat <<'EOF' | sudo tee /etc/polkit-1/rules.d/10-udisks2.rules
// Allow udisks2 to mount devices without authentication
// for users in the "disk" group.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.freedesktop.udisks2.filesystem-mount-system" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount" ||
         action.id == "org.freedesktop.udisks2.filesystem-mount-other-seat") &&
        subject.isInGroup("disk")) {
        return polkit.Result.YES;
    }
});
EOF

# For polkit <= 105
sudo cat <<'EOF' | sudo tee /etc/polkit-1/localauthority/50-local.d/10-udisks2.pkla
[Authorize mounting of devices for group disk]
Identity=unix-group:disk
Action=org.freedesktop.udisks2.filesystem-mount-system;org.freedesktop.udisks2.filesystem-mount;org.freedesktop.udisks2.filesystem-mount-other-seat
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

# Create udev rules:
# 1. binds usbstick-handler@.service to the add event of a usb device (both add and removal due to BindsTo=dev-%i.device)
# 2. triggers rerunning usbstick-cleanup@.service when a usb device is removed
sudo cat <<'EOF' | sudo tee /etc/udev/rules.d/usbstick.rules
ACTION=="add", KERNEL=="sd[a-z][0-9]", SUBSYSTEM=="block", TAG+="systemd", ENV{SYSTEMD_WANTS}="usbstick-handler@%k"
ACTION=="remove", ENV{DEVTYPE}=="usb_device", SUBSYSTEM=="usb", RUN+="/bin/systemctl --no-block restart usbstick-cleanup@%k.service"
EOF

# Scripts to trigger on creation and destruction of the device
sudo cat <<'EOF' | sudo tee /lib/systemd/system/usbstick-handler@.service
[Unit]
Description=Mount USB sticks
BindsTo=dev-%i.device
After=dev-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/automount.sh %I
ExecStop=/usr/bin/udisksctl unmount -b /dev/%I
EOF

# script for cleanup of samba after usb removal, sets the state when no usb is connected
sudo cat <<'EOF' | sudo tee /usr/local/bin/samba-init.sh
#!/bin/bash
#If a USB drive is present, do not initialize the samba share
USBDisk_Present=`sudo fdisk -l | grep /dev/sd`
if [ -n "${USBDisk_Present}" ]
then
    echo "exited to due to presence of USB storage"
    exit
fi

#if /usr/local/bin/ps3netsrv++ exists
if [ -f /usr/local/bin/ps3netsrv++ ]; then
  #restart ps3netsrv++
  pkill ps3netsrv++
  /usr/local/bin/ps3netsrv++ -d /share
fi

sudo cat <<'EOS' | sudo tee /etc/samba/smb.conf
[global]
server min protocol = NT1
workgroup = WORKGROUP
usershare allow guests = yes
map to guest = bad user
allow insecure wide links = yes
[share]
Comment = shared folder
Path = /share
Browseable = yes
Writeable = Yes
only guest = no
create mask = 0777
directory mask = 0777
Public = yes
Guest ok = yes
force user = userplaceholder
follow symlinks = yes
wide links = yes
EOS

#if you wish to create a samba user with password you can use the following:
#sudo smbpasswd -a userplaceholder
sudo /etc/init.d/smbd restart
EOF

sudo sed -i "s/userplaceholder/${USER}/g" /usr/local/bin/samba-init.sh
sudo chmod a+x /usr/local/bin/samba-init.sh

sudo cat <<'EOF' | sudo tee /lib/systemd/system/usbstick-cleanup@.service
[Unit]
Description=Cleanup USB sticks
BindsTo=dev-%i.device

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/samba-init.sh
EOF

# Configure script to run when an automount event is triggered
sudo cat <<'EOF' | sudo tee /usr/local/bin/automount.sh
#!/bin/bash

PART=$1
if [ -z ${PART} ]
then
	echo "Missing PART, exiting" >&2
    exit
fi

UUID=`blkid /dev/${PART} -o value -s UUID`
if [ -z ${UUID} ]
then
	echo "Missing UUID for /dev/${PART}, exiting" >&2
	exit
fi

FS_LABEL=`lsblk -o name,label | grep ${PART} | awk '{print $2}'`

if [[ "$FS_LABEL" == PS2SMB* ]]
then
    echo "found $FS_LABEL"
else
	echo "Missing PART, exiting" >&2
    exit
fi

for attempt in $(seq 1 10); do
    mount_output=$(runuser userplaceholder -s /bin/bash -c "udisksctl mount -b /dev/${PART} --no-user-interaction" 2>&1)
    mount_status=$?
    FS_PATH=`lsblk -o name,mountpoints | grep ${PART} | awk '{print $2}'`
    if [ -n "${FS_PATH}" ]; then
        break
    fi
    if [ "${mount_status}" -ne 0 ]; then
        echo "Mount attempt ${attempt} failed: ${mount_output}" >&2
    else
		echo "Mount attempt ${attempt} succeeded but mount point not found." 
	fi
    sleep 1
done

if [ -z "${FS_PATH}" ]; then
    echo "Failed to mount /dev/${PART}: ${mount_output}" >&2
    exit 1
fi

if [ -f /usr/local/bin/ps3netsrv++ ]; then
    pkill ps3netsrv++
    /usr/local/bin/ps3netsrv++ -d ${FS_PATH}
fi

#todo: multidrive support: https://gist.github.com/meetnick/fb5587d25d4174d7adbc8a1ded642d3c
#create a new smb share for the mounted drive
cat <<EOS | sudo tee /etc/samba/smb.conf
[global]
	browseable = yes
	deadtime = 30
	domain master = yes
	encrypt passwords = true
	enable core files = no
	guest account = userplaceholder
	guest ok = yes
	invalid users = root
	local master = yes
	load printers = no
	map to guest = bad user
	server min protocol = NT1
	max protocol = SMB2
	min receivefile size = 16384
	null passwords = yes
	obey pam restrictions = yes
	os level = 20
	preferred master = yes
	printable = no
	smb encrypt = disabled
	socket options = TCP_NODELAY IPTOS_LOWDELAY
	syslog = 2
	use sendfile = yes
	writeable = yes
	getwd cache = yes
	follow symlinks = yes
	wide links = yes
	only guest = no
	create mask = 0777
	directory mask = 0777
	Public = yes
	Guest ok = yes
	force user = userplaceholder
	#log level = 3 auth_audit:3 auth_json_audit:3
    #log file = /var/log/smb1.log

[GL-Samba2]
	path = pathplaceholder/MZ
	read only = no
	guest ok = yes

[GL-Samba1]
	path = pathplaceholder/AL
	read only = no
	guest ok = yes
EOS

#if you wish to create a samba user with password you can use the following:
#sudo smbpasswd -a userplaceholder
sudo sed -i "s:pathplaceholder:${FS_PATH}:g" /etc/samba/smb.conf
sudo /etc/init.d/smbd restart
EOF

sudo sed -i "s/userplaceholder/${USER}/g" /usr/local/bin/automount.sh

# Make script executable
sudo chmod a+x /usr/local/bin/automount.sh

# Reload udev rules and triggers
sudo udevadm control --reload-rules && sudo udevadm trigger
