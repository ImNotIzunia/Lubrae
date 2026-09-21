#!/bin/bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/tests/helpers.sh"

SCRIPT="$ROOT/lubrae.sh"
MIB=1048576
SIZE=$((32 * MIB))

if (( EUID != 0 )); then
    skip "tous les tests sur périphérique bloc" "nécessite root (sudo make test)"
    finish
    exit $?
fi

if ! command -v losetup > /dev/null 2>&1; then
    skip "tous les tests sur périphérique bloc" "losetup absent"
    finish
    exit $?
fi

TMP="$(mktemp -d)"
LOOPDEV=""

detach() {
    if [[ "$LOOPDEV" == /dev/loop* ]]; then
        losetup -d "$LOOPDEV" 2> /dev/null
    fi

    LOOPDEV=""
}

cleanup() {
    detach
    rm -rf "$TMP"
}
trap cleanup EXIT

# attach : crée un fichier de 32 MiB rempli de 0xAA et l'attache à un /dev/loopN
attach() {
    detach
    make_image "$TMP/disk.img" "$SIZE"
    LOOPDEV="$(losetup -f --show "$TMP/disk.img" 2> /dev/null)" || LOOPDEV=""

    if [[ "$LOOPDEV" != /dev/loop* ]]; then
        LOOPDEV=""
        return 1
    fi

    # Copie de lubrae.sh dont la cible est préchargée sur ce périphérique
    # (la liste de choix des disques ne montre pas les périphériques loop).
    sed "0,/^DISK=\"\"/s||DISK=\"$LOOPDEV\"|" "$SCRIPT" > "$TMP/forced.sh"
}

# run_forced "TOUCHES" : lance la copie préchargée avec des touches simulées
run_forced() {
    printf '%b' "$1" | bash "$TMP/forced.sh" 2>&1
}

if ! attach; then
    skip "tous les tests sur périphérique bloc" "impossible de créer un périphérique loop ici"
    finish
    exit $?
fi
detach


# ---------------------------------------------------------------------------
section "Disque sans formatage choisi (le cas par défaut)"

attach
assert_true "le test travaille bien sur un périphérique bloc" test -b "$LOOPDEV"
out="$(run_forced "4\n$LOOPDEV\n\n5\n")"
assert_contains "$out" "Type   : disk" "récapitulatif : type disk"
assert_zero "$LOOPDEV" "$SIZE" "le périphérique est entièrement à zéro"
assert_not_contains "$out" ">>> Formatting" "aucun formatage lancé"
assert_true "aucune table GPT créée (pas de signature 'EFI PART')" \
    test "$(text_at "$LOOPDEV" 512 8)" != "EFI PART"


# ---------------------------------------------------------------------------
section "Disque avec formatage vfat"

if command -v parted > /dev/null 2>&1 \
    && command -v partprobe > /dev/null 2>&1 \
    && command -v mkfs.vfat > /dev/null 2>&1; then

    attach
    out="$(run_forced "3\n4\n4\n$LOOPDEV\n\n5\n")"
    assert_contains "$out" ">>> Formatting (vfat)" "le formatage vfat est lancé"
    assert_not_contains "$out" "${LOOPDEV}p1 not found" "la partition a été trouvée"
    assert_eq "EFI PART" "$(text_at "$LOOPDEV" 512 8)" "une table GPT a été créée"
    assert_eq "FAT32   " "$(text_at "$LOOPDEV" $((MIB + 82)) 8)" "signature FAT32 présente dans la partition"
    assert_true "les anciennes données 0xAA sont écrasées (zone de données à zéro)" \
        cmp -s <(dd if="$LOOPDEV" bs=1M skip=8 count=16 2> /dev/null) <(head -c $((16 * MIB)) /dev/zero)
else
    skip "formatage vfat d'un disque" "parted, partprobe ou mkfs.vfat absent"
fi


# ---------------------------------------------------------------------------
section "Garde-fous"

attach
out="$(run_forced "4\nnon\n\n5\n")"
assert_contains "$out" "Cancelled" "mauvaise confirmation : annulé"
assert_untouched "$LOOPDEV" "$SIZE" "mauvaise confirmation : le périphérique est intact"

finish