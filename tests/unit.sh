EXIT#!/bin/bash

# shellcheck disable=SC2317

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/tests/helpers.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=/dev/null
source "$ROOT/lubrae.sh"
set -u


# ---------------------------------------------------------------------------
section "Get-Partition"

assert_eq "/dev/sda1"        "$(Get-Partition /dev/sda)"       "sda -> sda1"
assert_eq "/dev/vdb1"        "$(Get-Partition /dev/vdb)"       "vdb -> vdb1"
assert_eq "/dev/nvme0n1p1"   "$(Get-Partition /dev/nvme0n1)"   "nvme0n1 -> nvme0n1p1"
assert_eq "/dev/mmcblk0p1"   "$(Get-Partition /dev/mmcblk0)"   "mmcblk0 -> mmcblk0p1"
assert_eq "/dev/loop0p1"     "$(Get-Partition /dev/loop0)"     "loop0 -> loop0p1"


# ---------------------------------------------------------------------------
section "Get-DiskSize"

make_image "$TMP/size.img" 1048576
assert_eq "1048576" "$(Get-DiskSize "$TMP/size.img")" "taille d'un fichier de 1 MiB"

: > "$TMP/empty.img"
assert_eq "0" "$(Get-DiskSize "$TMP/empty.img")" "taille d'un fichier vide"


# ---------------------------------------------------------------------------
section "Get-File"

make_image "$TMP/ok.img" 4096

assert_true "fichier normal accepté" Get-File "$TMP/ok.img"

out="$(Get-File "$TMP/nope.img")"
rc=$?
assert_eq 1 "$rc" "fichier inexistant : code 1"
assert_contains "$out" "File not found" "fichier inexistant : message"

out="$(Get-File "$TMP")"
rc=$?
assert_eq 1 "$rc" "dossier : code 1"
assert_contains "$out" "not a regular file" "dossier : message"

blockdev_found=""
for d in /dev/loop0 /dev/sda /dev/vda /dev/nvme0n1 /dev/mmcblk0; do
    if [[ -b "$d" ]]; then
        blockdev_found="$d"
        break
    fi
done

if [[ -n "$blockdev_found" ]]; then
    out="$(Get-File "$blockdev_found")"
    rc=$?
    assert_eq 1 "$rc" "périphérique bloc : code 1"
    assert_contains "$out" "is a block device" "périphérique bloc : message"
else
    skip "périphérique bloc refusé" "aucun périphérique bloc trouvé"
fi

if (( EUID == 0 )); then
    skip "fichier non modifiable refusé" "root peut tout écrire"
else
    make_image "$TMP/ro.img" 4096
    chmod 444 "$TMP/ro.img"
    out="$(Get-File "$TMP/ro.img")"
    rc=$?
    assert_eq 1 "$rc" "fichier en lecture seule : code 1"
    assert_contains "$out" "not writable" "fichier en lecture seule : message"
fi


# ---------------------------------------------------------------------------
section "Get-Args"

out="$( (Get-Args --help) 2>&1 )"
rc=$?
assert_eq 0 "$rc" "--help : code 0"
assert_contains "$out" "Usage" "--help : affiche l'aide"

out="$( (Get-Args --version) 2>&1 )"
rc=$?
assert_eq 0 "$rc" "--version : code 0"
assert_contains "$out" "Lubrae $VERSION" "--version : affiche la version"

out="$( (Get-Args --bidon) 2>&1 )"
rc=$?
assert_eq 1 "$rc" "option inconnue : code 1"
assert_contains "$out" "Invalid Option" "option inconnue : message"

out="$( (Get-Args --file "$TMP/nope.img") 2>&1 )"
rc=$?
assert_eq 1 "$rc" "--file inexistant : code 1"

out="$( (Get-Args --file) 2>&1 )"
rc=$?
assert_eq 1 "$rc" "--file sans argument : code 1"

DISK=""
Get-Args --file "$TMP/ok.img"
assert_eq "$(realpath "$TMP/ok.img")" "$DISK" "--file valide : la cible est le chemin réel"

DISK=""
Get-Args
assert_eq "" "$DISK" "sans argument : aucune cible"


# ---------------------------------------------------------------------------
section "Set-Loops"

LOOPS=1
Set-Loops <<< "3" > /dev/null
assert_eq 3 "$LOOPS" "3 est accepté"

LOOPS=1
Set-Loops <<< $'abc\n0\n-2\n1.5\n7' > "$TMP/out.txt"
assert_eq 7 "$LOOPS" "valeurs invalides ignorées, 7 finit par passer"
assert_eq 4 "$(grep -c 'Invalid Number' "$TMP/out.txt")" "4 messages d'erreur pour abc, 0, -2, 1.5"

