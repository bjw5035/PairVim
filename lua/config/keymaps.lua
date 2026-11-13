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

-- F1: 실제로 쓰는 단축키만 추린 개인 매뉴얼 (LazyVim 전체 단축키가 아니라 PairVim 전용 요약)
local function show_cheatsheet()
  local lines = {
    "  PairVim 단축키",
    "",
    "  F1          단축키 도움말 (지금 이 창)",
    "  F2          AI 패널 선택 (Claude / Codex)",
    "",
    "  Space f f   파일 찾기",
    "  Space f r   최근 파일",
    "  Space /     텍스트 검색",
    "  Space e     파일 탐색기 토글",
    "",
    "  Shift+h     이전 탭(버퍼)",
    "  Shift+l     다음 탭(버퍼)",
    "  Space b d   탭(버퍼) 닫기",
    "",
    "  Space [     아래로 분할",
    "  Space ]     오른쪽으로 분할",
    "  Space \\    분할 창 닫기",
    "  Ctrl+h/j/k/l  창 이동",
    "",
    "  gd          정의로 이동",
    "  K           문서 보기",
    "  Space c a   코드 액션",
    "",
    "  q 또는 Esc 로 닫기",
  }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local width = 40
  local height = #lines
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
  })
  vim.wo[win].winhighlight = "Normal:NormalFloat"

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.keymap.set("n", "q", close, { buffer = buf })
  vim.keymap.set("n", "<esc>", close, { buffer = buf })
end

vim.keymap.set("n", "<F1>", show_cheatsheet, { desc = "단축키 도움말" })
