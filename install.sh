#!/usr/bin/env bash
# PairVim 설치 스크립트: (필요하면 기존 Neovim 설정을 백업하고) Neovim 빌드부터 PairVim 설정 적용까지 한 번에.
#
# 사용:
#   git clone https://github.com/bjw5035/PairVim.git ~/pairvim-setup
#   bash ~/pairvim-setup/install.sh              # 설치 (기존 설정이 있으면 옮길 목록을 보여 주고 확인)
#   bash ~/pairvim-setup/install.sh --dry-run    # 아무것도 바꾸지 않고 계획만 출력
#   bash ~/.config/nvim/install.sh --rollback    # 마지막 백업으로 되돌리기
# 옵션: --yes(확인 생략) --dry-run --rollback --help
set -euo pipefail

REPO_URL="https://github.com/bjw5035/PairVim.git"
CONFIG_DIR="$HOME/.config/nvim"
DATA_DIR="$HOME/.local/share/nvim"
STATE_DIR="$HOME/.local/state/nvim"
CACHE_DIR="$HOME/.cache/nvim"
BACKUP_MARK="$HOME/.config/.pairvim-last-backup"   # 마지막 백업 이름(롤백용)
SELF="${BASH_SOURCE[0]}"
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"

YES="${YES:-0}"
DRY="${DRY:-0}"

# Node: Claude/Codex CLI 설치에 18 이상이 필요하다. 없거나 낮으면 sudo 없이 사용자 폴더(~/.local/node)에 설치한다.
NODE_MAJOR="${NODE_MAJOR:-22}"                              # 받을 Node 메이저 버전(LTS)
NODE_DIST_BASE="${NODE_DIST_BASE:-https://nodejs.org/dist}"  # (시험에서만 바꾼다)
NODE_HOME="$HOME/.local/node"                               # 현재 버전을 가리키는 링크

run() {
  if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi
}

