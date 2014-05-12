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

echo "BiblioBox is now uninstalled!"

exit 0
