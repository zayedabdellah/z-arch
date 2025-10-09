#!/usr/bin/env bash

echo "Enter your EFI partition: ("/dev/sda1","/dev/nvme0n1p1")"
read EFI

echo "Enter your SWAP partition: ("/dev/sda2","/dev/nvme0n1p2")"
read SWAP

echo "Enter your root(/) paritition: ("/dev/sda3","/dev/nvme0n1p3")"
read ROOT  

echo "Please enter your Username:"
read USER 

echo "Please enter your Password"
read PASSWORD

echo "Enter your root password:"
read ROOT_PASSWORD

echo "Please enter your hostname:"
read HOSTNAME

echo "Choose Bootloader"
echo "1. Systemd-boot"
echo "2. GRUB"
read -p "Enter your choice: " BOOT

if [[ "$BOOT" != 2 ]]; then
    BOOT=1
fi

# make filesystems
echo -e "\nCreating Filesystems...\n"

existing_fs=$(blkid -s TYPE -o value "$EFI")
if [[ "$existing_fs" != "vfat" ]]; then
    mkfs.fat -F32 "$EFI"
    mkswap "$SWAP"
    swapon "$SWAP"
fi

mkfs.ext4 "${ROOT}"

# mount target
mount "${ROOT}" /mnt
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
if [[ $BOOT == 1 ]]; then
    mount --mkdir "$EFI" /mnt/boot
else
    mount --mkdir "$EFI" /mnt/boot/efi
fi

echo "--------------------------------------"
echo "-- INSTALLING Base Arch Linux --"
echo "--------------------------------------"
pacman-key --init
pacman-key --populate archlinux
reflector -c "SA" > /etc/pacman.d/mirrorlist
pacstrap /mnt base linux linux-firmware base-devel git nano bash-completion networkmanager fish fastfetch fzf tmux noto-fonts mpv ffmpeg yt-dlp

# fstab
genfstab -U /mnt > /mnt/etc/fstab

cat <<REALEND > /mnt/next.sh
echo root:$ROOT_PASSWORD | chpasswd
useradd -m -G wheel -s /bin/fish $USER
echo $USER:$PASSWORD | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

echo "-------------------------------------------------"
echo "Setup Language to US and set locale"
echo "-------------------------------------------------"
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#ar_AE.UTF-8 UTF-8/ar_AE.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

ln -sf /usr/share/zoneinfo/Asia/Dubai /etc/localtime
hwclock --systohc

echo $HOSTNAME > /etc/hostname

echo "-------------------------------------------------"
echo "Drivers"
echo "-------------------------------------------------"

pacman -S pipewire pipewire-alsa pipewire-pulse bluez bluez-tools bluez-utils --noconfirm --needed

systemctl enable NetworkManager bluetooth
systemctl --user enable pipewire pipewire-pulse

echo "--------------------------------------"
echo "-- Bootloader Installation  --"
echo "--------------------------------------"

if [[ $BOOT == 1 ]]; then
    bootctl install --path=/boot
    echo "default arch.conf" >> /boot/loader/loader.conf
    cat <<EOF > /boot/loader/entries/arch.conf
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options root=UUID=$ROOT_UUID rw quiet
EOF
else
    pacman -S grub efibootmgr --noconfirm --needed
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id="sigma"
    grub-mkconfig -o /boot/grub/grub.cfg
fi

echo "-------------------------------------------------"
echo "Install Complete, You can reboot now"
echo "-------------------------------------------------"
REALEND

arch-chroot /mnt sh next.sh && rm /mnt/next.sh

