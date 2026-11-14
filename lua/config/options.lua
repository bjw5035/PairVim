-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- PairVim: 전용 nvim 배포판 타이틀
vim.o.title = true
vim.o.titlestring = "PairVim — %t"

-- 꾸밈
vim.o.cursorline = true
vim.o.scrolloff = 8
vim.opt.fillchars = { vert = "│", horiz = "─", eob = " ", fold = " " }

-- 클립보드: 화면(DISPLAY/Wayland)도 WSL 도 없는 환경(서버, ssh 접속 등)에서는 시스템 클립보드를 쓰지 않는다.
-- (xclip 만 설치돼 있으면 yank 할 때마다 "clipboard: error" 가 뜬다)
if vim.fn.has("wsl") ~= 1 and vim.fn.has("mac") ~= 1 and vim.fn.has("win32") ~= 1
  and (vim.env.DISPLAY or "") == "" and (vim.env.WAYLAND_DISPLAY or "") == "" then
  vim.o.clipboard = ""
end
