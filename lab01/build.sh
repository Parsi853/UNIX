fail() {
    printf '%s\n' "$2" >&2
    exit "$1"
}

[ "$#" -eq 1 ] || fail 2 'Usage: sh build.sh SOURCE.c|SOURCE.cpp'
case $1 in
    /*) source=$1 ;;
    *)  source="$PWD/$1" ;;
esac
[ -f "$source" ] && [ -r "$source" ] || fail 2 "Cannot read source: $source"
case $source in
    *.c) compiler=${CC:-cc}; standard=c17 ;;
    *.cpp|*.cc|*.cxx) compiler=${CXX:-c++}; standard=c++17 ;;
    *) fail 2 'Expected a C or C++ source file.' ;;
esac


output=$(LC_ALL=C awk '
    /^[[:space:]]*\/(\/|\*)[[:space:]]*Output:/ {
        if ($0 ~ /^[[:space:]]*\/\*/ && !sub(/\*\/[[:space:]]*$/, "")) exit 1
        sub(/^[[:space:]]*\/(\/|\*)[[:space:]]*Output:/, "")
        name = $0
        count++
    }
    END {
        sub(/^[[:space:]]+/, "", name)
        sub(/[[:space:]]+$/, "", name)
        if (count != 1 || name !~ /^[A-Za-z0-9_][A-Za-z0-9_.-]*$/) exit 1
        print name
    }
' "$source") || fail 3 'Expected exactly one valid Output: filename in a comment.'
dest="${source%/*}/$output"

case $output in
    *.c|*.cpp|*.cc|*.cxx) fail 3 'Output must not have a C/C++ source extension.' ;;
esac
if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
    fail 3 "Output is not a regular file: $dest"
fi
command -v "$compiler" >/dev/null 2>&1 || fail 4 "Compiler not found: $compiler"

build_dir=
compiler_pid=
cleanup() {
    if [ -n "$build_dir" ]; then
        rm -rf "$build_dir"
    fi
}
interrupt() {
    trap '' HUP INT QUIT PIPE TERM
    if [ -n "$compiler_pid" ]; then
        kill -TERM "$compiler_pid" 2>/dev/null || :
        wait "$compiler_pid" 2>/dev/null || :
    fi
    exit "$1"
}
trap cleanup 0
trap 'interrupt 129' HUP
trap 'interrupt 130' INT
trap 'interrupt 131' QUIT
trap 'interrupt 141' PIPE
trap 'interrupt 143' TERM

temp_root=${TMPDIR:-/tmp}
case $temp_root in
    /*) ;;
    *) temp_root="$PWD/$temp_root" ;;
esac
build_dir=$(mktemp -d "${temp_root%/}/unix-build.XXXXXXXX") || fail 6 'Cannot create build directory.'

(
    cd "$build_dir" || exit 1
    TMPDIR=$build_dir
    export TMPDIR
    exec "$compiler" "-std=$standard" -Wall -Wextra -pedantic -O2 "$source" -o artifact
) &
compiler_pid=$!
wait "$compiler_pid"
status=$?
compiler_pid=
[ "$status" -eq 0 ] || fail 5 "Compilation failed (compiler exit code: $status)."
mv -f "$build_dir/artifact" "$dest" || fail 6 "Cannot install output: $dest"
printf '%s\n' "$dest"
