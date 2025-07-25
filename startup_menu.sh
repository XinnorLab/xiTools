#!/usr/bin/env bash
# Interactive provisioning menu for xiNAS
# POSIX-compliant startup menu script using whiptail
# Exits on errors and cleans up temporary files
# Requires: whiptail (usually provided by the 'whiptail' package)

set -euo pipefail
TMP_DIR="$(mktemp -d)"
# Path to whiptail if available
WHIPTAIL=$(command -v whiptail || true)
# Directory of the repository currently being configured
REPO_DIR="$(pwd)"
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

# Prompt user for license string and store it in /tmp/license
# Show license prompt and save to /tmp/license
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

    # Show HWKEY to the user
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

# Edit network configuration for Ansible netplan role
configure_network() {
    local template="collection/roles/net_controllers/templates/netplan.yaml.j2"
    if [ ! -f "$template" ]; then
        whiptail --msgbox "File $template not found" 8 60
        return
    fi

    local edit_tmp="$TMP_DIR/netplan_edit"
    cp "$template" "$edit_tmp"

    if command -v dialog >/dev/null 2>&1; then
        if dialog --title "Edit netplan template" --editbox "$edit_tmp" 20 70 2>"$TMP_DIR/netplan_new"; then
            cat "$TMP_DIR/netplan_new" > "$template"
        else
            return 0
        fi
    else
        whiptail --title "Edit netplan" --msgbox "Modify $template in the terminal. End with Ctrl-D." 10 60
        cat "$template" > "$TMP_DIR/netplan_new"
        cat >> "$TMP_DIR/netplan_new"
        cat "$TMP_DIR/netplan_new" > "$template"
    fi

    whiptail --title "Ansible Netplan" --textbox "$template" 20 70
}
# Configure hostname for Ansible role
configure_hostname() {
    ./configure_hostname.sh
}


# Display playbook information from /opt/provision/README.md
show_playbook_info() {
    local info_file="/opt/provision/README.md"
    if [ -f "$info_file" ]; then
        cat "$info_file"
    else
        echo "File $info_file not found" >&2
    fi
    read -rp "Press Enter to continue..." _
}

# Show NFS share configuration based on exports role defaults
configure_nfs_shares() {
    local vars_file="collection/roles/exports/defaults/main.yml"
    if [ ! -f "$vars_file" ]; then
        whiptail --msgbox "File $vars_file not found" 8 60
        return
    fi
    local share_start
    share_start=$(grep -n '^exports:' "$vars_file" | cut -d: -f1)
    local tmp="$TMP_DIR/nfs_info"
    sed -n "$((share_start+1)),$((share_start+3))p" "$vars_file" > "$tmp"
    whiptail --title "NFS Share" --textbox "$tmp" 12 70

    local default_path
    default_path=$(awk '/^exports:/ {flag=1; next} flag && /- path:/ {print $3; exit}' "$vars_file")

    while true; do
        local choice
        choice=$(whiptail --title "xiNAS Setup" --nocancel --menu "Choose an action:" 20 70 15 \
            1 "Configure Network" \
            2 "Set Hostname" \
            3 "Configure RAID" \
            4 "Edit NFS Exports" \
            5 "Git Repository Configuration" \
            6 "Install xiRAID Classic" \
            7 "Exit" \
            8 "Presets" \
            3>&1 1>&2 2>&3)
        case "$choice" in
            4) ./configure_nfs_exports.sh --edit "$default_path" ;;
            7) break ;;
        esac
    done
}

# Edit NFS export clients and options interactively
edit_nfs_exports() {
    ./configure_nfs_exports.sh
}

