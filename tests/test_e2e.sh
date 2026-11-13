#!/usr/bin/env bash
# e2e 시험 실행기: nvim 과 python3 이 있을 때만 돈다(없으면 건너뜀). 사용: bash tests/test_e2e.sh
cd "$(dirname "$0")/.." || exit 1
command -v nvim >/dev/null 2>&1 || [ -n "${NVIM:-}" ] || { echo "SKIP  nvim 이 없어 e2e 시험을 건너뜁니다"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP  python3 이 없습니다"; exit 0; }
exec python3 tests/e2e/e2e.py
