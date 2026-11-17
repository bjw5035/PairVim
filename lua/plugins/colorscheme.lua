-- 컬러스킴: catppuccin mocha. 윈도우 터미널(terminal-setup.sh 의 Catppuccin Mocha, 배경 #282828)과 배경을 맞추려고
-- base 만 #282828 로 바꾼다(mantle·crust 는 같은 계열의 더 어두운 중립 회색). catppuccin 은 LazyVim 에 이미 들어 있다.
-- 되돌리기: color_overrides 를 지우거나 colorscheme 을 "tokyonight" 로. 포인트 색은 config/autocmds.lua 가 현재 스킴에서 읽어 온다.
return {
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin-mocha" } },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      color_overrides = {
        mocha = { base = "#282828", mantle = "#222222", crust = "#1b1b1b" },
      },
    },
  },
}
