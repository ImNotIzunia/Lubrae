#!/bin/bash

# SYNOPSIS
# Lubrae - Main script functions
#
# DESCRIPTION
# Lubrae is a tool to wipe disks and partitions
#
# NOTES
# Author  : Izunia
# Version : 0.1
# License : MIT License


set -u

VERSION="0.1"
DISK=""
LOOPS=1
FORMAT=""


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
    ./lubrae.sh --file FILE     Launch the wipe on a file (testing without a risk)
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

#    --file)
#        [[ -f "${2:-}" ]] || { echo "File not found: ${2:-}" >&2; exit 1; }
#    ;;

    "")
    ;;

    *)
        echo "Invalid Option : $1" >&2;
        Usage >&2;
        exit 1
    ;;
esac


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
        read -rp "Format type (emptuy to cancel): " value || exit 0

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
                echo "disk" 
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
                echo "launch" 
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
Show-Menu

