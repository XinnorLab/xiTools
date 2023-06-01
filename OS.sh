#!/bin/bash

# Colors for formatting the output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check the Linux OS settings

# Get the system version
system_version=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)

# Get the kernel version
kernel_version=$(uname -r)

echo -e "${GREEN}System Version:${NC} $system_version"
echo -e "${GREEN}Kernel Version:${NC} $kernel_version"

# Check if a kernel update is available using apt
if [ -x "$(command -v apt)" ]; then
  apt_update=$(apt list --upgradable 2>/dev/null | grep linux-image)
  if [ -n "$apt_update" ]; then
    echo -e "${YELLOW}There is a kernel update available.${NC}"
    echo -e "Please run '${YELLOW}sudo apt update && sudo apt upgrade${NC}' to update the system."
  else
    echo -e "${GREEN}No kernel updates available.${NC}"
  fi
# Check if a kernel update is available using dnf
elif [ -x "$(command -v dnf)" ]; then
  dnf_update=$(dnf list --upgrades kernel 2>/dev/null | grep kernel)
  if [ -n "$dnf_update" ]; then
    echo -e "${YELLOW}There is a kernel update available.${NC}"
    echo -e "Please run '${YELLOW}sudo dnf upgrade${NC}' to update the system."
  else
    echo -e "${GREEN}No kernel updates available.${NC}"
  fi
else
  echo -e "${RED}Package manager not found. Unable to check for kernel updates.${NC}"
fi
