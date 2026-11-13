local STAR = { icon = "★", color = "yellow" }

return {
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        {
          mode = { "n", "x" },
          { "<leader><tab>", group = "탭" },
          { "<leader>c", group = "코드" },
          { "<leader>d", group = "디버그" },
          { "<leader>dp", group = "프로파일러" },
          { "<leader>f", group = "파일/찾기", icon = STAR },
          { "<leader>g", group = "git" },
          { "<leader>gh", group = "변경 블록" },
          { "<leader>q", group = "종료/세션" },
          { "<leader>s", group = "검색" },
          { "<leader>u", group = "UI 토글" },
          { "<leader>x", group = "진단/퀵픽스" },
          { "[", group = "이전" },
          { "]", group = "다음" },
          { "g", group = "이동(goto)" },
          { "gs", group = "서라운드" },
          { "z", group = "접기" },
          { "<leader>b", group = "버퍼", icon = STAR },
          { "<leader>w", group = "창" },

          -- 루트 레벨 개별 단축키 (그룹이 아닌 단일 항목들) 한글 설명으로 교체
          { "<leader>e", desc = "탐색기 (루트 기준)", icon = STAR },
          { "<leader>E", desc = "탐색기 (현재 폴더 기준)" },
          { "<leader>K", desc = "커서 아래 키워드 도움말" },
          { "<leader>l", desc = "플러그인 관리 (Lazy)" },
          { "<leader>L", desc = "업데이트 내역" },
          { "<leader>n", desc = "알림 히스토리" },
          { "<leader>S", desc = "스크래치 버퍼 선택" },
          { "<leader>,", desc = "버퍼 목록" },
          { "<leader>-", desc = "아래로 창 분할" },
          { "<leader>.", desc = "스크래치 버퍼 토글" },
          { "<leader>/", desc = "텍스트 검색 (루트 기준)", icon = STAR },
          { "<leader>:", desc = "명령어 히스토리" },
          { "<leader>?", desc = "버퍼 단축키 목록" },
          { "<leader>`", desc = "이전 버퍼로 전환" },
          { "<leader>|", desc = "오른쪽으로 창 분할" },
          { "<leader><space>", desc = "파일 찾기 (루트 기준)" },

          -- 자주 쓰는 것(★ 표시): 분할/닫기
          { "<leader>[", desc = "아래로 분할", icon = STAR },
          { "<leader>]", desc = "오른쪽으로 분할", icon = STAR },
          { "<leader>\\", desc = "현재 창 닫기 (분할 한쪽 끄기)", icon = STAR },
        },
      },
    },
  },
}