# 사용자 확인. --yes/--dry-run이면 통과, 대화형이 아니면(파이프 등) 안전하게 중단한다.
confirm() {
  [ "$YES" = 1 ] || [ "$DRY" = 1 ] && return 0
  if [ ! -t 0 ]; then
    echo "대화형 터미널이 아니라서 확인할 수 없습니다. 내용을 확인한 뒤 --yes 옵션을 붙여 다시 실행하세요." >&2
    return 1
  fi
  local ans
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# ~/.config/nvim 이 이 저장소(PairVim)의 클론인가? (.git 이 있다고 PairVim 은 아니다: 원격 주소로 판단)
is_pairvim_repo() {
  [ -d "$CONFIG_DIR/.git" ] || return 1
  git -C "$CONFIG_DIR" remote get-url origin 2>/dev/null | grep -qiE 'bjw5035/(PairVim|nvim-config)'
}

# PairVim 이 아닌 기존 설정이 있으면 이름을 붙여 옮겨 둔다. runtime·mason 은 건드리지 않는다.
backup_existing() {
  [ -e "$CONFIG_DIR" ] || return 0
  if is_pairvim_repo; then
    # shellcheck disable=SC2088  # 안내 문구의 ~ 는 확장하지 않는 것이 맞다
    echo "~/.config/nvim 은 이미 PairVim 설정입니다. 백업이 필요 없습니다."
    return 0
  fi
  local ts name
  ts="$(date +%Y%m%d%H%M%S)"
  name="nvim-old-$ts"
  echo "기존 Neovim 설정을 발견했습니다. 아래를 '$name' 이름으로 옮깁니다(되돌리기: --rollback)."
  echo "  설정   $CONFIG_DIR -> $HOME/.config/$name"
  [ -d "$DATA_DIR/lazy" ] && echo "  플러그인 $DATA_DIR/lazy -> $HOME/.local/share/$name/lazy"
  [ -d "$STATE_DIR" ] && echo "  상태   $STATE_DIR -> $HOME/.local/state/$name"
  [ -d "$CACHE_DIR" ] && echo "  캐시   $CACHE_DIR -> $HOME/.cache/$name"
  echo "  (runtime, mason 은 옮기지 않습니다. 옛 설정은 NVIM_APPNAME=$name nvim 으로 켤 수 있습니다.)"
  confirm "진행할까요?" || { echo "중단했습니다. 아무것도 바꾸지 않았습니다."; exit 1; }
  run mv "$CONFIG_DIR" "$HOME/.config/$name"
  if [ -d "$DATA_DIR/lazy" ]; then
    run mkdir -p "$HOME/.local/share/$name"
    run mv "$DATA_DIR/lazy" "$HOME/.local/share/$name/lazy"
  fi
  [ -d "$STATE_DIR" ] && run mv "$STATE_DIR" "$HOME/.local/state/$name"
  [ -d "$CACHE_DIR" ] && run mv "$CACHE_DIR" "$HOME/.cache/$name"
  if [ "$DRY" != 1 ]; then
    mkdir -p "$(dirname "$BACKUP_MARK")"
    echo "$name" >"$BACKUP_MARK"
  fi
}

# ~/.config/nvim 에 PairVim 설정을 둔다. 이 스크립트가 받아 둔 클론(예: ~/pairvim-setup)에서 실행됐으면 그 클론을 복제해 로그인을 다시 묻지 않는다.
place_config() {
  if [ "$SELF_DIR" = "$CONFIG_DIR" ]; then
    echo "$CONFIG_DIR 에서 바로 실행됨. 클론 단계 건너뜀."
    return 0
  fi
  if [ -e "$CONFIG_DIR" ]; then
    if is_pairvim_repo; then echo "$CONFIG_DIR 는 이미 PairVim 레포입니다. 건너뜀."; return 0; fi
    if [ "$DRY" = 1 ]; then echo "[dry-run] (기존 설정을 옮긴 뒤) PairVim 설정을 $CONFIG_DIR 에 둡니다"; return 0; fi
    echo "$CONFIG_DIR 가 남아 있어 중단합니다(기존 설정 백업이 취소됐거나 실패)." >&2
    exit 1
  fi
  if [ -d "$SELF_DIR/.git" ]; then
    echo "받아 둔 PairVim 클론($SELF_DIR)을 $CONFIG_DIR 로 복제합니다."
    run mkdir -p "$(dirname "$CONFIG_DIR")"
    run git clone "$SELF_DIR" "$CONFIG_DIR"
    run git -C "$CONFIG_DIR" remote set-url origin "$REPO_URL"
  else
    echo "PairVim 설정 클론 중..."
    run mkdir -p "$(dirname "$CONFIG_DIR")"
    run git clone "$REPO_URL" "$CONFIG_DIR"
  fi
}

# node 의 메이저 버전(없으면 0)
node_major() {
  command -v node >/dev/null 2>&1 || { echo 0; return; }
  local v; v="$(node -v 2>/dev/null)"; v="${v#v}"; v="${v%%.*}"
  case "$v" in ''|*[!0-9]*) echo 0 ;; *) echo "$v" ;; esac
}

# nodejs.org 공식 배포 파일(.tar.gz)을 받아 sha256 으로 검증한 뒤 ~/.local/node 에 푼다(sudo 불필요).
# 실패하면(네트워크 차단 등) 아무것도 바꾸지 않고 1 을 돌려준다.
install_node_user() {
  local arch dist tmp line sha file ver dest
  case "$(uname -m)" in
    x86_64 | amd64) arch=x64 ;;
    aarch64 | arm64) arch=arm64 ;;
    armv7l) arch=armv7l ;;
    *) echo "이 CPU($(uname -m))용 Node 배포 파일을 몰라 직접 설치를 건너뜁니다."; return 1 ;;
  esac
  dist="$NODE_DIST_BASE/latest-v${NODE_MAJOR}.x"
  if [ "$DRY" = 1 ]; then
    echo "[dry-run] $dist 에서 linux-$arch 배포 파일을 받아 sha256 검증 후 $NODE_HOME 에 설치"
    return 0
  fi
  command -v curl >/dev/null 2>&1 || { echo "curl 이 없어 Node 를 받을 수 없습니다."; return 1; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/pairvim-node.XXXXXX")" || return 1
  if ! curl -fsSL "$dist/SHASUMS256.txt" -o "$tmp/SHASUMS256.txt"; then
    echo "Node 배포 목록을 받지 못했습니다($dist)."; rm -rf "$tmp"; return 1
  fi
  line="$(grep -E " node-v[0-9.]+-linux-${arch}\.tar\.gz\$" "$tmp/SHASUMS256.txt" | head -1)"
  if [ -z "$line" ]; then echo "배포 목록에서 linux-$arch 파일을 찾지 못했습니다."; rm -rf "$tmp"; return 1; fi
  sha="${line%% *}"; file="${line##* }"
  if ! curl -fsSL "$dist/$file" -o "$tmp/$file"; then
    echo "Node 파일을 받지 못했습니다($file)."; rm -rf "$tmp"; return 1
  fi
  if ! ( cd "$tmp" && echo "$sha  $file" | sha256sum -c --quiet - ) >/dev/null 2>&1; then
    echo "Node 파일의 sha256 이 목록과 다릅니다. 설치하지 않습니다."; rm -rf "$tmp"; return 1
  fi
  ver="${file#node-}"; ver="${ver%%-linux*}"
  dest="$HOME/.local/share/pairvim-node/$ver"
  if ! { mkdir -p "$dest" && tar -xzf "$tmp/$file" -C "$dest" --strip-components=1; }; then
    echo "Node 압축을 풀지 못했습니다."; rm -rf "$tmp" "$dest"; return 1
  fi
  mkdir -p "$HOME/.local" && ln -sfn "$dest" "$NODE_HOME"
  rm -rf "$tmp"
  export PATH="$NODE_HOME/bin:$PATH"
  echo "Node $(node -v) 설치 완료 ($NODE_HOME)"
}

