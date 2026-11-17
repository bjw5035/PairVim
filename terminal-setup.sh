#!/usr/bin/env bash
# 터미널 설정 스크립트: zsh + Oh My Zsh + robbyrussell 프롬프트 + Catppuccin Mocha 색상 테마를 적용한다.
# - 새 PC: zsh / Oh My Zsh 를 설치하고 ~/.zshrc 를 만든다.
# - 이미 Starship 등이 설정된 PC(회사 PC): ~/.zshrc 를 백업한 뒤 테마만 robbyrussell 로 바꾸고 Starship 초기화 줄은 주석 처리한다(Starship 은 지우지 않음).
# - 색상 테마: ls 색상(LS_COLORS)을 Catppuccin Mocha 로 교체하고, WSL 이면 Windows Terminal 색상 스킴도 적용한다.
#   입력한 명령어와 출력이 구분되도록 zsh-syntax-highlighting 과 프롬프트 앞 빈 줄도 넣는다.
#   순수 Ubuntu 데스크탑이면 GNOME Terminal 색상과 JetBrainsMono Nerd Font 도 설정한다.
# - 환경: 자주 쓰는 alias(vi/ls/win/gs)와 PATH, eza, tmux·vim 설정(dotfiles/), 기본 쉘을 zsh 로 변경.
# 여러 번 실행해도 안전하다(이미 적용됐으면 건너뜀). 바꾸기 전에 항상 백업한다.
#
# 사용:
#   bash terminal-setup.sh --dry-run      # 아무것도 바꾸지 않고 계획만 출력
#   bash terminal-setup.sh                # 적용
#   bash terminal-setup.sh --yes          # 기본 쉘 변경 등 확인 질문에 모두 예
#   bash terminal-setup.sh --no-theme     # 색상 테마(ls 색상·창 색상·폰트)는 건너뜀
#   bash terminal-setup.sh                # 대화형 터미널이면 색상 테마를 번호로 고르는 메뉴가 뜬다(고른 값은 저장돼 다시 묻지 않음)
#   bash terminal-setup.sh --choose       # 저장된 선택이 있어도 메뉴를 다시 띄운다
#   bash terminal-setup.sh --scheme=dracula     # 메뉴 없이 직접 지정: dracula | nord | tokyonight | catppuccin(기본)
#                                               # (iTerm2-Color-Schemes 저장소의 스킴 이름도 그대로 쓸 수 있음)
#   bash terminal-setup.sh --bg=#1A1B26   # 터미널 배경색만 따로 지정(기본 #282828)
#   선택한 스킴/배경은 ~/.terminal-setup.conf 에 저장돼, 다음 실행에서 옵션 없이도 유지된다.
#   bash terminal-setup.sh --with-pairvim # 적용 후 PairVim(install.sh)까지 설치
#   bash terminal-setup.sh --rollback     # 백업한 설정(.zshrc, tmux/vim, 터미널 색상)으로 되돌리기
# 옵션: --dry-run --yes --choose --no-theme --scheme=이름 --bg=색 --with-pairvim --rollback --help
set -euo pipefail

ZSHRC="$HOME/.zshrc"
OMZ_DIR="$HOME/.oh-my-zsh"
THEME="robbyrussell"
SCHEME_NAME="Catppuccin Mocha"
BG="#282828"   # 터미널 배경색(--bg=#RRGGBB 로 바꿀 수 있음)
DEFAULT_BG="#282828"
BG_SET=0         # 1 이면 스킴의 배경 대신 BG 를 쓴다
SCHEME_ARG=""    # --scheme 값(비우면 내장 Catppuccin Mocha)
SCHEME_FILE=""   # 내려받은 스킴 JSON 임시 파일
CLI_SCHEME=0
CLI_BG=0
CHOOSE=0
CONF_HAS_SCHEME=0
CONF="$HOME/.terminal-setup.conf"
LS_START='# >>> terminal-setup: ls colors (catppuccin-mocha v1) >>>'
BACKUP_MARK="$HOME/.zshrc.last-backup"
WT_BACKUP_MARK="$HOME/.wt-settings.last-backup"
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRAS_START='# >>> terminal-setup: shell extras v1 >>>'
SSHGO_START='# >>> terminal-setup: sshgo/gitall v1 >>>'
PROMPT_START='# >>> terminal-setup: prompt colors v12 >>>'
DOT_LOG="$HOME/.terminal-setup.dotfiles.log"
GNOME_BACKUP="$HOME/.terminal-setup.gnome-terminal.last-backup"
DRY=0
YES=0
THEME_ON=1
WITH_PAIRVIM=0
SUDO_KEEPALIVE_PID=""

run() { if [ "$DRY" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

# root 로 실행 중이면 sudo 가 필요 없다(컨테이너 등)
if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi

# WSL 인가? (시험용으로 TS_FORCE_WSL=0/1 로 바꿀 수 있다)
is_wsl() {
  case "${TS_FORCE_WSL:-}" in 1) return 0 ;; 0) return 1 ;; esac
  grep -qi microsoft /proc/version 2>/dev/null
}

