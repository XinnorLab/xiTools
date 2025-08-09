#!/usr/bin/env bash
# Post installation information and management menu for xiNAS
set -euo pipefail

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Directory with Ansible repository
REPO_DIR="/opt/provision"
DEFAULT_GIT_URL="https://github.com/XinnorLab/xiNAS"

show_raid_info() {
    local out="$TMP_DIR/raid_info"
    local raw="$TMP_DIR/raid_raw"
    local pool_raw="$TMP_DIR/pool_raw"
    if xicli raid show -f json >"$raw" 2>&1; then
        if command -v jq >/dev/null && jq -e . "$raw" >/dev/null 2>&1; then
            jq -r '.[] |
                "RAID Name: \(.name)\n" +
                "RAID Level: \(.level)\n" +
                "Strip Size: \(.strip_size_kb // .strip_size) KB\n" +
                "Spare Pool: \(.spare_pool // "-" )\n" +
                "Size: \(.size // "-" )\n" +
                "Volume: /dev/xi_\(.name)\n" +
                ""' "$raw" >"$out"
        else
            if python3 -m json.tool "$raw" >"$out" 2>/dev/null; then
                :
            else
                cat "$raw" >"$out"
            fi
        fi
        {
            echo
            echo "Spare Pools:"
            if xicli pool show -f json >"$pool_raw" 2>&1; then
                if [ "$(tr -d '\n\r\t ' < "$pool_raw")" = "[]" ]; then
                    echo "None"
                else
                    if command -v jq >/dev/null && jq -e . "$pool_raw" >/dev/null 2>&1; then
                        jq -r 'to_entries[] | "\(.key): \(.value.state[0])\n  devices: \(.value.devices | map(.[1]) | join(" "))"' "$pool_raw"
                    else
                        python3 - "$pool_raw" <<'EOF'
import json,sys
data=json.load(open(sys.argv[1]))
for name,info in data.items():
    state=info.get("state",["-"])[0]
    devices=" ".join(d[1] for d in info.get("devices",[]))
    print(f"{name}: {state}\n  devices: {devices}")
EOF
                    fi
                fi
            else
                echo "Failed to run xicli pool show"
            fi
        } >>"$out"
    else
        echo "Failed to run xicli raid show" >"$out"
    fi
    whiptail --title "RAID Groups" --scrolltext --textbox "$out" 20 70
}

show_license_info() {
    local out="$TMP_DIR/license_info"
    if ! xicli license show >"$out" 2>&1; then
        echo "Failed to run xicli license show" >"$out"
    fi
    whiptail --title "xiRAID License" --textbox "$out" 20 70
}

show_nfs_info() {
    local out="$TMP_DIR/nfs_info"
    {
        echo "NFS exports from /etc/exports:";
        if [ -f /etc/exports ]; then
            cat /etc/exports
            echo
            awk '{print $1}' /etc/exports | while read -r p; do
                [ -z "$p" ] && continue
                df -hT "$p" 2>/dev/null || true
                echo
            done
        else
            echo "/etc/exports not found"
        fi
    } >"$out"
    whiptail --title "Filesystem & NFS" --textbox "$out" 20 70
}

manage_network() {
    local out="$TMP_DIR/net_info"
    {
        echo "Hostname: $(hostname)"
        ip -o -4 addr show | awk '{print $2, $4}'
    } >"$out"
    whiptail --title "Network Interfaces" --textbox "$out" 20 70
    if whiptail --yesno "Modify network configuration?" 8 60; then
        ROLE_TEMPLATE_OVERRIDE=/etc/netplan/99-xinas.yaml ./configure_network.sh
        netplan apply
    fi
}

is_custom_repo() {
    [ -d "$REPO_DIR/.git" ] || return 1
    local url
    url=$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || echo "")
    if [ -z "$url" ] && [ -f "$REPO_DIR/repo.url" ]; then
        url=$(cat "$REPO_DIR/repo.url")
    fi
    local def="${DEFAULT_GIT_URL%/}"
    case "$url" in
        "$def"|"$def.git"|*"XinnorLab/xiNAS"*) return 1 ;;
    esac
    return 0
}

has_repo_changes() {
    [ -d "$REPO_DIR/.git" ] || return 1
    git -C "$REPO_DIR" status --porcelain | grep -q .
}

store_config_repo() {
    local msg out
    msg=$(whiptail --inputbox "Commit message" 8 60 "Save configuration" 3>&1 1>&2 2>&3) || return 0
    git -C "$REPO_DIR" add -A
    if out=$(git -C "$REPO_DIR" commit -m "$msg" 2>&1); then
        if git -C "$REPO_DIR" push >/dev/null 2>&1; then
            whiptail --msgbox "Configuration saved to repository" 8 60
        else
            whiptail --msgbox "Failed to push changes" 8 60
        fi
    else
        whiptail --msgbox "Git commit failed:\n${out}" 15 70
    fi
}

while true; do
    options=(
        "RAID Groups information" ""
        "xiRAID license information" ""
        "File system and NFS share information" ""
        "Network post install settings" ""
    )
    if is_custom_repo && has_repo_changes; then
        options+=("Store configuration to Git repository" "")
    fi
    options+=("Exit" "")

    set +e
    choice=$(whiptail --title "Post Install Menu" --menu "Select action:" 20 70 10 "${options[@]}" 3>&1 1>&2 2>&3)
    status=$?
    set -e
    [ $status -ne 0 ] && break
    case "$choice" in
        "RAID Groups information") show_raid_info ;;
        "xiRAID license information") show_license_info ;;
        "File system and NFS share information") show_nfs_info ;;
        "Network post install settings") manage_network ;;
        "Store configuration to Git repository")
            if is_custom_repo && has_repo_changes; then
                store_config_repo
            else
                break
            fi
            ;;
        "Exit") break ;;
    esac
done
