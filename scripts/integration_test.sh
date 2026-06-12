#!/bin/sh
# ArUco integration test: runs the built CLI against testdata fixtures.
set -e
cd "$(dirname "$0")/.."

zig build
LOUPE=./zig-out/bin/loupe

fail() { echo "FAIL: $1"; echo "  output: $2"; exit 1; }

out=$($LOUPE aruco --json testdata/aruco_4x4_23.png)
echo "$out" | grep -q '"id":23' || fail "plain 4x4 id 23" "$out"
echo "$out" | grep -q '"dictionary":"DICT_4X4_50"' || fail "dictionary name" "$out"

out=$($LOUPE aruco --json testdata/aruco_6x6_42_rot25.png)
echo "$out" | grep -q '"id":42' || fail "rotated 6x6 id 42" "$out"

out=$($LOUPE aruco --json testdata/aruco_multi.png)
echo "$out" | grep -q '"id":7' || fail "multi: 4x4 id 7" "$out"
echo "$out" | grep -q '"id":42' || fail "multi: 6x6 id 42" "$out"

out=$($LOUPE aruco --json --dict 4X4_50 testdata/aruco_multi.png)
echo "$out" | grep -q '"id":7' || fail "--dict keeps 4x4 id 7" "$out"
if echo "$out" | grep -q '"id":42'; then fail "--dict 4X4_50 must exclude the 6x6 marker" "$out"; fi

out=$($LOUPE aruco testdata/aruco_4x4_23.png)
echo "$out" | grep -q "id 23 (DICT_4X4_50)" || fail "human output" "$out"

echo "PASS: all aruco integration checks"
