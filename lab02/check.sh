#!/bin/sh
set -eu

# Use a separate project and volume so the check does not alter a running demo.
cd "$(dirname "$0")"
project=unix-lab02-check-$$
compose() { docker compose -p "$project" "$@"; }
cleanup() { compose down -v >/dev/null 2>&1 || :; }
trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM

compose build worker
for replicas in 1 10 50; do
    compose up -d --no-build --scale "worker=$replicas"
    sleep 5
    count=$(compose ps --status running -q worker | wc -l)
    [ "$count" -eq "$replicas" ]

    snapshot=$(compose exec -T --index 1 worker sh -eu -c '
        cd /shared
        exec 9>>.lock
        flock -s 9
        for file in [0-9]*; do
            [ -f "$file" ] || continue
            cat "$file"
        done
    ')
    printf '%s\n' "$snapshot" | awk -v replicas="$replicas" '
        /^$/ { next }
        NF != 2 || length($1) != 32 || $1 !~ /^[0-9a-f]+$/ || $2 !~ /^[1-9][0-9]*$/ { bad = 1 }
        ++active[$1] != 1 { bad = 1 }
        { count++ }
        END { exit (bad || count > replicas) }
    '

    compose stop worker
    logs=$(compose logs --no-color --no-log-prefix worker)
    printf '%s\n' "$logs" | awk -v replicas="$replicas" '
        $1 == "создан" {
            if ($3 in opened || $4 != created[$3] + 1) bad = 1
            created[$3]++
            opened[$3] = $2
        }
        $1 == "удалён" {
            if (opened[$3] != $2 || created[$3] != $4) bad = 1
            closed[$3]++
            delete opened[$3]
        }
        END {
            for (id in created) {
                workers++
                if (closed[id] < 2) bad = 1
            }
            exit (bad || workers != replicas)
        }
    '

    compose run --rm --no-deps -T --entrypoint sh worker -ec '
        for file in /shared/[0-9]*; do
            [ ! -e "$file" ] && [ ! -L "$file" ] || exit 1
        done
    '
    printf 'Успешно проверены %d контейнеров, порядок операций и очистка\n' "$replicas"
    compose down -v
done
