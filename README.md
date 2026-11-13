# PairVim

[LazyVim](https://github.com/LazyVim/LazyVim) 기반의 개인 전용 Neovim 배포판입니다.

## 특징

- Claude Code / Codex를 에디터 옆 세로 분할 패널로 바로 사용 (`Space a a`로 선택, `Space a c` / `Space a x`로 각각 토글)
- 패널을 처음 열 때 이전 대화 히스토리가 있으면 이어서, 없으면 코드베이스 자동 분석/가이드 요청
- 새 머신에서 이 레포를 내려받아 nvim을 처음 실행하면 `codex`/`claude` CLI가 없을 경우 자동 설치
- 단축키 가이드(which-key) 상위 그룹명 한글화
- Neovim을 apt로 설치하지 않고, 소스를 받아 실행 파일 이름/버전 문구를 "pairvim"/"PairVim"으로 바꾼 뒤 직접 빌드 (`build-pairvim.sh`, `pairvim-rebrand.patch`)

## 설치

### 상황별 선택

| 상황 | 방법 |
|---|---|
| 처음 설치 (Neovim 설정이 없음) | 아래 **빠른 설치** |
| 이미 LazyVim/Neovim 설정이 있음 (`~/.config/nvim` 존재) | 같은 **빠른 설치** — 설치 스크립트가 기존 설정을 이름 붙여 옮겨 두고(확인 후), 언제든 되돌릴 수 있음 |
| apt가 없는 환경 (macOS, Fedora 등) | 스크립트는 지원하지 않음. **수동 설치**를 참고해 직접 설치 |

### 빠른 설치 (처음이든 기존 설정이 있든 같은 방법)

```bash
git clone https://github.com/bjw5035/PairVim.git ~/pairvim-setup
bash ~/pairvim-setup/install.sh --dry-run    # (선택) 무엇을 할지 미리 보기. 아무것도 바꾸지 않음
bash ~/pairvim-setup/install.sh
```

- 저장소는 공개라 로그인 없이 `git clone`이 됩니다. (비공개로 되돌린 경우: 사용자 이름 + 개인 액세스 토큰. fine-grained 토큰은 Repository access에서 이 저장소를 선택하고 Contents를 Read-only로 줘야 하며, 비밀번호는 받지 않습니다.)
- `~/.config/nvim`에 **PairVim이 아닌 기존 설정**이 있으면, 옮길 목록을 보여 주고 `[y/N]`로 확인한 뒤 `nvim-old-<시각>` 이름으로 옮깁니다.
  - 옮기는 것: 설정(`~/.config/nvim`), 플러그인(`~/.local/share/nvim/lazy`), 상태(`~/.local/state/nvim`), 캐시(`~/.cache/nvim`)
  - 옮기지 않는 것: `runtime`, `mason`(LSP 등 도구는 그대로 재사용)
  - `.git`이 있어도 원격 주소가 PairVim이 아니면 기존 설정으로 취급합니다.
- 이어서 (apt 기반 WSL/Ubuntu 기준):
  - git, node/npm, ripgrep, fd 같은 기본 도구 설치 (`sudo` 비밀번호 필요)
  - 받아 둔 클론을 `~/.config/nvim`으로 복제 (로그인을 다시 묻지 않음)
  - `neovim/neovim` 소스를 받아 `pairvim-rebrand.patch`를 적용(실행 파일 이름 `nvim`→`pairvim`, 버전 문구 `NVIM`→`PairVim`)하고 직접 빌드 — 몇 분 걸림. apt의 범용 Neovim과 따로 `~/.local/bin/pairvim`으로 설치되며 기존 `nvim` 바이너리는 건드리지 않음
  - codex/claude CLI를 sudo 없이 설치할 `~/.npm-global` 준비 (전역 `npm config`는 바꾸지 않음)
- 옵션: `--dry-run`(계획만 출력), `--yes`(확인 생략), `--rollback`(되돌리기), `--help`

설치 끝나면:

```bash
source ~/.zshrc   # bash면 ~/.bashrc, 또는 새 터미널 열기
pairvim --version | head -1   # "PairVim ..." 이 보이면 정상
pairvim
```

처음 실행하면 lazy.nvim이 플러그인을 설치하고, `codex`/`claude` CLI가 없으면 자동 설치됩니다(이미 있으면 건너뜀). 메시지 다 지나갈 때까지 기다렸다가 아무 키나 누르면 끝. 두 CLI의 로그인은 직접 합니다.

> **주의**: AI 패널(`Space a a`)을 처음 열면 열린 폴더의 "코드베이스 분석" 요청이 자동 실행됩니다. 민감한 자료가 있는 폴더에서는 처음 열지 마세요(빈 폴더에서 먼저 시험).

### 되돌리기

```bash
bash ~/.config/nvim/install.sh --rollback
```

- 마지막 백업 기록(`~/.config/.pairvim-last-backup`)을 읽어, **PairVim 쪽**(설정·플러그인·상태·캐시)을 지우고 옛 설정을 제자리로 복원합니다. 지우기 전에 확인을 받습니다.
- `pairvim` 실행 파일까지 지우려면: `rm -f ~/.local/bin/pairvim`
- 설치 후에는 그냥 `nvim`도 `~/.config/nvim`(PairVim 설정)을 읽습니다. 옛 설정을 따로 켜려면 `NVIM_APPNAME=nvim-old-<시각> nvim` (백업 이름은 설치 마지막에 출력됨)

### 업데이트

```bash
git -C ~/.config/nvim pull
```

`pairvim-rebrand.patch`가 바뀐 경우에만 다시 빌드: `rm ~/.local/bin/pairvim && bash ~/.config/nvim/build-pairvim.sh`

### 문제 해결

- **`destination path '~/.config/nvim' already exists`**: 예전 안내(`~/.config/nvim`에 바로 클론)로 하면 기존 설정이 있을 때 실패합니다. 위 **빠른 설치**(`~/pairvim-setup`에 클론)를 쓰세요.
- **`패치 적용 실패 - neovim 소스 버전이 패치와 맞지 않습니다`**: 이미 쓰는 Neovim 버전(`nvim --version`)과 같은 태그로 맞춰 다시 실행합니다.
  ```bash
  rm -rf ~/.local/src/pairvim-neovim
  PAIRVIM_NVIM_REF=v0.12.6 bash ~/.config/nvim/build-pairvim.sh
  ```
- **`codex` 자동 설치 실패**: `npm`이 없거나 네트워크 문제입니다. 직접: `npm install -g --prefix ~/.npm-global @openai/codex`
- **클론에서 403/로그인 요구**: 저장소가 비공개로 바뀐 경우입니다. 위 토큰 설정(Only select repositories + Contents 읽기 전용)을 확인하세요.

### 수동 설치 (스크립트를 못 쓰거나 직접 하나씩 하고 싶을 때)

#### 1. 필수 프로그램 설치

| 프로그램 | 용도 | 설치 (Ubuntu/WSL 기준) |
|---|---|---|
| 빌드 도구 | pairvim(Neovim) 소스 빌드용 | `sudo apt install -y ninja-build gettext cmake unzip curl build-essential autoconf automake libtool-bin pkg-config` |
| git | 플러그인/레포 관리, 소스 클론 | `sudo apt install git` |
| node / npm | codex, claude CLI 설치용 | `sudo apt install nodejs npm` |
| ripgrep, fd-find | 파일/텍스트 검색 (Telescope 등) | `sudo apt install ripgrep fd-find` |
| 어떤 Nerd Font | 아이콘 깨짐 방지 (터미널 폰트로 지정) | [nerdfonts.com](https://www.nerdfonts.com/)에서 하나 받아서 터미널 설정에 적용 |

#### 2. 기존 설정 옮기기 (있을 때만)

```bash
ts=$(date +%Y%m%d%H%M%S); n=nvim-old-$ts
mv ~/.config/nvim ~/.config/$n
mkdir -p ~/.local/share/$n && mv ~/.local/share/nvim/lazy ~/.local/share/$n/lazy
mv ~/.local/state/nvim ~/.local/state/$n
mv ~/.cache/nvim ~/.cache/$n
echo $n > ~/.config/.pairvim-last-backup     # --rollback 이 이 기록을 씁니다
```

그 다음 이 레포를 그 자리에 클론:

```bash
git clone https://github.com/bjw5035/PairVim.git ~/.config/nvim
```

#### 3. pairvim 빌드 + 실행

```bash
bash ~/.config/nvim/build-pairvim.sh   # neovim 소스 클론 + 패치 + 빌드 (몇 분 소요)
pairvim
```

처음 실행하면 lazy.nvim이 플러그인을 설치하고, `codex`/`claude` CLI가 PATH에 없으면 `npm install -g --prefix ~/.npm-global`로 자동 설치를 시도합니다. `~/.npm-global/bin`을 PATH에 넣어 두세요:

```bash
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.zshrc   # bash면 ~/.bashrc
```

## 단축키

| 키 | 동작 |
|---|---|
| `Space h` | 단축키 모음 (별도 창 없이 Space 메뉴 안에서 바로 고름: f=파일찾기, r=최근파일, g=검색, e=탐색기, t=다음탭, b=탭닫기, s=아래분할, v=오른쪽분할, x=분할닫기, c=코드액션, a=AI패널) |
| `F2` | Claude Code / Codex 패널 선택/토글 |
| `Space a c` | Claude Code 패널 토글 |
| `Space a x` | Codex 패널 토글 |
| `Ctrl+h/j/k/l` | 창 이동 (AI 패널 안에서도 동작) |
| `Tab` / `Shift+Tab` | 이 창의 다음/이전 탭 (탭은 분할 창마다 따로 있음, 마우스 클릭·✕도 됨) |
| `Space b d` | 이 창에서 탭 닫기 (다른 창에도 없으면 파일도 닫음) |
| `Space [` | 아래로 분할 |
| `Space ]` | 오른쪽으로 분할 (현재 파일은 새 창으로, 원래 창엔 다른 파일) |
| `Space \` | 분할 창 닫기(탭은 이웃 창으로 이동). 창이 하나면 현재 탭만 닫고, 마지막 탭이면 종료 |
| `Space e` | 좌측 파일 탐색기 토글 |
| `F3` / `Space t t` | 하단 셸 패널 토글 (현재 파일 폴더에서 시작) |
| `Space t p` / `t v` / `t f` | terraform plan / validate / fmt (현재 파일 폴더) |
| (패널 안에서) `F4` | 터미널 노멀 모드로 빠져나가기 (`Esc`는 Claude/vi에 그대로 전달) |

상태줄에는 `AWS_PROFILE`과 terraform 워크스페이스(`.terraform/environment`)가 표시됩니다. 인자 없이 `pairvim`만 켜면 그 폴더에서 마지막에 닫은 창·파일·탭이 복원됩니다.

`Space w` 그룹(분할/이동/창목록이 섞여있음)은 헷갈리니 그냥 안 쓰는 걸 추천.

## 시험

- `bash tests/test_install.sh` — 설치 스크립트 시험(nvim 불필요, 홈 폴더를 건드리지 않음)
- `nvim --headless -u NONE -l tests/test_pane_tabs.lua` — 창별 탭 단위 시험(플러그인 불필요)
- `bash tests/test_e2e.sh` — 실제 nvim 을 가상 터미널에서 켜서 창 종류(파일·탐색기·Claude/셸 패널·분할) × 동작(분할·닫기·탭·창 이동·종료) 조합과 무작위 조합을 점검한다. 격리 폴더(`/tmp/pairvim-e2e`)에 플러그인을 설치해 쓰며 내 설정은 건드리지 않는다. 버그를 고칠 때는 여기에 재현 시나리오를 먼저 추가한다.
