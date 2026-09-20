#!/bin/bash

# SYNOPSIS
# Lubrae - Main script functions
#
# DESCRIPTION
# Lubrae is a tool to wipe disks and partitions
#
# NOTES
# Author  : Izunia
# Version : 0.5
# License : MIT License


set -u

VERSION="0.5"

DISK=""
LOOPS=1
FORMAT=""

PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

declare -A PACKAGE_OF=(
    [dd]=coreutils
    [stat]=coreutils
    [realpath]=coreutils
    [lsblk]=util-linux
    [blockdev]=util-linux
    [parted]=parted
    [partprobe]=parted
    [mkfs.ext4]=e2fsprogs
    [mkfs.xfs]=xfsprogs
    [mkfs.vfat]=dosfstools
    [mkfs.exfat]=exfatprogs
    [mkfs.ntfs]=ntfs-3g
)


# SYNOPSIS
# Display a confirmation message
#
# DESCRIPTION
# Creating a "validation" action from the user
#
# EXAMPLE
# Confirm
#
# OUTPUTS
# None
#
Confirm() {
    read -rp "Press Enter to continue..." _ || exit 0
}


# SYNOPSIS
# Display the different usage options
#
# DESCRIPTION
# Display the different usage options for the script
#
# EXAMPLE
# Usage
#
# OUTPUTS
# None
#
Usage() {
    cat <<EOF
Lubrae

Version : $VERSION
Usage :
    sudo ./lubrae.sh            Launch the main menu
    ./lubrae.sh --file FILE     Launch the wipe on a file
    ./lubrae.sh --help          Show this menu
    ./lubrae.sh --version       Show the current version
EOF
}


case "${1:-}" in
    -h|--help)
        Usage;
        exit 0
    ;;

    -V|--version)
        echo "Lubrae $VERSION";
        exit 0
    ;;

    --file)
        [[ -f "${2:-}" ]] || { echo "File not found: ${2:-}" >&2; exit 1; }
        DISK="$2"
    ;;

    "")
    ;;

    *)
        echo "Invalid Option : $1" >&2;
        Usage >&2;
        exit 1
    ;;
esac


if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Lubrae only works on Linux" >&2
    exit 1
fi

if (( BASH_VERSINFO[0] < 4)); then
    echo "Lubrae needs Bash 4 or newer (found : $BASH_VERSION)" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Lubrae needs to run with root privileges..." >&2
    echo "Run : sudo $0" >&2
    exit 1
fi


# SYNOPSIS
# Install required Packages
#
# DESCRIPTION
# Verify if all needed packages are installed
# otherwise ask the user for the install
#
# EXAMPLE
# Install-Packages
# Get-Tools
#
# OUTPUTS
# None
#
Install-Packages() {
    local -a cmd

    if [[ $EUID -eq 0 ]]; then
        cmd=(apt-get install -y)
    elif command -v sudo >/dev/null; then
        cmd=(sudo apt-get install -y)
    else
        echo "Root privileges are required to install packages..."
        return 1
    fi

    "${cmd[@]}" "$@" || { echo "Installation failed... Try : sudo apt update"; return 1; }
}

Get-Tools() {
    local -a missing=() packages=()
    local -A seen=()
    local tool pkg answer

    for tool in "$@"; do
        command -v "$tool" >/dev/null || missing+=("$tool")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    echo "Missing tools : ${missing[*]}"

    if ! command -v apt-get >/dev/null; then
        echo "apt-get not found"
        return 1
    fi

    for tool in "${missing[@]}"; do
        pkg="${PACKAGE_OF[$tool]:-}"

        if [[ -z "$pkg" ]]; then
            echo "No package found for $tool"
            return 1
        fi

        if [[ -z "${seen[$pkg]:-}" ]]; then
            seen[$pkg]=1
            packages+=("$pkg")
        fi
    done

    echo "Packages to install : ${packages[*]}"
    
    read -rp "Install them now with apt? [y/N] " answer || exit 0

    if [[ ! "$answer" =~ ^[yY]$ ]]; then
        echo "Abort Installation"
        return 1
    fi

    Install-Packages "${packages[@]}" || return 1

    for tool in "${missing[@]}"; do
        if ! command -v "$tool" >/dev/null; then
            echo "$tool is still missing after the installation"
            return 1
        fi
    done
}


