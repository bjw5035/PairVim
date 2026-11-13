#!/usr/bin/env bash
# install.sh 의 백업·롤백·판별 시험. 가짜 HOME(임시 폴더)만 쓰고 apt·네트워크·빌드는 부르지 않는다.
# 실행: bash tests/test_install.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
ok() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "PASS  $1"; else FAIL=$((FAIL+1)); echo "FAIL  $1"; fi; }
mkhome() { mktemp -d /tmp/pairvim-test.XXXXXX; }
# 함수만 불러서 실행한다: install.sh 를 source 하고 인자로 받은 함수를 부른다(HOME 은 호출 전에 가짜로 바꿔 둔다).
call() { local h="$1"; shift; ( export HOME="$h"; export YES="${YES:-0}" DRY="${DRY:-0}"; source "$HERE/install.sh"; "$@" ); }
lazyvim() { # 옛 LazyVim 흉내: 설정·플러그인·mason·runtime·state·cache
  mkdir -p "$1/.config/nvim/lua" "$1/.local/share/nvim/lazy/foo" "$1/.local/share/nvim/mason/bin" "$1/.local/share/nvim/runtime" "$1/.local/state/nvim" "$1/.cache/nvim"
  echo OLD >"$1/.config/nvim/init.lua"; echo OLD >"$1/.local/share/nvim/lazy/foo/x"
}
pairvim_repo() { # PairVim 클론 흉내(원격 주소만 맞춘 git 저장소)
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" remote add origin "${2:-https://github.com/bjw5035/PairVim.git}"; echo NEW >"$1/init.lua"
}

# 1) 아무것도 없는 새 PC: 백업 없음
H=$(mkhome); YES=1 call "$H" backup_existing >/dev/null; [ ! -e "$H/.config/.pairvim-last-backup" ]; ok "새 PC: 백업하지 않음" $?

# 2) .git 없는 LazyVim: 이름 붙여 옮기고 runtime·mason 은 그대로
H=$(mkhome); lazyvim "$H"; YES=1 call "$H" backup_existing >/dev/null
N=$(cat "$H/.config/.pairvim-last-backup" 2>/dev/null)
[ -n "$N" ] && [ ! -e "$H/.config/nvim" ] && [ "$(cat "$H/.config/$N/init.lua")" = OLD ]; ok "LazyVim(.git 없음): 설정을 $N 으로 옮김" $?
[ -f "$H/.local/share/$N/lazy/foo/x" ] && [ ! -d "$H/.local/share/nvim/lazy" ]; ok "플러그인(lazy)을 옮김" $?
[ -d "$H/.local/state/$N" ] && [ -d "$H/.cache/$N" ]; ok "state·cache 를 같은 이름으로 옮김" $?
[ -d "$H/.local/share/nvim/mason/bin" ] && [ -d "$H/.local/share/nvim/runtime" ]; ok "mason·runtime 은 건드리지 않음" $?
case "$N" in nvim-old-[0-9]*) r=0;; *) r=1;; esac; ok "백업 이름 형식 nvim-old-<시각>" $r

# 3) 다른 원격의 .git 이 있는 설정(예: LazyVim starter 클론)도 '기존 설정'으로 취급
H=$(mkhome); pairvim_repo "$H/.config/nvim" "https://github.com/LazyVim/starter.git"; YES=1 call "$H" backup_existing >/dev/null
[ ! -e "$H/.config/nvim" ] && [ -f "$H/.config/.pairvim-last-backup" ]; ok "다른 원격의 .git: PairVim 으로 착각하지 않고 백업" $?

# 4) 이미 PairVim 이면 백업하지 않음(옛 이름 nvim-config 도 인정)
for U in https://github.com/bjw5035/PairVim.git git@github.com:bjw5035/nvim-config.git; do
  H=$(mkhome); pairvim_repo "$H/.config/nvim" "$U"; YES=1 call "$H" backup_existing >/dev/null
  [ -f "$H/.config/nvim/init.lua" ] && [ ! -f "$H/.config/.pairvim-last-backup" ]; ok "이미 PairVim($U): 백업 없음" $?
done

# 5) --dry-run: 아무것도 옮기지 않고 계획만 출력
H=$(mkhome); lazyvim "$H"; OUT=$(DRY=1 call "$H" backup_existing)
[ -f "$H/.config/nvim/init.lua" ] && [ -d "$H/.local/share/nvim/lazy" ] && [ ! -f "$H/.config/.pairvim-last-backup" ] && echo "$OUT" | grep -q '\[dry-run\] mv'; ok "dry-run: 옮기지 않고 계획만 출력" $?

