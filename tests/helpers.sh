#!/usr/bin/env bash

PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

PASS=0
FAIL=0
SKIP=0

section() {
    printf '\n== %s ==\n' "$1"
}

pass() {
    PASS=$((PASS + 1))
    printf '  ok   - %s\n' "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf '  FAIL - %s\n' "$1"

    if [[ -n "${2:-}" ]]; then
        printf '         %s\n' "$2"
    fi
}

skip() {
    SKIP=$((SKIP + 1))
    printf '  skip - %s (%s)\n' "$1" "$2"
}

assert_eq() {
    if [[ "$1" == "$2" ]]; then
        pass "$3"
    else
        fail "$3" "attendu : '$1' / obtenu : '$2'"
    fi
}

assert_contains() {
    if [[ "$1" == *"$2"* ]]; then
        pass "$3"
    else
        fail "$3" "'$2' est introuvable dans la sortie"
    fi
}

assert_not_contains() {
    if [[ "$1" != *"$2"* ]]; then
        pass "$3"
    else
        fail "$3" "'$2' ne devrait pas apparaitre dans la sortie"
    fi
}

assert_true() {
    local msg="$1"
    shift

    if "$@"; then
        pass "$msg"
    else
        fail "$msg" "la commande a échoué : $*"
    fi
}

assert_false() {
    local msg="$1"
    shift

    if "$@"; then
        fail "$msg" "la commande aurait dû échouer : $*"
    else
        pass "$msg"
    fi
}

make_image() {
    head -c "$2" /dev/zero | tr '\0' '\252' > "$1"
}

assert_zero() {
    if cmp -s <(head -c "$2" "$1") <(head -c "$2" /dev/zero); then
        pass "$3"
    else
        fail "$3" "des octets non nuls restent dans $1"
    fi
}

assert_untouched() {
    if cmp -s "$1" <(head -c "$2" /dev/zero | tr '\0' '\252'); then
        pass "$3"
    else
        fail "$3" "$1 a été modifié"
    fi
}

hex_at() {
    od -An -tx1 -j"$2" -N"$3" "$1" | tr -d ' \n'
}

text_at() {
    dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null
}

finish() {
    printf '\nRésultat : %d réussis, %d échoués, %d ignorés\n' "$PASS" "$FAIL" "$SKIP"
    [[ "$FAIL" -eq 0 ]]
}