# SYNOPSIS
# Set number of loops
#
# DESCRIPTION
# Ask the user how many loops he wants
# the script run for the wipe
#
# EXAMPLE
# Set-Loops
#
# OUTPUTS
# None
#
Set-Loops() {
    local value
    
    while true; do
        read -rp "Number of loops (>= 1, empty to cancel): " value || exit 0

        if [[ -z "$value" ]]; then
            return
        fi

        if [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
            LOOPS="$value"
            return
        fi

        echo "Invalid Number. Please try again..."
    done
}


# SYNOPSIS
# Set Disk Format
#
# DESCRIPTION
# Ask the user what kind of 
# format he wants after the wipe
#
# EXAMPLE
# Set-Format
#
# OUTPUTS
# None
#
Set-Format() {
    local value

    echo ""

    echo "1. none"
    echo "2. ext4"
    echo "3. xfs"
    echo "4. vfat (FAT32)"
    echo "5. exfat"
    echo "6. ntfs"

    echo ""

    while true; do
        read -rp "Format type (empty to cancel): " value || exit 0

        case "$value" in
            1)
            FORMAT=""; return ;;
            
            2)
            FORMAT="ext4"; return ;;

            3)
            FORMAT="xfs"; return ;;

            4)
            FORMAT="vfat"; return ;;

            5)
            FORMAT="exfat"; return ;;

            6)
            FORMAT="ntfs"; return ;;

            "")
            return ;;

            *)
            echo "Invalid choice. Please try again..." ;;
        esac
    done
}


# SYNOPSIS
# Set Disk for the wipe
#
# DESCRIPTION
# Retrieve all the disks available and 
# check if it's mounted or not then ask
# the user to choose 
# 
# EXAMPLE
# Is-Mounted
# Is-System
# Is-SSD
# Set-Disk
#
# OUTPUTS
# None
#
Is-Mounted() {
    lsblk -nrpo MOUNTPOINT "$1" 2>/dev/null | grep -q .
}

Is-System() {
    lsblk -nrpo MOUNTPOINT "$1" 2>/dev/null | grep -qx "/"
}

Is-SSD() {
    [[ "$(lsblk -dno ROTA "$1" 2>/dev/null | tr -d '[:space:]')" == "0" ]]
}

