# PairVim

[LazyVim](https://github.com/LazyVim/LazyVim) 기반의 개인 전용 Neovim 배포판입니다.

## 특징

- Claude Code / Codex를 에디터 옆 세로 분할 패널로 바로 사용 (`Space a a`로 선택, `Space a c` / `Space a x`로 각각 토글)
- 패널을 처음 열 때 이전 대화 히스토리가 있으면 이어서, 없으면 코드베이스 자동 분석/가이드 요청
- 새 머신에서 이 레포를 내려받아 nvim을 처음 실행하면 `codex`/`claude` CLI가 없을 경우 자동 설치
- 단축키 가이드(which-key) 상위 그룹명 한글화

## 새 PC에서 세팅하기

### 빠른 설치 (추천)

Neovim 설치부터 PairVim 설정 적용까지 한 번에:

```bash
git clone https://github.com/bjw5035/PairVim.git ~/.config/nvim && bash ~/.config/nvim/install.sh
```

(저장소가 비공개라 `curl`로 직접 받을 수 없어서, `git clone`으로 받은 뒤 그 안의 설치 스크립트를 실행하는 방식입니다. `git clone` 과정에서 GitHub 로그인 창이 뜨면 로그인하면 됩니다.)

apt 기반 배포판/WSL 기준으로, 내부적으로 Neovim, git, node/npm, ripgrep, fd가 없으면 설치하고, `pairvim`이라는 실행 파일(`~/.local/bin/pairvim`, alias가 아니라 진짜 실행 파일이라 어떤 쉘에서도 동작)과 npm 전역 설치 경로까지 자동으로 잡아줍니다.

설치 끝나면:

```bash
source ~/.zshrc   # 또는 새 터미널 열기
pairvim           # 또는 nvim
```

처음 실행하면 lazy.nvim이 플러그인을 설치하고, `codex`/`claude` CLI도 없으면 자동 설치됩니다. 메시지 다 지나갈 때까지 기다렸다가 아무 키나 누르면 끝.

### 수동 설치 (curl 스크립트를 못 쓰거나 직접 하나씩 하고 싶을 때)

#### 1. 필수 프로그램 설치

| 프로그램 | 용도 | 설치 (Ubuntu/WSL 기준) |
|---|---|---|
| Neovim 0.10+ | 에디터 본체 | `sudo apt install neovim` (너무 구버전이면 [공식 releases](https://github.com/neovim/neovim/releases)에서 받기) |
| git | 플러그인/레포 관리 | `sudo apt install git` |
| node / npm | codex, claude CLI 설치용 | `sudo apt install nodejs npm` |
| ripgrep, fd-find | 파일/텍스트 검색 (Telescope 등) | `sudo apt install ripgrep fd-find` |
| 어떤 Nerd Font | 아이콘 깨짐 방지 (터미널 폰트로 지정) | [nerdfonts.com](https://www.nerdfonts.com/)에서 하나 받아서 터미널 설정에 적용 |

#### 2. 이 설정 받기

기존 `~/.config/nvim`이 있다면 먼저 백업:

```bash
mv ~/.config/nvim ~/.config/nvim.bak
```

그 다음 이 레포를 그 자리에 클론:

```bash
git clone https://github.com/bjw5035/PairVim.git ~/.config/nvim
```

#### 3. 실행

```bash
nvim
```

처음 실행하면:
- lazy.nvim이 자동으로 모든 플러그인(toggleterm, which-key 등) 설치
- `codex`/`claude` CLI가 PATH에 없으면 자동으로 `npm install -g`로 설치 시도 (sudo 권한 문제로 실패하면 아래처럼 사용자 전용 npm 경로를 먼저 잡아줄 것)

설치 중 메시지가 다 지나갈 때까지 기다린 뒤 아무 키나 누르면 끝.

#### 4. (선택) npm 전역 설치가 권한 때문에 실패할 경우

```bash
mkdir -p ~/.npm-global
npm config set prefix "$HOME/.npm-global"
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.zshrc   # bash면 ~/.bashrc
source ~/.zshrc
```

이후 nvim을 다시 열면 `codex`/`claude` 자동 설치가 정상적으로 진행됨.

## 단축키

| 키 | 동작 |
|---|---|
| `Space a a` | Claude Code / Codex 선택 메뉴 |
| `Space a c` | Claude Code 패널 토글 |
| `Space a x` | Codex 패널 토글 |
| (패널 안에서) `Esc` | 터미널 노멀 모드로 빠져나가기 |
| (패널 안에서) `Ctrl+h/j/k/l` | 창 이동 |
