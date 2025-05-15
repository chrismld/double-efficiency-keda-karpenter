#!/usr/bin/env bash
set -euo pipefail

## 10-100
SPEED=50
#SPEED=1000

function cmd() {
    local cmd="${1}"
    if [[ ! -z ${cmd} ]]; then
        echo -e ""    
        echo -en "> ${cmd}" | pv -qL "${SPEED}"
        read -n 1 -s
        echo -e ""
        eval $cmd
        # echo -e "\n"
    fi
}