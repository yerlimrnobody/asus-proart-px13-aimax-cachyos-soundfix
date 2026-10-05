#!/usr/bin/env bash
# ASUS ProArt PX13 HN7306 / CachyOS TAS2783 stereo-audio fix
# One-command installer. Requires an internet connection on a fresh install.
set -euo pipefail

REPO_URL="https://github.com/ftoleedo/px13-audio-fix.git"
WORKDIR="/var/tmp/px13-audio-fix"

if [[ $EUID -eq 0 ]]; then
  echo "Run this file as your normal desktop user, not with sudo."
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "ERROR: sudo is required."
  exit 1
fi

KREL="$(uname -r)"
if [[ ! -d "/usr/lib/modules/$KREL/build" ]]; then
  echo "Kernel headers/build tree are missing for $KREL."
  echo "Installing the matching CachyOS kernel headers..."
  if [[ "$KREL" == *cachyos-lts* ]]; then
    sudo pacman -S --needed --noconfirm linux-cachyos-lts-headers
  elif [[ "$KREL" == *cachyos* ]]; then
    sudo pacman -S --needed --noconfirm linux-cachyos-headers
  else
    sudo pacman -S --needed --noconfirm linux-headers
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm git
fi

if [[ -d "$WORKDIR/.git" ]]; then
  git -C "$WORKDIR" fetch --depth=1 origin main
  git -C "$WORKDIR" reset --hard origin/main
else
  sudo rm -rf "$WORKDIR"
  git clone --depth=1 "$REPO_URL" "$WORKDIR"
fi

# DKMS makes the fix survive future kernel updates. The upstream installer
# already has a manual-build fallback if DKMS cannot be installed.
if ! command -v dkms >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm dkms
fi

cd "$WORKDIR"
bash ./install-durable.sh

echo
echo "PX13 audio fix installation completed."
echo "Verify stereo after installation/reboot with:"
echo "  speaker-test -D pulse -c2 -l1 -t wav"