LOOPS=5
Set-Loops <<< "" > /dev/null
assert_eq 5 "$LOOPS" "entrée vide : annulation, valeur inchangée"

out="$( (Set-Loops < /dev/null) 2>&1 )"
rc=$?
assert_eq 0 "$rc" "Ctrl+D : sortie propre (code 0)"


# ---------------------------------------------------------------------------
section "Set-Format"

for pair in "1:" "2:ext4" "3:xfs" "4:vfat" "5:exfat" "6:ntfs"; do
    number="${pair%%:*}"
    expected="${pair#*:}"

    FORMAT="valeur-de-depart"
    Set-Format <<< "$number" > /dev/null
    assert_eq "$expected" "$FORMAT" "choix $number -> '${expected:-aucun}'"
done

FORMAT="ext4"
Set-Format <<< "" > /dev/null
assert_eq "ext4" "$FORMAT" "entrée vide : annulation, valeur inchangée"

FORMAT=""
Set-Format <<< $'9\nx\n2' > "$TMP/out.txt"
assert_eq "ext4" "$FORMAT" "choix invalides ignorés, 2 finit par passer"
assert_eq 2 "$(grep -c 'Invalid choice' "$TMP/out.txt")" "2 messages d'erreur pour 9 et x"


# ---------------------------------------------------------------------------
section "Is-Mounted / Is-System / Is-SSD (lsblk simulé)"

lsblk() {
    case "$*" in
        "-dnpo NAME,SIZE,TYPE,MODEL")
            printf '%s\n' \
                "/dev/sda 500G disk Samsung SSD" \
                "/dev/sdb 16G disk USB Flash" \
                "/dev/sdc 1T disk WD Blue" \
                "/dev/zram0 4G disk " \
                "/dev/sr0 1G rom DVD"
            ;;
        "-nrpo MOUNTPOINT /dev/sda") printf '\n/\n' ;;
        "-nrpo MOUNTPOINT /dev/sdb") printf '/media/usb\n' ;;
        "-nrpo MOUNTPOINT /dev/sdc") printf '\n\n' ;;
        "-dno ROTA "*) echo "${MOCK_ROTA:-1}" ;;
    esac
}

assert_true  "sda est monté (sa partition contient /)" Is-Mounted /dev/sda
assert_true  "sdb est monté"                            Is-Mounted /dev/sdb
assert_false "sdc n'est pas monté"                      Is-Mounted /dev/sdc

assert_true  "sda est le disque système"                Is-System /dev/sda
assert_false "sdb n'est pas le disque système"          Is-System /dev/sdb
assert_false "sdc n'est pas le disque système"          Is-System /dev/sdc

MOCK_ROTA=0
assert_true  "ROTA=0 : SSD ou clé"                      Is-SSD /dev/sdc
MOCK_ROTA=1
assert_false "ROTA=1 : disque rotatif"                  Is-SSD /dev/sdc


# ---------------------------------------------------------------------------
section "Set-Disk (lsblk simulé)"

blockdev() { echo 1000; }

if (( EUID != 0 )); then
    out="$(Set-Disk <<< "")"
    assert_contains "$out" "requires root" "sans root : le choix d'un disque est refusé"
    skip "liste et verrous des disques" "nécessite root (lancé en utilisateur normal)"
else
    skip "refus sans root" "lancé en root"

    DISK=""
    Set-Disk <<< $'1\n2\n9\nx\n3\n' > "$TMP/out.txt"
    out="$(cat "$TMP/out.txt")"

    assert_contains     "$out" "[SYSTEM DISK - locked]" "le disque système est verrouillé"
    assert_contains     "$out" "[MOUNTED - locked]"     "le disque monté est verrouillé"
    assert_not_contains "$out" "zram0"                  "zram est ignoré"
    assert_not_contains "$out" "sr0"                    "le lecteur CD est ignoré"
    assert_contains     "$out" "/dev/sda is locked (SYSTEM DISK)" "sda refusé (système)"
    assert_contains     "$out" "/dev/sdb is locked (MOUNTED)"     "sdb refusé (monté)"
    assert_eq 2 "$(grep -c 'Invalid choice' "$TMP/out.txt")" "9 et x sont invalides"
    assert_eq "/dev/sdc" "$DISK" "le disque libre (3) est sélectionné"

    DISK=""
    Set-Disk <<< "" > /dev/null
    assert_eq "" "$DISK" "entrée vide : rien de sélectionné"
fi

unset -f lsblk blockdev


# ---------------------------------------------------------------------------
section "Set-File / Set-Target"

