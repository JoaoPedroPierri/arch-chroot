#!/usr/bin/env bash

# Script archlinux chroot (versão atualizada)
# Original: João Pedro Pierri (@joaoppierri)
# Chamado automaticamente pelo arch-install.sh (não é preciso correr à mão).

set -euo pipefail
source /root/install.env

msg(){ printf '\n\e[1;36m[!] %s\e[0m\n' "$*"; }

timezone_config(){
  ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
  hwclock --systohc
}

language_system(){
  sed -i -e 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' \
         -e "s/^#\(${LOCALE}\.UTF-8 UTF-8\)/\1/" /etc/locale.gen
  locale-gen
  echo "LANG=${LOCALE}.UTF-8" > /etc/locale.conf
  echo "KEYMAP=${KEYMAP}"     > /etc/vconsole.conf
}

hostname_config(){
  echo "$HOST_NAME" > /etc/hostname
  cat > /etc/hosts <<EOF
127.0.0.1  localhost
::1        localhost
127.0.1.1  ${HOST_NAME}.localdomain ${HOST_NAME}
EOF
}

pacman_config(){
  sed -i -e 's/^#Color/Color/' \
         -e 's/^#VerbosePkgLists/VerbosePkgLists/' \
         -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 10/' /etc/pacman.conf
  grep -q '^ILoveCandy' /etc/pacman.conf || sed -i '/^Color/a ILoveCandy' /etc/pacman.conf
  # multilib (Steam, Wine, etc.)
  sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
  pacman -Sy --noconfirm
}

zram_config(){
  cat > /etc/systemd/zram-generator.conf <<EOF
[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
EOF
}

gpu_amd_config(){
  # libs 32 bits (Steam/Wine) - multilib já ativado em pacman_config
  pacman -S --noconfirm --needed lib32-mesa lib32-vulkan-radeon
}

keyboard_x11_config(){
  # layout PT para o SDDM/XWayland
  mkdir -p /etc/X11/xorg.conf.d
  cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "pt"
EndSection
EOF
}

hyprland_config(){
  local cfg="/home/$USERNAME/.config/hypr"
  mkdir -p "$cfg"
  cat > "$cfg/hyprland.conf" <<'EOF'
# Config inicial Hyprland (teclado PT, GPU AMD)
monitor = , preferred, auto, 1

$terminal = kitty
$files    = thunar
$menu     = wofi --show drun
$mod      = SUPER

exec-once = waybar
exec-once = dunst
exec-once = systemctl --user start hyprpolkitagent
exec-once = nm-applet --indicator

env = XCURSOR_SIZE,24
env = LIBVA_DRIVER_NAME,radeonsi
env = VDPAU_DRIVER,radeonsi

input {
    kb_layout = pt
    follow_mouse = 1
    touchpad {
        natural_scroll = true
    }
}

general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    layout = dwindle
}

decoration {
    rounding = 8
}

dwindle {
    pseudotile = true
    preserve_split = true
}

bind = $mod, Return, exec, $terminal
bind = $mod, Q, killactive
bind = $mod, M, exit
bind = $mod, E, exec, $files
bind = $mod, D, exec, $menu
bind = $mod, F, fullscreen
bind = $mod, V, togglefloating
bind = $mod, L, exec, hyprlock
bind = , Print, exec, grim -g "$(slurp)" - | wl-copy

bind = $mod, left,  movefocus, l
bind = $mod, right, movefocus, r
bind = $mod, up,    movefocus, u
bind = $mod, down,  movefocus, d

bind = $mod, 1, workspace, 1
bind = $mod, 2, workspace, 2
bind = $mod, 3, workspace, 3
bind = $mod, 4, workspace, 4
bind = $mod, 5, workspace, 5
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5

bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow

bindel = , XF86AudioRaiseVolume,  exec, wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+
bindel = , XF86AudioLowerVolume,  exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindel = , XF86AudioMute,         exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = , XF86MonBrightnessUp,   exec, brightnessctl set 5%+
bindel = , XF86MonBrightnessDown, exec, brightnessctl set 5%-
EOF
  chown -R "$USERNAME:$(id -gn "$USERNAME")" "/home/$USERNAME/.config"
}

initramfs_rebuild(){
  mkinitcpio -P   # aplica o KEYMAP do vconsole.conf
}

users_config(){
  msg "Palavra-passe para o root"
  until passwd root; do :; done
  useradd -m -G wheel -s /bin/zsh "$USERNAME"
  msg "Palavra-passe de $USERNAME"
  until passwd "$USERNAME"; do :; done
  echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel
  chmod 440 /etc/sudoers.d/10-wheel
}

grub_install(){
  if [[ $UEFI == 1 ]]; then
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux --recheck
    # entrada de fallback para firmwares problemáticos
    grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck
  else
    grub-install --target=i386-pc --recheck "$DISK"
  fi
  grub-mkconfig -o /boot/grub/grub.cfg
}

services_enable(){
  systemctl enable NetworkManager fstrim.timer systemd-timesyncd sddm
}

timezone_config
language_system
hostname_config
pacman_config
zram_config
gpu_amd_config
keyboard_x11_config
initramfs_rebuild
users_config
hyprland_config
grub_install
services_enable