# 관리자 권한(apt 설치, 기본 쉘 변경)이 필요한 작업이 있으면 시작할 때 비밀번호를 한 번 묻고, 긴 설치 동안 인증이 만료되지 않게 유지한다.
needs_sudo() {
  [ "$WITH_PAIRVIM" = 1 ] && return 0
  local c
  for c in zsh git curl python3 tmux vim unzip fc-cache eza; do command -v "$c" >/dev/null 2>&1 || return 0; done
  [ "$(getent passwd "$(id -un)" | cut -d: -f7)" = "$(command -v zsh)" ] || return 0
  return 1
}
ensure_sudo() {
  [ -n "$SUDO" ] && [ "$DRY" != 1 ] || return 0
  needs_sudo || return 0
  if sudo -n true 2>/dev/null; then :; else
    echo "관리자 권한이 필요한 작업(패키지 설치, 기본 쉘 변경)이 있습니다. 비밀번호를 입력하세요."
    sudo -v || { echo "관리자 인증에 실패했습니다. 'sudo' 권한이 있는 계정으로 다시 실행하세요." >&2; exit 1; }
  fi
  ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "${BASH_SOURCE[0]}"; }

ensure_packages() {
  local pkgs=()
  command -v zsh >/dev/null 2>&1 || pkgs+=(zsh)
  command -v git >/dev/null 2>&1 || pkgs+=(git)
  command -v curl >/dev/null 2>&1 || pkgs+=(curl)
  command -v python3 >/dev/null 2>&1 || pkgs+=(python3)
  command -v tmux >/dev/null 2>&1 || pkgs+=(tmux)
  command -v vim >/dev/null 2>&1 || pkgs+=(vim)
  command -v unzip >/dev/null 2>&1 || pkgs+=(unzip)
  command -v fc-cache >/dev/null 2>&1 || pkgs+=(fontconfig)
  if [ "${#pkgs[@]}" -eq 0 ]; then echo "필수 패키지 이미 설치됨"; return 0; fi
  if ! command -v apt >/dev/null 2>&1; then
    echo "apt 가 없습니다. ${pkgs[*]} 를 직접 설치한 뒤 다시 실행하세요." >&2
    exit 1
  fi
  echo "설치할 패키지: ${pkgs[*]}"
  run $SUDO apt update
  run $SUDO apt install -y "${pkgs[@]}"
}

ensure_omz() {
  if [ -d "$OMZ_DIR" ]; then echo "Oh My Zsh 이미 설치됨"; return 0; fi
  echo "Oh My Zsh 설치 중(기본 쉘 변경·zsh 자동 실행 없음)..."
  if [ "$DRY" = 1 ]; then echo "[dry-run] Oh My Zsh 설치 스크립트 실행"; return 0; fi
  env -u ZSH RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
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
  grep -qF "zstyle ':omz:alpha:lib:git' async-prompt no" "$ZSHRC" || return 0
  if [ "$THEME_ON" = 1 ]; then
    grep -qF "$LS_START" "$ZSHRC" || return 0
    grep -qF "$SPACING_START" "$ZSHRC" || return 0
    grep -qE "^plugins=\(.*$SYN_NAME" "$ZSHRC" || return 0
    grep -qF "$EXTRAS_START" "$ZSHRC" || return 0
    grep -qF "$SSHGO_START" "$ZSHRC" || return 0
    grep -qF "$PROMPT_START" "$ZSHRC" || return 0
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
  # 3) git 상태(✗ 표시)를 비동기 대신 동기로: 비동기면 방금 바뀐 파일이 반영 안 되고 한 박자 늦게(또는 안) 뜰 수 있음
  if grep -qF "zstyle ':omz:alpha:lib:git' async-prompt no" "$ZSHRC"; then
    echo "git 상태 동기 표시 이미 적용됨"
  elif grep -q 'oh-my-zsh.sh' "$ZSHRC"; then
    echo "git 상태(✗)를 동기 방식으로 변경"
    run sed -i "/^source .*oh-my-zsh.sh/i zstyle ':omz:alpha:lib:git' async-prompt no" "$ZSHRC"
    changed=1
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

# 저장해 둔 스킴/배경 읽기(파일을 실행하지 않고 값만 읽는다)
load_conf() {
  [ -f "$CONF" ] || return 0
  local v
  grep -q '^SCHEME=' "$CONF" && CONF_HAS_SCHEME=1
  v="$(sed -n 's/^SCHEME=//p' "$CONF" | head -1)"
  [ -n "$v" ] && SCHEME_ARG="$v"
  v="$(sed -n 's/^BG=//p' "$CONF" | head -1 | tr 'a-f' 'A-F')"
  if [[ "$v" =~ ^#[0-9A-F]{6}$ ]]; then BG="$v"; BG_SET=1; fi
  return 0
}

# 색상 테마 선택 메뉴. 대화형 터미널이고, --scheme/--yes 가 없고, 저장된 선택이 없을 때(또는 --choose)만 뜬다.
choose_scheme_menu() {
  [ "$THEME_ON" = 1 ] || return 0
  [ "$CLI_SCHEME" = 1 ] && return 0
  [ "$YES" = 1 ] && return 0
  if [ "$CONF_HAS_SCHEME" = 1 ] && [ "$CHOOSE" != 1 ]; then return 0; fi
  [ -t 0 ] && [ -t 1 ] || return 0
  local ans
  echo
  echo "색상 테마를 고르세요:"
  echo "  1) Catppuccin Mocha  파스텔 톤, 따뜻한 회색 배경 (기본)"
  echo "  2) Dracula           선명한 보라/분홍/초록"
  echo "  3) Nord              차분한 회청색"
  echo "  4) Tokyo Night       짙은 남색"
  echo "  5) 건너뛰기          색상 테마는 적용하지 않음"
  while true; do
    read -r -p "번호를 입력하세요 [1]: " ans || ans=1
    case "${ans:-1}" in
      1) SCHEME_ARG="" ;;
      2) SCHEME_ARG="dracula" ;;
      3) SCHEME_ARG="nord" ;;
      4) SCHEME_ARG="tokyonight" ;;
      5) THEME_ON=0 ;;
      *) echo "1~5 중에서 고르세요."; continue ;;
    esac
    break
  done
  # 메뉴로 고른 경우 저장돼 있던 배경은 버리고 스킴의 배경을 쓴다
  BG_SET=0; BG="$DEFAULT_BG"
  return 0
}

