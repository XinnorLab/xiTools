#!/usr/bin/env bash
# Display xiRAID hardware keys in the terminal UI
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

show_hwkeys() {
    local out="$TMP_DIR/hwkeys"

    if xicli license show >"$out" 2>&1; then
        grep -i hwkey "$out" | sed "s/^/$(hostname) : /" >"${out}.fmt"
        mv "${out}.fmt" "$out"
    else
        echo "Failed to run xicli license show" >"$out"
    fi

    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "Hardware Keys" --textbox "$out" 20 70
    else
        cat "$out"
    fi
}

main() {
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

    show_hwkeys
}

main "$@"
