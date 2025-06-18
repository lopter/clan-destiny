#!/bin/sh

set -e

origin_var_dir() {
    local machine="$1"
    local username="$2"
    local var_name="$3"
    printf "vars/per-machine/%s/clan-destiny-syncthing-accounts/%s-%s" "$machine" "$username" "$var_name"
}

dest_var_dir() {
    local machine="$1"
    local username="$2"
    local var_name="$3"
    printf "vars/per-machine/%s/clan-destiny-syncthing-account-%s/%s" "$machine" "$username" "$var_name"
}

fix_secret_files() {
    local files="
        cert
        key
        apiKey
        deviceId
    "
    local machine="$1"
    local username="$2"

    for var_name in $files
    do
        # move secrets
        local from="$(origin_var_dir "$machine" "$username" "$var_name")"
        local to="$(dest_var_dir "$machine" "$username" "$var_name")"
        if [ -d "$to" ]
        then
            printf "destination %s already exists\n" "$to"
            continue
        fi
        mkdir -p "$(dirname "$to")"
        mv -v "$from" "$to"
    done
}

fix_secret_files nsrv-cdg-jellicent higuma
fix_secret_files nsrv-cdg-jellicent kal
fix_secret_files nsrv-sfo-ashpool higuma
fix_secret_files nsrv-sfo-ashpool kal
