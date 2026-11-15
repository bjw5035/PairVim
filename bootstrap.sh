#!/usr/bin/env bash
# 한 줄 설치: git 설치 → 저장소 받기 → 터미널 환경(zsh·테마·tmux/vim·폰트) + PairVim 설치까지 한 번에.
# 관리자 비밀번호가 필요한 작업이 있으면 중간에 입력창이 뜬다.
#
# 사용(Ubuntu 데스크탑에는 wget 이 기본 설치돼 있다):
#   bash -c "$(wget -qO- https://raw.githubusercontent.com/bjw5035/PairVim/main/bootstrap.sh)"
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/bjw5035/PairVim/main/bootstrap.sh)"
# 옵션(뒤에 이어서 붙인다):
#   --dry-run      아무것도 바꾸지 않고 계획만 출력
#   --no-pairvim   PairVim(Neovim 직접 빌드, 수 분 걸림)은 설치하지 않음
#   --no-theme     색상 테마는 건너뜀
#   --yes          확인 질문에 모두 예
set -euo pipefail

REPO_URL="${PAIRVIM_REPO_URL:-https://github.com/bjw5035/PairVim.git}"
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi

# 이미 ~/.config/nvim 이 PairVim 이면 그것을 쓰고, 아니면 ~/pairvim-setup 에 받는다.
DIR="$HOME/pairvim-setup"
if [ -d "$HOME/.config/nvim/.git" ] && git -C "$HOME/.config/nvim" remote get-url origin 2>/dev/null | grep -qiE 'bjw5035/(PairVim|nvim-config)'; then
  DIR="$HOME/.config/nvim"
fi

args=() ; with_pairvim=1
for a in "$@"; do
  case "$a" in
    --no-pairvim) with_pairvim=0 ;;
    *) args+=("$a") ;;
  esac
done
[ "$with_pairvim" = 1 ] && args+=(--with-pairvim)

if ! command -v git >/dev/null 2>&1; then
  command -v apt >/dev/null 2>&1 || { echo "git 이 없고 apt 도 없습니다. git 을 직접 설치한 뒤 다시 실행하세요." >&2; exit 1; }
  echo "git 이 없어 설치합니다(관리자 비밀번호를 물을 수 있습니다)."
  $SUDO apt update
  $SUDO apt install -y git
fi

if [ -d "$DIR/.git" ]; then
  echo "저장소 업데이트: $DIR"
  git -C "$DIR" pull --ff-only || echo "업데이트에 실패했지만(로컬 수정 등) 받아 둔 버전으로 계속합니다."
else
  echo "저장소 받기: $DIR"
  git clone "$REPO_URL" "$DIR"
fi

exec bash "$DIR/terminal-setup.sh" "${args[@]}"
