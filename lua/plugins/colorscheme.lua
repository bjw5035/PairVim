-- 컬러스킴: LazyVim 기본(tokyonight) 대신 catppuccin mocha. catppuccin 은 LazyVim 에 이미 들어 있어 따로 받지 않는다.
-- 되돌리기: 아래 값을 "tokyonight" 로 바꾼다. 포인트 색은 config/autocmds.lua 가 현재 스킴에서 읽어 온다.
return {
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin-mocha" } },
}
