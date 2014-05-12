#!/bin/sh

# first of all, check script is launched by root
if [ "root" != "$(whoami)" ]; then
    echo "ERROR - you must be root to execute this script"
    exit 1
fi

echo -n "Do you want to uninstall bibliobox? (y/n): "
read answer

if [ "y" != "$answer" ]; then
    exit 0
fi

# stop and remove piratebox service
/etc/init.d/piratebox stop
update-rc.d piratebox remove
rm -rf /etc/init.d/piratebox

# umount usb stick
umount /opt/piratebox/share

# remove piratebox files
rm -rf /opt/piratebox

# uninstall hostapd
[ ! -L /usr/sbin/hostapd ] || rm -f /usr/sbin/hostapd
[ ! -f /usr/sbin/hostapd.edimax ] || rm -f /usr/sbin/hostapd.edimax
[ -f /usr/sbin/hostapd.original ] && mv /usr/sbin/hostapd.original /usr/sbin/hostapd

echo "BiblioBox is now uninstalled!"

reboot

exit 0