# 6) 비대화형 + --yes 없음: 확인할 수 없으니 중단하고 아무것도 바꾸지 않음
H=$(mkhome); lazyvim "$H"; call "$H" backup_existing </dev/null >/dev/null 2>&1; RC=$?
[ "$RC" != 0 ] && [ -f "$H/.config/nvim/init.lua" ]; ok "확인 불가(비대화형): 중단, 변경 없음" $?

# 7) 롤백: 백업 후 PairVim 이 깔린 상태에서 되돌리면 옛 설정이 제자리로 돌아오고 PairVim 쪽은 사라짐
H=$(mkhome); lazyvim "$H"; YES=1 call "$H" backup_existing >/dev/null
pairvim_repo "$H/.config/nvim"; mkdir -p "$H/.local/share/nvim/lazy/new" "$H/.local/state/nvim" "$H/.cache/nvim"; echo NEW >"$H/.local/share/nvim/lazy/new/y"
YES=1 call "$H" rollback >/dev/null
[ "$(cat "$H/.config/nvim/init.lua")" = OLD ] && [ -f "$H/.local/share/nvim/lazy/foo/x" ] && [ ! -e "$H/.local/share/nvim/lazy/new" ] && [ ! -f "$H/.config/.pairvim-last-backup" ]; ok "롤백: 옛 설정·플러그인 복원, PairVim 쪽 제거, 기록 삭제" $?
[ -d "$H/.local/share/nvim/mason/bin" ] && [ -d "$H/.local/share/nvim/runtime" ]; ok "롤백 뒤에도 mason·runtime 유지" $?

# 8) 백업 기록이 없으면 롤백을 거절
H=$(mkhome); call "$H" rollback >/dev/null 2>&1; [ $? != 0 ]; ok "백업 기록 없음: 롤백 거절" $?

# 9) 받아 둔 클론(~/pairvim-setup)에서 실행: 로그인을 다시 묻지 않도록 로컬 클론을 복제하고 원격 주소를 맞춘다
H=$(mkhome); S="$H/pairvim-setup"; pairvim_repo "$S"; git -C "$S" -c user.email=t@t -c user.name=t add -A >/dev/null; git -C "$S" -c user.email=t@t -c user.name=t commit -qm init; cp "$HERE/install.sh" "$S/install.sh"
( export HOME="$H"; export YES=1; cd "$S"; source ./install.sh; place_config ) >/dev/null 2>&1
[ -f "$H/.config/nvim/init.lua" ] && git -C "$H/.config/nvim" remote get-url origin | grep -q 'bjw5035/PairVim'; ok "bootstrap 클론에서 ~/.config/nvim 구성(원격 주소 PairVim)" $?

# 10) 옛 README 방식(~/.config/nvim 에 직접 클론한 PairVim 에서 실행)은 그대로 동작
H=$(mkhome); pairvim_repo "$H/.config/nvim"; cp "$HERE/install.sh" "$H/.config/nvim/install.sh"
( export HOME="$H"; cd "$H/.config/nvim"; source ./install.sh; place_config ) 2>&1 | grep -q "바로 실행됨"; ok "~/.config/nvim 안에서 실행: 클론 단계 건너뜀" $?

# 11) dry-run 전체 흐름: 기존 LazyVim + apt 환경이어도 아무것도 바꾸지 않음(apt 가 없으면 이 항목은 건너뜀)
if command -v apt >/dev/null 2>&1; then
  H=$(mkhome); lazyvim "$H"; BEFORE=$(cd "$H" && find . | sort | sha256sum)
  ( export HOME="$H"; bash "$HERE/install.sh" --dry-run ) >/tmp/pv-dry.out 2>&1; RC=$?
  AFTER=$(cd "$H" && find . | sort | sha256sum)
  [ "$RC" = 0 ] && [ "$BEFORE" = "$AFTER" ] && grep -q "dry-run 끝" /tmp/pv-dry.out; ok "전체 dry-run: 종료 0, 파일 변화 없음" $?
fi

# 12) 실제 스크립트로 롤백: 스크립트가 지워질 ~/.config/nvim 안에 있어도 끝까지 동작(임시 복사본으로 재실행)
H=$(mkhome); lazyvim "$H"; YES=1 call "$H" backup_existing >/dev/null
pairvim_repo "$H/.config/nvim"; cp "$HERE/install.sh" "$H/.config/nvim/install.sh"; mkdir -p "$H/.local/share/nvim/lazy/new"
( export HOME="$H"; bash "$H/.config/nvim/install.sh" --rollback --yes ) >/dev/null 2>&1; RC=$?
[ "$RC" = 0 ] && [ "$(cat "$H/.config/nvim/init.lua" 2>/dev/null)" = OLD ] && [ ! -e "$H/.local/share/nvim/lazy/new" ]; ok "--rollback 실행: 자기 자신이 든 폴더를 지워도 정상 종료·복원" $?

echo; echo "TOTAL $((PASS+FAIL)), FAIL $FAIL"
exit $FAIL
