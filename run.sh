#!/bin/bash

init_image() {
	dd if=/dev/zero of="$IMAGE" bs=1M count=$SIZE_MIB status=progress
}

IMAGE="image1"
#SIZE_MIB=22000
SIZE_MIB=4000
MOUNT_DIR="/tmp/usb"
LABEL3="1"

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "Selected image file: $IMAGE"
echo "Selected image size: $SIZE_MIB"

if [ -f "$IMAGE" ]; then
	echo "Image file found!"
	
	actualsize=$(wc -c < "$IMAGE")
	if [ $actualsize -eq $((SIZE_MIB * 1024 * 1024)) ]; then
		echo "Image size is equal!"
		echo "Exiting!"
	else
		echo "Image size is not equal!"
		echo "Overwriting image!"

		init_image
	fi
else
	echo "Image not found!"
	echo "Creating image!"

	init_image
fi

echo

echo "Setup loop device $LOOP"
#if ! losetup "$LOOP" "$IMAGE"; then
if ! losetup -fP "$IMAGE"; then
	echo "Unable to set up loop device $LOOP!"
	exit 1
fi

#Get loop device name
LOOP=$(losetup -a | grep -i -m1 "$IMAGE" | cut -d':' -f1)

echo "Selected loop device: $LOOP"

#Partition image

#Input format:
#   <start>, <size>, <type>, <bootable>
#
#   <start>  Beginning of the partition in sectors, or bytes if
#            specified in the format <number>{K,M,G,T,P,E,Z,Y}.
#            The default is the first free space.
#
#   <size>   Size of the partition in sectors, or bytes if
#            specified in the format <number>{K,M,G,T,P,E,Z,Y}.
#            The default is all available space.
#
#   <type>   The partition type.  Default is a Linux data partition.
#            MBR: hex or L,S,E,X shortcuts.
#            GPT: UUID or L,S,H shortcuts.
#
#   <bootable>  Use '*' to mark an MBR partition as bootable.
#
# Example:
#   , 4G     Creates a 4GiB partition at default start offset.
#

#First partition is in FAT32, it will be the partition of data (it could also be NTFS, ext, or any other filesystem) (data partition on it that could be used by (almost) any computer, mostly to store some portable apps, just in case)
#
#Second  partition is an EFI partition (based on FAT) and must be bootable and around 150M
#
#Last partition is with the iso, and must be bootable and in FAT32 (if you use ext2, if will boot, but you wont be able to use persistence
#sfdisk "$LOOP" << EOF
#, 4G,   c,   ,
#, 150M, ef, *,
#;     , c,  *
#EOF

fdisk image1 << EOF
o
n
p


+256MB
n
p


+256MB
n
p



t
1
c
t
2
ef
t
3
83
a
1
a
2
w
EOF

echo "partprobe $LOOP"
partprobe "$LOOP"

#Create filesystem on partitions
#sudo mkfs.fat -F32 "${LOOP}p1"
sudo mkdosfs -F16 "${LOOP}p1"
#sudo mkfs.vfat "${LOOP}p2"
sudo mkdosfs -F16 "${LOOP}p2"
#sudo mkfs.fat -F32 "${LOOP}p3"
sudo mkfs.xfs -f "${LOOP}p3"

#Label parition 3
#sfdisk --part-label "$LOOP" 3 "$LABEL3"
xfs_admin -L "$LABEL3" "${LOOP}p3"

#Mount the partitions
mkdir -pv "${MOUNT_DIR}"/{p1,p2,p3}
sudo mount "${LOOP}p1" "${MOUNT_DIR}/p1/"
sudo mount "${LOOP}p2" "${MOUNT_DIR}/p2/"
sudo mount "${LOOP}p3" "${MOUNT_DIR}/p3/"

#Install Grub
sudo yum -y install grub2 grub2-efi-modules
sudo grub2-install --boot-directory="${MOUNT_DIR}/p1/boot" --target=i386-pc "${LOOP}"
sudo grub2-install --boot-directory="${MOUNT_DIR}/p2/boot" --target=x86_64-efi --efi-directory "${MOUNT_DIR}/p2/boot" --removable "${LOOP}" 

sudo cp grub.cfg "${MOUNT_DIR}/p1/boot/grub2/grub.cfg"

#Create subfolder for syslinux
sudo mkdir -p "${MOUNT_DIR}/p1/syslinux"
sudo cp vesamenu.c32 "${MOUNT_DIR}/p1/syslinux/vesamenu.c32"
#Copy and rename
sudo cp isolinux.cfg "${MOUNT_DIR}/p1/syslinux/syslinux.cfg"
#Need to umount before syslinux installation
sudo umount "${MOUNT_DIR}/p1"
sudo syslinux --install "${LOOP}p1" --directory "syslinux"

sudo mount "${LOOP}p1" "${MOUNT_DIR}/p1/"



cp -rf source/images/ "${MOUNT_DIR}/p3/"
cp -rf source/.treeinfo "${MOUNT_DIR}/p3/"

sudo rm ./image1.vmdk
sudo VBoxManage internalcommands createrawvmdk -filename ./image1.vmdk -rawdisk "${LOOP}"
#sudo umount /tmp/usb/p{,1,2,3}; sudo losetup -d /dev/loop0; rm -f image1

exit 1






#Install grub on the two partitions (EFI and non-EFI)

#Be sure to have grub installed
#which grub-install
#	/usr/sbin/grub-install
#
#apt-file search "/usr/sbin/grub-install"
#	grub2-common: /usr/sbin/grub-install
#
#apt-file search "/usr/lib/grub/x86_64-efi/modinfo.sh"
#	grub-efi-amd64-bin: /usr/lib/grub/x86_64-efi/modinfo.sh
#
sudo apt-get install grub2-common grub-efi-amd64-bin

#Then, you need to install grub on the two partitions.
if ! grub-install -v --no-floppy --boot-directory="${MOUNT_DIR}/p3/" --target=i386-pc "${LOOP}"; then
	echo "grub-install failed!"
	exit 1
fi

if ! grub-install -v --no-floppy --boot-directory="${MOUNT_DIR}/p2/" --efi-directory="${MOUNT_DIR}/p2/" --removable --target=x86_64-efi "$LOOP"; then
	echo "grub-install failed!"
	exit 1
fi

#echo "Detach a loop device $LOOP"
#losetup -d "$LOOP"
