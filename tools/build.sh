#!/usr/bin/env bash
# BIG RAID LEADER 빌드: 정적 검사 → 자동 테스트 → 배포 ZIP
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 '^## Version:' BigRaidLeader/BigRaidLeader.toc | sed 's/## Version:[[:space:]]*//' | tr -d '\r')
echo "== BIG RAID LEADER v${VERSION} =="

if command -v luacheck >/dev/null 2>&1; then
  echo "-- luacheck"
  luacheck BigRaidLeader -q
else
  echo "-- luacheck 없음: 정적 검사 생략"
fi

LUA=$(command -v lua5.1 || command -v lua || true)
if [ -z "$LUA" ]; then
  echo "Lua 5.1 이 필요합니다" >&2
  exit 1
fi
echo "-- 자동 테스트"
"$LUA" Tests/run_tests.lua Tests/test_*.lua | tail -n 3

echo "-- 배포 ZIP"
mkdir -p dist
rm -f "dist/BigRaidLeader-${VERSION}.zip"
zip -qr -X "dist/BigRaidLeader-${VERSION}.zip" BigRaidLeader -x '*.DS_Store' -x '*/.*'
unzip -l "dist/BigRaidLeader-${VERSION}.zip" | tail -n 1
echo "완료: dist/BigRaidLeader-${VERSION}.zip"
