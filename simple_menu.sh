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
        whiptail --msgbox "License file $license_file not found. Please add the license file before continuing." 10 60
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

# Prompt for RAID parameters and create the array on all inventory systems
raid_preset() {
    local name level stripe devices status var_file

    set +e
    name=$(whiptail --inputbox "RAID name" 8 60 3>&1 1>&2 2>&3)
    status=$?
    set -e
    [ $status -ne 0 ] && return

    set +e
    level=$(whiptail --inputbox "RAID level" 8 60 3>&1 1>&2 2>&3)
    status=$?
    set -e
    [ $status -ne 0 ] && return

    set +e
    stripe=$(whiptail --inputbox "Stripe size (KB)" 8 60 3>&1 1>&2 2>&3)
    status=$?
    set -e
    [ $status -ne 0 ] && return

    set +e
    devices=$(whiptail --inputbox "Space-separated devices" 8 70 3>&1 1>&2 2>&3)
    status=$?
    set -e
    [ $status -ne 0 ] && return

    local extra_opts="" input
    local opts="--adaptive_merge --single_run --block_size --cpu_allowed --init_prio --merge_write_enabled --merge_read_enabled --merge_read_max --merge_read_wait --merge_write_max --merge_write_wait --memory_limit --memory_prealloc --recon_prio --request_limit --restripe_prio --sdc_prio --sched_enabled --sparepool --force_metadata --trim --no_trim"
    whiptail --title "Optional RAID Parameters" --scrolltext --msgbox "Supported optional parameters:\n${opts}\nRefer to docs for details." 20 70 || true
    input=$(whiptail --inputbox "Enter optional parameters" 10 70 3>&1 1>&2 2>&3)
    extra_opts="$input"

    var_file="$TMP_DIR/raid_vars.yml"
    {
        echo "xiraid_arrays:"
        echo "  - name: ${name}"
        echo "    level: ${level}"
        echo "    strip_size_kb: ${stripe}"
        if [ -n "$extra_opts" ]; then
            echo "    extra_opts: \"$extra_opts\""
        fi
        echo "    devices:"
        for dev in $devices; do
            echo "      - $dev"
        done
        echo "xfs_filesystems: []"
    } > "$var_file"

    ansible-playbook "$REPO_DIR/playbooks/raid_preset.yml" -i inventories/lab.ini -e "@$var_file" -v
}

run_perf_tuning() {
    local playbook="$REPO_DIR/playbooks/perf_tuning.yml"
    local inventory="inventories/lab.ini"
    local os_name
    os_name=$(source /etc/os-release && echo "$PRETTY_NAME")
    whiptail --msgbox "Detected OS: $os_name" 8 60
    if confirm_perf_tuning; then
        ansible-playbook "$playbook" -i "$inventory" -v
    fi
}

