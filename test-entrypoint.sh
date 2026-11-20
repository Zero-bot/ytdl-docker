#!/bin/sh
# Run under dash: dash test-entrypoint.sh
set -eu

PASS=0
FAIL=0
TOTAL=0

pass() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '  PASS: %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1))
    printf '  FAIL: %s\n    expected: %s\n    got:      %s\n' "$1" "$2" "$3"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/yt-dlp" << 'STUB'
#!/bin/sh
for arg in "$@"; do printf '%s\n' "$arg"; done
STUB
chmod +x "$TMPDIR/yt-dlp"

ENTRYPOINT="$(cd "$(dirname "$0")" && pwd)/entrypoint.sh"
export PATH="$TMPDIR:$PATH"

run() { "$ENTRYPOINT" "$@" 2>/dev/null; }

has()    { printf '%s\n' "$1" | grep -qF -- "$2"; }
hasnot() { ! printf '%s\n' "$1" | grep -qF -- "$2"; }

printf 'Testing entrypoint argument parsing...\n'

# --- 1. Default (video) mode ---
printf '\n1. Default mode\n'
out=$(run "https://example.com/v")
has    "$out" "--ignore-config"        && pass "--ignore-config present"       || fail "--ignore-config" "present" "absent"
has    "$out" "--no-exec"              && pass "--no-exec present"             || fail "--no-exec" "present" "absent"
has    "$out" "--embed-metadata"       && pass "--embed-metadata present"      || fail "--embed-metadata" "present" "absent"
has    "$out" "bv*+ba/b"              && pass "video format selector"         || fail "video format" "bv*+ba/b" "absent"
has    "$out" "--merge-output-format"  && pass "--merge-output-format present" || fail "--merge-output-format" "present" "absent"
has    "$out" "mkv"                    && pass "mkv container"                 || fail "container" "mkv" "absent"
has    "$out" "https://example.com/v"  && pass "URL passed through"            || fail "URL" "present" "absent"

# --- 2. --audio before URL ---
printf '\n2. --audio before URL\n'
out=$(run --audio "https://example.com/a")
has    "$out" "ba/b"              && pass "audio format selector"      || fail "audio format" "ba/b" "absent"
has    "$out" "--embed-thumbnail" && pass "--embed-thumbnail present"   || fail "--embed-thumbnail" "present" "absent"
has    "$out" "-x"                && pass "-x (extract audio) present"  || fail "-x" "present" "absent"
hasnot "$out" "--merge-output-format" && pass "no --merge-output-format" || fail "no merge" "absent" "present"
hasnot "$out" "--audio"               && pass "--audio stripped"         || fail "--audio stripped" "absent" "present"
has    "$out" "https://example.com/a" && pass "URL passed through"      || fail "URL" "present" "absent"

# --- 3. --audio after URL ---
printf '\n3. --audio after URL\n'
out=$(run "https://example.com/b" --audio)
has    "$out" "--embed-thumbnail"      && pass "--embed-thumbnail present" || fail "--embed-thumbnail" "present" "absent"
has    "$out" "https://example.com/b"  && pass "URL passed through"       || fail "URL" "present" "absent"
hasnot "$out" "--audio"                && pass "--audio stripped"          || fail "--audio stripped" "absent" "present"

# --- 4. Quoted / spaced arguments ---
printf '\n4. Quoted arguments\n'
out=$(run --output "my file.%(ext)s" "https://example.com/c")
has "$out" "my file.%(ext)s"          && pass "space-containing arg preserved" || fail "quoted arg" "my file.%(ext)s" "split"
has "$out" "https://example.com/c"    && pass "URL passed through"             || fail "URL" "present" "absent"

# --- 5. No arguments → exit 2 ---
printf '\n5. No arguments\n'
rc=0
"$ENTRYPOINT" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 2 ] && pass "exits 2 with no arguments" || fail "exit code" "2" "$rc"

# --- Summary ---
printf '\n%d/%d passed' "$PASS" "$TOTAL"
[ "$FAIL" -gt 0 ] && printf ', %d FAILED' "$FAIL"
printf '\n'
[ "$FAIL" -eq 0 ]
