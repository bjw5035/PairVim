# SSH 단축키 이름만 보기 (인자 주면 그 문자열 포함된 것만: sshls prd)
sshls() { alias | sed -n "s/^\([A-Za-z0-9_-]*\)='ssh .*/\1/p" | sort | grep -i -- "."; }

# Host 기반 ssh config 항목 조회 (bastion 내부 서버용, sshls와 별개)
sshhosts() { grep -h "^Host " ~/.ssh/config ~/.ssh/config.d/internal 2>/dev/null | awk '{print $2}' | grep -v '\*' | sort -u | grep -i -- "${1:-.}"; }

# sshgo 1단계 선택용 프로젝트별 bastion 그룹
# (여기 나오는 이름은 ~/.ssh/config 의 Host 별명일 뿐, 실제 IP/서버 목록은 이 레포에 없음 - 머신마다 따로 둔다)
typeset -A SSHGO_PROJECT=(
  prd_frankfurt_front             GalaxyStore
  prd_ireland_front        GalaxyStore
  kiro_bastion             GalaxyStore
  stg_frankfurt_front              GalaxyStore
  stg_ireland_front        GalaxyStore
  prd_backoffice_jmp       GSNEXT
  prd_backoffice_ops_jmp   GSNEXT
  stg_backoffice_jmp       GSNEXT
  stg_backoffice_ops_jmp   GSNEXT
  issep_prd_appsroot       ISSEP
  issep_stg_appsroot       ISSEP
)
typeset -a SSHGO_PROJECT_ORDER=(GalaxyStore GSNEXT ISSEP)

# sshgo 내부에서 실제 접속할 때 쓰는 헬퍼: "비밀번호"/host-key 확인은 자동, OTP(Second Factor)부터는 직접 입력
# - 비밀번호는 이 터미널 세션에서 처음 한 번만 물어보고 메모리(_SSHP_PW)에 유지, 디스크 저장 없음
# - expect가 없으면 그냥 평범한 ssh로 접속 (수동 입력)
# - 세션 중 비밀번호 캐시를 지우고 싶으면 sshp_clear
_sshgo_connect() {
  local target="$1"
  if ! command -v expect >/dev/null 2>&1; then
    ssh "$target"
    return
  fi
  if [ -z "$_SSHP_PW" ]; then
    read -s "_SSHP_PW?계정 비밀번호 (이 터미널 세션 동안만 메모리에 유지): "
    echo
  fi
  SSHP_PW="$_SSHP_PW" SSHP_HOST="$target" SSHGO_DEBUG="${SSHGO_DEBUG:-0}" expect -c '
    if {$env(SSHGO_DEBUG) == "1"} { exp_internal 1 }
    set timeout 15
    set pwcount 0
    spawn ssh $env(SSHP_HOST)
    # interact 자체의 -re 매칭은 (a) 데이터가 여러 조각으로 나뉘어 도착하면 못 잡는 경우가 있고
    # (b) -nocase 옵션 자체를 지원하지 않아서(지원 안 되면 에러로 스크립트가 죽음) 신뢰할 수 없었다.
    # 그래서 자동 처리는 항상 버퍼링되는 expect{}+exp_continue로 하고, Second Factor(OTP)만
    # gets stdin으로 한 줄 받아서 그대로 전달한다 (이 시점엔 아직 interact를 안 써서 터미널이 일반
    # 모드 그대로라 백스페이스 등 편집도 정상 동작한다).
    # (?i) 대신 -nocase를 쓰는 이유: expect가 패턴에서 자동으로 만드는 "gate" 사전 필터가 (?i)를 무시하고
    # 대소문자를 구분해버려서, 실제로 대문자가 섞인 프롬프트(예: Second Factor)를 통째로 놓치는 버그가 있었다.
    expect {
      -nocase -re {continue connecting|yes/no} { send -- "yes\r"; exp_continue }
      -nocase -re {(password|first factor)\s*:\s*$} {
        if {$pwcount < 2} {
          send -- "$env(SSHP_PW)\r"
          incr pwcount
        }
        exp_continue
      }
      -nocase -re {second factor\s*:\s*$} {
        send -- "[gets stdin]\r"
        exp_continue
      }
      timeout { }
      eof { }
    }
    interact
  '
}

sshp_clear() {
  unset _SSHP_PW
  echo "세션에 캐시된 비밀번호를 지웠습니다."
}