# Check for installed xiRAID packages and optionally remove them
check_remove_xiraid() {
    local pkgs found repo_status log=/tmp/xiraid_remove.log pkg_mgr

    if command -v dpkg-query >/dev/null 2>&1; then
        pkgs=$(dpkg-query -W -f='${Package} ${Status}\n' 'xiraid*' 2>/dev/null | awk '$4=="installed"{print $1}')
        repo_status=$(pkg_status xiraid-repo)
        pkg_mgr="apt"
    else
        pkgs=$(rpm -qa 'xiraid*' 2>/dev/null)
        repo_status=$(rpm -q xiraid-repo 2>/dev/null || true)
        pkg_mgr="dnf"
    fi

    [ -n "$repo_status" ] && echo "xiraid-repo: $repo_status"
    rm -f "$log"

    if [ -z "$pkgs" ]; then
        if [ "$pkg_mgr" = "apt" ]; then
            sudo apt-get autoremove -y -qq --allow-change-held-packages >"$log" 2>&1 || true
        else
            sudo dnf autoremove -y >"$log" 2>&1 || true
        fi
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

    if [ "$pkg_mgr" = "apt" ]; then
        if sudo apt-get purge -y -qq --allow-change-held-packages "$pkgs" >"$log" 2>&1 \
            && sudo apt-get autoremove -y -qq --allow-change-held-packages >>"$log" 2>&1; then
            msg="xiRAID packages removed successfully"
        else
            msg="Errors occurred during removal. See $log for details"
        fi
    else
        if sudo dnf remove -y "$pkgs" >"$log" 2>&1 \
            && sudo dnf autoremove -y >>"$log" 2>&1; then
            msg="xiRAID packages removed successfully"
        else
            msg="Errors occurred during removal. See $log for details"
        fi
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

confirm_perf_tuning() {
    local info_file="$REPO_DIR/collection/roles/perf_tuning/README.md"
    [ -f "$info_file" ] && whiptail --title "Performance Tuning" --scrolltext --textbox "$info_file" 20 70
    whiptail --yesno "Run performance tuning playbook?" 8 70
}

# Convert dotted quad IP to integer
ip_to_int() {
    local IFS=. a b c d
    read -r a b c d <<< "$1"
    echo $(((a<<24)|(b<<16)|(c<<8)|d))
}

# Convert integer back to dotted quad IP
int_to_ip() {
    local ip=$1
    printf "%d.%d.%d.%d" $(((ip>>24)&255)) $(((ip>>16)&255)) $(((ip>>8)&255)) $((ip&255))
}

# Systems list editing is handled by inventory_manager.py

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

# Remove all systems from the default inventory after confirmation
clear_inventory() {
    local inv="inventories/lab.ini"
    if [ ! -f "$inv" ]; then
        return
    fi
    if whiptail --yesno "Clear systems list in $inv?" 8 60; then
        echo "[storage_nodes]" > "$inv"
        whiptail --msgbox "Inventory cleared" 8 40
    fi
}

# Remove auxiliary packages installed by the performance tuning role
remove_perf_packages() {
    local pkgs pkg_mgr
    if command -v dpkg-query >/dev/null 2>&1; then
        pkgs=(cpufrequtils linux-tools-common "linux-tools-$(uname -r)" tuned)
        pkg_mgr="apt"
    else
        pkgs=(tuned kernel-tools)
        pkg_mgr="dnf"
    fi

    if ! whiptail --yesno "Remove performance tuning packages?" 8 70; then
        return
    fi

    if [ "$pkg_mgr" = "apt" ]; then
        sudo apt-get purge -y -qq --allow-change-held-packages "${pkgs[@]}" || true
        sudo apt-get autoremove -y -qq --allow-change-held-packages || true
    else
        sudo dnf remove -y "${pkgs[@]}" || true
        sudo dnf autoremove -y || true
    fi
}

# Remove kernel headers packages for the running kernel
remove_kernel_headers() {
    local pkg pkg_mgr
    if command -v dpkg-query >/dev/null 2>&1; then
        pkg="linux-headers-$(uname -r)"
        pkg_mgr="apt"
    else
        pkg="kernel-devel-$(uname -r)"
        pkg_mgr="dnf"
    fi

    if dpkg-query -W "$pkg" >/dev/null 2>&1 || rpm -q "$pkg" >/dev/null 2>&1; then
        if whiptail --yesno "Remove $pkg?" 8 60; then
            if [ "$pkg_mgr" = "apt" ]; then
                sudo apt-get purge -y -qq --allow-change-held-packages "$pkg" || true
                sudo apt-get autoremove -y -qq --allow-change-held-packages || true
            else
                sudo dnf remove -y "$pkg" || true
                sudo dnf autoremove -y || true
            fi
        fi
    fi
}

# Clean systems, xiRAID and performance tuning packages
cleanup_system() {
    local pb="$REPO_DIR/playbooks/system_cleanup.yml"
    if confirm_playbook; then
        run_playbook "$pb" "inventories/lab.ini"
    fi
}

while true; do
    set +e
    choice=$(whiptail --title "xiNAS Setup" --menu "Select action:" 20 70 10 \
        "Systems list" "" \
        "Install xiRAID Classic" "" \
        "Performance Tuning" "" \
        "Collect HW Keys" "" \
        "RAID Preset" "" \
        "System Cleanup" "" \
        "Exit" "" 3>&1 1>&2 2>&3)
    status=$?
    set -e
    [ $status -ne 0 ] && exit 2
    case "$choice" in
        "Systems list") python3 inventory_manager.py ;;
        "Install xiRAID Classic")
            if check_remove_xiraid && confirm_playbook "playbooks/xiraid_only.yml"; then
                run_playbook "playbooks/xiraid_only.yml" "inventories/lab.ini"
                whiptail --msgbox "Installation completed. Returning to main menu." 8 60 || true
            fi
            ;;
        "Performance Tuning") run_perf_tuning ;;
        "Collect HW Keys") ./collect_hw_keys.sh ;;
        "RAID Preset") raid_preset ;;
        "System Cleanup") cleanup_system ;;
        "Exit") exit 2 ;;
    esac
done
