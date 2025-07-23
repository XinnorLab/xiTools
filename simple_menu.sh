#!/usr/bin/env bash
# Simplified startup menu for xiNAS
set -euo pipefail
TMP_DIR="$(mktemp -d)"
REPO_DIR="$(pwd)"
# Path to whiptail if available
WHIPTAIL=$(command -v whiptail || true)
trap 'rm -rf "$TMP_DIR"' EXIT

check_license() {
    local license_file="/tmp/license"
    if [ ! -f "$license_file" ]; then
        whiptail --msgbox "License file $license_file not found. Please run 'Enter License' first." 10 60
        return 1
    fi
    return 0
}

# Display package status using dpkg-query with a trailing newline
pkg_status() {
    local pkg="$1"
    dpkg-query -W -f='${Status}\n' "$pkg" 2>/dev/null || true
}

enter_license() {
    local license_file="/tmp/license"
    [ -x ./hwkey ] || chmod +x ./hwkey
    local hwkey_val
    local replace=0

    local ts=""
    if [ -f "$license_file" ]; then
        if whiptail --yesno "License already exists. Replace it?" 10 60; then
            replace=1
            ts=$(date +%Y%m%d%H%M%S)
        else
            return 0
        fi
    fi

    hwkey_val=$(./hwkey 2>/dev/null | tr -d '\n' | tr '[:lower:]' '[:upper:]')
    whiptail --title "Hardware Key" --msgbox "HWKEY: ${hwkey_val}\nRequest your license key from xiNNOR Support." 10 60

    : > "$TMP_DIR/license_tmp"
    if command -v dialog >/dev/null 2>&1; then
        if dialog --title "Enter License" --editbox "$TMP_DIR/license_tmp" 20 70 2>"$TMP_DIR/license"; then
            :
        else
            return 0
        fi
    else
        whiptail --title "Enter License" --msgbox "Paste license in the terminal. End with Ctrl-D." 10 60
        cat >>"$TMP_DIR/license"
    fi
    if [ $replace -eq 1 ]; then
        cp "$license_file" "${license_file}.${ts}.bak"
    fi
    cat "$TMP_DIR/license" > "$license_file"
}

run_playbook() {
    local playbook="${1:-$REPO_DIR/playbooks/site.yml}"
    local inventory="${2:-inventories/lab.ini}"
    ansible-playbook "$playbook" -i "$inventory" -v
    return $?
}

# Check for installed xiRAID packages and optionally remove them
check_remove_xiraid() {
    local pkgs found repo_status log=/tmp/xiraid_remove.log
    pkgs=$(dpkg-query -W -f='${Package} ${Status}\n' 'xiraid*' 2>/dev/null | \
        awk '$4=="installed"{print $1}')
    repo_status=$(pkg_status xiraid-repo)
    [ -n "$repo_status" ] && echo "xiraid-repo: $repo_status"
    rm -f "$log"
    if [ -z "$pkgs" ]; then
        sudo apt-get autoremove -y -qq --allow-change-held-packages >"$log" 2>&1 || true
        if [ -s "$log" ]; then
            msg="Obsolete packages removed"
            if [ -n "$WHIPTAIL" ]; then
                whiptail --msgbox "$msg" 8 60
            else
                echo "$msg"
            fi
            rm -f "$log"
        fi
        return 0
    fi

    found=$(echo "$pkgs" | tr '\n' ' ')
    if ! whiptail --yesno "Found installed xiRAID packages:\n${found}\nRemove them before running Ansible?" 12 70; then
        return 1
    fi

    if sudo apt-get purge -y -qq --allow-change-held-packages $pkgs >"$log" 2>&1 \
        && sudo apt-get autoremove -y -qq --allow-change-held-packages >>"$log" 2>&1 \
        && sudo rm -rf /etc/xiraid >>"$log" 2>&1; then
        msg="xiRAID packages removed successfully"
    else
        msg="Errors occurred during removal. See $log for details"
    fi
    if [ -n "$WHIPTAIL" ]; then
        whiptail --msgbox "$msg" 8 60
    else
        echo "$msg"
    fi
    rm -f "$log"
    return 0
}

