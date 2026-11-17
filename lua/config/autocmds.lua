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

-- 시작 화면(대시보드)은 열려 있는 동안 창 크기가 바뀌어도(AI/셸 패널 열고 닫기, 탐색기 토글 등) 스스로
-- 다시 그리지 않아서, 가로 폭이 바뀌면 로고가 한쪽으로 잘리거나 메뉴 한글이 깨져 보였다.
-- 창 크기가 바뀔 때마다 강제로 다시 그려서 항상 현재 폭에 맞게 고치게 한다.
-- WinResized 한 번으로는 부족할 때가 있어서(토글터미널이 창을 여는 동안 레이아웃이 여러 단계로 바뀜),
-- 약간 지연시켜 레이아웃이 다 정리된 다음 그리고, 추가로 WinNew/TermOpen 에서도 한 번 더 그린다.
local function redraw_dashboard()
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.dashboard and snacks.dashboard.update then
    pcall(snacks.dashboard.update)
  end
  -- 혹시 wrap이 다시 켜져서 한글이 줄바꿈으로 잘려 보이는 것까지 방지(대시보드 창은 항상 wrap 꺼둔다)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "snacks_dashboard" then
      vim.wo[w].wrap = false
      vim.wo[w].linebreak = false
    end
  end
end
vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "WinNew", "TermOpen", "WinClosed" }, {
  group = vim.api.nvim_create_augroup("pairvim_dashboard_redraw", { clear = true }),
  callback = function()
    redraw_dashboard()
    vim.defer_fn(redraw_dashboard, 60)
  end,
})

-- vi 쓸 때 입력기(IME)를 영문으로 강제 전환 (WSL + im-select.exe)
require("config.ime")

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
  -- 포인트 색은 현재 컬러스킴의 문법 색에서 읽어 온다(스킴을 바꿔도 따라간다). 못 읽으면 예전 tokyonight 값을 쓴다.
  local function fg_of(group, fallback)
    local c = vim.api.nvim_get_hl(0, { name = group, link = false }).fg
    return type(c) == "number" and string.format("#%06x", c) or fallback
  end
  local blue = fg_of("Function", "#7aa2f7")
  local orange = fg_of("Constant", "#ff9e64")
  local purple = fg_of("Keyword", "#bb9af7")
  local yellow = fg_of("DiagnosticWarn", "#e0af68")
  local text = fg_of("Normal", "#c0caf5")
  local dim = fg_of("Comment", "#636c96")
  set(0, "NormalNC", { bg = dark })                          -- 포커스 없는 창: 어둡게
  set(0, "WinSeparator", { fg = blue, bg = "NONE" })         -- 창 구분선
  set(0, "TabLine", { fg = dim, bg = dark })                 -- 비활성 탭
  set(0, "TabLineSel", { fg = text, bg = lift, bold = true }) -- 활성 탭
  set(0, "TabLineFill", { bg = dark })
  set(0, "PairTabAccent", { fg = blue, bg = lift })          -- 활성 탭 왼쪽 막대
  set(0, "PairTabClose", { fg = dim, bg = dark })
  set(0, "PairTabModified", { fg = yellow, bg = lift, bold = true })
  set(0, "WinBar", { bg = dark })
  set(0, "WinBarNC", { bg = dark })
  set(0, "CursorLine", { bg = lift })
  set(0, "CursorLineNr", { fg = orange, bold = true })
  set(0, "SnacksDashboardHeader", { fg = blue })
  set(0, "SnacksIndentScope", { fg = purple })
  -- 탐색기 폴더(이름 Directory, 아이콘 MiniIconsAzure)는 파랑 대신 옅은 로즈워터로 눌러 둔다. catppuccin 이면 팔레트에서, 아니면 고정값.
  local ok, pal = pcall(function() return require("catppuccin.palettes").get_palette() end)
  local folder = (ok and type(pal) == "table" and pal.rosewater) or "#f5e0dc"
  set(0, "Directory", { fg = folder })
  set(0, "MiniIconsAzure", { fg = folder })
end
vim.schedule(pairvim_highlights)
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("pairvim_highlights", { clear = true }),
  callback = function() vim.schedule(pairvim_highlights) end,
})

-- 파일 창이 있었다가 마지막 파일 창이 닫혔을 때(:q 등) 탐색기나 터미널 패널만 남으면 nvim 을 종료한다
-- (저장 안 한 파일이 있으면 물어본다). 파일을 한 번도 연 적이 없거나 시작 직후(3초)에는 동작하지 않는다:
-- `nvim .` 처럼 시작하는 중에 창이 정리되는 것을 "마지막 파일 창을 닫음"으로 오해해 종료를 시도하면 안 된다.
local pairvim_start = vim.uv.now()
vim.api.nvim_create_autocmd("WinClosed", {
  group = vim.api.nvim_create_augroup("pairvim_quit_when_no_files", { clear = true }),
  callback = function()
    vim.schedule(function()
      if vim.v.vim_did_enter ~= 1 or vim.g.SessionLoad ~= nil then return end
      if not vim.g.pairvim_had_file then return end
      if vim.uv.now() - pairvim_start < 3000 then return end
      local pt = require("config.pane-tabs")
      local others = 0
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(w).relative == "" then
          if pt.is_file_win(w) then return end
          local b = vim.api.nvim_win_get_buf(w)
          local ft = vim.bo[b].filetype
          local aux = vim.bo[b].buftype == "terminal" or ft:find("^snacks_picker") or ft == "snacks_layout_box"
          if not aux then return end -- 대시보드·도움말·기타 창이 있으면 그대로 둔다
          others = others + 1
        end
      end
      if others > 0 then pcall(vim.cmd, "confirm qall") end
    end)
  end,
})

-- PairVim 관리 명령(:Pair)과 시작 시 업데이트 확인
require("config.pair").setup()
