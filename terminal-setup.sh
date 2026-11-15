#!/usr/bin/env bash
# 터미널 설정 스크립트: zsh + Oh My Zsh + robbyrussell 프롬프트 + Catppuccin Mocha 색상 테마를 적용한다.
# - 새 PC: zsh / Oh My Zsh 를 설치하고 ~/.zshrc 를 만든다.
# - 이미 Starship 등이 설정된 PC(회사 PC): ~/.zshrc 를 백업한 뒤 테마만 robbyrussell 로 바꾸고 Starship 초기화 줄은 주석 처리한다(Starship 은 지우지 않음).
# - 색상 테마: ls 색상(LS_COLORS)을 Catppuccin Mocha 로 교체하고, WSL 이면 Windows Terminal 색상 스킴도 적용한다.
#   입력한 명령어와 출력이 구분되도록 zsh-syntax-highlighting 과 프롬프트 앞 빈 줄도 넣는다.
# 여러 번 실행해도 안전하다(이미 적용됐으면 건너뜀). 바꾸기 전에 항상 백업한다.
#
# 사용:
#   bash terminal-setup.sh --dry-run      # 아무것도 바꾸지 않고 계획만 출력
#   bash terminal-setup.sh                # 적용
#   bash terminal-setup.sh --no-theme     # 색상 테마(ls 색상 + Windows Terminal)는 건너뜀
#   bash terminal-setup.sh --with-pairvim # 적용 후 PairVim(install.sh)까지 설치
#   bash terminal-setup.sh --rollback     # ~/.zshrc 와 Windows Terminal 설정을 마지막 백업으로 되돌리기
# 옵션: --dry-run --no-theme --with-pairvim --rollback --help
set -euo pipefail

ZSHRC="$HOME/.zshrc"
OMZ_DIR="$HOME/.oh-my-zsh"
THEME="robbyrussell"
SCHEME_NAME="Catppuccin Mocha"
LS_START='# >>> terminal-setup: ls colors (catppuccin-mocha v1) >>>'
BACKUP_MARK="$HOME/.zshrc.last-backup"
WT_BACKUP_MARK="$HOME/.wt-settings.last-backup"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY=0
THEME_ON=1

run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

