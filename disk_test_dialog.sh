#!/usr/bin/env bash
set -euo pipefail

# Discover NVMe disks
mapfile -t NVME_DISKS < <(lsblk -ndo NAME,TYPE,TRAN | awk '$2=="disk" && $3=="nvme"{print "/dev/"$1}')

if [[ ${#NVME_DISKS[@]} -eq 0 ]]; then
    echo "No NVMe disks found." >&2
    exit 1
fi

echo "Found the following NVMe disks:"
for d in "${NVME_DISKS[@]}"; do
    echo "  - $d"
fi

echo
cat <<'MENU'
Where to conduct testing?
1) All disks
2) First N disks
3) Specific disks
MENU
read -rp "Choose an option [1-3]: " choice

case "$choice" in
    1)
        selected_disks=("${NVME_DISKS[@]}")
        ;;
    2)
        read -rp "Enter N: " N
        if ! [[ $N =~ ^[0-9]+$ ]] || (( N < 1 )) || (( N > ${#NVME_DISKS[@]} )); then
            echo "Invalid value for N." >&2
            exit 1
        fi
        selected_disks=("${NVME_DISKS[@]:0:N}")
        ;;
    3)
        read -rp "Enter disk names separated by space (e.g., nvme0n1 nvme1n1): " names
        selected_disks=()
        for name in $names; do
            disk="/dev/$name"
            if [[ " ${NVME_DISKS[*]} " == *" $disk "* ]]; then
                selected_disks+=("$disk")
            else
                echo "Disk $disk not found." >&2
            fi
        done
        if [[ ${#selected_disks[@]} -eq 0 ]]; then
            echo "No valid disk selected." >&2
            exit 1
        fi
        ;;
    *)
        echo "Unknown option." >&2
        exit 1
        ;;
esac

echo "Selected disks for testing:"
for d in "${selected_disks[@]}"; do
    echo "  - $d"
fi
