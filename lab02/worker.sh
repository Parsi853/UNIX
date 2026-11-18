#!/bin/sh
set -eu

shared_dir=${SHARED_DIR:-/shared}
container_id=$(od -An -N16 -tx1 /dev/urandom | tr -d '[:space:]')
[ "${#container_id}" -eq 32 ] || { printf 'Не удалось создать идентификатор контейнера\n' >&2; exit 1; }

# Дескриптор 9 у каждого контейнера открыт на один и тот же файл в томе.
exec 9>>"$shared_dir/.lock"
current_file=
sleeper=
file_index=0

cleanup() {
    trap '' HUP INT TERM
    if [ -n "$sleeper" ]; then
        kill -TERM "$sleeper" 2>/dev/null || :
        wait "$sleeper" 2>/dev/null || :
    fi
    if [ -n "$current_file" ]; then
        flock -x 9 && rm -f "$current_file" || return 1
    fi
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

pause() {
    sleep 1 9>&- &
    sleeper=$!
    wait "$sleeper"
    sleeper=
}

while :; do
    file_index=$((file_index + 1))
    # Поиск свободного имени и запись файла идут под одной блокировкой.
    flock -x 9
    number=1
    while :; do
        case $number in
            ?)  name=00$number ;;
            ??) name=0$number ;;
            *)  name=$number ;;
        esac
        candidate=$shared_dir/$name
        if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
            break
        fi
        number=$((number + 1))
    done
    current_file=$candidate
    printf '%s %s\n' "$container_id" "$file_index" >"$current_file"
    flock -u 9
    printf 'создан %s %s %s\n' "$name" "$container_id" "$file_index"

    pause

    flock -x 9
    rm -f "$current_file"
    current_file=
    flock -u 9
    printf 'удалён %s %s %s\n' "$name" "$container_id" "$file_index"

    pause
done
