-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- which-key: ★(노란색)로 표시한 자주 쓰는 항목 외에는 전부 파란색 아이콘으로 통일
local function flatten_whichkey_icons_to_blue()
  for _, name in ipairs({ "Azure", "Cyan", "Green", "Grey", "Orange", "Purple", "Red" }) do
    vim.api.nvim_set_hl(0, "WhichKeyIcon" .. name, { link = "DiagnosticInfo" })
  end
end

-- which-key 자체가 ColorScheme 이벤트에서 같은 그룹을 mini.icons 색으로 되돌려놓기 때문에,
-- 그 처리가 끝난 다음 틱에 다시 덮어써야 실제로 파란색이 유지됨
vim.schedule(flatten_whichkey_icons_to_blue)
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("pairvim_whichkey_colors", { clear = true }),
  callback = function()
    vim.schedule(flatten_whichkey_icons_to_blue)
  end,
})

-- 창(분할)마다 자기 탭 목록을 갖는 탭줄
require("config.pane-tabs")

-- 꾸밈: 창 구분선·탭·창 상단 막대를 테마(tokyonight)에 맞춰 다듬는다.
local function pairvim_highlights()
  local set = vim.api.nvim_set_hl
  set(0, "WinSeparator", { fg = "#3b4261", bg = "NONE" })
  set(0, "TabLine", { fg = "#6c7399", bg = "#1a1b26" })
  set(0, "TabLineSel", { fg = "#7aa2f7", bg = "#292e42", bold = true })
  set(0, "TabLineFill", { bg = "#16161e" })
  set(0, "WinBar", { bg = "#16161e" })
  set(0, "WinBarNC", { bg = "#16161e" })
  set(0, "CursorLineNr", { fg = "#ff9e64", bold = true })
end
pairvim_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("pairvim_highlights", { clear = true }),
  callback = function() vim.schedule(pairvim_highlights) end,
})
