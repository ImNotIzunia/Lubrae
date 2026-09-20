#!/bin/bash

# SYNOPSIS
# Lubrae  Main script functions
#
# DESCRIPTION
# Lubrae is a tool to wipe disks, partitions and files
#
# NOTES
# Author  : Izunia
# Version : 1.0
# License : MIT License


VERSION="1.0"


if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Lubrae only works on Linux" >&2
    exit 1
fi

if (( BASH_VERSINFO[0] < 4 )); then
    echo "Lubrae needs Bash 4 or newer (found : $BASH_VERSION)" >&2
    exit 1
fi


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
# Wait for the user
#
# DESCRIPTION
# Pause the script until the user presses Enter
#
# EXAMPLE
# Wait-Key
#
# OUTPUTS
# None
#
Wait-Key() {
    read -rp "Press Enter to continue..." _ || exit 0
}


# SYNOPSIS
# Display the different usage options
# 
# DESCRIPTION
# Display the different usages options for the script
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
    sudo ./lubrae.sh            Launch the main menu (root is needed to wipe a disk)
    ./lubrae.sh --file FILE     Launch the main menu with a file as a target (no root needed)
    ./lubrae.sh --help          Show this menu
    ./lubrae.sh --version       Show the current version
EOF
}


# SYNOPSIS
# Check and read the arguments
#
# DESCRIPTION
# Validate a file given by the user and 
# handle the options of the script
#
# EXAMPLE
# Get-File
# Get-Args
#
# OUTPUTS
# None
#
Get-File() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        echo "[ERROR] File not found : $path"
        return 1
    fi

    if [[ -b "$path" ]]; then
        echo "[WARNING] $path is a block device : use \"Choose Target > Disk\" instead"
        return 1
    fi

    if [[ ! -f $path ]]; then
        echo "[ERROR] $path is not a regular file"
        return 1
    fi 

    if [[ ! -w "$path" ]]; then
        echo "[ERROR] $path is not writable (permission denied)"
        return 1
    fi

    return 0
}

Get-Args() {
    case "${1:-}" in
        -h|--help)
            Usage
            exit 0
        ;;

        -V|--version)
            echo "Lubrae $VERSION"
            exit 0
        ;;

        -f|--file)
            Get-File "${2:-}" >&2 || exit 1
            DISK="$(realpath "$2")"
        ;;

        "")
        ;;

        *)
            echo "Invalid Option : $1" >&2
            Usage >&2
            exit 1
        ;;
    esac
}


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
# Set the target for the wipe
#
# DESCRIPTION
# Retrieve all the disks available and
# check if it's mounted or not then ask
# the user to choose, or ask for a file
#
# EXAMPLE
# Is-Mounted
# Is-System
# Is-SSD
# Set-Disk
# Set-File
# Set-Target
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
    local -a names=() lock=()
    local name size type model lock choice i

    if [[ $EUID -ne 0 ]]; then
        echo "Wiping a disk requires Lubrae to run with root privileges..."
        echo "Please run : sudo $0"
        echo "(A file can be wiped without root : choose \"File\")"
        Wait-Key
        return
    fi

    Get-Tools lsblk blockdev || { Wait-Key; return; }

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
        Wait-Key
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
 
        i=$((choice - 1))
 
        if [[ -n "${locks[$i]}" ]]; then
            echo "${names[$i]} is locked (${locks[$i]}), choose another disk..."
            continue
        fi
 
        DISK="${names[$i]}"
        return
    done
}

Set-File() {
    local path

    while true; do
        read -erp "File path (empty to cancel): " path || exit 0

        if [[ -z "$path" ]]; then
            return
        fi

        if Get-File "$path"; then
            DISK="$(realpath "$path")"
            return
        fi
    done
}

Set-Target() {
    local choice

    echo ""

    echo "1. Disk"
    echo "2. File"

    echo ""

    while true; do
        read -rp "Target type (empty to cancel): " choice || exit 0

        case "$choice" in
            1)
            Set-Disk; return ;;

            2)
            Set-File; return ;;

            "")
            return ;;

            *)
            echo "Invalid choice. Please try again..."
            ;;
        esac
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
# Make-Filesystem
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

Make-Filesystem() {
    case "$FORMAT" in
        ext4) 
            mkfs.ext4 -F "$1" ;;

        xfs) 
            mkfs.xfs -f "$1" ;;

        vfat) 
            mkfs.vfat -F 32 "$1" ;;

        exfat) 
            mkfs.exfat "$1" ;;

        ntfs)
            if [[ -f "$1" ]]; then
                mkfs.ntfs -F -f "$1"
            else
                mkfs.ntfs -f "$1"
            fi
        ;;
    esac
}