usage() { sed -n 2,17p "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

ensure_packages() {
  local pkgs=()
  command -v zsh >/dev/null 2>&1 || pkgs+=(zsh)
  command -v git >/dev/null 2>&1 || pkgs+=(git)
  command -v curl >/dev/null 2>&1 || pkgs+=(curl)
  command -v python3 >/dev/null 2>&1 || pkgs+=(python3)
  if [ "${#pkgs[@]}" -eq 0 ]; then echo "zsh/git/curl/python3 이미 설치됨"; return 0; fi
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

SYN_NAME="zsh-syntax-highlighting"
SYN_DIR="$OMZ_DIR/custom/plugins/$SYN_NAME"
SPACING_START='# >>> terminal-setup: prompt spacing v1 >>>'

# 입력 중인 명령어에 색을 입히는 플러그인(출력과 구분하기 쉬워진다)
ensure_syntax_plugin() {
  if [ -d "$SYN_DIR" ]; then echo "$SYN_NAME 이미 설치됨"; return 0; fi
  echo "$SYN_NAME 설치 중..."
  run git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYN_DIR"
}

# plugins=(...) 한 줄에 zsh-syntax-highlighting 을 추가한다(여러 줄로 쓴 경우는 건드리지 않고 안내만 한다)
apply_syntax_plugin() {
  [ -f "$ZSHRC" ] || return 0
  if grep -qE "^plugins=\(.*$SYN_NAME" "$ZSHRC"; then echo "$SYN_NAME 이미 plugins 에 있음"; return 0; fi
  if grep -qE '^plugins=\([^)]*\)' "$ZSHRC"; then
    echo "plugins 에 $SYN_NAME 추가"
    run sed -i -E "s|^plugins=\(([^)]*)\)|plugins=(\1 $SYN_NAME)|; s|^plugins=\( +|plugins=(|" "$ZSHRC"
  else
    echo "plugins=(...) 한 줄을 찾지 못했습니다. ~/.zshrc 의 plugins 에 $SYN_NAME 을 직접 추가하세요(맨 끝에)." >&2
  fi
}

# 명령 실행 후 다음 프롬프트 앞에 빈 줄을 넣어 명령어/출력 묶음을 나눈다(첫 프롬프트에는 넣지 않음)
apply_spacing() {
  [ -f "$ZSHRC" ] || return 0
  if grep -qF "$SPACING_START" "$ZSHRC"; then echo "프롬프트 간격 이미 적용됨"; return 0; fi
  echo "프롬프트 앞 빈 줄 추가"
  if [ "$DRY" = 1 ]; then echo "[dry-run] ~/.zshrc 끝에 프롬프트 간격 블록 추가"; return 0; fi
  cat >>"$ZSHRC" <<'EOF'
# >>> terminal-setup: prompt spacing v1 >>>
_ts_blank_line() { [[ -n $_ts_prompt_shown ]] && print; _ts_prompt_shown=1 }
precmd_functions+=(_ts_blank_line)
# <<< terminal-setup: prompt spacing <<<
EOF
}

backup_zshrc() {
  [ -f "$ZSHRC" ] || return 0
  local name="$ZSHRC.bak-$(date +%Y%m%d%H%M%S)"
  echo "~/.zshrc 백업: $name"
  run cp -p "$ZSHRC" "$name"
  [ "$DRY" = 1 ] || echo "$name" >"$BACKUP_MARK"
}

# ~/.zshrc 에 바꿀 내용이 있는가(없으면 백업도 만들지 않는다)
zshrc_needs_change() {
  [ -f "$ZSHRC" ] || return 1
  grep -qE "^ZSH_THEME=\"$THEME\"" "$ZSHRC" || return 0
  grep -qE '^[[:space:]]*eval[[:space:]]+"\$\(starship init zsh\)"' "$ZSHRC" && return 0
  if [ "$THEME_ON" = 1 ]; then
    grep -qF "$LS_START" "$ZSHRC" || return 0
    grep -qF "$SPACING_START" "$ZSHRC" || return 0
    grep -qE "^plugins=\(.*$SYN_NAME" "$ZSHRC" || return 0
  fi
  return 1
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
  [ "$changed" = 1 ] && echo "~/.zshrc 프롬프트 설정 완료" || echo "~/.zshrc 프롬프트 변경 없음"
}

# ls 색상(LS_COLORS)을 Catppuccin Mocha 로. 이 스크립트가 관리하는 블록(시작/끝 표시 사이)으로 넣고,
# 예전 Nord 블록이나 이전 버전 블록은 시작·끝이 모두 있을 때만 지운다(끝 표시가 없으면 건드리지 않음).
apply_ls_colors() {
  [ -f "$ZSHRC" ] || { echo "[dry-run] ~/.zshrc 생성 후 ls 색상 블록 추가"; return 0; }
  if grep -qF "$LS_START" "$ZSHRC"; then echo "ls 색상 이미 Catppuccin Mocha"; return 0; fi
  echo "ls 색상을 Catppuccin Mocha 로 교체"
  if grep -q '^# >>> terminal-setup: ls colors' "$ZSHRC" && grep -q '^# <<< terminal-setup: ls colors <<<' "$ZSHRC"; then
    run sed -i '/^# >>> terminal-setup: ls colors/,/^# <<< terminal-setup: ls colors <<</d' "$ZSHRC"
  fi
  if grep -q '^# ---- ls colors: Nord' "$ZSHRC" && grep -q '^unset _e _nord_' "$ZSHRC"; then
    run sed -i '/^# ---- ls colors: Nord/,/^unset _e _nord_/d' "$ZSHRC"
  fi
  if [ "$DRY" = 1 ]; then echo "[dry-run] ~/.zshrc 끝에 Catppuccin Mocha ls 색상 블록 추가"; return 0; fi
  cat >>"$ZSHRC" <<'EOF'
# >>> terminal-setup: ls colors (catppuccin-mocha v1) >>>
_ctp_dir="1;38;2;137;180;250"     # blue
_ctp_ex="38;2;166;227;161"        # green
_ctp_ln="38;2;203;166;247"        # mauve
_ctp_arc="38;2;249;226;175"       # yellow
_ctp_media="38;2;250;179;135"     # peach
_ctp_code="38;2;148;226;213"      # teal
_ctp_cfg="38;2;180;190;254"       # lavender
_ctp_doc="38;2;205;214;244"       # text
_ctp_err="38;2;243;139;168"       # red
LS_COLORS="rs=0:fi=0:di=${_ctp_dir}:ow=${_ctp_dir}:tw=${_ctp_dir}:st=${_ctp_dir}"
LS_COLORS+=":ln=${_ctp_ln}:or=${_ctp_err}:mi=${_ctp_err}:ex=${_ctp_ex}"
LS_COLORS+=":pi=${_ctp_arc}:so=${_ctp_ln}:bd=${_ctp_arc}:cd=${_ctp_arc}"
for _e in tar gz tgz zip 7z rar bz2 xz zst jar war deb rpm; do LS_COLORS+=":*.${_e}=${_ctp_arc}"; done
for _e in png jpg jpeg gif svg webp bmp ico mp3 mp4 mkv wav avi mov pdf; do LS_COLORS+=":*.${_e}=${_ctp_media}"; done
for _e in py js jsx ts tsx go rs c h cpp hpp cc java kt swift rb php pl lua sh zsh bash fish vim; do LS_COLORS+=":*.${_e}=${_ctp_code}"; done
for _e in json yaml yml toml ini cfg conf env xml csv lock properties; do LS_COLORS+=":*.${_e}=${_ctp_cfg}"; done
for _e in md markdown txt rst log adoc; do LS_COLORS+=":*.${_e}=${_ctp_doc}"; done
export LS_COLORS
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
unset _e _ctp_dir _ctp_ex _ctp_ln _ctp_arc _ctp_media _ctp_code _ctp_cfg _ctp_doc _ctp_err
# <<< terminal-setup: ls colors <<<
EOF
}

# WSL 이면 Windows Terminal 의 settings.json 에 Catppuccin Mocha 스킴을 추가하고 기본 색상 스킴으로 지정한다.
# 그 외 설정(폰트·투명도 등)은 건드리지 않는다. 바꿀 때만 백업한다. (WT_SETTINGS 환경변수로 경로를 직접 줄 수 있다)
apply_windows_terminal() {
  local f="${WT_SETTINGS:-}"
  if [ -z "$f" ]; then
    grep -qi microsoft /proc/version 2>/dev/null || { echo "WSL 이 아니라 Windows Terminal 설정은 건너뜁니다."; return 0; }
    local c
    for c in /mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminal_*/LocalState/settings.json \
      /mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminalPreview_*/LocalState/settings.json; do
      [ -f "$c" ] && { f="$c"; break; }
    done
  fi
  if [ -z "$f" ] || [ ! -f "$f" ]; then echo "Windows Terminal settings.json 을 찾지 못해 건너뜁니다."; return 0; fi
  echo "Windows Terminal 설정: $f"
  python3 -I - "$f" "$DRY" "$SCHEME_NAME" "$WT_BACKUP_MARK" <<'PY'
import json, re, shutil, sys, time
path, dry, name, mark = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4]
scheme = {
    "name": name,
    "background": "#1E1E2E", "foreground": "#CDD6F4",
    "cursorColor": "#F5E0DC", "selectionBackground": "#585B70",
    "black": "#45475A", "red": "#F38BA8", "green": "#A6E3A1", "yellow": "#F9E2AF",
    "blue": "#89B4FA", "purple": "#F5C2E7", "cyan": "#94E2D5", "white": "#BAC2DE",
    "brightBlack": "#585B70", "brightRed": "#F38BA8", "brightGreen": "#A6E3A1", "brightYellow": "#F9E2AF",
    "brightBlue": "#89B4FA", "brightPurple": "#F5C2E7", "brightCyan": "#94E2D5", "brightWhite": "#A6ADC8",
}
text = open(path, encoding="utf-8-sig").read()
try:
    clean = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    data = json.loads(re.sub(r",(\s*[}\]])", r"\1", clean))
except Exception as e:
    print(f"settings.json 을 읽지 못해 건너뜁니다({e}). 파일은 바꾸지 않았습니다.")
    sys.exit(0)
schemes = data.setdefault("schemes", [])
defaults = data.setdefault("profiles", {}).setdefault("defaults", {})
have = next((s for s in schemes if s.get("name") == name), None)
if have == scheme and defaults.get("colorScheme") == name:
    print(f"Windows Terminal 은 이미 '{name}' 적용됨")
    sys.exit(0)
for p in data["profiles"].get("list", []):
    if p.get("colorScheme") and p["colorScheme"] != name:
        print(f"  참고: 프로필 '{p.get('name')}' 은 자체 색상 스킴({p['colorScheme']})이 지정돼 있어 기본값이 적용되지 않습니다.")
if dry:
    print(f"[dry-run] '{name}' 스킴 추가/갱신 후 기본 색상 스킴으로 지정(백업 후 {path} 수정)")
    sys.exit(0)
backup = f"{path}.bak-{time.strftime('%Y%m%d%H%M%S')}"
shutil.copy2(path, backup)
open(mark, "w").write(backup + "\n")
data["schemes"] = [s for s in schemes if s.get("name") != name] + [scheme]
defaults["colorScheme"] = name
with open(path, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(data, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
print(f"Windows Terminal 에 '{name}' 적용 완료. 백업: {backup}")
print("  (settings.json 의 주석은 저장 과정에서 사라질 수 있습니다. 필요하면 위 백업을 보세요.)")
PY
}

rollback() {
  local name; name="$(cat "$BACKUP_MARK" 2>/dev/null || true)"
  if [ -n "$name" ] && [ -f "$name" ]; then
    echo "$name 로 ~/.zshrc 를 되돌립니다."
    run cp -p "$name" "$ZSHRC"
  else
    echo "~/.zshrc 백업이 없어 건너뜁니다($BACKUP_MARK)."
  fi
  local wt; wt="$(cat "$WT_BACKUP_MARK" 2>/dev/null || true)"
  if [ -n "$wt" ] && [ -f "$wt" ]; then
    local target="${wt%.bak-*}"
    echo "$wt 로 Windows Terminal 설정을 되돌립니다."
    run cp -p "$wt" "$target"
  else
    echo "Windows Terminal 백업이 없어 건너뜁니다($WT_BACKUP_MARK)."
  fi
}

main() {
  local with_pairvim=0 action=apply a
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY=1 ;;
      --no-theme) THEME_ON=0 ;;
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
  zshrc_needs_change && backup_zshrc
  apply_zshrc
  if [ "$THEME_ON" = 1 ]; then
    ensure_syntax_plugin
    apply_syntax_plugin
    apply_spacing
    apply_ls_colors
    apply_windows_terminal
  fi
  if [ "$with_pairvim" = 1 ]; then
    echo "== PairVim 설치 =="
    if [ "$DRY" = 1 ]; then run bash "$SELF_DIR/install.sh" --dry-run; else bash "$SELF_DIR/install.sh"; fi
  fi
  echo "== 완료 =="
  echo "새 터미널을 열거나 'exec zsh' 로 적용하세요. 기본 쉘이 zsh 가 아니면: chsh -s \$(which zsh)"
  echo "Windows Terminal 색상은 설정 저장 즉시 바뀝니다."
}

main "$@"
