#!/bin/bash

#------------------------------------------------------------------------------
# TODO: add explanations
#
#
#------------------------------------------------------------------------------

# print message then exit with error
die()
{
    echo "$1"
    exit 1
}

#------------------------------------------------------------------------------

# default hostapt wifi driver
HOSTAPD_DRIVER=nl80211

# first of all, check script is launched by root
if [ "root" != "$(whoami)" ]; then
    echo "ERROR - you must be root to execute this script"
    exit 1
fi

#------------------------------------------------------------------------------
#
# DO PREREQUISITE STUFF
#
#------------------------------------------------------------------------------

# check everything is installed on the Rpi
echo -n "checking packages..."
for f in /usr/sbin/lighttpd /usr/sbin/dnsmasq /usr/sbin/hostapd \
         /sbin/iw /usr/sbin/proftpd /usr/bin/php-cgi \
         /usr/lib/php5/20100525+lfs/sqlite3.so; do

    [ -f $f ] || die "ERROR - $f is not correctly installed"

done
echo "done"

# check usb wireless adapter
echo -n "insert your usb wireless adapter and press Enter..."
read foo

if [ -n "$(lsusb | grep RTL8188CUS)" ]; then

    # we are using EDIMAX Wifi device

    if [ ! -f /usr/sbin/hostapd.edimax ]; then

        # download and install specific hostapd file
        # cf. http://willhaley.com/blog/raspberry-pi-hotspot-ew7811un-rtl8188cus

        echo -n "installing specific hostapd binary for Edimax Wireless Adapter..."
        wget http://dl.dropbox.com/u/1663660/hostapd/hostapd.zip > /dev/null
        if [ 0 -ne $? ]; then
            echo "ERROR - cannot download http://dl.dropbox.com/u/1663660/hostapd/hostapd.zip"
            exit 1
        fi

        unzip hostapd.zip > /dev/null
        [ 0 -ne $? ] && die "ERROR - cannot unzip hostapd.zip"

        mv /usr/sbin/hostapd /usr/sbin/hostapd.original && \
        mv hostapd /usr/sbin/hostapd.edimax && \
        ln -sf /usr/sbin/hostapd.edimax /usr/sbin/hostapd && \
        chown root:root /usr/sbin/hostapd && \
        chmod 755 /usr/sbin/hostapd
        [ 0 -ne $? ] && die "ERROR - cannot install hostapd binary"

        echo done
    fi

    # we will use rtl871xdrv driver with hostapd
    HOSTAPD_DRIVER=rtl871xdrv
fi

#------------------------------------------------------------------------------
#
# BUILD LIBRARYBOX FROM GIT SOURCE
#
#------------------------------------------------------------------------------

# download library-core files
echo -n "downloading LibraryBox-Dev archive..."

wget https://github.com/LibraryBox-Dev/LibraryBox-core/archive/master.zip
[ 0 -ne $? ] && die "ERROR - cannot download LibraryBox files"

# unzip archive
unzip master.zip > /dev/null
[ 0 -ne $? ] && die "ERROR - cannot unzip LibraryBox files"

echo "done"

parent=$(pwd)

cd LibraryBox-core-master

# generate librarybox filesystem into build_dir directory
make image
[ 0 -ne $? ] && cd $parent && die "ERROR - cannot unzip LibraryBox filesystem"

#-----------------------------------
# customize generated filesystem
#-----------------------------------

# change ssid in hostapd.conf
echo -n "Enter your librarybox ssid: "
read ssid
sed -i 's#^ssid=.*$#ssid='"$ssid"'#' build_dir/piratebox/conf/hostapd.conf

# change driver in hostapd
sed -i 's#^driver=.*$#driver='"$HOSTAPD_DRIVER"'#' build_dir/piratebox/conf/hostapd.conf
# change tmp cleaning command in piratebox script
sed -i 's#^[[:space:]]*find[[:space:]]\+$PIRATEBOX/tmp/[[:space:]]\+-exec rm {} \\;[[:space:]]*$#    find $PIRATEBOX/tmp/* -exec rm {} \\;#' build_dir/piratebox/init.d/piratebox
# disable IPV6 support
sed -i 's#^IPV6_ENABLE=.*$#IPV6_ENABLE="no"#' build_dir/piratebox/conf/ipv6.conf
sed -i 's/^\(\$SERVER\["socket"\].*\)$/#\1/' build_dir/piratebox/conf/lighttpd/lighttpd.conf
echo 'server.use-ipv6="disable"' >> build_dir/piratebox/conf/lighttpd/lighttpd.conf

