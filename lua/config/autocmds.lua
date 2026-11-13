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

flatten_whichkey_icons_to_blue()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("pairvim_whichkey_colors", { clear = true }),
  callback = flatten_whichkey_icons_to_blue,
})