save_conf() {
  [ "$DRY" = 1 ] && return 0
  {
    echo "SCHEME=$SCHEME_ARG"
    [ "$BG_SET" = 1 ] && echo "BG=$BG"
  } >"$CONF"
  return 0
}

# --scheme 이름을 iTerm2-Color-Schemes 저장소의 Windows Terminal JSON 으로 받아 형식을 검사한다.
# 이름이 비었거나 catppuccin 이면 내장 스킴을 쓴다.
resolve_scheme() {
  SCHEME_FILE=""
  local key fname url tmp
  key="$(printf '%s' "$SCHEME_ARG" | tr 'A-Z' 'a-z' | tr -d ' _-')"
  case "$key" in
    "" | catppuccin | catppuccinmocha | default) SCHEME_ARG=""; return 0 ;;
    dracula) fname="Dracula" ;;
    nord) fname="Nord" ;;
    tokyonight | tokyo) fname="TokyoNight" ;;
    *) fname="$SCHEME_ARG" ;;
  esac
  if ! [[ "$fname" =~ ^[A-Za-z0-9\ +._-]+$ ]]; then echo "--scheme 이름에 쓸 수 없는 문자가 있습니다: $fname" >&2; exit 2; fi
  url="https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/windowsterminal/${fname// /%20}.json"
  echo "색상 스킴 '$fname' 받는 중..."
  tmp="$(mktemp "${TMPDIR:-/tmp}/ts-scheme.XXXXXX")"
  if ! curl -fsSL "$url" -o "$tmp"; then
    echo "스킴 '$fname' 을 받지 못했습니다. 이름을 확인하세요: https://github.com/mbadolato/iTerm2-Color-Schemes/tree/master/windowsterminal" >&2
    rm -f "$tmp"; exit 1
  fi
  if ! python3 -I - "$tmp" <<'PY'
import json, re, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
keys = ["black","red","green","yellow","blue","purple","cyan","white",
        "brightBlack","brightRed","brightGreen","brightYellow","brightBlue","brightPurple","brightCyan","brightWhite",
        "background","foreground"]
assert isinstance(d.get("name"), str) and d["name"]
for k in keys:
    assert re.fullmatch(r"#[0-9a-fA-F]{6}", d.get(k, "")), k
PY
  then
    echo "스킴 파일 형식이 올바르지 않아 건너뜁니다." >&2; rm -f "$tmp"; exit 1
  fi
  SCHEME_FILE="$tmp"
}