cd $parent

#---------------------------------
# deploy librarybox filesystem
#---------------------------------
if [ -d /opt/piratebox ]; then

    # save old piratebox directory
    echo -n "moving /opt/piratebox to /opt/piratebox.original..."
    mv /opt/piratebox /opt/piratebox.original
    echo done
fi

# copy filesystem and modify permissions in order to let lighttpd
# work on some directories
cp -rf LibraryBox-core-master/build_dir/piratebox /opt/piratebox
chown -R root:root /opt/piratebox
chown -R nobody:nogroup /opt/piratebox/tmp
chown -R nobody:nogroup /opt/piratebox/www

#---------------------------------
# prepare usb stick content
#---------------------------------
echo -n "do you want to prepare a new usb stick that will contain librarybox files? (y/n) ?"
read answer
while [ "$answer" != "y" -a "$answer" != "n" ]; do
    echo -n "do you want to prepare a new usb stick that will contain librarybox files? (y/n) ?"
    read answer
done

if [ "$answer" == "y" ]; then

    # we need to know the device
    echo -n "insert the usb stick and press Enter: "
    read foo

    # we will loop until valid usb device is entered
    usb=""
    while [ -z "$usb" ]; do

        # display disks to operator
        fdisk -l

        # ask about usb device
        echo -n "what is the usb device that will contain librarybox files (eg. /dev/sdaX) ?: "
        read usb

        # try to read information on device
        blkid $usb
        [ 0 == $? ] || usb=""

    done

    # read usb device uuid
    UUID=$(blkid $usb | grep -o 'UUID="[^"]\+"' | sed 's#^UUID="\([^"]\+\)"$#\1#')
    [ -n "$UUID" ] || die "ERROR - cannot get usb device $usb UUID"

    # read usb device type
    TYPE=$(blkid $usb | grep -o 'TYPE="[^"]\+"' | sed 's#^TYPE="\([^"]\+\)"$#\1#')
    [ -n "$TYPE" ] || die "ERROR - cannot get usb device $usb TYPE"

    # update /etc/fstab
    grep "$UUID" /etc/fstab >> /dev/null
    if [ 0  -ne $? ]; then

        echo "# automatically mount usb device on /opt/piratebox/share" >> /etc/fstab
        echo "UUID=$UUID    /opt/piratebox/share    $TYPE    rw,user,auto,gid=65534,uid=65534    0   0" >> /etc/fstab
    fi

    # try to mount usb device
    mount $usb
    [ 0 -ne $? ] && die "ERROR - cannot mount $usb"

    if [ -d /opt/piratebox/share/content ]; then
        mv /opt/piratebox/share/content /opt/piratebox/share/content.original
    fi
    cp -Rf /opt/piratebox/www_content /opt/piratebox/share/content
    rm -rf /opt/piratebox/www_content

    [ -d /opt/piratebox/share/Shared ] || mkdir /opt/piratebox/share/Shared
    [ -d /opt/piratebox/share/Shared/audio ] || mkdir /opt/piratebox/share/Shared/audio
    [ -d /opt/piratebox/share/Shared/software ] || mkdir /opt/piratebox/share/Shared/software
    [ -d /opt/piratebox/share/Shared/text ] || mkdir /opt/piratebox/share/Shared/text
    [ -d /opt/piratebox/share/Shared/video ] || mkdir /opt/piratebox/share/Shared/video

    # remount usb device
    umount /opt/piratebox/share
    mount $usb

fi

# do final stuff
[ -L /opt/piratebox/init.d/piratebox ] || ln -sf /opt/piratebox/init.d/piratebox /etc/init.d/piratebox
update-rc.d piratebox defaults
/etc/init.d/piratebox start

exit 0