# Node 18 이상을 보장한다: 이미 충분하면 건너뛰고, 아니면 사용자 폴더 설치 → 실패하면 apt 로 대체.
ensure_node() {
  local m; m="$(node_major)"
  if [ "$m" -ge 18 ]; then
    echo "Node v$m 이미 충분함(18 이상)"
    return 0
  fi
  if [ "$m" = 0 ]; then echo "Node 가 없습니다. sudo 없이 사용자 폴더에 설치합니다."
  else echo "Node v$m 은 낮습니다(18 이상 필요). sudo 없이 사용자 폴더에 새로 설치합니다(기존 것은 그대로 둠)."; fi
  install_node_user && return 0
  echo "직접 설치에 실패했습니다."
  if [ "$m" = 0 ]; then
    echo "apt 로 nodejs/npm 을 설치합니다(버전이 낮을 수 있음. Claude CLI 가 안 되면 nvm 등으로 올리세요)."
    run sudo apt install -y nodejs npm
  else
    echo "기존 Node v$m 을 그대로 둡니다. Claude CLI 설치가 실패하면 Node 18 이상으로 올린 뒤 다시 실행하세요."
  fi
  return 0
}

install_apt_pkgs() {
  local pkgs=()
  command -v git >/dev/null 2>&1 || pkgs+=(git)
  command -v curl >/dev/null 2>&1 || pkgs+=(curl)
  command -v rg >/dev/null 2>&1 || pkgs+=(ripgrep)
  { command -v fdfind >/dev/null 2>&1 || command -v fd >/dev/null 2>&1; } || pkgs+=(fd-find)
  if [ "${#pkgs[@]}" -gt 0 ]; then
    echo "설치할 패키지: ${pkgs[*]}"
    run sudo apt update
    run sudo apt install -y "${pkgs[@]}"
  else
    echo "필수 패키지 이미 설치되어 있음"
  fi
}

# 되돌리기: PairVim 쪽(설정·플러그인·상태·캐시)을 지우고 마지막 백업을 제자리로 복원한다.
rollback() {
  local name
  name="$(cat "$BACKUP_MARK" 2>/dev/null || true)"
  if [ -z "$name" ] || [ ! -d "$HOME/.config/$name" ]; then
    echo "되돌릴 백업 기록이 없습니다($BACKUP_MARK). 수동으로 ~/.config/nvim-old-* 를 확인하세요." >&2
    exit 1
  fi
  echo "마지막 백업 '$name' 으로 되돌립니다. 아래 PairVim 쪽이 삭제됩니다:"
  echo "  $CONFIG_DIR  $DATA_DIR/lazy  $STATE_DIR  $CACHE_DIR"
  confirm "정말 되돌릴까요?" || { echo "중단했습니다."; exit 1; }
  run rm -rf "$CONFIG_DIR" "$DATA_DIR/lazy" "$STATE_DIR" "$CACHE_DIR"
  run mv "$HOME/.config/$name" "$CONFIG_DIR"
  if [ -d "$HOME/.local/share/$name/lazy" ]; then
    run mkdir -p "$DATA_DIR"
    run mv "$HOME/.local/share/$name/lazy" "$DATA_DIR/lazy"
    run rmdir "$HOME/.local/share/$name" 2>/dev/null || true
  fi
  [ -d "$HOME/.local/state/$name" ] && run mv "$HOME/.local/state/$name" "$STATE_DIR"
  [ -d "$HOME/.cache/$name" ] && run mv "$HOME/.cache/$name" "$CACHE_DIR"
  [ "$DRY" = 1 ] || rm -f "$BACKUP_MARK"
  echo "되돌렸습니다. pairvim 실행 파일을 지우려면: rm -f ~/.local/bin/pairvim"
}

