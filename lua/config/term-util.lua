-- toggleterm 패널(F7 셸, Space a c/x AI)을 열기 전에 공통으로 해야 하는 처리.
-- ai-terminal.lua 와 keymaps.lua(F7 셸 패널)가 같이 쓴다 — 따로 복사해두면
-- 한쪽만 고치고 잊어버리기 쉬워서 여기 하나로 모았다.
local M = {}

-- 파일 없이 켠 시작 화면(Snacks 대시보드)은 화면 전체를 덮는 플로팅 창이다.
-- 그 위에서 패널을 열면 플로팅 창 뒤에 가려지거나, 포커스가 엉뚱한(수정 불가능한)
-- 대시보드 버퍼로 남아 입력이 안 먹힌다(E21). 패널을 열기 전에 대시보드를
-- 플로팅이 아닌 일반 창 안으로 옮겨("도킹") 둔다.
function M.dock_dashboard()
  local float
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative ~= "" and vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "snacks_dashboard" then
      float = w
      break
    end
  end
  if not float then return end
  local base
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) == "" then
      base = w
      break
    end
  end
  local ok, snacks = pcall(require, "snacks")
  if not (base and ok and snacks.dashboard) then return end
  pcall(vim.api.nvim_win_close, float, true)
  if vim.api.nvim_win_is_valid(base) then
    vim.api.nvim_set_current_win(base)
    pcall(snacks.dashboard.open, { win = base })
  end
end

-- 탐색기(Explorer) 같은 플로팅 창, 또는 다른 터미널/피커 창에 포커스가 있으면
-- toggleterm 이 분할 기준 창을 못 찾아 "Invalid terminal direction" 오류를 낸다.
-- 패널을 열기 전에 포커스를 일반 파일창(또는 도킹된 대시보드)으로 옮긴다.
function M.focus_main()
  local cur = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(cur).relative == "" and vim.bo[vim.api.nvim_win_get_buf(cur)].buftype ~= "terminal" then
    return
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(w)
    local ft = vim.bo[b].filetype
    if vim.api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype ~= "terminal" and not ft:find("^snacks_picker") and not ft:find("^snacks_layout") then
      vim.api.nvim_set_current_win(w)
      return
    end
  end
end

return M
