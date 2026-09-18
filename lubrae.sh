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

        read -rp "Choice : " choice

        case "$choice" in
            1) 
                clear
                echo "disk" 
            ;;

            2) 
                clear
                echo "loops" 
            ;;

            3) 
                clear
                echo "format" 
            ;;

            4) 
                clear
                echo "launch" 
            ;;

            5) 
                exit 0 
            ;;
            
            *) ;;
        esac
    done
}



Show-Menu

