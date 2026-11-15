#!/usr/bin/env bash
# 터미널 설정 스크립트: zsh + Oh My Zsh + robbyrussell 프롬프트를 적용한다.
# - 새 PC: zsh / Oh My Zsh 를 설치하고 ~/.zshrc 를 만든다.
# - 이미 Starship 등이 설정된 PC(회사 PC): ~/.zshrc 를 백업한 뒤 테마만 robbyrussell 로 바꾸고 Starship 초기화 줄은 주석 처리한다(Starship 은 지우지 않음).
# 여러 번 실행해도 안전하다(이미 적용됐으면 건너뜀).
#
# 사용:
#   bash terminal-setup.sh --dry-run      # 아무것도 바꾸지 않고 계획만 출력
#   bash terminal-setup.sh                # 적용
#   bash terminal-setup.sh --with-pairvim # 적용 후 PairVim(install.sh)까지 설치
#   bash terminal-setup.sh --rollback     # 마지막 ~/.zshrc 백업으로 되돌리기
# 옵션: --dry-run --with-pairvim --rollback --help
set -euo pipefail

ZSHRC="$HOME/.zshrc"
OMZ_DIR="$HOME/.oh-my-zsh"
THEME="robbyrussell"
BACKUP_MARK="$HOME/.zshrc.last-backup"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0

run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

usage() { sed -n 2,13p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ensure_packages() {
  local pkgs=()
  command -v zsh >/dev/null 2>&1 || pkgs+=(zsh)
  command -v git >/dev/null 2>&1 || pkgs+=(git)
  command -v curl >/dev/null 2>&1 || pkgs+=(curl)
  if [ "${#pkgs[@]}" -eq 0 ]; then echo "zsh/git/curl 이미 설치됨"; return 0; fi
  if ! command -v apt >/dev/null 2>&1; then
    echo "apt 가 없습니다. ${pkgs[*]} 를 직접 설치한 뒤 다시 실행하세요." >&2
    exit 1
  fi
  echo "설치할 패키지: ${pkgs[*]}"
  run sudo apt update
  run sudo apt install -y "${pkgs[@]}"
}

ensure_omz() {
  if [ -d "$OMZ_DIR" ]; then echo "Oh My Zsh 이미 설치됨"; return 0; fi
  echo "Oh My Zsh 설치 중(기본 쉘 변경·zsh 자동 실행 없음)..."
  if [ "$DRY" = 1 ]; then echo "[dry-run] Oh My Zsh 설치 스크립트 실행"; return 0; fi
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
}

backup_zshrc() {
  [ -f "$ZSHRC" ] || return 0
  local name="$ZSHRC.bak-$(date +%Y%m%d%H%M%S)"
  echo "~/.zshrc 백업: $name"
  run cp -p "$ZSHRC" "$name"
  [ "$DRY" = 1 ] || echo "$name" >"$BACKUP_MARK"
}

apply_zshrc() {
  if [ ! -f "$ZSHRC" ]; then
    echo "~/.zshrc 가 없어 새로 만듭니다."
    if [ "$DRY" = 1 ]; then echo "[dry-run] 최소 ~/.zshrc 생성(ZSH_THEME=$THEME)"; return 0; fi
    cat >"$ZSHRC" <<EOF
export ZSH="\$HOME/.oh-my-zsh"
ZSH_THEME="$THEME"
plugins=(git)
source \$ZSH/oh-my-zsh.sh
export PATH="\$HOME/.local/bin:\$PATH"
EOF
    return 0
  fi

  local changed=0
  # 1) ZSH_THEME 를 robbyrussell 로
  if grep -qE "^ZSH_THEME=\"$THEME\"" "$ZSHRC"; then
    echo "ZSH_THEME 이미 $THEME"
  elif grep -qE '^[[:space:]]*#?[[:space:]]*ZSH_THEME=' "$ZSHRC"; then
    echo "ZSH_THEME 를 $THEME 로 변경"
    run sed -i -E "s|^[[:space:]]*#?[[:space:]]*ZSH_THEME=.*|ZSH_THEME=\"$THEME\"|" "$ZSHRC"
    changed=1
  else
    echo "ZSH_THEME 줄이 없어 추가(source oh-my-zsh.sh 앞)"
    if grep -q 'oh-my-zsh.sh' "$ZSHRC"; then
      run sed -i "/^source .*oh-my-zsh.sh/i ZSH_THEME=\"$THEME\"" "$ZSHRC"
      changed=1
    else
      echo "  oh-my-zsh 를 불러오는 줄이 없습니다. ~/.zshrc 에 직접 추가하세요." >&2
    fi
  fi
  # 2) Starship 초기화 줄 주석 처리(이미 주석이면 그대로)
  if grep -qE '^[[:space:]]*eval[[:space:]]+"\$\(starship init zsh\)"' "$ZSHRC"; then
    echo "Starship 초기화 줄 주석 처리"
    run sed -i -E 's|^([[:space:]]*)(eval[[:space:]]+"\$\(starship init zsh\)".*)$|\1# \2  # disabled by terminal-setup.sh|' "$ZSHRC"
    changed=1
  else
    echo "활성 Starship 초기화 줄 없음"
  fi
  [ "$changed" = 1 ] && echo "~/.zshrc 수정 완료" || echo "~/.zshrc 변경 없음"
}

rollback() {
  local name; name="$(cat "$BACKUP_MARK" 2>/dev/null || true)"
  if [ -z "$name" ] || [ ! -f "$name" ]; then echo "되돌릴 백업이 없습니다($BACKUP_MARK)." >&2; exit 1; fi
  echo "$name 로 ~/.zshrc 를 되돌립니다."
  run cp -p "$name" "$ZSHRC"
}

main() {
  local with_pairvim=0 action=apply a
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY=1 ;;
      --with-pairvim) with_pairvim=1 ;;
      --rollback) action=rollback ;;
      --help | -h) usage; exit 0 ;;
      *) echo "알 수 없는 옵션: $a" >&2; usage; exit 2 ;;
    esac
  done
  if [ "$action" = rollback ]; then rollback; exit 0; fi

  echo "== 터미널 설정 시작 =="
  ensure_packages
  ensure_omz
  # 변경할 내용이 있을 때만 백업한다(안 그러면 재실행이 원본 백업을 덮어써 롤백이 무의미해짐)
  if [ -f "$ZSHRC" ] && {
    ! grep -qE "^ZSH_THEME=\"$THEME\"" "$ZSHRC" ||
      grep -qE '^[[:space:]]*eval[[:space:]]+"\$\(starship init zsh\)"' "$ZSHRC"
  }; then
    backup_zshrc
  fi
  apply_zshrc
  if [ "$with_pairvim" = 1 ]; then
    echo "== PairVim 설치 =="
    if [ "$DRY" = 1 ]; then run bash "$SELF_DIR/install.sh" --dry-run; else bash "$SELF_DIR/install.sh"; fi
  fi
  echo "== 완료 =="
  echo "새 터미널을 열거나 'exec zsh' 로 적용하세요. 기본 쉘이 zsh 가 아니면: chsh -s \$(which zsh)"
}

main "$@"