usage() { sed -n 2,9p "$SELF" | sed 's/^# \{0,1\}//'; }

install_all() {
  echo "== PairVim 설치 시작 =="
  if ! command -v apt >/dev/null 2>&1; then
    echo "apt가 없는 환경입니다. git / node+npm / ripgrep / fd 를 직접 설치한 뒤 다시 실행해주세요."
    exit 1
  fi
  backup_existing
  install_apt_pkgs
  ensure_node
  place_config

  # codex/claude CLI 를 sudo 없이 설치할 사용자 전용 경로. 전역 npm 설정(npm config)은 바꾸지 않는다.
  run mkdir -p "$HOME/.npm-global"
  for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$rc" ] || continue
    if [ -e "$NODE_HOME/bin/node" ]; then
      grep -q 'local/node/bin' "$rc" || echo 'export PATH="$HOME/.local/node/bin:$PATH"' >>"$rc"
    fi
    grep -q 'npm-global/bin' "$rc" || { [ "$DRY" = 1 ] && echo "[dry-run] $rc 에 PATH 추가" || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >>"$rc"; }
    grep -q 'HOME/.local/bin' "$rc" || { [ "$DRY" = 1 ] && echo "[dry-run] $rc 에 PATH 추가" || echo 'export PATH="$HOME/.local/bin:$PATH"' >>"$rc"; }
  done
  export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
  [ -e "$NODE_HOME/bin/node" ] && export PATH="$NODE_HOME/bin:$PATH"

  # neovim/neovim 소스를 받아 PairVim 리브랜딩 패치를 적용하고 직접 빌드/설치('pairvim' 실행 파일, 몇 분 걸릴 수 있음)
  if [ "$DRY" = 1 ]; then
    echo "[dry-run] bash $CONFIG_DIR/build-pairvim.sh"
    echo "== dry-run 끝: 아무것도 바꾸지 않았습니다 =="
    return 0
  fi
  bash "$CONFIG_DIR/build-pairvim.sh"

  echo "== 설치 완료 =="
  echo "새 터미널을 열거나 'source ~/.zshrc'(bash면 ~/.bashrc) 실행 후 'pairvim'으로 시작하세요."
  echo "처음 실행하면 플러그인과 codex/claude CLI(없는 경우)가 자동으로 설치됩니다."
  [ -f "$BACKUP_MARK" ] && echo "기존 설정을 되돌리려면: bash ~/.config/nvim/install.sh --rollback  (옛 설정 실행: NVIM_APPNAME=$(cat "$BACKUP_MARK") nvim)"
  return 0
}

main() {
  local action=install a
  for a in "$@"; do
    case "$a" in
      --yes | -y) YES=1 ;;
      --dry-run) DRY=1 ;;
      --rollback) action=rollback ;;
      --help | -h) usage; exit 0 ;;
      *) echo "알 수 없는 옵션: $a" >&2; usage; exit 2 ;;
    esac
  done
  if [ "$action" = rollback ]; then
    # 이 스크립트는 지워질 ~/.config/nvim 안에 있으므로, 복사본으로 다시 실행해 안전하게 끝까지 돈다.
    if [ "${PAIRVIM_FROM_TMP:-0}" != 1 ] && [[ "$SELF_DIR" == "$CONFIG_DIR"* ]]; then
      local tmp
      tmp="$(mktemp /tmp/pairvim-rollback.XXXXXX.sh)"
      cp "$SELF" "$tmp"
      PAIRVIM_FROM_TMP=1 YES="$YES" DRY="$DRY" exec bash "$tmp" "$@"
    fi
    rollback
  else
    install_all
  fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
