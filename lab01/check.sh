set -eu

cd "$(dirname "$0")"
build=$PWD/build.sh
test_dir=$(mktemp -d)
builder=
cleanup() {
    if [ -n "$builder" ]; then
        kill -TERM "$builder" 2>/dev/null || :
        wait "$builder" 2>/dev/null || :
    fi
    rm -rf "$test_dir"
}
trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$test_dir/source files" "$test_dir/scratch"
source=$test_dir/source\ files/hello.c
cp hello.c "$source"
TMPDIR=$test_dir/scratch
export TMPDIR

expect_status() {
    expected=$1
    shift
    actual=0
    "$@" || actual=$?
    [ "$actual" -eq "$expected" ] || {
        printf 'Ожидался код %s, получен %s\n' "$expected" "$actual" >&2
        exit 1
    }
    [ -z "$(ls -A "$TMPDIR")" ]
}

expect_status 0 sh "$build" "$source"
[ "$("${source%/*}/hello")" = 'Привет, UNIX!' ]
printf '%s\n' '// Output: ../unsafe' 'int main(void) { return 0; }' >"$source"
expect_status 3 sh "$build" "$source"
printf '%s\n' '// Output: fail' 'int main(void) { invalid }' >"$source"
expect_status 5 sh "$build" "$source"
[ ! -e "${source%/*}/fail" ]

cat >"$test_dir/slow-cc" <<'EOF'
#!/bin/sh
: >"$READY"
exec sleep 30
EOF
chmod +x "$test_dir/slow-cc"
READY=$test_dir/ready CC=$test_dir/slow-cc sh "$build" "$source" &
builder=$!
attempt=0
while [ ! -f "$test_dir/ready" ] && [ "$attempt" -lt 5 ]; do
    sleep 1
    attempt=$((attempt + 1))
done
[ -f "$test_dir/ready" ]
kill -TERM "$builder"
expect_status 143 wait "$builder"
builder=
[ ! -e "${source%/*}/fail" ]
printf 'Успешно проверены сборка, неверный комментарий, ошибка компиляции и очистка при SIGTERM\n'
