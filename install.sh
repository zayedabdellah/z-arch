#!/usr/bin/env bash

echo "Enter the target disk to format and partition (e.g. /dev/sda or /dev/nvme0n1):"
read DISK

echo "This will ERASE ALL DATA on $DISK. Are you absolutely sure? (yes/no)"
read CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Aborting."
    exit 1
fi

# Wipe disk and create new GPT table
echo "Wiping $DISK..."
wipefs -af "$DISK"
sgdisk -Z "$DISK"

echo "Enter EFI partition size (e.g. 512M):"
read EFI_SIZE

echo "Do you want a SWAP partition? (yes/no)"
read HAS_SWAP
if [[ "$HAS_SWAP" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    echo "Enter SWAP partition size (e.g. 2G):"
    read SWAP_SIZE
fi

echo "Use remaining space for ROOT partition? (yes/no)"
read USE_REMAINING
if [[ "$USE_REMAINING" =~ ^[Nn][Oo]$ ]]; then
    echo "Enter ROOT partition size (e.g. 20G):"
    read ROOT_SIZE
fi

echo "Please enter your Username:"
read USER 

echo "Please enter your Password:"
read PASSWORD

echo "Enter your root password:"
read ROOT_PASSWORD

echo "Please enter your hostname:"
read HOSTNAME

echo "Choose Bootloader"
echo "1. Systemd-boot"
echo "2. GRUB"
read -p "Enter your choice [1/2]: " BOOT
if [[ "$BOOT" != "2" ]]; then BOOT=1; fi

echo "Do you want to install yay (AUR helper)? [y/N]"
read INSTALL_YAY

echo "Choose a desktop environment:"
echo "1. GNOME"
echo "2. KDE Plasma"
echo "3. None"
read -p "Enter your choice [1/2/3]: " DESKTOP

# Partition disk
echo "Partitioning $DISK..."
fdisk "$DISK" <<EOF
g
n
1

+$EFI_SIZE
t
1
$( [[ "$HAS_SWAP" =~ ^[Yy][Ee]?[Ss]?$ ]] && echo "n\n2\n\n+$SWAP_SIZE\nt\n2\n19" )
n
$( [[ "$HAS_SWAP" =~ ^[Yy][Ee]?[Ss]?$ ]] && echo "3" || echo "2" )
$([[ "$USE_REMAINING" =~ ^[Yy][Ee]?[Ss]?$ ]] && echo "" || echo "+$ROOT_SIZE")
w
EOF

# Assign partition names
if [[ "$DISK" == *"nvme"* ]]; then
    EFI="${DISK}p1"
    if [[ "$HAS_SWAP" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        SWAP="${DISK}p2"
        ROOT="${DISK}p3"
    else
        ROOT="${DISK}p2"
    fi
else
    EFI="${DISK}1"
    if [[ "$HAS_SWAP" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
        SWAP="${DISK}2"
        ROOT="${DISK}3"
    else
        ROOT="${DISK}2"
    fi
fi

# Format partitions
echo -e "\nCreating Filesystems...\n"
mkfs.fat -F32 "$EFI"
mkfs.ext4 "$ROOT"
if [[ "$HAS_SWAP" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    mkswap "$SWAP"
    swapon "$SWAP"
fi

# Mount partitions
mount "$ROOT" /mnt
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
if [[ "$BOOT" == "1" ]]; then
    mount --mkdir "$EFI" /mnt/boot
else
    mount --mkdir "$EFI" /mnt/boot/efi
fi

# Install base system
echo "--------------------------------------"
echo "-- INSTALLING Base Arch Linux --"
echo "--------------------------------------"
pacman-key --init
pacman-key --populate archlinux
reflector -c "SA" > /etc/pacman.d/mirrorlist
pacstrap /mnt base linux linux-firmware base-devel git nano bash-completion networkmanager mpv ffmpeg yt-dlp fish fastfetch fzf docker docker-compose noto-fonts

# Generate fstab
genfstab -U /mnt > /mnt/etc/fstab

# Post-install script
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
echo "LANG=en_US.UTF-8" > /etc/locale.conf

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
    echo "default arch.conf" > /boot/loader/loader.conf
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
echo "Installing Desktop Environment"
echo "-------------------------------------------------"
if [[ "$DESKTOP" == "1" ]]; then
    pacman -S gnome gdm --noconfirm --needed
    systemctl enable gdm
elif [[ "$DESKTOP" == "2" ]]; then
    pacman -S plasma sddm --noconfirm --needed
    systemctl enable sddm
else
    echo "Skipping desktop environment installation."
fi

echo "-------------------------------------------------"
echo "yay installation"
echo "-------------------------------------------------"
if [[ "$INSTALL_YAY" =~ ^[Yy]$ ]]; then
    pacman -S --needed git base-devel --noconfirm
    sudo -u $USER git clone https://aur.archlinux.org/yay.git /home/$USER/yay
    cd /home/$USER/yay
    chown -R $USER:wheel /home/$USER/yay
    sudo -u $USER bash -c "cd ~/yay && makepkg -si --noconfirm"
    rm -rf /home/$USER/yay
fi

echo "-------------------------------------------------"
echo "Install Complete, You can reboot now"
echo "-------------------------------------------------"
REALEND

export INSTALL_YAY DESKTOP
arch-chroot /mnt bash -c 'INSTALL_YAY=$INSTALL_YAY DESKTOP=$DESKTOP sh next.sh' && rm /mnt/next.sh
