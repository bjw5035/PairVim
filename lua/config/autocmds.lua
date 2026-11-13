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

-- 분할 창마다 위에 그 창의 파일 이름을 보여 준다(위쪽 탭줄은 열린 파일 전체 목록이라 창별 구분이 안 된다).
-- 파일 창이 2개 이상일 때만 표시하고, 탐색기·터미널·떠 있는 창에는 붙이지 않는다.
local function update_winbars()
  local file_wins = {}
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local cfg = vim.api.nvim_win_get_config(w)
    local buf = vim.api.nvim_win_get_buf(w)
    if cfg.relative == "" and vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "snacks_dashboard" then
      table.insert(file_wins, w)
    end
  end
  local show = #file_wins > 1
  for _, w in ipairs(file_wins) do
    vim.wo[w].winbar = show and "%#WinBar# %t%( %m%) " or ""
  end
end

vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinEnter", "BufWinEnter", "BufWritePost", "TextChanged", "TextChangedI" }, {
  group = vim.api.nvim_create_augroup("pairvim_winbar", { clear = true }),
  callback = function()
    vim.schedule(update_winbars)
  end,
})