# Configure RAID devices interactively
configure_raid() {
    ./configure_raid.sh
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

# Configure or update git repository under /opt/provision
configure_git_repo() {
    local repo_dir="/opt/provision"
    mkdir -p "$repo_dir"

    local out="$TMP_DIR/git_config"
    if [ -d "$repo_dir/.git" ]; then
        git -C "$repo_dir" config --list >"$out" 2>&1
    else
        git config --list >"$out" 2>&1 || echo "No git configuration found" >"$out"
    fi
    whiptail --title "Current Git Configuration" --textbox "$out" 20 70
    if ! whiptail --yesno "Modify Git repository settings?" 8 60; then
        return 0
    fi

    local current_url=""
    local current_branch="main"
    if [ -d "$repo_dir/.git" ]; then
        current_url=$(git -C "$repo_dir" remote get-url origin 2>/dev/null || true)
        current_branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    elif [ -f "$repo_dir/repo.url" ]; then
        current_url=$(cat "$repo_dir/repo.url")
        [ -f "$repo_dir/repo.branch" ] && current_branch=$(cat "$repo_dir/repo.branch")
    fi

    url=$(whiptail --inputbox "Git repository URL" 8 60 "$current_url" 3>&1 1>&2 2>&3) || return 0
    branch=$(whiptail --inputbox "Git branch" 8 60 "$current_branch" 3>&1 1>&2 2>&3) || return 0

    if [ -d "$repo_dir/.git" ]; then
        git -C "$repo_dir" remote set-url origin "$url"
        git -C "$repo_dir" fetch origin
        git -C "$repo_dir" checkout "$branch"
        git -C "$repo_dir" pull origin "$branch"
    else
        rm -rf "$repo_dir"
        git clone -b "$branch" "$url" "$repo_dir"
    fi

    echo "$url" >"$repo_dir/repo.url"
    echo "$branch" >"$repo_dir/repo.branch"

    whiptail --msgbox "Repository configured at $repo_dir" 8 60
    REPO_DIR="$repo_dir"
    cd "$REPO_DIR"
}

# Run ansible-playbook and stream output
run_playbook() {
    local playbook="${1:-$REPO_DIR/playbooks/site.yml}"
    local inventory="${2:-inventories/lab.ini}"
    ansible-playbook "$playbook" -i "$inventory" -v
    return $?
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

# Display roles from a playbook and confirm execution
confirm_playbook() {
    local playbook="${1:-$REPO_DIR/playbooks/site.yml}"
    local roles role_list desc_file desc
    roles=$(grep -E '^\s*- role:' "$playbook" | awk '{print $3}')
    role_list=""
    for r in $roles; do
        desc_file="$REPO_DIR/collection/roles/${r}/README.md"
        if [ -f "$desc_file" ]; then
            desc=$(awk '/^#/ {next} /^[[:space:]]*$/ {if(found) exit; next} {if(found){printf " %s", $0} else {printf "%s", $0; found=1}} END{print ""}' "$desc_file")
        else
            desc="No description available"
        fi
        role_list="${role_list}\n - ${r}: ${desc}"
    done
    whiptail --yesno --scrolltext "Run Ansible playbook to configure the system?\n\nThis will execute the following roles:${role_list}" 20 70
}

confirm_perf_tuning() {
    local info_file="$REPO_DIR/collection/roles/perf_tuning/README.md"
    [ -f "$info_file" ] && whiptail --title "Performance Tuning" --scrolltext --textbox "$info_file" 20 70
    whiptail --yesno "Run performance tuning playbook?" 8 70
}

# Copy configuration files from a preset directory and optionally run its playbook
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

# Present available presets to the user
choose_preset() {
    local preset_dir="$REPO_DIR/presets"
    [ -d "$preset_dir" ] || { whiptail --msgbox "No presets available" 8 60; return; }

    local items=()
    for d in "$preset_dir"/*/; do
        [ -d "$d" ] || continue
        items+=("$(basename "$d")" "")
    done
    items+=("Save" "Save current configuration")
    items+=("Back" "Return")

    set +e
    local choice
    choice=$(whiptail --title "Presets" --menu "Select preset or save current:" 20 70 10 "${items[@]}" 3>&1 1>&2 2>&3)
    local status=$?
    set -e
    if [ $status -ne 0 ] || [ "$choice" = "Back" ]; then
        return
    fi
    if [ "$choice" = "Save" ]; then
        save_preset
        return
    fi
    apply_preset "$choice"
}

# Save current configuration files as a new preset directory
save_preset() {
    local preset
    preset=$(whiptail --inputbox "Preset name" 8 60 3>&1 1>&2 2>&3) || return
    [ -n "$preset" ] || { whiptail --msgbox "Preset name cannot be empty" 8 60; return; }

    local pdir="$REPO_DIR/presets/$preset"
    if [ -d "$pdir" ]; then
        if ! whiptail --yesno "Preset exists. Overwrite?" 8 60; then
            return
        fi
        rm -rf "$pdir"
    fi
    mkdir -p "$pdir"
    cp "collection/roles/net_controllers/templates/netplan.yaml.j2" "$pdir/netplan.yaml.j2" 2>/dev/null || true
    cp "collection/roles/raid_fs/defaults/main.yml" "$pdir/raid_fs.yml" 2>/dev/null || true
    cp "collection/roles/exports/defaults/main.yml" "$pdir/nfs_exports.yml" 2>/dev/null || true
    [ -f "playbooks/site.yml" ] && cp "playbooks/site.yml" "$pdir/playbook.yml"
    whiptail --msgbox "Preset saved to $pdir" 8 60
}

# Remove all systems from the default inventory after confirmation
clear_inventory() {
    local inv="inventories/lab.ini"
    [ -f "$inv" ] || return
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
    clear_inventory
    check_remove_xiraid || true
    remove_perf_packages
    remove_kernel_headers
}

# Main menu loop
while true; do
    choice=$(whiptail --title "xiNAS Setup" --nocancel --menu "Choose an action:" 20 70 17 \
        1 "Configure Network" \
        2 "Set Hostname" \
        3 "Configure RAID" \
        4 "Edit NFS Exports" \
        5 "Git Repository Configuration" \
        6 "Install xiRAID Classic" \
        7 "Performance Tuning" \
        8 "Collect HW Keys" \
        9 "Exit" \
        10 "RAID Preset" \
        11 "System Cleanup" \
        3>&1 1>&2 2>&3)
    case "$choice" in
        1) configure_network ;;
        2) configure_hostname ;;
        3) configure_raid ;;
        4) edit_nfs_exports ;;
        5) configure_git_repo ;;
        6)
            if check_remove_xiraid && confirm_playbook "playbooks/xiraid_only.yml"; then
                run_playbook "playbooks/xiraid_only.yml"
                whiptail --msgbox "Installation completed. Returning to main menu." 8 60 || true
            fi
            ;;
        7) run_perf_tuning ;;
        8) ./collect_hw_keys.sh ;;
        9) exit 2 ;;
        10) raid_preset ;;
        11) cleanup_system ;;
    esac
done

