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

# 13) 전체 설치(가짜 apt/sudo, 빌드는 가짜 pairvim 로 건너뜀): 새 PC 에서 끝까지 돌고, 두 번 돌려도 같은 결과(멱등)
mkstubs() { # apt·sudo·pairvim 가짜(실제 설치·빌드·네트워크 없음). 호출 기록은 $1/calls.log
  mkdir -p "$1/bin"
  printf '#!/bin/sh\necho "apt $*" >>"%s/calls.log"\n' "$1" >"$1/bin/apt"
  printf '#!/bin/sh\necho "sudo $*" >>"%s/calls.log"\nexec "$@"\n' "$1" >"$1/bin/sudo"
  printf '#!/bin/sh\necho "NVIM v0.12.6 (PairVim)"\n' >"$1/bin/pairvim"
  chmod +x "$1/bin/"*
}
H=$(mkhome); T=$(mkhome); mkstubs "$T"; mkdir -p "$H/.config"
touch "$H/.zshrc" "$H/.bashrc"
if [ -d "$HERE/.git" ]; then
  run_install() { ( export HOME="$H" PATH="$T/bin:$PATH"; bash "$HERE/install.sh" --yes ) >"$T/out$1.log" 2>&1; }
  run_install 1; RC1=$?
  [ "$RC1" = 0 ] && [ -f "$H/.config/nvim/init.lua" ] && [ -f "$H/.config/nvim/install.sh" ]; ok "전체 설치(새 PC): 종료 0, 설정이 ~/.config/nvim 에 놓임" $?
  [ "$(git -C "$H/.config/nvim" remote get-url origin)" = "https://github.com/bjw5035/PairVim.git" ]; ok "전체 설치: 원격 주소가 PairVim 공개 주소" $?
  [ "$(grep -c 'npm-global/bin' "$H/.zshrc")" = 1 ] && [ "$(grep -c 'HOME/.local/bin' "$H/.bashrc")" = 1 ]; ok "전체 설치: rc 파일에 PATH 한 줄씩 추가" $?
  [ -d "$H/.npm-global" ]; ok "전체 설치: ~/.npm-global 생성(sudo 없는 npm 전역 경로)" $?
  ! grep -q "npm config" "$T/calls.log" 2>/dev/null; ok "전체 설치: 전역 npm 설정을 바꾸지 않음" $?
  run_install 2; RC2=$?
  [ "$RC2" = 0 ] && [ "$(grep -c 'npm-global/bin' "$H/.zshrc")" = 1 ] && [ "$(grep -c 'HOME/.local/bin' "$H/.bashrc")" = 1 ]; ok "전체 설치 2회차: 멱등(PATH 중복 없음)" $?
  [ ! -e "$H/.config/.pairvim-last-backup" ] && ! ls "$H/.config" | grep -q "nvim-old"; ok "전체 설치 2회차: 이미 PairVim 이라 백업하지 않음" $?
  grep -q "이미 설치되어 있습니다" "$T/out2.log"; ok "빌드 단계: pairvim 이 이미 있으면 다시 빌드하지 않음" $?
fi

# 14) 옛 LazyVim 이 있는 PC 에서 전체 설치: 백업 후 설치, 롤백까지 한 번에
if [ -d "$HERE/.git" ]; then
  H=$(mkhome); T=$(mkhome); mkstubs "$T"; lazyvim "$H"; touch "$H/.zshrc"
  ( export HOME="$H" PATH="$T/bin:$PATH"; bash "$HERE/install.sh" --yes ) >"$T/out.log" 2>&1; RC=$?
  N=$(cat "$H/.config/.pairvim-last-backup" 2>/dev/null)
  [ "$RC" = 0 ] && [ -n "$N" ] && [ "$(cat "$H/.config/$N/init.lua")" = OLD ] && [ -f "$H/.config/nvim/install.sh" ]; ok "옛 LazyVim 있는 PC: 백업 후 전체 설치" $?
  ( export HOME="$H" PATH="$T/bin:$PATH"; bash "$H/.config/nvim/install.sh" --rollback --yes ) >"$T/rb.log" 2>&1; RC=$?
  [ "$RC" = 0 ] && [ "$(cat "$H/.config/nvim/init.lua" 2>/dev/null)" = OLD ] && [ -f "$H/.local/share/nvim/lazy/foo/x" ]; ok "설치 직후 롤백: 옛 설정과 플러그인 복원" $?
fi