Format-Disk() {
    local part
 
    echo ""
    echo ">>> Formatting ($FORMAT)"
 
    if [[ -f "$DISK" ]]; then
        Make-Filesystem "$DISK"
        return
    fi
 
    parted -s "$DISK" mklabel gpt mkpart primary 1MiB 100% || return 1
    partprobe "$DISK" 2>/dev/null
    command -v udevadm >/dev/null && udevadm settle
 
    part=$(Get-Partition "$DISK")
    Wait-Partition "$part" || { echo "Partition $part not found"; return 1; }
 
    Make-Filesystem "$part"
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
# Start-Wipe
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

Start-Wipe() {
    local size validate n
    local -a flags
 
    if [[ -z "$DISK" ]]; then
        echo "A target needs to be chosen first (option 1)"
        Wait-Key
        return
    fi
 
    if [[ ! -e "$DISK" ]]; then
        echo "$DISK does not exist anymore, operation aborted"
        Wait-Key
        return
    fi
 
    if [[ -f "$DISK" ]]; then
        Get-File "$DISK" || { Wait-Key; return; }
    fi
 
    if [[ -b "$DISK" && $EUID -ne 0 ]]; then
        echo "Wiping a disk requires root privileges. Run : sudo $0"
        Wait-Key
        return
    fi
 
    if [[ -b "$DISK" ]] && Is-Mounted "$DISK"; then
        echo "$DISK is mounted, operation aborted"
        Wait-Key
        return
    fi   

    size=$(Get-DiskSize "$DISK") || { echo "Cannot read the size of $DISK"; Wait-Key; return; }
 
    if [[ "$size" -le 0 ]]; then
        echo "Size of $DISK is 0, nothing to wipe..."
        Wait-Key
        return
    fi
 
    if [[ -n "$FORMAT" ]]; then
        Check-Tools || { Wait-Key; return; }
    fi
 
    echo ""
 
    echo "SUMMARY"
    echo ""
    echo "Target : $DISK"
 
    if [[ -f "$DISK" ]]; then
        echo "Type   : file"
    else
        echo "Type   : disk"
    fi
 
    echo "Size   : $size bytes"
    echo "Loops  : $LOOPS"
    echo "Format : ${FORMAT:-none}"

    if [[ -n "$FORMAT" && -f "$DISK" ]]; then
        echo "         (filesystem written directly in the file, no partition table)"
    fi
 
    echo ""

    if [[ -f "$DISK" ]]; then
        echo "NOTE : the file is overwritten in place and kept (same size), it is not deleted"
        echo ""
    fi

    echo "ALL DATA ON $DISK WILL BE DESTROYED"

    read -rp "Type the exact path of the target to confirm (empty to cancel): " validate || exit 0

    if [[ "$validate" != "$DISK" ]]; then
        echo "Cancelled..."
        Wait-Key
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
        echo ""
        Set-Random || { echo "dd failed, aborting..."; Wait-Key; return; }
        echo ""
        Set-Zero || { echo "dd failed, aborting..."; Wait-Key; return; }
    done
 
    echo ""
    echo ">>> Final pass"
    echo ""
 
    Set-Zero || { echo "dd failed, aborting..."; Wait-Key; return; }
 
    if [[ -n "$FORMAT" ]]; then
        Format-Disk || echo "Formatting failed"
    fi
 
    echo ""
    echo "Done"
 
    DISK=""
 
    Wait-Key
}


# SYNOPSIS
# Display the header
#
# DESCRIPTION
# Display the title and information for the menu
#
# EXAMPLE
# Clear-Screen
# Show-Header
#
# OUTPUTS
# None
#
Clear-Screen() {
    if [[ -t 1 ]]; then
        clear
    fi
}
 
Show-Header() {
    local kind=""
 
    if [[ -b "$DISK" ]]; then
        kind=" (disk)"
    elif [[ -f "$DISK" ]]; then
        kind=" (file)"
    fi
 
    echo ""
    echo "=========="
    echo "  Lubrae"
    echo "=========="
    echo ""
    echo "Target : ${DISK:-(none)}$kind"
    echo "Loops  : $LOOPS"
    echo "Format : ${FORMAT:-(none)}"
    echo ""
}


# SYNOPSIS
# Displays the main menu
#
# DESCRIPTION
# Loops and prompt the user to choose a target, a number
# of loops, the type of format and launch the wipe
#
# EXAMPLE
# Show-Menu
#
# OUTPUTS
# None
#
Show-Menu() {
    local choice
 
    while true; do
        Clear-Screen
        Show-Header
 
        echo "1. Choose target (disk or file)"
        echo "2. Number of loops"
        echo "3. Format type"
 
        if [[ -z "$DISK" ]]; then
            echo "4. Launch (choose a target first)"
        else
            echo "4. Launch"
        fi
 
        echo "5. Exit"
 
        echo ""
 
        read -rp "Choice : " choice || exit 0
 
        case "$choice" in
            1)
                Clear-Screen
                Set-Target
            ;;
 
            2)
                Clear-Screen
                Set-Loops
            ;;
 
            3)
                Clear-Screen
                Set-Format
            ;;
 
            4)
                Clear-Screen
                Start-Wipe
            ;;
 
            5)
                exit 0
            ;;
 
            *)
                Clear-Screen
                echo "Invalid choice. Please try again..."
                sleep 1
            ;;
        esac
    done
}


# SYNOPSIS
# Main
#
# DESCRIPTION
# Entry point of the script, only run when the
# file is executed and not when it is sourced (tests)
#
# EXAMPLE
# main
#
# OUTPUTS
# None
#
main() {
    set -u
 
    Get-Args "$@"
 
    Get-Tools dd stat realpath || exit 1
 
    Show-Menu
}
 
if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
    main "$@"
fi

