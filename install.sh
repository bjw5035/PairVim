#!/usr/bin/env bash
# PairVim 설치 스크립트: Neovim 자체 설치부터 PairVim 설정 적용까지 한 번에
set -euo pipefail

REPO_URL="https://github.com/bjw5035/PairVim.git"
CONFIG_DIR="$HOME/.config/nvim"

echo "== PairVim 설치 시작 =="

install_apt_pkgs() {
  local pkgs=()
  command -v nvim >/dev/null 2>&1 || pkgs+=(neovim)
  command -v git >/dev/null 2>&1 || pkgs+=(git)
  command -v node >/dev/null 2>&1 || pkgs+=(nodejs npm)
  command -v rg >/dev/null 2>&1 || pkgs+=(ripgrep)
  { command -v fdfind >/dev/null 2>&1 || command -v fd >/dev/null 2>&1; } || pkgs+=(fd-find)

  if [ "${#pkgs[@]}" -gt 0 ]; then
    echo "설치할 패키지: ${pkgs[*]}"
    sudo apt update
    sudo apt install -y "${pkgs[@]}"
  else
    echo "필수 패키지 이미 설치되어 있음"
  fi
}

if command -v apt >/dev/null 2>&1; then
  install_apt_pkgs
else
  echo "apt가 없는 환경입니다. neovim / git / node+npm / ripgrep / fd 를 직접 설치한 뒤 다시 실행해주세요."
  exit 1
fi

if [ -d "$CONFIG_DIR" ] && [ ! -d "$CONFIG_DIR/.git" ]; then
  backup="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
  echo "기존 nvim 설정을 $backup 으로 백업합니다"
  mv "$CONFIG_DIR" "$backup"
fi

if [ ! -d "$CONFIG_DIR" ]; then
  echo "PairVim 설정 클론 중..."
  git clone "$REPO_URL" "$CONFIG_DIR"
else
  echo "$CONFIG_DIR 는 이미 PairVim 레포입니다. 건너뜀."
fi

# npm 전역 설치를 sudo 없이 하기 위한 사용자 전용 prefix
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global" >/dev/null 2>&1 || true

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  grep -q 'npm-global/bin' "$rc" || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >>"$rc"
  grep -q "alias pairvim=" "$rc" || echo "alias pairvim='nvim'" >>"$rc"
done

export PATH="$HOME/.npm-global/bin:$PATH"

echo "== 설치 완료 =="
echo "새 터미널을 열거나 'source ~/.zshrc' 실행 후 'pairvim' (또는 nvim) 으로 시작하세요."
echo "처음 실행하면 플러그인과 codex/claude CLI가 자동으로 설치됩니다."
