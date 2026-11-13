-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- 분할만 딱 두 개 키로 단순하게 (Space w 그룹은 분할/이동/창목록이 섞여있어 헷갈려서 분리)
-- 분할: 현재 파일은 새 창에 두고, 원래 창에는 다른 파일(직전에 보던 파일)을 보여 준다(VS Code의 "분할로 이동"과 같다).
-- 열린 파일이 하나뿐이면 같은 파일이 두 창에 보인다.
local function split_move(cmd)
  local cur = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local function usable(b)
    return b > 0 and b ~= cur and vim.fn.buflisted(b) == 1
  end
  local other
  local alt = vim.fn.bufnr("#")
  if usable(alt) then
    other = alt
  else
    for _, b in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
      if usable(b.bufnr) then
        other = b.bufnr
        break
      end
    end
  end
  vim.cmd(cmd)
  if other then
    vim.cmd("wincmd p")
    vim.cmd("buffer " .. other)
    vim.cmd("wincmd p")
  end
  -- 새 창의 커서는 분할 직전 위치 그대로 둔다(자동 "마지막 위치 복원"이 끼어들어 움직이는 것을 막는다)
  pcall(vim.api.nvim_win_set_cursor, 0, cursor)
end
vim.keymap.set("n", "<leader>[", function() split_move("split") end, { desc = "아래로 분할" })
vim.keymap.set("n", "<leader>]", function() split_move("vsplit") end, { desc = "오른쪽으로 분할" })
vim.keymap.set("n", "<leader>\\", function()
  -- which-key·오류 팝업 같은 떠 있는(floating) 창은 세지 않는다. 세면 마지막 창을 닫으려다 E444가 난다.
  local normal = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      normal = normal + 1
    end
  end
  if normal > 1 then
    vim.cmd("close")
  else
    -- 마지막 창이면 nvim을 종료한다(저장 안 한 파일이 있으면 물어본다)
    vim.cmd("confirm qall")
  end
end, { desc = "현재 창 닫기 (마지막 창이면 종료)" })

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
  wk_h.add({ { "<leader>h", group = "단축키 모음", icon = { icon = "★", color = "yellow" } } })
end
