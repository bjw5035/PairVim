#!/usr/bin/env bash
# neovim/neovim 소스를 받아 PairVim 패치(실행 파일 이름/버전 문자열 리브랜딩)를 적용하고
# 직접 빌드해서 설치하는 스크립트. install.sh에서 호출되거나 단독으로도 실행 가능.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/pairvim-rebrand.patch"
NVIM_SRC_DIR="$HOME/.local/src/pairvim-neovim"
NVIM_REF="${PAIRVIM_NVIM_REF:-stable}"   # 패치가 안 맞으면 PAIRVIM_NVIM_REF=v0.12.6 처럼 태그를 지정해 다시 실행
PREFIX="$HOME/.local"

echo "== PairVim(개인 Neovim 빌드) 시작 =="

if command -v pairvim >/dev/null 2>&1; then
  echo "pairvim이 이미 설치되어 있습니다: $(command -v pairvim)"
  pairvim --version | head -1
  echo "다시 빌드하려면 이 바이너리를 지우고 재실행하세요: rm $(command -v pairvim)"
  exit 0
fi

install_build_deps() {
  if ! command -v apt >/dev/null 2>&1; then
    echo "apt가 없는 환경입니다. cmake / ninja-build / gettext / autoconf / automake / libtool-bin / pkg-config / build-essential / unzip / curl 을 직접 설치한 뒤 다시 실행하세요."
    return
  fi
  local pkgs=()
  command -v cmake >/dev/null 2>&1 || pkgs+=(cmake)
  command -v ninja >/dev/null 2>&1 || pkgs+=(ninja-build)
  command -v gettext >/dev/null 2>&1 || pkgs+=(gettext)
  command -v autoconf >/dev/null 2>&1 || pkgs+=(autoconf)
  command -v automake >/dev/null 2>&1 || pkgs+=(automake)
  command -v libtool >/dev/null 2>&1 || pkgs+=(libtool-bin)
  command -v pkg-config >/dev/null 2>&1 || pkgs+=(pkg-config)
  command -v gcc >/dev/null 2>&1 || pkgs+=(build-essential)
  command -v unzip >/dev/null 2>&1 || pkgs+=(unzip)
  command -v curl >/dev/null 2>&1 || pkgs+=(curl)
  if [ "${#pkgs[@]}" -gt 0 ]; then
    echo "빌드에 필요한 패키지 설치: ${pkgs[*]}"
    sudo apt update
    sudo apt install -y "${pkgs[@]}"
  else
    echo "빌드 도구 이미 설치되어 있음"
  fi
}

install_build_deps

if [ ! -d "$NVIM_SRC_DIR" ]; then
  echo "neovim 소스 클론 중 ($NVIM_REF)..."
  git clone --depth 1 --branch "$NVIM_REF" https://github.com/neovim/neovim.git "$NVIM_SRC_DIR"
fi

cd "$NVIM_SRC_DIR"

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
  echo "PairVim 패치 이미 적용됨."
elif git apply --check "$PATCH_FILE" 2>/dev/null; then
  git apply "$PATCH_FILE"
  echo "PairVim 패치 적용 완료."
else
  echo "패치 적용 실패 - neovim 소스 버전이 패치와 맞지 않습니다: $PATCH_FILE"
  echo "해결: rm -rf \"$NVIM_SRC_DIR\" 후 PAIRVIM_NVIM_REF=v0.12.6 bash $0  (맞는 태그는 이미 쓰는 nvim --version 으로 확인)"
  exit 1
fi

echo "빌드 중... (몇 분 걸릴 수 있음)"
make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX="$PREFIX"
make install

echo "== 빌드 완료 =="
export PATH="$PREFIX/bin:$PATH"
if command -v pairvim >/dev/null 2>&1; then
  pairvim --version | head -1
else
  echo "빌드는 됐지만 PATH에 $PREFIX/bin 이 없습니다. ~/.zshrc 에 export PATH=\"$PREFIX/bin:\$PATH\" 추가 후 다시 시작하세요."
fi
