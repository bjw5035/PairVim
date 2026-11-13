-- 파일이 하나뿐이어도 위쪽 탭(버퍼 목록)을 항상 보여 준다. (LazyVim 기본은 2개 이상일 때만 표시)
return {
  {
    "akinsho/bufferline.nvim",
    opts = {
      options = {
        always_show_bufferline = true,
      },
    },
  },
}
