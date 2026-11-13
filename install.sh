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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$SCRIPT_DIR" = "$CONFIG_DIR" ]; then
  # 이미 ~/.config/nvim 안에서(= git clone 된 상태로) 실행된 경우 - 클론 불필요
  echo "$CONFIG_DIR 에서 바로 실행됨. 클론 단계 건너뜀."
else
  if [ -d "$CONFIG_DIR" ] && [ ! -d "$CONFIG_DIR/.git" ]; then
    backup="$CONFIG_DIR.bak.$(date +%Y%m%d%H%M%S)"
    echo "기존 nvim 설정을 $backup 으로 백업합니다"
    mv "$CONFIG_DIR" "$backup"
  fi

  if [ ! -d "$CONFIG_DIR" ]; then
    echo "PairVim 설정 클론 중... (비공개 저장소라 GitHub 로그인 창이 뜰 수 있음)"
    git clone "$REPO_URL" "$CONFIG_DIR"
  else
    echo "$CONFIG_DIR 는 이미 PairVim 레포입니다. 건너뜀."
  fi
fi

# npm 전역 설치를 sudo 없이 하기 위한 사용자 전용 prefix
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global" >/dev/null 2>&1 || true

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  grep -q 'npm-global/bin' "$rc" || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >>"$rc"
  grep -q 'HOME/.local/bin' "$rc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$rc"
done

# 'pairvim'을 alias가 아니라 실제 실행 파일로 설치 - PATH상 어디서든, 어떤 쉘에서든 동작
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/pairvim" <<'EOF'
#!/usr/bin/env bash
exec nvim "$@"
EOF
chmod +x "$HOME/.local/bin/pairvim"

export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"

echo "== 설치 완료 =="
echo "새 터미널을 열거나 'source ~/.zshrc' 실행 후 'pairvim' (또는 nvim) 으로 시작하세요."
echo "처음 실행하면 플러그인과 codex/claude CLI가 자동으로 설치됩니다."