DISK=""
Set-File <<< $'/nope\n'"$TMP/ok.img" > "$TMP/out.txt"
assert_contains "$(cat "$TMP/out.txt")" "File not found" "chemin invalide signalé"
assert_eq "$(realpath "$TMP/ok.img")" "$DISK" "puis le bon chemin devient la cible"

DISK=""
Set-File <<< "" > /dev/null
assert_eq "" "$DISK" "entrée vide : annulation"

DISK=""
Set-Target <<< $'x\n2\n'"$TMP/ok.img" > "$TMP/out.txt"
assert_contains "$(cat "$TMP/out.txt")" "Invalid choice" "type de cible invalide signalé"
assert_eq "$(realpath "$TMP/ok.img")" "$DISK" "Set-Target > 2 (File) sélectionne le fichier"


# ---------------------------------------------------------------------------
section "Get-Tools (apt-get, sudo simulés)"

PACKAGE_OF["fakeA1"]=pkgA
PACKAGE_OF["fakeA2"]=pkgA
PACKAGE_OF["fakeB"]=pkgB

# shellcheck disable=SC2034
PACKAGE_OF["fakeC"]=pkgC

APT_LOG="$TMP/apt.log"
APT_OK=1

apt-get() {
    echo "apt-get $*" >> "$APT_LOG"
    [[ "$APT_OK" == 1 ]] || return 1

    local p
    for p in "${@:3}"; do
        case "$p" in
            pkgA) fakeA1() { :; }; fakeA2() { :; } ;;
            pkgB) fakeB() { :; } ;;
        esac
    done
}

sudo() {
    "$@"
}

reset_fakes() {
    unset -f fakeA1 fakeA2 fakeB fakeC
    : > "$APT_LOG"
    APT_OK=1
}

reset_fakes
Get-Tools bash dd < /dev/null > "$TMP/out.txt" 2>&1
rc=$?
assert_eq 0 "$rc" "outils présents : code 0"
assert_eq "" "$(cat "$TMP/out.txt")" "outils présents : aucune question posée"

reset_fakes
Get-Tools fakeA1 <<< "n" > "$TMP/out.txt" 2>&1
rc=$?
assert_eq 1 "$rc" "réponse n : code 1"
assert_contains "$(cat "$TMP/out.txt")" "Abort Installation" "réponse n : abandon annoncé"
assert_false "réponse n : apt-get n'est pas appelé" test -s "$APT_LOG"

reset_fakes
Get-Tools fakeA1 <<< "" > /dev/null 2>&1
rc=$?
assert_eq 1 "$rc" "Entrée seule : refus par défaut (N)"
assert_false "Entrée seule : apt-get n'est pas appelé" test -s "$APT_LOG"

reset_fakes
Get-Tools fakeA1 <<< "y" > /dev/null 2>&1
rc=$?
assert_eq 0 "$rc" "réponse y : code 0"
assert_contains "$(cat "$APT_LOG")" "install -y pkgA" "réponse y : installe pkgA"

reset_fakes
Get-Tools fakeB <<< "Y" > /dev/null 2>&1
assert_contains "$(cat "$APT_LOG")" "install -y pkgB" "réponse Y (majuscule) acceptée"

reset_fakes
Get-Tools fakeA1 fakeA2 fakeB <<< "y" > /dev/null 2>&1
assert_eq "apt-get install -y pkgA pkgB" "$(cat "$APT_LOG")" "deux outils du même paquet : pkgA une seule fois"

reset_fakes
Get-Tools outil_inconnu_xyz <<< "y" > "$TMP/out.txt" 2>&1
rc=$?
assert_eq 1 "$rc" "outil sans paquet connu : code 1"
assert_contains "$(cat "$TMP/out.txt")" "No package found for outil_inconnu_xyz" "outil sans paquet connu : message"
assert_false "outil sans paquet connu : apt-get n'est pas appelé" test -s "$APT_LOG"

reset_fakes
APT_OK=0
Get-Tools fakeA1 <<< "y" > "$TMP/out.txt" 2>&1
rc=$?
assert_eq 1 "$rc" "installation qui échoue : code 1"
assert_contains "$(cat "$TMP/out.txt")" "Installation failed" "installation qui échoue : message"

reset_fakes
Get-Tools fakeC <<< "y" > "$TMP/out.txt" 2>&1
rc=$?
assert_eq 1 "$rc" "outil toujours absent après l'installation : code 1"
assert_contains "$(cat "$TMP/out.txt")" "still missing" "outil toujours absent : message"

reset_fakes
# shellcheck disable=SC2123
out="$( ( unset -f apt-get; PATH=/nonexistent; Get-Tools fakeA1 <<< "y" ) 2>&1 )"
assert_contains "$out" "apt-get not found" "sans apt-get : message clair"

