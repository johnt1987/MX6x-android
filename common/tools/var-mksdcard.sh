#!/bin/bash

# android-tools-fsutils should be installed as
# "sudo apt-get install android-tools-fsutils"

# partition size in MB
BOOTLOAD_RESERVE=8
BOOT_ROM_SIZE=16
SYSTEM_ROM_SIZE=512
CACHE_SIZE=512
RECOVERY_ROM_SIZE=16
DEVICE_SIZE=8
MISC_SIZE=6
DATAFOOTER_SIZE=2

help() {

bn=`basename $0`
cat << EOF
usage $bn <option> device_node

options:
  -h				displays this help message
  -s				only get partition size
  -np 				not partition.
  -f soc_name			flash android image.
EOF

}

# parse command line
moreoptions=1
node="na"
soc_name=""
cal_only=0
flash_images=0
not_partition=0
not_format_fs=0
built_images_folder="out/target/product/var_mx6"
spl_file="SPL-var-imx6-sd"
bootloader_file="u-boot-var-imx6-sd.img"
bootimage_file="boot.img"
systemimage_file="system.img"
systemimage_raw_file="system_raw.img"
recoveryimage_file="recovery.img"
while [ "$moreoptions" = 1 -a $# -gt 0 ]; do
	case $1 in
	    -h) help; exit ;;
	    -s) cal_only=1 ;;
	    -f) flash_images=1 ; soc_name=$2; shift;;
	    -np) not_partition=1 ;;
	    -nf) not_format_fs=1 ;;
	    *)  moreoptions=0; node=$1 ;;
	esac
	[ "$moreoptions" = 0 ] && [ $# -gt 1 ] && help && exit
	[ "$moreoptions" = 1 ] && shift
done

if [ "${node}" = "/dev/sda" ]; then
        echo "====== dangerous!"
        exit
fi

if [ ! -e ${node} ]; then
	echo "no such node ${node}"
	help
	exit
fi

part=""
echo ${node} | grep mmcblk > /dev/null
if [ "$?" -eq "0" ]; then
	part="p"
fi

# call sfdisk to create partition table
# get total card size
seprate=40
total_size=`sfdisk -s ${node}`
total_size=`expr ${total_size} / 1024`
boot_rom_sizeb=`expr ${BOOT_ROM_SIZE} + ${BOOTLOAD_RESERVE}`
extend_size=`expr ${SYSTEM_ROM_SIZE} + ${CACHE_SIZE} + ${DEVICE_SIZE} + ${MISC_SIZE} + ${DATAFOOTER_SIZE} + ${seprate}`
data_size=`expr ${total_size} - ${boot_rom_sizeb} - ${RECOVERY_ROM_SIZE} - ${extend_size} + ${seprate}`

echo "total_size $total_size"
echo "boot_rom_sizeb $boot_rom_sizeb"
echo "extend_size $extend_size"
echo "data_size $data_size"

# create partitions
if [ "${cal_only}" -eq "1" ]; then
cat << EOF
BOOT   : ${boot_rom_sizeb}MB
RECOVERY: ${RECOVERY_ROM_SIZE}MB
SYSTEM : ${SYSTEM_ROM_SIZE}MB
CACHE  : ${CACHE_SIZE}MB
DATA   : ${data_size}MB
MISC   : ${MISC_SIZE}MB
DEVICE : ${DEVICE_SIZE}MB
DATAFOOTER : ${DATAFOOTER_SIZE}MB
EOF
exit
fi

function umount_android
{
    echo "unmountig android partitions"
    umount ${node}${part}9
    umount ${node}${part}8
    umount ${node}${part}7
    umount ${node}${part}6
    umount ${node}${part}5
    umount ${node}${part}4
    umount ${node}${part}3
    umount ${node}${part}2
    umount ${node}${part}1
}

function format_android
{
    echo "formatting android partitions"
    mkfs.ext4 ${node}${part}4 -Ldata
    mkfs.ext4 ${node}${part}5 -Lsystem
    mkfs.ext4 ${node}${part}6 -Lcache
    mkfs.ext4 ${node}${part}7 -Ldevice
}

function flash_android
{
    bootimage_file="boot-${soc_name}.img"
    recoveryimage_file="recovery-${soc_name}.img"
if [ "${flash_images}" -eq "1" ]; then
    cd ${built_images_folder}
    echo "flashing android images..."
    dd if=/dev/zero of=${node} bs=1k seek=384 count=129
    echo "spl: ${spl_file}"
    dd if=${spl_file} of=${node} bs=1k seek=1
    echo "bootloader: ${bootloader_file}"
    dd if=${bootloader_file} of=${node} bs=1k seek=69
    echo "boot image: ${bootimage_file}"
    dd if=${bootimage_file} of=${node}${part}1
    echo "recovery image: ${recoveryimage_file}"
    dd if=${recoveryimage_file} of=${node}${part}2
    echo "system image: ${systemimage_file}"
    simg2img ${systemimage_file} ${systemimage_raw_file}
    dd if=${systemimage_raw_file} of=${node}${part}5
    rm ${systemimage_raw_file}
    sync
    cd -
fi
}

if [[ "${not_partition}" -eq "1" && "${flash_images}" -eq "1" ]] ; then
    flash_android
    exit
fi

umount_android

echo "partitioning ${node}..."
sfdisk --force -uM ${node} << EOF
,${boot_rom_sizeb},83
,${RECOVERY_ROM_SIZE},83
,${extend_size},5
,${data_size},83
,${SYSTEM_ROM_SIZE},83
,${CACHE_SIZE},83
,${DEVICE_SIZE},83
,${MISC_SIZE},83
,${DATAFOOTER_SIZE},83
EOF

echo "adjust bootloader partition..."
# adjust the partition reserve for bootloader.
# if you don't put the uboot on same device, you can remove the BOOTLOADER_ERSERVE
# to have 8M space.
# the minimal sylinder for some card is 4M, maybe some was 8M
# just 8M for some big eMMC 's sylinder
sfdisk --force -uM ${node} -N1 << EOF
${BOOTLOAD_RESERVE},${BOOT_ROM_SIZE},83
EOF

sleep 10
umount_android

# format the SDCARD/DATA/CACHE partition
format_android
flash_android
