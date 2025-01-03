#!/bin/sh

DOTFILES="https://github.com/llGaetanll/rice.git"
BRANCH="master"

PROGS="https://raw.githubusercontent.com/llGaetanll/autorice/refs/heads/master/progs.tsv"

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
install.sh
.config/Xresources
.config/xinitrc
.config/polybar/modules.ini"

handle_user_and_passwd() {
  echo -n "Enter username: "
  read name

  # Check if the user exists
  if id -u "$name" &>/dev/null; then
    echo "User $name already exists!"
    echo "This script can install the dotfiles for that user, but all their data would be wiped."
    read -p "Is this ok? [y/N]: " answer

    # Default to 'N' if no input is provided
    case "${answer:-N}" in
      [Yy]*)
        echo "Removing user $name"
        userdel -r "$name" &>/dev/null
        ;;
      *)
        echo "Aborting"
        return
        ;;
    esac
  fi

  echo -n "Enter new password for $name: "
  read -s pass1
  echo

  echo -n "Confirm new password: "
  read -s pass2
  echo

  while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
    echo "Passwords don't match, try again"

    echo -n "Enter new password for $name: "
    read -s pass1
    echo

    echo -n "Confirm new password: "
    read -s pass2
    echo
	done ;

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

  # Start the chrony daemon
  if pgrep chronyd >/dev/null; then
    chronyd >/dev/null 2> err.log
  fi

  # Wait for chronyd to start and verify that it's running
  sleep 2

  if pgrep chronyd >/dev/null; then
    chronyc -a 'burst 4/4' >/dev/null 2> err.log && chronyc -a makestep >/dev/null 2> err.log
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
  curl -Lo "/etc/pacman.d/mirrorlist-arch" "https://archlinux.org/mirrorlist/?country=US&protocol=https&ip_version=4&ip_version=6" &>/dev/null

  # Remove the leading comment on Server lines
  sed -i '/^#Server = /s/^#//g' "/etc/pacman.d/mirrorlist-arch"

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

  # Sync databases
  pacman -Sy >/dev/null 2> err.log
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
  pacman --noconfirm --needed -S $pre_requisites_list >/dev/null 2> err.log
}

# The main install routine
install_progs() {
  echo "Installing system programs"

  curl -Ls "$PROGS" > "/tmp/progs.tsv"

  # Extract only the programs names, and space separate them
  progs="$(awk 'NR > 1 { printf "%s ", $1 }' /tmp/progs.tsv)"

  # Install the programs in parallel
  sudo -u "$name" paru --needed -S $progs 2> err.log ;
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
  local git_index_ignore_lst=$(echo -n "$GIT_INDEX_IGNORE" | tr '\n' ' ')

  cd "$dir" || exit

  sudo -u "$name" git update-index --assume-unchanged $git_index_ignore_lst

  # install.sh in the base rice repo is only useful when
  # git cloning the repo manually, it's of no use here
  [ -f "install.sh" ] && rm "install.sh"

  cd - >/dev/null

	sudo -u "$name" cp -rfT "$dir" "$1"
}

# dmenu is used by a lot of the system
install_dmenu() {
  echo "Installing dmenu"

  local suckless_home="/tmp/suckless"

  # Remove any existing installation
  rm -rf "$suckless_home"

  sudo -u "$name" git clone https://github.com/llGaetanll/suckless "$suckless_home"

  chown -R "$name":wheel "$suckless_home"

  cd "$suckless_home/dmenu" || exit

  make install

  cd - >/dev/null
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

#
# ===== The actual script starts here =====
#

echo "-=-=-=-=-=-=-=-=-=-=-=-=-=-=-"
echo "Gaetan's Artix Install Script"
echo "=-=-=-=-=-=-=-=-=-=-=-=-=-=-="

# This script must be ran as root
[ "$EUID" = 0 ] || { echo "You must be root to run this script"; return; }

handle_user_and_passwd  || { echo "Failed to create new user. Exiting"; return; }

upd_pacman_conf

install_prereqs || { echo "Failed to install pre-requisite packages. Exiting"; return; }

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers

sync_time

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

install_paru || { echo "Failed to install paru. Exiting"; return; }

install_progs

install_dotfiles "/home/$name"

install_dmenu

remove_beep

setup_zsh

echo "Install complete."
echo "As long as there weren't any horrible silent errors in err.log, you should be good to go!"
