#!/usr/bin/env bash
# Collect hardware keys and system data, then upload via transfer.sh
set -euo pipefail

main() {
    local cfg tmp archive server

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

    cfg="hwkeys"
    tmp=$(mktemp -d)

    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT > "$tmp/lsblk.txt"
    cat /proc/mdstat > "$tmp/mdstat.txt" 2>/dev/null || true
    pvs > "$tmp/pvs.txt" 2>&1 || true
    nvme list > "$tmp/nvme_list.txt" 2>&1 || true
    lspci > "$tmp/lspci.txt" 2>&1 || true
    echo "Hardware keys:"
    rdcli license show | grep hwkey | tee "$tmp/hwkey.txt" || true

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
