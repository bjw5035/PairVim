# PairVim

[LazyVim](https://github.com/LazyVim/LazyVim) 기반의 개인 전용 Neovim 배포판입니다.

## 특징

- Claude Code / Codex를 에디터 옆 세로 분할 패널로 바로 사용 (`Space a a`로 선택, `Space a c` / `Space a x`로 각각 토글)
- 패널을 처음 열 때 이전 대화 히스토리가 있으면 이어서, 없으면 코드베이스 자동 분석/가이드 요청
- 새 머신에서 이 레포를 내려받아 nvim을 처음 실행하면 `codex`/`claude` CLI가 없을 경우 자동 설치
- 단축키 가이드(which-key) 상위 그룹명 한글화