confirm_playbook() {
    whiptail --yesno "Run Ansible playbook to configure the system?" 8 60
}

# Prompt for a list of systems and store them in the default inventory
enter_systems() {
    local inv="inventories/lab.ini"
    local -a hosts=()
    if [ -f "$inv" ]; then
        mapfile -t hosts < <(awk '!/^\[/ && NF {print $1}' "$inv")
    fi

    while true; do
        set +e
        local new_host status
        new_host=$(whiptail --inputbox "Enter system" 10 60 "" 3>&1 1>&2 2>&3)
        status=$?
        set -e
        [ $status -ne 0 ] && break
        [ -n "$new_host" ] && hosts+=("$new_host")

        local list
        list=$(printf '%s\n' "${hosts[@]}")
        set +e
        whiptail --yesno "Current systems:\n$list\nAdd another?" 15 60
        status=$?
        set -e
        [ $status -eq 0 ] || break
    done

    if [ ${#hosts[@]} -gt 0 ]; then
        local tmp="$TMP_DIR/inventory"
        echo "[storage_nodes]" > "$tmp"
        printf '%s\n' "${hosts[@]}" | sed '/^\s*$/d' >> "$tmp"
        mv "$tmp" "$inv"
        whiptail --title "Systems list" --textbox "$inv" 20 70
    fi
}

apply_preset() {
    local preset="$1"
    local pdir="$REPO_DIR/presets/$preset"
    [ -d "$pdir" ] || { whiptail --msgbox "Preset $preset not found" 8 60; return; }
    local msg="Applying preset: $preset\n"
    if [ -f "$pdir/netplan.yaml.j2" ]; then
        cp "$pdir/netplan.yaml.j2" "collection/roles/net_controllers/templates/netplan.yaml.j2"
        msg+="- network configuration\n"
    fi
    if [ -f "$pdir/raid_fs.yml" ]; then
        cp "$pdir/raid_fs.yml" "collection/roles/raid_fs/defaults/main.yml"
        msg+="- RAID configuration\n"
    fi
    if [ -f "$pdir/nfs_exports.yml" ]; then
        cp "$pdir/nfs_exports.yml" "collection/roles/exports/defaults/main.yml"
        msg+="- NFS exports\n"
    fi
    if [ -f "$pdir/playbook.yml" ]; then
        cp "$pdir/playbook.yml" "playbooks/site.yml"
        msg+="- playbook updated\n"
    fi
    whiptail --msgbox "$msg" 15 70
}

choose_preset() {
    local preset_dir="$REPO_DIR/presets"
    [ -d "$preset_dir" ] || { whiptail --msgbox "No presets available" 8 60; return; }
    local items=()
    for d in "$preset_dir"/*/; do
        [ -d "$d" ] || continue
        items+=("$(basename "$d")" "")
    done
    items+=("Back" "Return")
    set +e
    local choice
    choice=$(whiptail --title "Presets" --menu "Select preset:" 20 70 10 "${items[@]}" 3>&1 1>&2 2>&3)
    local status=$?
    set -e
    if [ $status -ne 0 ] || [ "$choice" = "Back" ]; then
        return
    fi
    apply_preset "$choice"
}

while true; do
    choice=$(whiptail --title "xiNAS Setup" --nocancel --menu "Choose an action:" 15 70 7 \
        1 "Enter Systems" \
        2 "Presets" \
        3 "Install" \
        4 "Collect Data" \
        5 "Exit" \
        3>&1 1>&2 2>&3)
    case "$choice" in
        1) enter_systems ;;
        2) choose_preset ;;
        3)
            if check_license && check_remove_xiraid && confirm_playbook "playbooks/site.yml"; then
                run_playbook "playbooks/site.yml" "inventories/lab.ini"
                chmod +x post_install_menu.sh
                ./post_install_menu.sh
                exit 0
            fi
            ;;
        4) ./collect_data.sh ;;
        5) exit 2 ;;
    esac
done