# WSL 이면 Windows Terminal 의 settings.json 에 색상 스킴(기본 Catppuccin Mocha, --scheme 으로 변경)을 추가하고 기본 색상 스킴으로 지정한다.
# 그 외 설정(폰트·투명도 등)은 건드리지 않는다. 바꿀 때만 백업한다. (WT_SETTINGS 환경변수로 경로를 직접 줄 수 있다)
apply_windows_terminal() {
  local f="${WT_SETTINGS:-}"
  if [ -z "$f" ]; then
    is_wsl || { echo "WSL 이 아니라 Windows Terminal 설정은 건너뜁니다."; return 0; }
    local c
    for c in /mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminal_*/LocalState/settings.json \
      /mnt/c/Users/*/AppData/Local/Packages/Microsoft.WindowsTerminalPreview_*/LocalState/settings.json; do
      [ -f "$c" ] && { f="$c"; break; }
    done
  fi
  if [ -z "$f" ] || [ ! -f "$f" ]; then echo "Windows Terminal settings.json 을 찾지 못해 건너뜁니다."; return 0; fi
  echo "Windows Terminal 설정: $f"
  python3 -I - "$f" "$DRY" "$SCHEME_NAME" "$WT_BACKUP_MARK" "$BG" "$SCHEME_FILE" "$BG_SET" <<'PY'
import json, re, shutil, sys, time
path, dry, name, mark, bg = sys.argv[1], sys.argv[2] == "1", sys.argv[3], sys.argv[4], sys.argv[5]
scheme = {
    "name": name,
    "background": bg, "foreground": "#CDD6F4",
    "cursorColor": "#F5E0DC", "selectionBackground": "#585B70",
    "black": "#45475A", "red": "#F38BA8", "green": "#A6E3A1", "yellow": "#F9E2AF",
    "blue": "#89B4FA", "purple": "#F5C2E7", "cyan": "#94E2D5", "white": "#BAC2DE",
    "brightBlack": "#585B70", "brightRed": "#F38BA8", "brightGreen": "#A6E3A1", "brightYellow": "#F9E2AF",
    "brightBlue": "#89B4FA", "brightPurple": "#F5C2E7", "brightCyan": "#94E2D5", "brightWhite": "#A6ADC8",
}
scheme_file, bg_set = sys.argv[6], sys.argv[7] == "1"
if scheme_file:
    scheme = json.load(open(scheme_file, encoding="utf-8"))
    name = scheme["name"]
    if bg_set:
        scheme["background"] = bg
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
# 배경이 비치면 색이 탁해 보이므로 불투명(투명도 100, 아크릴 끔)으로 맞춘다
solid = defaults.get("opacity") == 100 and defaults.get("useAcrylic") is False
if have == scheme and defaults.get("colorScheme") == name and solid:
    print(f"Windows Terminal 은 이미 '{name}' + 불투명 배경 적용됨")
    sys.exit(0)
for p in data["profiles"].get("list", []):
    if p.get("colorScheme") and p["colorScheme"] != name:
        print(f"  참고: 프로필 '{p.get('name')}' 은 자체 색상 스킴({p['colorScheme']})이 지정돼 있어 기본값이 적용되지 않습니다.")
if dry:
    print(f"[dry-run] '{name}' 스킴 추가/갱신 + 불투명 배경(투명도 100, 아크릴 끔)으로 지정(백업 후 {path} 수정)")
    sys.exit(0)
backup = f"{path}.bak-{time.strftime('%Y%m%d%H%M%S')}"
shutil.copy2(path, backup)
open(mark, "w").write(backup + "\n")
data["schemes"] = [s for s in schemes if s.get("name") != name] + [scheme]
defaults["colorScheme"] = name
defaults["opacity"] = 100
defaults["useAcrylic"] = False
with open(path, "w", encoding="utf-8", newline="\n") as fh:
    json.dump(data, fh, indent=4, ensure_ascii=False)
    fh.write("\n")
print(f"Windows Terminal 에 '{name}' 적용 완료. 백업: {backup}")
print("  (settings.json 의 주석은 저장 과정에서 사라질 수 있습니다. 필요하면 위 백업을 보세요.)")
PY
}

# WSL이면 nvim(vi)이 쓸 im-select.exe(윈도우 IME 한/영 전환 도구)를 %LOCALAPPDATA%\im-select 에 받아 둔다.
# (nvim 쪽 설정은 lua/config/ime.lua 에 있고, 이 파일이 있어야 작동한다. 공식 배포 바이너리를 그대로 받는다.)
ensure_im_select() {
  is_wsl || { echo "WSL이 아니라 IME 자동 전환(im-select)은 건너뜁니다."; return 0; }
  local appdata; appdata="$(wslpath "$(cmd.exe /c "echo %LOCALAPPDATA%" 2>/dev/null | tr -d '\r')" 2>/dev/null)"
  [ -n "$appdata" ] || { echo "윈도우 LOCALAPPDATA 경로를 못 찾아 im-select 설치를 건너뜁니다."; return 0; }
  local dest="$appdata/im-select/im-select.exe"
  if [ -f "$dest" ]; then echo "im-select.exe 이미 있음: $dest"; return 0; fi
  echo "im-select.exe 받는 중 (vi 쓸 때 영문 IME로 자동 전환용)..."
  if [ "$DRY" = 1 ]; then echo "[dry-run] im-select.exe 를 $dest 에 받음"; return 0; fi
  run mkdir -p "$appdata/im-select"
  if run curl -fsSL "https://raw.githubusercontent.com/daipeihust/im-select/master/win/out/x64/im-select.exe" -o "$dest"; then
    echo "im-select.exe 설치 완료: $dest"
  else
    echo "im-select.exe 받기 실패 - vi에서 IME 자동 전환은 안 됩니다(기능에는 영향 없음)." >&2
  fi
}

