#!/bin/sh
set -eu

cd "$(dirname "$0")"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' 0
trap 'exit 130' INT
trap 'exit 143' TERM
cp Makefile dedup.cpp "$test_dir/"
make -C "$test_dir"

tree=$test_dir/data
mkdir -p "$tree/sub dir"
printf 'same\000binary\n' >"$tree/a.bin"
cp "$tree/a.bin" "$tree/sub dir/b.bin"
ln "$tree/a.bin" "$tree/a-linked.bin"
printf 'else\000binary\n' >"$tree/unique.bin"
: >"$tree/empty-a"
: >"$tree/empty-b"
ln -s a.bin "$tree/symlink"
mkfifo "$tree/fifo"

result=$("$test_dir/dedup" --dry-run "$tree")
printf '%s\n' "$result" | grep -Fx 'Файлов=6 к_замене=2 уже_связаны=1 ошибок=0'
[ ! "$tree/a.bin" -ef "$tree/sub dir/b.bin" ]

result=$("$test_dir/dedup" "$tree")
printf '%s\n' "$result" | grep -Fx 'Файлов=6 заменено=2 уже_связаны=1 ошибок=0'
[ "$tree/a.bin" -ef "$tree/sub dir/b.bin" ]
[ "$tree/a-linked.bin" -ef "$tree/sub dir/b.bin" ]
[ "$tree/empty-a" -ef "$tree/empty-b" ]
[ ! "$tree/a.bin" -ef "$tree/unique.bin" ]
[ -L "$tree/symlink" ] && [ -p "$tree/fifo" ]

result=$("$test_dir/dedup" "$tree")
printf '%s\n' "$result" | grep -Fx 'Файлов=6 заменено=0 уже_связаны=3 ошибок=0'
printf 'Успешно проверены ссылки, обход подкаталогов, двоичные и пустые файлы, повторный запуск\n'
