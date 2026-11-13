-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- 분할만 딱 두 개 키로 단순하게 (Space w 그룹은 분할/이동/창목록이 섞여있어 헷갈려서 분리)
vim.keymap.set("n", "<leader>[", "<C-W>s", { desc = "아래로 분할" })
vim.keymap.set("n", "<leader>]", "<C-W>v", { desc = "오른쪽으로 분할" })
vim.keymap.set("n", "<leader>qw", "<C-W>c", { desc = "현재 창 닫기 (분할 한쪽 끄기)" })
