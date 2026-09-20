#!/bin/bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=/dev/null
source "$ROOT/tests/helpers.sh"

SCRIPT="$ROOT/lubrae.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MIB=1048576

run_lubrae() {
    local input="$1"
    shift

    printf '%b' "$input" | bash "$SCRIPT" "$@" 2>&1
}


# ---------------------------------------------------------------------------
section "Options de la ligne de commande"

out="$(bash "$SCRIPT" --help 2>&1 < /dev/null)"
rc=$?
assert_eq 0 "$rc" "--help : code 0"
assert_contains "$out" "Usage" "--help : affiche l'aide"
assert_contains "$out" "no root needed" "--help : précise que --file n'a pas besoin de root"

out="$(bash "$SCRIPT" --version 2>&1 < /dev/null)"
rc=$?
assert_eq 0 "$rc" "--version : code 0"
assert_contains "$out" "Lubrae " "--version : affiche la version"

out="$(bash "$SCRIPT" --bidon 2>&1 < /dev/null)"
rc=$?
assert_eq 1 "$rc" "option inconnue : code 1"
assert_contains "$out" "Invalid Option" "option inconnue : message"

bash "$SCRIPT" --file "$TMP/nope.img" > /dev/null 2>&1 < /dev/null
assert_eq 1 "$?" "--file inexistant : code 1"

bash "$SCRIPT" --file "$TMP" > /dev/null 2>&1 < /dev/null
assert_eq 1 "$?" "--file sur un dossier : code 1"

bash "$SCRIPT" --file > /dev/null 2>&1 < /dev/null
assert_eq 1 "$?" "--file sans argument : code 1"

if (( EUID == 0 )); then
    skip "--file sur un fichier en lecture seule" "root peut tout écrire"
else
    make_image "$TMP/ro.img" 4096
    chmod 444 "$TMP/ro.img"
    out="$(bash "$SCRIPT" --file "$TMP/ro.img" 2>&1 < /dev/null)"
    rc=$?
    assert_eq 1 "$rc" "--file en lecture seule : code 1"
    assert_contains "$out" "not writable" "--file en lecture seule : message"
fi


# ---------------------------------------------------------------------------
section "Menu"

out="$(run_lubrae "5\n")"
assert_contains "$out" "Lubrae" "le menu s'ouvre"
assert_contains "$out" "Launch (choose a target first)" "sans cible : Launch indique de choisir une cible"
assert_contains "$out" "Loops  : 1 (3 passes)" "en-tête : 1 boucle = 3 passes"

run_lubrae "5\n" > /dev/null
assert_eq 0 "$?" "5 : quitte avec le code 0"

run_lubrae "q\n" > /dev/null
assert_eq 0 "$?" "q : quitte avec le code 0"

run_lubrae "" > /dev/null
assert_eq 0 "$?" "Ctrl+D : sortie propre"

out="$(run_lubrae "x\n5\n")"
assert_contains "$out" "Invalid choice" "choix invalide : message puis retour au menu"

out="$(run_lubrae "4\n\n5\n")"
assert_contains "$out" "needs to be chosen first" "Launch sans cible : message clair"


# ---------------------------------------------------------------------------
section "Effacement d'un fichier"

make_image "$TMP/w1.img" $((4 * MIB))
real="$(realpath "$TMP/w1.img")"
out="$(run_lubrae "4\n$real\n\n5\n" --file "$TMP/w1.img")"
assert_zero "$TMP/w1.img" $((4 * MIB)) "1 boucle : le fichier est entièrement à zéro"
assert_eq $((4 * MIB)) "$(stat -c %s "$TMP/w1.img")" "la taille du fichier est inchangée"
assert_true "le fichier n'est pas supprimé" test -f "$TMP/w1.img"
assert_contains "$out" "Type   : file" "récapitulatif : type file"
assert_contains "$out" ">>> Pass 1/1" "1 boucle : passe 1/1"
assert_contains "$out" ">>> Final pass" "la passe finale est exécutée"
assert_contains "$out" "Done" "message final"
assert_not_contains "$out" ">>> Formatting" "sans formatage choisi : aucun formatage lancé"
after_done="${out#*Done}"
assert_contains "$after_done" "Target : (none)" "après l'effacement : la cible est désélectionnée"

make_image "$TMP/w2.img" $((4 * MIB))
real="$(realpath "$TMP/w2.img")"
out="$(run_lubrae "2\n2\n4\n$real\n\n5\n" --file "$TMP/w2.img")"
assert_contains "$out" "Loops  : 2 (5 passes)" "2 boucles : l'en-tête annonce 5 passes"
assert_contains "$out" ">>> Pass 2/2" "2 boucles : passe 2/2 exécutée"
assert_zero "$TMP/w2.img" $((4 * MIB)) "2 boucles : le fichier est entièrement à zéro"

make_image "$TMP/c1.img" $((4 * MIB))
real="$(realpath "$TMP/c1.img")"
out="$(run_lubrae "4\nnon\n\n5\n" --file "$TMP/c1.img")"
assert_contains "$out" "Cancelled" "mauvaise confirmation : annulé"
assert_untouched "$TMP/c1.img" $((4 * MIB)) "mauvaise confirmation : fichier intact"

