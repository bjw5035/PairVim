-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- 분할만 딱 두 개 키로 단순하게 (Space w 그룹은 분할/이동/창목록이 섞여있어 헷갈려서 분리)
vim.keymap.set("n", "<leader>[", "<C-W>s", { desc = "아래로 분할" })
vim.keymap.set("n", "<leader>]", "<C-W>v", { desc = "오른쪽으로 분할" })
vim.keymap.set("n", "<leader>\\", function()
  if #vim.api.nvim_tabpage_list_wins(0) > 1 then
    vim.cmd("close")
  else
    vim.notify("분할된 창이 하나뿐이라 닫을 게 없습니다 (nvim 전체 종료 방지)", vim.log.levels.WARN)
  end
end, { desc = "현재 창 닫기 (분할 한쪽 끄기)" })

-- 탭(버퍼) 이동/닫기를 Shift+h/l 대신 더 직관적인 Tab 키로 (브라우저 탭 전환과 같은 느낌)
vim.keymap.set("n", "<Tab>", "<cmd>bnext<cr>", { desc = "다음 탭(버퍼)" })
vim.keymap.set("n", "<S-Tab>", "<cmd>bprevious<cr>", { desc = "이전 탭(버퍼)" })

-- Space h: 실제로 쓰는 단축키만 모아서 Space 메뉴(which-key) 안에서 바로 고르는 모음
-- (별도 팝업 창 없이, Space를 눌렀을 때 보이는 그 목록 안에서 바로 보고 실행)
local function feed(keys)
  return function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "m", false)
  end
end

vim.keymap.set("n", "<leader>hf", feed("<leader>ff"), { desc = "파일 찾기" })
vim.keymap.set("n", "<leader>hr", feed("<leader>fr"), { desc = "최근 파일" })
vim.keymap.set("n", "<leader>hg", feed("<leader>/"), { desc = "텍스트 검색" })
vim.keymap.set("n", "<leader>he", feed("<leader>e"), { desc = "파일 탐색기 토글" })
vim.keymap.set("n", "<leader>ht", feed("<Tab>"), { desc = "다음 탭(버퍼)" })
vim.keymap.set("n", "<leader>hb", feed("<leader>bd"), { desc = "탭(버퍼) 닫기" })
vim.keymap.set("n", "<leader>hs", feed("<leader>["), { desc = "아래로 분할" })
vim.keymap.set("n", "<leader>hv", feed("<leader>]"), { desc = "오른쪽으로 분할" })
vim.keymap.set("n", "<leader>hx", feed("<leader>\\"), { desc = "분할 창 닫기" })
vim.keymap.set("n", "<leader>hc", feed("<leader>ca"), { desc = "코드 액션" })
vim.keymap.set("n", "<leader>ha", feed("<F2>"), { desc = "AI 패널 선택 (Claude/Codex)" })

local ok_wk_h, wk_h = pcall(require, "which-key")
if ok_wk_h then
  wk_h.add({ { "<leader>h", group = "단축키 모음" } })
end