Set-Disk() {
    local -a names=() locks=()
    local name size type model lock choice i

    Get-Tools lsblk blockdev || { Confirm; return; }

    while read -r name size type model; do
        [[ "$type" == "disk" ]] || continue
        [[ "$name" == /dev/zram* ]] && continue

        lock=""

        if Is-System "$name"; then
            lock="SYSTEM DISK"
        elif Is-Mounted "$name"; then
            lock="MOUNTED"
        fi

        names+=("$name")
        locks+=("$lock")

        printf '%s. %-12s %-8s %s' "${#names[@]}" "$name" "$size" "$model"
        [[ -n "$lock" ]] && printf '    [%s - locked]' "$lock"
        printf '\n'
    done < <(lsblk -dnpo NAME,SIZE,TYPE,MODEL)

    if [[ ${#names[@]} -eq 0 ]]; then
        echo "No disk found"
        read -rp "Press Enter to continue..." _ || exit 0
        return
    fi

    echo ""

    while true; do
        read -rp "Disk number (empty to cancel): " choice || exit 0

        if [[ -z "$choice" ]]; then
            return
        fi

        if ! [[ "$choice" =~ ^[1-9][0-9]*$ ]] || (( choice > ${#names[@]} )); then
            echo "Invalid choice. Please try again..."
            continue
        fi

        i=$((choice -1))

        if [[ -n "${locks[$i]}" ]]; then
            echo "${names[$i]} is locked (${locks[$i]}), choose another disk..."
            continue
        fi

        DISK="${names[$i]}"
        return
    done
}


# SYNOPSIS
# Setup the partition
#
# DESCRIPTION
# Retrieve the partition of the disk and
# Format it in the right format
#
# EXAMPLE
# Get-Partition
# Wait-Partition
# Check-Tools
# Format-Disk
#
# OUTPUTS
# None
#
Get-Partition() {
    if [[ "$1" =~ [0-9]$ ]]; then
        echo "${1}p1"
    else
        echo "${1}1"
    fi
}

Wait-Partition() {
    local i

    for (( i = 1; i <= 20; i++)); do
        [[ -b "$1" ]] && return 0
        sleep 0.5
    done

    return 1
}

Check-Tools() {
    local -a tools=("mkfs.$FORMAT")

    if [[ -b "$DISK" ]]; then
        tools+=(parted partprobe)
    fi

    Get-Tools "${tools[@]}"
}

Format-Disk() {
    local part

    echo ""
    echo ">>> Formatting ($FORMAT)"

    parted -s "$DISK" mklabel gpt mkpart primary 1MiB 100% || return 1
    partprobe "$DISK" 2>/dev/null
    command -v udevadm >/dev/null && udevadm settle

    part=$(Get-Partition "$DISK")
    Wait-Partition "$part" || { echo "Partition $part not found"; return 1; }

    case "$FORMAT" in
        ext4) mkfs.ext4 -F "$part" ;;
        xfs) mkfs.xfs -f "$part" ;;
        vfat) mkfs.vfat -F 32 "$part" ;;
        exfat) mkfs.exfat "$part" ;;
        ntfs) mkfs.ntfs -f "$part" ;;
    esac
}


# SYNOPSIS
# Replace data
#
# DESCRIPTION
# Use the dd command to replace the data
# with random data and zeros
#
# EXAMPLE
# Set-Random
# Set-Zero
#
# OUTPUTS
# None
#
Set-Random() {
    echo "> Fill with random data"
    dd if=/dev/urandom of="$DISK" bs=4M count="$size" iflag=fullblock,count_bytes "${flags[@]}" status=progress
}

Set-Zero() {
    echo "> Fill with zero"
    dd if=/dev/zero of="$DISK" bs=4M count="$size" iflag=fullblock,count_bytes "${flags[@]}" status=progress
}


# SYNOPSIS
# Get Disk wiped
#
# DESCRIPTION
# Retrieve the size of the disk and
# proceed to the wipe after confirmation from the user
#
# EXAMPLE
# Get-DiskSize
# WipeDisk
#
# OUTPUTS
# None
#
Get-DiskSize() {
    if [[ -b "$1" ]]; then
        blockdev --getsize64 "$1"
    else
        stat -c %s "$1"
    fi
}

WipeDisk(){
    local size validate n
    local -a flags

    if [[ -z "$DISK" ]]; then
        echo "A disk need to be choosen first (option 1)"
        Confirm
        return
    fi

    if [[ -b "$DISK" ]] && Is-Mounted "$DISK"; then
        echo "$DISK is mounted, operation aborted"
        Confirm
        return
    fi

    size=$(Get-DiskSize "$DISK")
    
    if [[ "$size" -le 0 ]]; then
        echo "Size of $DISK is 0, nothing to wipe..."
        Confirm
        return
    fi

    if [[ -n "$FORMAT" ]]; then
        Check-Tools || { Confirm; return; }
    fi

    echo ""

    echo "SUMMARY"
    echo ""
    echo "Target : $DISK"
    echo "Size   : $size bytes"
    echo "Loops  : $LOOPS"
    echo "Format : $FORMAT"
    echo ""
    echo "ALL DATA ON $DISK WILL BE DESTROYED"

    read -rp "Type the exact path of the disk to confirm (empty to cancel): " validate || exit 0

    if [[ "$validate" != "$DISK" ]]; then
        echo "Cancelled..."
        Confirm
        return
    fi

    if [[ -b "$DISK" ]]; then
        flags=(conv=fsync oflag=direct)
    else
        flags=("conv=fsync,notrunc")
    fi

    for (( n = 1; n <= LOOPS; n++)); do
        echo ""
        echo ">>> Pass $n/$LOOPS"
        Set-Random || { echo "dd failed, aborting..."; Confirm; return; }
        Set-Zero || { echo "dd failed, aborting..."; Confirm; return; }
    done

    echo ""
    echo ">>> Final pass"
    echo ""

    Set-Zero || { echo "dd failed, aborting..."; Confirm; return; }

    if [[ -n "$FORMAT" ]]; then
        echo ""
        echo "No formatting"
    else
        Format-Disk || echo "Formatting failed"
    fi

    echo ""
    echo "Done"

    Confirm
}


# SYNOPSIS
# Display the header
#
# DESCRIPTION
# Display the title and information for the menu
#
# EXAMPLE
# Show-Header
#
# OUTPUTS
# None
#
Show-Header() {
    echo ""
    echo "=========="
    echo "  Lubrae"
    echo "=========="
    echo ""
    echo "Disk   : ${DISK:-(none)}"
    echo "Loops  : $LOOPS"
    echo "Format : ${FORMAT:-(none)}"
    echo ""
}


# SYNOPSIS
# Displays the main menu
#
# DESCRIPTION
# Loops and prompt the user to choose a disk, a number
# of loops, the type of format and launch the wipe
# 
# EXAMPLE
# Show-Menu
#
# OUTPUTS
# None
#
Show-Menu() {
    
    while true; do
        echo ""

        Show-Header

        echo "1. Choose disk"
        echo "2. Number of loops"
        echo "3. Format type"
        echo "4. Launch"
        echo "5. Exit"

        echo ""

        read -rp "Choice : " choice || exit 0

        case "$choice" in
            1) 
                clear
                Set-Disk
            ;;

            2) 
                clear
                Set-Loops
            ;;

            3) 
                clear
                Set-Format
            ;;

            4) 
                clear
                WipeDisk
            ;;

            5) 
                exit 0 
            ;;
            
            *) 
                clear
                echo "Invalid choice. Please try again.."
                sleep 1
            ;;
        esac
    done
}



# Main

Get-Tools dd stat realpath || exit 1

Show-Menu

