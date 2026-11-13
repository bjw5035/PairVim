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
    require("config.pane-tabs").remove(vim.api.nvim_get_current_win(), cur)
    vim.cmd("wincmd p")
  end
  -- 새 창의 커서는 분할 직전 위치 그대로 둔다(자동 "마지막 위치 복원"이 끼어들어 움직이는 것을 막는다)
  pcall(vim.api.nvim_win_set_cursor, 0, cursor)
end
vim.keymap.set("n", "<leader>[", function() split_move("split") end, { desc = "아래로 분할" })
vim.keymap.set("n", "<leader>]", function() split_move("vsplit") end, { desc = "오른쪽으로 분할" })
vim.keymap.set("n", "<leader>\\", function()
  local pt = require("config.pane-tabs")
  -- which-key·오류 팝업 같은 떠 있는(floating) 창은 세지 않는다. 세면 마지막 창을 닫으려다 E444가 난다.
  local normal = 0
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(w).relative == "" then
      normal = normal + 1
    end
  end
  local win = vim.api.nvim_get_current_win()
  if normal > 1 then
    -- 분할 창 닫기: 닫는 창의 탭은 사라지지 않고 포커스가 가는 이웃 창으로 옮겨 간다.
    local moved = pt.list(win)
    vim.cmd("close")
    local now = vim.api.nvim_get_current_win()
    for _, b in ipairs(moved) do pt.add(now, b) end
  elseif #pt.list(win) > 1 then
    -- 창은 하나, 탭이 여럿: 전부 닫지 않고 지금 탭만 닫는다.
    pt.close()
  else
    -- 마지막 창의 마지막 탭이면 nvim을 종료한다(저장 안 한 파일이 있으면 물어본다)
    vim.cmd("confirm qall")
  end
end, { desc = "창 닫기 (탭이 여럿이면 탭만, 마지막이면 종료)" })

-- 탭(버퍼) 이동/닫기를 Shift+h/l 대신 더 직관적인 Tab 키로 (브라우저 탭 전환과 같은 느낌)
-- 탭은 창마다 따로다: 이동·닫기는 현재 창의 탭 목록 안에서만 한다.
vim.keymap.set("n", "<Tab>", function() require("config.pane-tabs").cycle(1) end, { desc = "다음 탭(이 창)" })
vim.keymap.set("n", "<S-Tab>", function() require("config.pane-tabs").cycle(-1) end, { desc = "이전 탭(이 창)" })
vim.keymap.set("n", "<S-l>", function() require("config.pane-tabs").cycle(1) end, { desc = "다음 탭(이 창)" })
vim.keymap.set("n", "<S-h>", function() require("config.pane-tabs").cycle(-1) end, { desc = "이전 탭(이 창)" })
vim.keymap.set("n", "]b", function() require("config.pane-tabs").cycle(1) end, { desc = "다음 탭(이 창)" })
vim.keymap.set("n", "[b", function() require("config.pane-tabs").cycle(-1) end, { desc = "이전 탭(이 창)" })
vim.keymap.set("n", "<leader>bd", function() require("config.pane-tabs").close() end, { desc = "이 창에서 탭 닫기" })

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

-- 터미널(셸) 패널: 편집하던 화면 아래에 기존 셸을 그대로 쓴다. 나가지 않고 terraform 등을 돌린다.
--   Space t t  셸 패널 토글(현재 파일이 있는 폴더에서 시작)   Space t p  terraform plan
--   Space t v  terraform validate   Space t f  terraform fmt   Space t a  terraform apply는 일부러 만들지 않았다
local shell_term
local function shell_dir()
  local f = vim.api.nvim_buf_get_name(0)
  if f ~= "" and vim.bo.buftype == "" then
    return vim.fn.fnamemodify(f, ":p:h")
  end
  return vim.fn.getcwd()
end
local function get_shell()
  if not shell_term then
    local Terminal = require("toggleterm.terminal").Terminal
    shell_term = Terminal:new({
      direction = "horizontal",
      size = 16,
      close_on_exit = true,
      start_in_insert = true,
      on_exit = function() shell_term = nil end,
    })
  end
  return shell_term
end
local function shell_toggle()
  local t = get_shell()
  if not t:is_open() and not t.job_id then t.dir = shell_dir() end
  t:toggle()
end
local function shell_run(cmd)
  local dir = shell_dir()
  local t = get_shell()
  if not t:is_open() then
    if not t.job_id then t.dir = dir end
    t:open()
  end
  t:send("cd " .. vim.fn.shellescape(dir) .. " && " .. cmd)
end
vim.keymap.set("n", "<leader>tt", shell_toggle, { desc = "셸 패널 토글" })
vim.keymap.set("t", "<F3>", function() if shell_term then shell_term:toggle() end end, { desc = "셸 패널 닫기" })
vim.keymap.set("n", "<F3>", shell_toggle, { desc = "셸 패널 토글" })
vim.keymap.set("n", "<leader>tp", function() shell_run("terraform plan") end, { desc = "terraform plan (이 파일 폴더)" })
vim.keymap.set("n", "<leader>tv", function() shell_run("terraform validate") end, { desc = "terraform validate" })
vim.keymap.set("n", "<leader>tf", function() shell_run("terraform fmt") end, { desc = "terraform fmt" })
local ok_wk_t, wk_t = pcall(require, "which-key")
if ok_wk_t then
  wk_t.add({ { "<leader>t", group = "터미널/terraform", icon = { icon = "★", color = "yellow" } } })
end

