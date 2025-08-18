#!/usr/bin/env bash
set -euo pipefail

# Discover NVMe disks
mapfile -t NVME_DISKS < <(lsblk -ndo NAME,TYPE,TRAN | awk '$2=="disk" && $3=="nvme"{print "/dev/"$1}')

if [[ ${#NVME_DISKS[@]} -eq 0 ]]; then
    echo "NVMe дисков не найдено." >&2
    exit 1
fi

echo "Найдены следующие NVMe диски:"
for d in "${NVME_DISKS[@]}"; do
    echo "  - $d"
fi

echo
cat <<'MENU'
Где проводить тестирование?
1) Все диски
2) Первые N дисков
3) Конкретные диски
MENU
read -rp "Выберите вариант [1-3]: " choice

case "$choice" in
    1)
        selected_disks=("${NVME_DISKS[@]}")
        ;;
    2)
        read -rp "Введите N: " N
        if ! [[ $N =~ ^[0-9]+$ ]] || (( N < 1 )) || (( N > ${#NVME_DISKS[@]} )); then
            echo "Некорректное значение N." >&2
            exit 1
        fi
        selected_disks=("${NVME_DISKS[@]:0:N}")
        ;;
    3)
        read -rp "Введите имена дисков через пробел (например: nvme0n1 nvme1n1): " names
        selected_disks=()
        for name in $names; do
            disk="/dev/$name"
            if [[ " ${NVME_DISKS[*]} " == *" $disk "* ]]; then
                selected_disks+=("$disk")
            else
                echo "Диск $disk не найден." >&2
            fi
        done
        if [[ ${#selected_disks[@]} -eq 0 ]]; then
            echo "Не выбрано ни одного корректного диска." >&2
            exit 1
        fi
        ;;
    *)
        echo "Неизвестный вариант." >&2
        exit 1
        ;;
 esac

echo "Выбраны диски для тестирования:"
for d in "${selected_disks[@]}"; do
    echo "  - $d"
fi