reset_fakes
( Get-Tools fakeA1 < /dev/null ) > /dev/null 2>&1
rc=$?
assert_eq 0 "$rc" "Ctrl+D pendant la question : sortie propre"

unset -f apt-get sudo


# ---------------------------------------------------------------------------
section "Make-Filesystem / Format-Disk (mkfs et parted simulés)"

MK_LOG="$TMP/mk.log"

mkfs.ext4()  { echo "ext4 $*"  > "$MK_LOG"; }
mkfs.xfs()   { echo "xfs $*"   > "$MK_LOG"; }
mkfs.vfat()  { echo "vfat $*"  > "$MK_LOG"; }
mkfs.exfat() { echo "exfat $*" > "$MK_LOG"; }
mkfs.ntfs()  { echo "ntfs $*"  > "$MK_LOG"; }
parted()     { echo "parted $*" >> "$TMP/parted.log"; }

check_mkfs() { # FORMAT CIBLE ATTENDU
    FORMAT="$1"
    : > "$MK_LOG"
    Make-Filesystem "$2"
    assert_eq "$3" "$(cat "$MK_LOG")" "$1 sur $(basename "$2") : arguments de mkfs"
}

check_mkfs ext4  /dev/x1 "ext4 -F /dev/x1"
check_mkfs xfs   /dev/x1 "xfs -f /dev/x1"
check_mkfs vfat  /dev/x1 "vfat -F 32 /dev/x1"
check_mkfs exfat /dev/x1 "exfat /dev/x1"
check_mkfs ntfs  /dev/x1 "ntfs -f /dev/x1"
check_mkfs ntfs  "$TMP/ok.img" "ntfs -F -f $TMP/ok.img"

DISK="$TMP/ok.img"
FORMAT="ext4"
rm -f "$TMP/parted.log"
Format-Disk > "$TMP/out.txt"
assert_contains "$(cat "$TMP/out.txt")" ">>> Formatting (ext4)" "Format-Disk : annonce le formatage"
assert_eq "ext4 -F $TMP/ok.img" "$(cat "$MK_LOG")" "fichier : le système de fichiers est écrit dans le fichier"
assert_false "fichier : parted n'est pas utilisé (pas de table de partitions)" test -e "$TMP/parted.log"

unset -f mkfs.ext4 mkfs.xfs mkfs.vfat mkfs.exfat mkfs.ntfs parted


# ---------------------------------------------------------------------------
section "Show-Header"

DISK=""
LOOPS=1
FORMAT=""
out="$(Show-Header)"
assert_contains "$out" "Target : (none)"       "sans cible : (none)"
assert_contains "$out" "Loops  : 1"             "1 boucle"
assert_contains "$out" "Format : (none)"       "sans formatage : (none)"

DISK="$TMP/ok.img"
LOOPS=3
FORMAT="ext4"
out="$(Show-Header)"
assert_contains "$out" "Target : $TMP/ok.img (file)" "fichier : (file)"
assert_contains "$out" "Loops  : 3"                  "3 boucles"
assert_contains "$out" "Format : ext4"               "formatage affiché"


# ---------------------------------------------------------------------------
section "Start-Wipe : refus avant d'écrire quoi que ce soit"

DISK=""
FORMAT=""
LOOPS=1
out="$(Start-Wipe <<< "")"
assert_contains "$out" "needs to be chosen first" "sans cible : message clair"

DISK="$TMP/disparu.img"
out="$(Start-Wipe <<< "")"
assert_contains "$out" "does not exist anymore" "cible supprimée entre le choix et le lancement"

: > "$TMP/vide.img"
DISK="$TMP/vide.img"
out="$(Start-Wipe <<< "")"
assert_contains "$out" "nothing to wipe" "fichier de 0 octet : rien à effacer"

make_image "$TMP/c.img" 4096
DISK="$TMP/c.img"
out="$(Start-Wipe <<< $'nope\n\n')"
assert_contains "$out" "SUMMARY" "un récapitulatif est affiché"
assert_contains "$out" "Type   : file" "récapitulatif : type file"
assert_contains "$out" "Format : none" "récapitulatif : pas de formatage"
assert_contains "$out" "NOTE : the file is overwritten in place" "récapitulatif : note sur l'écrasement en place"
assert_contains "$out" "Cancelled" "mauvaise confirmation : annulé"
assert_untouched "$TMP/c.img" 4096 "mauvaise confirmation : fichier intact"

DISK="$TMP/c.img"
out="$(Start-Wipe <<< $'\n\n')"
assert_contains "$out" "Cancelled" "confirmation vide : annulé"
assert_untouched "$TMP/c.img" 4096 "confirmation vide : fichier intact"

finish