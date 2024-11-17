#!/bin/sh

DOTFILES="https://github.com/llGaetanll/rice.git"
BRANCH="rewrite"

PROGS="https://raw.githubusercontent.com/llGaetanll/autorice/refs/heads/rewrite/progs.tsv"

# The max number of parallel downloads to set pacman/paru to
NUM_PARALLEL=20

# A small list of programs that need to be installed before the mass install,
# just to make sure everything runs smoothly
PRE_REQUISITES="archlinux-keyring
artix-keyring
curl
base-devel
git
chrony
chrony-runit
zsh"

# Files that git should ignore in its index after installing the dotfiles
GIT_INDEX_IGNORE="README.md
.local/share/bg
.config/Xresources
.config/xinitrc
.config/polybar/modules.ini"

get_user_and_passwd() {
  echo -n "Enter username: "
  read name

  echo -n "Enter password: "
  read -s pass1
  echo

  echo -n "Confirm password: "
  read -s pass2
  echo

  while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
    echo "Passwords don't match, try again"

    echo -n "Enter password: "
    read -s pass1
    echo

    echo -n "Confirm password: "
    read -s pass2
    echo
	done ;
}

# Determines whether username $name exists or not
user_dne() {
  (! (id -u "$name" &>/dev/null)) || { echo "User \"$name\" already exists!"; return 1; }
}

# Add a user and password to the system, add it to the wheel group, and create
# its home directory
set_user_and_passwd() {
  # this function must be ran as root
  [ "$EUID" = 0 ] || { echo "You must be root to set a new user and password!"; return 1; }

  # Add a new user with a home directory and set their shell to zsh
  useradd -m -s /bin/zsh "$name" &>/dev/null

  # Add the user to the wheel group for sudo access
  usermod -aG wheel "$name"

  # Ensure the home directory has the correct ownership
  mkdir -p /home/"$name"
  chown "$name":wheel /home/"$name"

  echo "$name:$pass1" | chpasswd
  unset pass1 pass2 ;
}

sync_time() {
  echo "Syncing system time"
  
  # Enable and start chronyd using runit
  ln -sf /etc/runit/sv/chronyd /run/runit/service

  sleep 1 

  chronyd

  # Wait for chronyd to start and verify that it's running
  sleep 2
  if pgrep chronyd >/dev/null; then
    chronyc -a 'burst 4/4' && chronyc -a makestep
  else
    echo "Failed to start chronyd; time synchronization skipped."
  fi
}

upd_pacman_conf() {
  echo "Updating pacman config"

  local pacman_conf_home="/etc/pacman.conf"

  # Enable colored output
  grep -q "^Color" "$pacman_conf_home" || sed -i "s/^#Color$/Color/" "$pacman_conf_home"

  # Turn on whimsical pacman progress bar
  grep -q "ILoveCandy" "$pacman_conf_home" || sed -i "/#VerbosePkgLists/a ILoveCandy" "$pacman_conf_home"

  # Set parallel downloads
  if grep -q "^ParallelDownloads" "$pacman_conf_home"; then
    sed -i "s/^ParallelDownloads.*/ParallelDownloads = $NUM_PARALLEL/" "$pacman_conf_home"
  else
    sed -i "/ILoveCandy/a ParallelDownloads = $NUM_PARALLEL" "$pacman_conf_home"
  fi

  # Generate arch mirrorlist
  curl -Lo "/etc/pacman.d/mirrorlist-arch" "https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4&ip_version=6"

  # Add arch repos to pacman.conf
  local arch_repos=$(cat <<'EOF'

# Arch
[extra]
Include = /etc/pacman.d/mirrorlist-arch

[community]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch

[universe]
Server = https://universe.artixlinux.org/$arch
Server = https://mirror1.artixlinux.org/universe/$arch
Server = https://mirror.pascalpuffke.de/artix-universe/$arch
Server = https://artixlinux.qontinuum.space/artixlinux/universe/os/$arch
Server = https://mirror1.cl.netactuate.com/artix/universe/$arch
Server = https://ftp.crifo.org/artix-universe/$arch
Server = https://artix.sakamoto.pl/universe/$arch
EOF
)

  if ! grep -q "^# Arch" "$pacman_conf_home"; then
    echo "$arch_repos" >> "$pacman_conf_home"
  fi
}