out="$(run_lubrae "4\n\n\n5\n" --file "$TMP/c1.img")"
assert_untouched "$TMP/c1.img" $((4 * MIB)) "confirmation vide : fichier intact"

bash "$SCRIPT" --file "$TMP/c1.img" < /dev/null > /dev/null 2>&1
assert_eq 0 "$?" "Ctrl+D au menu (avec --file) : sortie propre"
assert_untouched "$TMP/c1.img" $((4 * MIB)) "Ctrl+D : fichier intact"

make_image "$TMP/target.img" $((4 * MIB))
ln -s "$TMP/target.img" "$TMP/link.img"
real="$(realpath "$TMP/target.img")"
out="$(run_lubrae "4\n$real\n\n5\n" --file "$TMP/link.img")"
assert_contains "$out" "Target : $real" "lien symbolique : la vraie cible est affichée"
assert_zero "$TMP/target.img" $((4 * MIB)) "lien symbolique : la cible réelle est effacée"
assert_true "lien symbolique : le lien existe toujours" test -L "$TMP/link.img"

make_image "$TMP/mon disque.img" $((4 * MIB))
real="$(realpath "$TMP/mon disque.img")"
out="$(run_lubrae "4\n$real\n\n5\n" --file "$TMP/mon disque.img")"
assert_zero "$TMP/mon disque.img" $((4 * MIB)) "chemin avec des espaces : fichier effacé"


# ---------------------------------------------------------------------------
section "Choisir le fichier depuis le menu"

make_image "$TMP/m1.img" $((4 * MIB))
real="$(realpath "$TMP/m1.img")"
out="$(run_lubrae "1\n2\n$TMP/nope.img\n$real\n5\n")"
assert_contains "$out" "File not found" "chemin invalide signalé"
assert_contains "$out" "Target : $real (file)" "le bon chemin devient la cible (file)"
assert_contains "$out" "4. Launch" "Launch ne demande plus de choisir une cible"

out="$(run_lubrae "1\n2\n\n5\n")"
assert_contains "$out" "Target : (none)" "annulation : aucune cible"

out="$(run_lubrae "1\n2\n$real\n4\n$real\n\n5\n")"
assert_zero "$TMP/m1.img" $((4 * MIB)) "sélection par le menu puis effacement : fichier à zéro"

if (( EUID == 0 )); then
    skip "choisir un disque sans root est refusé" "lancé en root"
else
    out="$(run_lubrae "1\n1\n\n5\n")"
    assert_contains "$out" "requires root" "sans root : le choix d'un disque est refusé"
fi


# ---------------------------------------------------------------------------
section "Formatage d'un fichier (outils réels, ignoré s'ils sont absents)"

if command -v mkfs.ext4 > /dev/null 2>&1; then
    make_image "$TMP/f1.img" $((8 * MIB))
    real="$(realpath "$TMP/f1.img")"
    out="$(run_lubrae "3\n2\n4\n$real\n\n5\n" --file "$TMP/f1.img")"
    assert_contains "$out" "Format : ext4" "récapitulatif : ext4"
    assert_contains "$out" ">>> Formatting (ext4)" "le formatage est lancé"
    assert_eq "53ef" "$(hex_at "$TMP/f1.img" 1080 2)" "signature ext4 (0xEF53) présente dans le fichier"
    assert_eq $((8 * MIB)) "$(stat -c %s "$TMP/f1.img")" "la taille du fichier est inchangée"
else
    skip "formatage ext4" "mkfs.ext4 absent"
fi

if command -v mkfs.vfat > /dev/null 2>&1; then
    make_image "$TMP/f2.img" $((64 * MIB))
    real="$(realpath "$TMP/f2.img")"
    out="$(run_lubrae "3\n4\n4\n$real\n\n5\n" --file "$TMP/f2.img")"
    assert_contains "$out" ">>> Formatting (vfat)" "le formatage vfat est lancé"
    assert_eq "FAT32   " "$(text_at "$TMP/f2.img" 82 8)" "signature FAT32 présente dans le fichier"
else
    skip "formatage vfat" "mkfs.vfat absent"
fi

if command -v mkfs.exfat > /dev/null 2>&1; then
    skip "outil manquant (exfat)" "mkfs.exfat est installé"
else
    make_image "$TMP/f3.img" $((4 * MIB))
    real="$(realpath "$TMP/f3.img")"
    out="$(run_lubrae "3\n5\n4\nn\n\n5\n" --file "$TMP/f3.img")"
    assert_contains "$out" "Missing tools : mkfs.exfat" "outil manquant : signalé avant de commencer"
    assert_untouched "$TMP/f3.img" $((4 * MIB)) "outil manquant : rien n'a été écrit dans le fichier"
fi


# ---------------------------------------------------------------------------
section "Modes de lancement"

out="$(printf '5\n' | bash -c "$(cat "$SCRIPT")" bash 2>&1)"
assert_contains "$out" "Lubrae" "bash -c \"\$(cat lubrae.sh)\" : le menu s'ouvre"

out="$(bash -c "$(cat "$SCRIPT")" bash --version 2>&1 < /dev/null)"
assert_contains "$out" "Lubrae " "bash -c avec un argument : --version fonctionne"

out="$(bash -c "source '$SCRIPT'; echo charge" 2>&1 < /dev/null)"
assert_eq "charge" "$out" "source : aucun effet de bord (pas de menu, pas de sortie)"

finish