# 3단계 fzf: 프로젝트 선택 -> bastion 선택 -> 그 안의 내부 서버 선택 -> 접속
# Backspace(검색어가 비어있을 때 한 번 더): 이전 단계로 되돌아가기
# Esc: 그 단계 자체를 취소 (1~2단계는 sshgo 종료, 3단계는 bastion 자체로 접속 — 기존 단축키 유지)
sshgo() {
  local project bastion sel host all_bastions b stage=1
  local back_bind='bspace:transform:[ -z "$FZF_QUERY" ] && echo "change-query(__BACK__)+print-query" || echo backward-delete-char'

  all_bastions=$(grep -h "^Host " ~/.ssh/config | awk '{print $2}' | grep -v '\*' | sort -u)

  while true; do
    case $stage in
      1)
        project=$(
          { for p in "${SSHGO_PROJECT_ORDER[@]}"; do echo "$p"; done
            while IFS= read -r b; do echo "${SSHGO_PROJECT[$b]:-기타}"; done <<< "$all_bastions"
          } | awk '!seen[$0]++' | \
          fzf --height=40% --reverse --header="프로젝트 선택" \
              --bind 'bspace:backward-delete-char/eof')
        [ -z "$project" ] && return
        stage=2
        ;;
      2)
        sel=$(while IFS= read -r b; do
          [ "${SSHGO_PROJECT[$b]:-기타}" = "$project" ] || continue
          ip=$(awk -v h="$b" '
            $1=="Host" && $2==h { f=1; next }
            f && /^[ \t]*HostName/ { print $2; exit }
            f && /^Host / { exit }
          ' ~/.ssh/config)
          printf '%s\t%s\n' "$b" "$ip"
        done <<< "$all_bastions" | column -t -s$'\t' | \
          fzf --height=40% --reverse --header="$project bastion 선택 (Backspace: 프로젝트 재선택)" \
              --bind "$back_bind")
        if [ "$sel" = "__BACK__" ]; then
          stage=1
          continue
        fi
        [ -z "$sel" ] && return
        bastion=$(echo "$sel" | awk '{print $1}')
        stage=3
        ;;
      3)
        sel=$(awk -v b="$bastion" '
          function flush() {
            if (host != "" && jump == b) {
              line = host "\t" hostname ":" port
              if (tag != "") line = line "\t" tag
              print line
            }
          }
          /^[ \t]*#/ { pending = $0; sub(/^[ \t]*#[ \t]*/, "", pending); next }
          /^Host / { flush(); host=$2; hostname=""; jump=""; port=""; tag=pending; pending="" }
          /^[ \t]*HostName/ { hostname=$2 }
          /^[ \t]*ProxyJump/ { jump=$2 }
          /^[ \t]*Port/ { port=$2 }
          END { flush() }
        ' ~/.ssh/config.d/internal | sort -u | column -t -s$'\t')

        if [ -z "$sel" ]; then
          _sshgo_connect "$bastion"
          return
        fi

        sel=$(echo "$sel" | fzf --height=60% --reverse --tiebreak=index \
              --header="$bastion 내부 서버 선택 (Esc: $bastion 자체 접속 / Backspace: bastion 재선택)" \
              --bind "$back_bind")
        if [ "$sel" = "__BACK__" ]; then
          stage=2
          continue
        fi
        if [ -z "$sel" ]; then
          _sshgo_connect "$bastion"
          return
        fi
        host=$(echo "$sel" | awk '{print $1}')
        _sshgo_connect "$host"
        return
        ;;
    esac
  done
}

# gitall: GalaxyStore 레포 3개 git pull origin main + 색 구분 + 요약
gitall() { local _t _e _l _r
  local base=/mnt/c/GalaxyStore
  local repos=($base/argocd $base/infra $base/ISSEP-infra/infra)
  local d name
  local -a results
  for d in "${repos[@]}"; do
    name=${d#$base/}
_t=" $name "; _e=""; _l=$(( (44 - ${(m)#_t}) / 2 )); _r=$(( 44 - ${(m)#_t} - _l )); print; print -P "%F{208}%B${(l:$_l::=:)_e}${_t}${(l:$_r::=:)_e}%b%f"
    if git -C "$d" pull origin main; then
      results+=("%F{green}[OK]%f   $name")
    else
      results+=("%F{red}[실패]%f $name")
    fi
  done
_t=" 요약 "; _e=""; _l=$(( (44 - ${(m)#_t}) / 2 )); _r=$(( 44 - ${(m)#_t} - _l )); print; print -P "%B${(l:$_l::=:)_e}${_t}${(l:$_r::=:)_e}%b"
  for r in "${results[@]}"; do print -P "$r"; done
}