# 15) build-pairvim.sh: 가짜 git/make 로 흐름만 확인(실제 빌드 없음)
mkbuild() { # $1=임시폴더 $2=git apply 성공 여부(0/1)
  mkdir -p "$1/bin" "$1/home"
  printf '#!/bin/sh\necho "git $*" >>"%s/calls.log"\ncase "$1" in\n  clone) mkdir -p "$HOME/.local/src/pairvim-neovim" ;;\n  apply) case "$*" in *--reverse*) exit 1;; *) exit %s;; esac ;;\nesac\nexit 0\n' "$1" "$2" >"$1/bin/git"
  printf '#!/bin/sh\necho "make $*" >>"%s/calls.log"\nexit 0\n' "$1" >"$1/bin/make"
  for b in cmake ninja gettext autoconf automake libtool pkg-config gcc unzip curl sudo apt; do printf '#!/bin/sh\nexit 0\n' >"$1/bin/$b"; done
  chmod +x "$1/bin/"*
}
T=$(mkhome); mkbuild "$T" 0
( export HOME="$T/home" PATH="$T/bin:/usr/bin:/bin" PAIRVIM_NVIM_REF=v0.12.6; bash "$HERE/build-pairvim.sh" ) >"$T/out.log" 2>&1; RC=$?
[ "$RC" = 0 ] && grep -q "git clone --depth 1 --branch v0.12.6" "$T/calls.log" && grep -q "^make " "$T/calls.log"; ok "build-pairvim.sh: PAIRVIM_NVIM_REF 태그로 클론하고 make 실행" $?
T=$(mkhome); mkbuild "$T" 1
( export HOME="$T/home" PATH="$T/bin:/usr/bin:/bin"; bash "$HERE/build-pairvim.sh" ) >"$T/out.log" 2>&1; RC=$?
[ "$RC" != 0 ] && grep -q "패치 적용 실패" "$T/out.log" && ! grep -q "^make " "$T/calls.log"; ok "build-pairvim.sh: 패치가 안 맞으면 안내하고 빌드하지 않음" $?
T=$(mkhome); mkbuild "$T" 0
( export HOME="$T/home" PATH="$T/bin:/usr/bin:/bin"; bash "$HERE/build-pairvim.sh" ) >"$T/out.log" 2>&1
grep -q "git clone --depth 1 --branch stable" "$T/calls.log"; ok "build-pairvim.sh: 태그 미지정 시 stable" $?