# 프롬프트를 명령어/출력과 구분한다: 한 줄, 배경 블록 없이 색 글자만 쓴다.
#   ➜  폴더 git:(브랜치) ✗ 입력   ← robbyrussell 원래 모양(이미지 그대로). ➜ 는 초록(직전 명령이 실패하면 빨강)
#   폴더는 마지막 이름만(파랑 굵게), git:( ) 청록, 브랜치 분홍, ✗ 노랑 굵게. 색은 터미널 스킴을 따른다.
#   경로는 최근 3단계(/mnt/c 처럼)까지 보여 준다. 입력은 아래 구문 강조 색으로 프롬프트와 구분된다.
#   입력 중인 명령어: 존재하는 명령 초록 굵게, 옵션 주황, 문자열 노랑, 경로 밑줄, 없는 명령 빨강, 주석 회색
# 색 이름(green, blue ...)은 터미널의 Catppuccin 팔레트로 바뀌어 표시된다. oh-my-zsh 로드 뒤에 실행돼야 하므로 .zshrc 끝에 둔다.
# 이전 버전 블록이 있으면 시작·끝 표시가 모두 있을 때만 지우고 새 블록으로 바꾼다.
apply_prompt_colors() {
  [ -f "$ZSHRC" ] || return 0
  if grep -qF "$PROMPT_START" "$ZSHRC"; then echo "프롬프트 색상 이미 적용됨"; return 0; fi
  echo "프롬프트·명령어 색상 적용(한 줄, 색 글자)"
  if [ "$DRY" = 1 ]; then echo "[dry-run] ~/.zshrc 의 프롬프트 색상 블록을 새 버전으로 교체"; return 0; fi
  if grep -q '^# >>> terminal-setup: prompt colors' "$ZSHRC" && grep -q '^# <<< terminal-setup: prompt colors <<<' "$ZSHRC"; then
    sed -i '/^# >>> terminal-setup: prompt colors/,/^# <<< terminal-setup: prompt colors <<</d' "$ZSHRC"
  fi
  cat >>"$ZSHRC" <<'EOF'
# >>> terminal-setup: prompt colors v12 >>>
PROMPT='%(?:%B%F{green}%1{➜%}%f%b :%B%F{red}%1{➜%}%f%b ) %B%F{blue}%c%f%b $(git_prompt_info)'
ZSH_THEME_GIT_PROMPT_PREFIX="%F{cyan}git:(%f%F{magenta}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%f "
ZSH_THEME_GIT_PROMPT_DIRTY="%F{cyan})%f %B%F{yellow}%1{✗%}%f%b"
ZSH_THEME_GIT_PROMPT_CLEAN="%F{cyan})%f"
typeset -gA ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=green,bold'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=green,bold'
ZSH_HIGHLIGHT_STYLES[alias]='fg=green,bold'
ZSH_HIGHLIGHT_STYLES[function]='fg=green,bold'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=cyan,bold'
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#FAB387'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#FAB387'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=yellow'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=yellow'
ZSH_HIGHLIGHT_STYLES[path]='fg=white,underline'
ZSH_HIGHLIGHT_STYLES[comment]='fg=8'
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red,bold'
# <<< terminal-setup: prompt colors <<<
EOF
}

# 자주 쓰는 alias·PATH 블록. 개인 서버 주소 같은 비밀은 넣지 않는다(이 저장소는 공개).
# WSL 전용 alias(win, gs)는 WSL 일 때만 넣는다. win 은 사용자명을 하드코딩하지 않고 실행 시 찾는다.
apply_extras() {
  [ -f "$ZSHRC" ] || return 0
  if grep -qF "$EXTRAS_START" "$ZSHRC"; then echo "shell extras(alias/PATH) 이미 적용됨"; return 0; fi
  echo "shell extras(alias/PATH) 추가"
  if [ "$DRY" = 1 ]; then echo "[dry-run] ~/.zshrc 끝에 alias/PATH 블록 추가"; return 0; fi
  {
    cat <<'EOF'
# >>> terminal-setup: shell extras v1 >>>
# oh-my-zsh 기본 alias 중 방해되는 것 제거
unalias -- - 2>/dev/null
unalias '...' '....' '.....' '......' 2>/dev/null
unalias 1 2 3 4 5 6 7 8 9 _ 2>/dev/null
export PATH="$HOME/.local/bin:$HOME/.npm-global/bin:$PATH"
if command -v nvim >/dev/null 2>&1; then alias vi='nvim'; elif command -v pairvim >/dev/null 2>&1; then alias vi='pairvim'; fi
# eza: 소유자/용량/날짜까지 색상 적용된 ls 대체(Nerd Font 필요)
command -v eza >/dev/null 2>&1 && alias ls="eza --color=always --icons=auto --group-directories-first"
EOF
    if is_wsl; then
      cat <<'EOF'
# Windows 사용자 폴더 / C 드라이브로 이동
alias win='cd "$(wslpath "$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d "\r")")"'
alias gs='cd /mnt/c/'
EOF
    fi
    echo '# <<< terminal-setup: shell extras <<<'
  } >>"$ZSHRC"
}

