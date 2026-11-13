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
          { "<leader>f", group = "파일/찾기" },
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
          { "<leader>b", group = "버퍼" },
          { "<leader>w", group = "창" },
        },
      },
    },
  },
}
