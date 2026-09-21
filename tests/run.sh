#!/bin/bash

# shellcheck disable=SC2317,SC2329,SC2034

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

suites=("$@")

if [[ ${#suites[@]} -eq 0 ]]; then
    suites=(unit integration block)
fi

failed=()

for suite in "${suites[@]}"; do
    if [[ ! -f "$ROOT/tests/$suite.sh" ]]; then
        echo "Suite de tests inconnue : $suite (unit, integration ou block)" >&2
        exit 2
    fi

    printf '\n################ %s ################\n' "$suite"

    if command -v timeout > /dev/null 2>&1; then
        run_suite=(timeout 300 bash "$ROOT/tests/$suite.sh")
    else
        run_suite=(bash "$ROOT/tests/$suite.sh")
    fi

    if ! "${run_suite[@]}"; then
        failed+=("$suite")
    fi
done

echo

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "ECHEC dans : ${failed[*]}"
    exit 1
fi

echo "Tous les tests sont passés"