# sshgo/gitall: 개인 SSH 접속 헬퍼 + 레포 일괄 pull 함수. 실제 서버 IP/상세 목록은 안 들어있고
# (그건 머신마다 ~/.ssh/config 에 따로 두는 것), bastion 분류용 별명과 함수 코드만 들어있다.
apply_sshgo() {
  [ -f "$ZSHRC" ] || return 0
  if grep -qF "$SSHGO_START" "$ZSHRC"; then echo "sshgo/gitall 이미 적용됨"; return 0; fi
  [ -f "$SELF_DIR/dotfiles/sshgo.zsh" ] || { echo "dotfiles/sshgo.zsh 가 없어 건너뜀" >&2; return 0; }
  echo "sshgo/gitall 추가"
  if [ "$DRY" = 1 ]; then echo "[dry-run] ~/.zshrc 끝에 sshgo/gitall 블록 추가"; return 0; fi
  {
    echo "$SSHGO_START"
    cat "$SELF_DIR/dotfiles/sshgo.zsh"
    echo '# <<< terminal-setup: sshgo/gitall <<<'
  } >>"$ZSHRC"
}

# eza(색상 ls). apt 에 없으면(오래된 Ubuntu) 건너뛰고 안내만 한다.
ensure_eza() {
  if command -v eza >/dev/null 2>&1; then echo "eza 이미 설치됨"; return 0; fi
  command -v apt >/dev/null 2>&1 || { echo "apt 가 없어 eza 설치를 건너뜁니다."; return 0; }
  local pol; pol="$(apt-cache policy eza 2>/dev/null || true)"
  if grep -q 'Candidate: [^(]' <<<"$pol"; then
    echo "eza 설치 중..."
    run $SUDO apt install -y eza
  else
    echo "이 배포판 apt 에는 eza 가 없어 건너뜁니다(Ubuntu 24.04 이상에는 있음). alias 는 eza 가 없으면 자동으로 적용되지 않습니다."
  fi
}

# dotfiles/ 의 설정을 홈으로 복사한다. 이미 같으면 건너뛰고, 다르면 백업한 뒤 덮어쓴다.
install_dotfile() {
  local src="$1" dest="$2" bak
  [ -f "$src" ] || { echo "$src 가 없어 건너뜁니다." >&2; return 0; }
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then echo "$dest 이미 같음"; return 0; fi
  if [ -e "$dest" ]; then
    bak="$dest.bak-$(date +%Y%m%d%H%M%S)"
    echo "$dest 백업: $bak"
    run cp -p "$dest" "$bak"
    [ "$DRY" = 1 ] || echo "$dest|$bak" >>"$DOT_LOG"
  fi
  echo "$dest 설치"
  run cp "$src" "$dest"
}

setup_dotfiles() {
  install_dotfile "$SELF_DIR/dotfiles/tmux.conf" "$HOME/.tmux.conf"
  install_dotfile "$SELF_DIR/dotfiles/vimrc" "$HOME/.vimrc"
}

