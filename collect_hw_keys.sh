#!/usr/bin/env bash
# Collect hardware keys and system data, then upload via transfer.sh
set -euo pipefail

WHIPTAIL=$(command -v whiptail || true)

ask_input() {
    local prompt="$1" default="$2" result
    if [ -n "$WHIPTAIL" ]; then
        result=$(whiptail --inputbox "$prompt" 8 60 "$default" 3>&1 1>&2 2>&3) || return 1
        echo "$result"
    else
        read -rp "$prompt [$default]: " result
        echo "${result:-$default}"
    fi
}

main() {
    local cfg email tmp archive server

    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                echo "Usage: $0" >&2
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: $0" >&2
                return 1
                ;;
        esac
    done

    cfg=$(ask_input "Enter config name" "config") || exit 1
    email=$(ask_input "Enter your email" "user@example.com") || exit 1
    tmp=$(mktemp -d)

    echo "Config name: $cfg" > "$tmp/info.txt"
    echo "Email: $email" >> "$tmp/info.txt"

    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT > "$tmp/lsblk.txt"
    cat /proc/mdstat > "$tmp/mdstat.txt" 2>/dev/null || true
    pvs > "$tmp/pvs.txt" 2>&1 || true
    nvme list > "$tmp/nvme_list.txt" 2>&1 || true
    lspci > "$tmp/lspci.txt" 2>&1 || true
    [ -x ./hwkey ] || chmod +x ./hwkey
    echo "Hardware key:"
    ./hwkey 2>&1 || true

    # NUMA node for each disk
    for dev in $(lsblk -ndo NAME,TYPE | awk '$2=="disk"{print $1}'); do
        node_file="/sys/block/$dev/device/numa_node"
        if [ -f "$node_file" ]; then
            echo "$dev $(cat "$node_file")" >> "$tmp/numa_nodes.txt"
        else
            echo "$dev unknown" >> "$tmp/numa_nodes.txt"
        fi
    done

    archive="/tmp/${cfg}.tgz"
    tar czf "$archive" -C "$tmp" .

    server=${TRANSFER_SERVER:-"http://178.253.23.152:8080"}

    if ! curl --fail --upload-file "$archive" "$server/$(basename "$archive")"; then
        echo "Warning: transfer.sh upload failed" >&2
    fi

    rm -rf "$tmp"
    echo "Archive created: $archive"
}

main "$@"
