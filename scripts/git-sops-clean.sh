#!/usr/bin/env bash

PS4='${LINENO}: '

set -euo pipefail

# Exit if no file given
test $# -eq 1
file="$1"

# Exit if no stdin
test -t 0 && exit 1

decrypt() {
  sops --decrypt --path "$file" /dev/stdin
}

encrypt() {
  sops --encrypt --path "$file" /dev/stdin
}

show() {
  printf "%s\n" "${@}"
}

INPUT=$(cat)
: ${ENCRYPTED:=$(encrypt <<<${INPUT})}
: ${CONTENTS:=$(git cat-file -p "HEAD:$file" 2>/dev/null)}
: ${DECRYPTED=$(decrypt <<<${CONTENTS} 2>/dev/null)}

if [[ -z "${CONTENTS}" || "${DECRYPTED}" != "${INPUT}" ]]
then
  show "${ENCRYPTED}"
else
  show "${CONTENTS}"
fi
