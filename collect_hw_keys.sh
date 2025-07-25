#!/usr/bin/env bash
# Display xiRAID hardware keys for systems in the inventory
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

show_hwkeys() {
    local inventory=$1 out="$TMP_DIR/hwkeys"

    if ! command -v ansible >/dev/null 2>&1; then
        echo "ansible is required but not installed" >"$out"
    else
        local cmd="xicli license show 2>/dev/null | grep -i hwkey | awk '{print \$NF}'"
        ansible storage_nodes -i "$inventory" -b -m shell -a "$cmd" -o \
            | sed -E 's/^([^ ]+) \|.*\(stdout\) */\1 : /' >"$out" || \
            echo "Failed to collect hardware keys" >"$out"
    fi

    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "Hardware Keys" --textbox "$out" 20 70
    else
        cat "$out"
    fi
}

main() {
    local inventory="inventories/lab.ini"
    while [ $# -gt 0 ]; do
        case $1 in
            -i|--inventory)
                shift
                inventory=$1
                ;;
            -h|--help)
                echo "Usage: $0 [-i inventory]" >&2
                return 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: $0 [-i inventory]" >&2
                return 1
                ;;
        esac
        shift
    done

    show_hwkeys "$inventory"
}

main "$@"