# 순수 Ubuntu(GNOME Terminal)의 기본 프로필 색상을 Catppuccin Mocha 로. 바꾸기 전 값은 롤백용으로 저장한다.
apply_gnome_terminal() {
  is_wsl && return 0
  command -v gsettings >/dev/null 2>&1 || { echo "gsettings 가 없어 GNOME Terminal 색상은 건너뜁니다."; return 0; }
  local schemas; schemas="$(gsettings list-schemas 2>/dev/null || true)"
  grep -qx 'org.gnome.Terminal.ProfilesList' <<<"$schemas" ||
    { echo "GNOME Terminal 이 없어 창 색상은 건너뜁니다(다른 터미널은 catppuccin.com 에서 직접 적용)."; return 0; }
  if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ ! -S "/run/user/$(id -u)/bus" ]; then
    echo "데스크탑 세션이 아니라(SSH 등) GNOME Terminal 색상은 건너뜁니다. 데스크탑 터미널에서 다시 실행하세요."; return 0
  fi
  local uuid schema cur
  uuid="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")"
  [ -n "$uuid" ] || { echo "GNOME Terminal 기본 프로필을 찾지 못해 건너뜁니다."; return 0; }
  schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"
  cur="$(gsettings get "$schema" background-color 2>/dev/null | tr -d "'" | tr 'a-f' 'A-F')"
  local gbg="$BG" gfg='#CDD6F4' gpal="['#45475A','#F38BA8','#A6E3A1','#F9E2AF','#89B4FA','#F5C2E7','#94E2D5','#BAC2DE','#585B70','#F38BA8','#A6E3A1','#F9E2AF','#89B4FA','#F5C2E7','#94E2D5','#A6ADC8']"
  if [ -n "$SCHEME_FILE" ]; then
    local g
    mapfile -t g < <(python3 -I - "$SCHEME_FILE" "$BG_SET" "$BG" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
bg = sys.argv[3] if sys.argv[2] == "1" else s["background"]
order = ["black","red","green","yellow","blue","purple","cyan","white",
         "brightBlack","brightRed","brightGreen","brightYellow","brightBlue","brightPurple","brightCyan","brightWhite"]
print(bg.upper()); print(s["foreground"].upper())
print("[" + ",".join("'%s'" % s[k].upper() for k in order) + "]")
PY
)
    gbg="${g[0]}"; gfg="${g[1]}"; gpal="${g[2]}"
  fi
  if [ "$cur" = "$gbg" ]; then echo "GNOME Terminal 이미 같은 색상($gbg)"; return 0; fi
  echo "GNOME Terminal 색상 설정(프로필 $uuid, 배경 $gbg)"
  if [ "$DRY" = 1 ]; then echo "[dry-run] gsettings set $schema (배경/글자/팔레트)"; return 0; fi
  {
    echo "uuid=$uuid"
    local k
    for k in use-theme-colors background-color foreground-color palette; do
      printf '%s\t%s\n' "$k" "$(gsettings get "$schema" "$k" 2>/dev/null || true)"
    done
  } >"$GNOME_BACKUP"
  gsettings set "$schema" use-theme-colors false
  gsettings set "$schema" background-color "$gbg"
  gsettings set "$schema" foreground-color "$gfg"
  gsettings set "$schema" palette "$gpal"
  echo "  완료. 이미 열려 있는 터미널 창에는 바로 반영됩니다. 터미널 프로필 설정에서 폰트를 'JetBrainsMono Nerd Font' 로 고르세요."
}

