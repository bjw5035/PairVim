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

-- 꾸밈: 눈에 띄는 변화만 둔다 — (1) 포커스 없는 창을 어둡게, (2) 활성 탭에 파란 막대·밝은 배경,
-- (3) 현재 줄 강조, (4) 창 구분선, (5) 시작 화면 로고·들여쓰기 가이드 색.
local function shade(color, f)
  if type(color) ~= "number" then return nil end
  local r, g, b = math.floor(color / 65536) % 256, math.floor(color / 256) % 256, color % 256
  return string.format("#%02x%02x%02x", math.floor(r * f), math.floor(g * f), math.floor(b * f))
end

local function pairvim_highlights()
  local set = vim.api.nvim_set_hl
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal.bg
  local dark = shade(bg, 0.72) or "#14141c"
  local lift = shade(bg, 1.0) and string.format("#%06x", math.min(0xffffff, (bg or 0x1a1b26) + 0x141418)) or "#2a2e45"
  set(0, "NormalNC", { bg = dark })                          -- 포커스 없는 창: 어둡게
  set(0, "WinSeparator", { fg = "#7aa2f7", bg = "NONE" })    -- 창 구분선: 파란색
  set(0, "TabLine", { fg = "#7a82a8", bg = dark })           -- 비활성 탭
  set(0, "TabLineSel", { fg = "#c0caf5", bg = lift, bold = true }) -- 활성 탭
  set(0, "TabLineFill", { bg = dark })
  set(0, "PairTabAccent", { fg = "#7aa2f7", bg = lift })     -- 활성 탭 왼쪽 파란 막대
  set(0, "PairTabClose", { fg = "#565f89", bg = dark })
  set(0, "PairTabModified", { fg = "#e0af68", bg = lift, bold = true })
  set(0, "WinBar", { bg = dark })
  set(0, "WinBarNC", { bg = dark })
  set(0, "CursorLine", { bg = lift })
  set(0, "CursorLineNr", { fg = "#ff9e64", bold = true })
  set(0, "SnacksDashboardHeader", { fg = "#7aa2f7" })
  set(0, "SnacksIndentScope", { fg = "#bb9af7" })
end
vim.schedule(pairvim_highlights)
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("pairvim_highlights", { clear = true }),
  callback = function() vim.schedule(pairvim_highlights) end,
})