# 16) Node 자동 설치(가짜 nodejs.org: file:// 로 받음, 실제 네트워크 없음)
case "$(uname -m)" in x86_64|amd64) NARCH=x64 ;; aarch64|arm64) NARCH=arm64 ;; *) NARCH="" ;; esac
if [ -n "$NARCH" ] && command -v sha256sum >/dev/null 2>&1 && command -v curl >/dev/null 2>&1; then
  F=$(mkhome); NV="node-v22.99.0-linux-$NARCH"
  mkdir -p "$F/pkg/$NV/bin" "$F/dist/latest-v22.x"
  printf '#!/bin/sh\n[ "$1" = "-v" ] && echo v22.99.0 || echo node-stub\n' >"$F/pkg/$NV/bin/node"
  printf '#!/bin/sh\necho 10.0.0\n' >"$F/pkg/$NV/bin/npm"; chmod +x "$F/pkg/$NV/bin/"*
  ( cd "$F/pkg" && tar -czf "$F/dist/latest-v22.x/$NV.tar.gz" "$NV" )
  ( cd "$F/dist/latest-v22.x" && sha256sum "$NV.tar.gz" >SHASUMS256.txt )
  # 최소 PATH: 필요한 도구만 연결(시스템의 node 가 섞이지 않게). apt/sudo 는 호출만 기록하는 가짜
  SHIM=$(mkhome); L=$(mkhome)
  for b in curl tar gzip sha256sum grep sed head mkdir ln rm mktemp uname cat bash sh env dirname cut sort awk mv cp date git cmp; do
    w=$(command -v "$b" 2>/dev/null); [ -n "$w" ] && [ -x "$w" ] && ln -s "$w" "$SHIM/$b"
  done
  printf '#!/bin/sh\necho "apt $*" >>"%s/calls.log"\n' "$L" >"$SHIM/apt"
  printf '#!/bin/sh\necho "sudo $*" >>"%s/calls.log"\nexec "$@"\n' "$L" >"$SHIM/sudo"
  printf '#!/bin/sh\necho "NVIM v0.12.6 (PairVim)"\n' >"$SHIM/pairvim"; chmod +x "$SHIM/apt" "$SHIM/sudo" "$SHIM/pairvim"
  nodestub() { mkdir -p "$1"; printf '#!/bin/sh\necho %s\n' "$2" >"$1/node"; chmod +x "$1/node"; } # $2 = 출력할 버전 문자열
  runnode() { # $1=HOME $2=PATH 앞부분 $3=NODE_DIST_BASE 나머지=함수
    local h="$1" pp="$2" base="$3"; shift 3
    ( export HOME="$h" PATH="$pp$SHIM" NODE_DIST_BASE="$base" YES=1 DRY="${DRY:-0}"; source "$HERE/install.sh"; "$@" )
  }

  H=$(mkhome); runnode "$H" "" "file://$F/dist" ensure_node >"$F/o1.log" 2>&1; RC=$?
  [ "$RC" = 0 ] && [ -x "$H/.local/node/bin/node" ] && [ "$("$H/.local/node/bin/node" -v)" = v22.99.0 ]; ok "Node 없음: 사용자 폴더(~/.local/node)에 설치" $?
  [ -x "$H/.local/node/bin/npm" ]; ok "Node 설치: npm 도 함께" $?
  runnode "$H" "" "file://$F/dist" ensure_node >"$F/o1b.log" 2>&1; RC=$?
  [ "$RC" = 0 ] && [ "$(readlink "$H/.local/node")" = "$H/.local/share/pairvim-node/v22.99.0" ]; ok "Node 설치 2회차: 멱등(링크 그대로)" $?

  H=$(mkhome); nodestub "$F/old" v12.22.9
  runnode "$H" "$F/old:" "file://$F/dist" ensure_node >"$F/o2.log" 2>&1; RC=$?
  [ "$RC" = 0 ] && [ "$("$H/.local/node/bin/node" -v 2>/dev/null)" = v22.99.0 ] && [ "$(PATH="$F/old:$SHIM" node -v)" = v12.22.9 ]; ok "Node 12(낮음): 새로 설치하고 기존 것은 건드리지 않음" $?

  H=$(mkhome); nodestub "$F/ok" v20.11.0
  runnode "$H" "$F/ok:" "file:///nonexistent" ensure_node >"$F/o3.log" 2>&1; RC=$?
  [ "$RC" = 0 ] && [ ! -e "$H/.local/node" ] && grep -q "이미 충분" "$F/o3.log"; ok "Node 20(충분): 받지 않고 건너뜀" $?

  H=$(mkhome); : >"$L/calls.log"; BAD=$(mkhome); mkdir -p "$BAD/latest-v22.x"; cp "$F/dist/latest-v22.x/$NV.tar.gz" "$BAD/latest-v22.x/"
  sed 's/^./0/' "$F/dist/latest-v22.x/SHASUMS256.txt" >"$BAD/latest-v22.x/SHASUMS256.txt"
  runnode "$H" "" "file://$BAD" ensure_node >"$F/o4.log" 2>&1; RC=$?
  [ ! -e "$H/.local/node" ] && grep -q "sha256" "$F/o4.log"; ok "해시 불일치: 설치하지 않음" $?
  grep -q "apt install -y nodejs npm" "$L/calls.log"; ok "해시 불일치·Node 없음: apt 로 대체 설치 시도" $?

  H=$(mkhome); : >"$L/calls.log"
  runnode "$H" "" "file:///nonexistent" ensure_node >"$F/o5.log" 2>&1
  [ ! -e "$H/.local/node" ] && grep -q "apt install -y nodejs npm" "$L/calls.log"; ok "네트워크 차단(받기 실패): apt 로 대체" $?

  H=$(mkhome); DRY=1 runnode "$H" "" "file:///nonexistent" ensure_node >"$F/o6.log" 2>&1; RC=$?
  [ "$RC" = 0 ] && [ ! -e "$H/.local/node" ] && grep -q "dry-run" "$F/o6.log"; ok "dry-run: 받지 않고 계획만 출력" $?

  # 전체 설치: Node 없는 새 PC → rc 에 PATH 한 줄, 두 번 돌려도 중복 없음
  H=$(mkhome); mkdir -p "$H/.config"; touch "$H/.zshrc" "$H/.bashrc"; : >"$L/calls.log"
  if [ -d "$HERE/.git" ]; then
    for i in 1 2; do ( export HOME="$H" PATH="$SHIM" NODE_DIST_BASE="file://$F/dist"; bash "$HERE/install.sh" --yes ) >"$F/full$i.log" 2>&1; RC=$?; done
    [ "$RC" = 0 ] && [ "$("$H/.local/node/bin/node" -v)" = v22.99.0 ]; ok "전체 설치(Node 없는 새 PC): Node 자동 설치까지 완료" $?
    [ "$(grep -c 'local/node/bin' "$H/.zshrc")" = 1 ] && [ "$(grep -c 'local/node/bin' "$H/.bashrc")" = 1 ]; ok "전체 설치: rc 에 Node PATH 한 줄씩(2회 실행해도 중복 없음)" $?
  fi
fi

echo; echo "TOTAL $((PASS+FAIL)), FAIL $FAIL"
exit $FAIL