install_paru() {
  [ -f "/usr/bin/paru" ] && (
    echo "paru already installed, skipping..."
  ) || (
    echo "Installing paru"

    sudo pacman -S --needed base-devel rustup

    # Cargo is needed to build paru
    sudo -u "$name" rustup default stable

    local paru_home="/tmp/paru"

    # Remove any existing paru installation
    rm -rf "$paru_home"

    sudo -u "$name" git clone https://aur.archlinux.org/paru.git "$paru_home"

    chown -R "$name":wheel "$paru_home"

    # Add "$name" to sudoers file, we need this to build paru
    echo "$name  ALL=(ALL:ALL) ALL" >> /etc/sudoers

    cd "$paru_home" && sudo -u "$name" makepkg --noconfirm -si

    # Remove "$name" from sudoers file
    sed -i "/^$name ALL=(ALL:ALL) ALL$/d" /etc/sudoers

    cd - || return
  );
}

install_prereqs() {
  echo "Installing prereq programs"

  pre_requisites_list=$(echo "$PRE_REQUISITES" | tr '\n' ' ')

  # For prereqs, we don't yet have paru installed
  pacman --noconfirm --needed -S $pre_requisites_list
}

# The main install routine
install_progs() {
  curl -Ls "$PROGS" > "/tmp/progs.tsv"

  # Extract only the programs names, and space separate them
  progs="$(awk 'NR > 1 { printf "%s ", $1 }' /tmp/progs.tsv)"

  # Install the programs in parallel
  paru --noconfirm --needed -S $progs 2> err.log ;
}

install_dotfiles() {
  # $1 is the destination directory

  echo "Installing dotfiles"

  # We make a temporary directory and clone the repo there
  # Then, we copy it to the actual directory
	dir=$(mktemp -d)
	[ ! -d "$1" ] && mkdir -p "$1"

	chown -R "$name":wheel "$dir" "$1"
	sudo -u "$name" git clone --recursive -b "$BRANCH" --depth 1 "$DOTFILES" "$dir" &>/dev/null

  # All the files in GIT_INDEX_IGNORE should be ignored by git's index
  git_index_ignore_lst=$(echo -n "$GIT_INDEX_IGNORE" | tr '\n' ' ' | sed "s|[^ ]*|$dir/&|g")

  (cd "$dir" && git update-index --assume-unchanged "$git_index_ignore_lst" && cd -)

	sudo -u "$name" cp -rfT "$dir" "$1"
}

remove_beep() {
  if lsmod | grep -q pcspkr; then
    rmmod pcspkr
  fi
  echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;
}

setup_zsh() {
  echo "Setting up zsh"

  # Make zsh the default shell for the user.
  chsh -s /bin/zsh "$name" >/dev/null 2>&1
  sudo -u "$name" mkdir -p "/home/$name/.cache/zsh/"
}

gen_dbus_uuid() {
  # dbus UUID must be generated for Artix runit.
  dbus-uuidgen > /var/lib/dbus/machine-id || echo "Failed to generate dbus UUID"
}

restart_pulseaudio() {
  echo "Restarting pulseaudio"

  # Start/Restart PulseAudio.
  killall pulseaudio; sudo -u "$name" pulseaudio --start
}

#
# ===== The actual script starts here =====
#

get_user_and_passwd && user_dne && set_user_and_passwd || { echo "Failed adding new user. Exiting"; return 1; }

upd_pacman_conf

install_prereqs || { echo "Failed to install pre-requisite packages. Exiting"; return 1; }

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers

sync_time

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

install_paru || { echo "Failed to install paru. Exiting"; return 1; }

install_progs

# install_dotfiles "/home/$name"

# remove_beep

# setup_zsh

# gen_dbus_uuid

# restart_pulseaudio

# echo "Install complete!"