# JetBrainsMono Nerd Font(아이콘용). 순수 Linux 에서만 설치한다(WSL 은 Windows 쪽에 설치해야 함). 체크섬이 맞을 때만 설치한다.
ensure_font() {
  if is_wsl; then
    echo "WSL: 폰트는 Windows 에 설치해야 합니다. https://www.nerdfonts.com/font-downloads 의 JetBrainsMono 를 설치하세요(없으면 eza 아이콘이 네모로 보일 수 있음)."
    return 0
  fi
  # 주의: `cmd | grep -q` 는 pipefail 에서 SIGPIPE 로 실패 처리되므로, 출력을 변수에 받아 검사한다.
  local fonts=""
  command -v fc-list >/dev/null 2>&1 && fonts="$(fc-list 2>/dev/null || true)"
  if grep -qiE 'JetBrainsMono.*(Nerd|NF)' <<<"$fonts"; then
    echo "JetBrainsMono Nerd Font 이미 설치됨"; return 0
  fi
  local base="https://github.com/ryanoasis/nerd-fonts/releases/latest/download" dest="$HOME/.local/share/fonts/JetBrainsMonoNF"
  echo "JetBrainsMono Nerd Font 설치 중(체크섬 검증)..."
  if [ "$DRY" = 1 ]; then echo "[dry-run] $base/JetBrainsMono.zip 을 받아 sha256 검증 후 $dest 에 설치"; return 0; fi
  local tmp expected actual
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ts-font.XXXXXX")"
  if ! curl -fsSL "$base/JetBrainsMono.zip" -o "$tmp/f.zip" || ! curl -fsSL "$base/SHA-256.txt" -o "$tmp/sha.txt"; then
    echo "폰트를 받지 못했습니다. 건너뜁니다."; rm -rf "$tmp"; return 0
  fi
  expected="$(grep -E ' JetBrainsMono\.zip$' "$tmp/sha.txt" | awk '{print $1}' | head -1)"
  actual="$(sha256sum "$tmp/f.zip" | awk '{print $1}')"
  if [ -z "$expected" ] || [ "$expected" != "$actual" ]; then
    echo "폰트 체크섬이 맞지 않아 설치하지 않습니다."; rm -rf "$tmp"; return 0
  fi
  mkdir -p "$dest" && unzip -oq "$tmp/f.zip" -d "$dest" && { command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$dest" >/dev/null 2>&1 || true; }
  rm -rf "$tmp"
  echo "폰트 설치 완료($dest)"
}

# 기본 로그인 쉘을 zsh 로. 확인 후에만 바꾼다(--yes 로 확인 생략, 대화형이 아니면 안내만 한다).
change_default_shell() {
  local z cur
  z="$(command -v zsh || true)"
  [ -n "$z" ] || return 0
  cur="$(getent passwd "$(id -un)" | cut -d: -f7)"
  if [ "$cur" = "$z" ]; then echo "기본 쉘 이미 zsh"; return 0; fi
  if [ "$DRY" = 1 ]; then echo "[dry-run] 기본 쉘을 $z 로 변경(chsh)"; return 0; fi
  if [ "$YES" != 1 ]; then
    if [ ! -t 0 ]; then echo "기본 쉘이 zsh 가 아닙니다. 대화형이 아니라 바꾸지 않았습니다. 직접: chsh -s $z (또는 --yes)"; return 0; fi
    local ans
    read -r -p "기본 쉘을 zsh 로 바꿀까요? (다음 로그인부터 적용) [Y/n] " ans
    [[ -z "$ans" || "$ans" =~ ^[Yy]$ ]] || { echo "기본 쉘은 그대로 둡니다. 나중에: chsh -s $z"; return 0; }
  fi
  grep -qx "$z" /etc/shells 2>/dev/null || echo "$z" | $SUDO tee -a /etc/shells >/dev/null
  $SUDO chsh -s "$z" "$(id -un)" && echo "기본 쉘을 zsh 로 변경했습니다. 로그아웃 후 다시 로그인하세요."
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
  # tmux/vim 등 dotfiles: 파일마다 가장 최근 백업으로 복원(새로 만든 파일은 그대로 둔다)
  if [ -f "$DOT_LOG" ]; then
    local dest bak
    while IFS='|' read -r dest bak; do
      [ -f "$bak" ] && { echo "$bak 로 $dest 를 되돌립니다."; run cp -p "$bak" "$dest"; }
    done < <(tac "$DOT_LOG" | awk -F'|' '!seen[$1]++')
  fi
  # GNOME Terminal 색상
  if [ -f "$GNOME_BACKUP" ] && command -v gsettings >/dev/null 2>&1; then
    local uuid schema k v
    uuid="$(sed -n 's/^uuid=//p' "$GNOME_BACKUP")"
    schema="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$uuid/"
    echo "GNOME Terminal 색상을 되돌립니다."
    while IFS=$'\t' read -r k v; do
      [ -n "$k" ] && [ -n "$v" ] && run gsettings set "$schema" "$k" "$v"
    done < <(grep -v '^uuid=' "$GNOME_BACKUP")
  fi
}

main() {
  local with_pairvim=0 action=apply a
  load_conf
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY=1 ;;
      --yes | -y) YES=1 ;;
      --no-theme) THEME_ON=0 ;;
      --choose) CHOOSE=1 ;;
      --scheme=*) SCHEME_ARG="${a#--scheme=}"; CLI_SCHEME=1 ;;
      --bg=*)
        BG_SET=1; CLI_BG=1
        BG="$(printf '%s' "${a#--bg=}" | tr 'a-f' 'A-F')"
        [[ "$BG" =~ ^#[0-9A-F]{6}$ ]] || { echo "--bg 는 #RRGGBB 형식이어야 합니다(예: --bg=#1A1B26)" >&2; exit 2; }
        ;;
      --with-pairvim) with_pairvim=1; WITH_PAIRVIM=1 ;;
      --rollback) action=rollback ;;
      --help | -h) usage; exit 0 ;;
      *) echo "알 수 없는 옵션: $a" >&2; usage; exit 2 ;;
    esac
  done
  # --scheme 만 새로 줬고 --bg 는 안 줬으면, 저장돼 있던 배경은 버리고 스킴의 배경을 쓴다
  if [ "$CLI_SCHEME" = 1 ] && [ "$CLI_BG" = 0 ]; then BG_SET=0; BG="$DEFAULT_BG"; fi
  if [ "$action" = rollback ]; then rollback; exit 0; fi
  choose_scheme_menu

  echo "== 터미널 설정 시작 =="
  ensure_sudo
  ensure_packages
  if [ "$THEME_ON" = 1 ]; then resolve_scheme; fi
  ensure_omz
  # 변경할 내용이 있을 때만 백업한다(안 그러면 재실행이 원본 백업을 덮어써 롤백이 무의미해짐)
  zshrc_needs_change && backup_zshrc
  apply_zshrc
  if [ "$THEME_ON" = 1 ]; then
    ensure_syntax_plugin
    apply_syntax_plugin
    apply_spacing
    apply_ls_colors
    apply_extras
    apply_prompt_colors
    apply_windows_terminal
    ensure_im_select
    apply_gnome_terminal
    ensure_font
    save_conf
    if [ -n "$SCHEME_FILE" ]; then rm -f "$SCHEME_FILE"; fi
  fi
  apply_sshgo
  ensure_eza
  setup_dotfiles
  change_default_shell
  if [ "$with_pairvim" = 1 ]; then
    echo "== PairVim 설치 =="
    if [ "$DRY" = 1 ]; then run bash "$SELF_DIR/install.sh" --dry-run; else bash "$SELF_DIR/install.sh"; fi
  fi
  echo "== 완료 =="
  echo "새 터미널을 열거나 'exec zsh' 로 적용하세요. tmux 는 'tmux kill-server' 후 다시 켜거나 tmux 안에서 prefix+r 로 다시 읽습니다."
  echo "되돌리기: bash terminal-setup.sh --rollback"
}

main "$@"
