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
  local win = vim.api.nvim_get_current_win()
  -- 탐색기·터미널·떠 있는 창은 "파일 창"으로 세지 않는다. (세면 탐색기가 열린 채로 파일 창이 닫힌다)
  if not pt.is_file_win(win) then
    -- 파일 창이 아닌 곳(탐색기, 터미널 패널)에서 누르면 그 창만 닫는다
    if vim.api.nvim_win_get_config(win).relative == "" then pcall(vim.cmd, "close") end
    return
  end
  local files = pt.file_wins()
  if #files > 1 then
    -- 분할 창 닫기: 닫는 창의 탭은 사라지지 않고 포커스가 가는 이웃 파일 창으로 옮겨 간다.
    local moved = pt.list(win)
    vim.cmd("close")
    local now = vim.api.nvim_get_current_win()
    if pt.is_file_win(now) then
      for _, b in ipairs(moved) do pt.add(now, b) end
    end
  elseif #pt.list(win) > 1 then
    -- 파일 창은 하나, 탭이 여럿: 전부 닫지 않고 지금 탭만 닫는다.
    pt.close()
  else
    -- 마지막 파일: nvim 은 종료하지 않고 그 파일만 닫는다(저장 안 한 변경은 pane-tabs 가 물어본다).
    -- 닫은 자리에는 시작 화면을 보여 주고, 탐색기가 열려 있으면 그쪽으로 포커스를 옮긴다.
    local before = vim.api.nvim_win_get_buf(win)
    pt.close(win)
    -- 저장 확인에서 취소했으면(같은 버퍼가 그대로) 아무것도 하지 않는다
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == before then return end
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.dashboard and vim.api.nvim_win_is_valid(win) then
      -- win 을 넘겨서 "닫은 그 창 안에" 시작 화면을 그린다. 넘기지 않으면 Snacks 가 화면 전체를 덮는 플로팅 창으로 열어서,
      -- 이후 탐색기(l)로 연 파일이 그 아래 원래 창에 열려 시작 화면에 가려져 "파일이 안 뜬다"로 보였다.
      pcall(snacks.dashboard.open, { win = win })
    end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "snacks_picker_list" then
        vim.api.nvim_set_current_win(w)
        return
      end
    end
  end
end, { desc = "창 닫기 (탭이 여럿이면 탭만, 마지막 파일이면 그 파일만 닫고 탐색기로)" })

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
--   Space t t  셸 패널 토글(현재 파일이 있는 폴더에서 시작)   Space t r / F5  현재 파이썬 파일 실행   Space t p  terraform plan
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
      on_exit = function(t)
        -- 셸이 끝나면(exit) 죽은 터미널 창이 남지 않게 정리하고, 다음 F7 가 새 셸을 연다
        shell_term = nil
        vim.schedule(function() pcall(function() t:shutdown() end) end)
      end,
    })
  end
  return shell_term
end
-- 대시보드 도킹 / 포커스 이동(둘 다 "Invalid terminal direction", E21 같은 오류를 막는다)은
-- Space a c/x AI 패널과 공유한다 — lua/config/term-util.lua 참고.
local term_util = require("config.term-util")
local focus_main = term_util.focus_main
local dock_dashboard = term_util.dock_dashboard
-- 처음 열 때는 toggleterm 전역 size(=AI 패널용 panel_size, 가로폭 기준 함수)가
-- 잘못 적용돼 패널이 화면을 거의 다 차지하던 버그가 있어 16줄로 강제한다.
-- 그 다음부터는 강제하지 않아서, 사용자가 직접 리사이즈(Ctrl-w +/-, 마우스 드래그)한
-- 크기가 persist_size(toggleterm 기본 동작)로 세션 내내 유지된다.
local shell_sized = false
local function shell_toggle()
  local t = get_shell()
  if not t:is_open() and not t.job_id then t.dir = shell_dir() end
  dock_dashboard()
  focus_main()
  if shell_sized then
    t:toggle()
  else
    shell_sized = true
    t:toggle(16, "horizontal")
  end
end
local function shell_run(cmd)
  local dir = shell_dir()
  local t = get_shell()
  if not t:is_open() then
    if not t.job_id then t.dir = dir end
    dock_dashboard()
    focus_main()
    if shell_sized then
      t:open()
    else
      shell_sized = true
      t:open(16, "horizontal")
    end
  end
  t:send("cd " .. vim.fn.shellescape(dir) .. " && " .. cmd)
end
-- 현재 파일 실행(Space t r 또는 F5): 아래에 실행 전용 패널을 열어 `python3 파일` 을 직접 돌린다.
--  - 저장 안 한 변경은 먼저 저장하고, 파일이 있는 폴더에서 실행한다(그 폴더의 todos.json 같은 상대 경로 파일을 그대로 쓴다).
--  - input() 이 있는 프로그램은 패널에서 바로 입력한다(패널이 열리면 입력 모드로 시작).
--  - 끝나면 출력이 패널에 남는다. 코드를 고치고 다시 F5 를 누르면 이전 실행을 끄고 새로 돌린다.
--  - 패널 안: F8 노멀 모드 → q 로 닫기, 또는 F5 로 코드 창으로 돌아가 다시 실행. (셸 패널 F7 과는 별개다)
local run_term
local function run_file()
  if vim.bo.buftype ~= "" or vim.api.nvim_buf_get_name(0) == "" then
    vim.notify("실행할 파일이 아닙니다(파일 창에서 눌러 주세요).", vim.log.levels.WARN)
    return
  end
  if vim.bo.filetype ~= "python" then
    vim.notify("지금은 파이썬 파일만 실행합니다. (셸 패널은 F7)", vim.log.levels.WARN)
    return
  end
  local py = (vim.fn.executable("python3") == 1 and "python3") or (vim.fn.executable("python") == 1 and "python") or nil
  if not py then
    vim.notify("python3 를 찾지 못했습니다. 설치되어 있는지 확인하세요.", vim.log.levels.ERROR)
    return
  end
  if vim.bo.modified then pcall(vim.cmd, "silent write") end
  local file, dir = vim.fn.expand("%:t"), vim.fn.expand("%:p:h")
  if run_term then
    local old = run_term
    run_term = nil
    pcall(function() old:shutdown() end)
  end
  local Terminal = require("toggleterm.terminal").Terminal
  local t
  t = Terminal:new({
    cmd = py .. " " .. vim.fn.shellescape(file),
    dir = dir,
    direction = "horizontal",
    size = 16,
    close_on_exit = false,
    start_in_insert = true,
    on_open = function(term)
      local back = function()
        pcall(vim.cmd, "stopinsert")
        pcall(vim.cmd, "wincmd p")
        run_file()
      end
      vim.keymap.set({ "n", "t" }, "<F5>", back, { buffer = term.bufnr, desc = "코드 창으로 돌아가 다시 실행" })
      vim.keymap.set("n", "q", function() term:shutdown() end, { buffer = term.bufnr, desc = "실행 패널 닫기" })
    end,
    on_exit = function() if run_term == t then run_term = nil end end,
  })
  run_term = t
  t:open()
end
vim.keymap.set("n", "<leader>tr", run_file, { desc = "현재 파일 실행 (python3)" })
vim.keymap.set("n", "<F5>", run_file, { desc = "현재 파일 실행 (python3)" })
vim.keymap.set("n", "<leader>tt", shell_toggle, { desc = "셸 패널 토글" })
vim.keymap.set("t", "<F7>", function() if shell_term then shell_term:toggle() end end, { desc = "셸 패널 닫기" })
vim.keymap.set("n", "<F7>", shell_toggle, { desc = "셸 패널 토글" })
vim.keymap.set("n", "<leader>tp", function() shell_run("terraform plan") end, { desc = "terraform plan (이 파일 폴더)" })
vim.keymap.set("n", "<leader>tv", function() shell_run("terraform validate") end, { desc = "terraform validate" })
vim.keymap.set("n", "<leader>tf", function() shell_run("terraform fmt") end, { desc = "terraform fmt" })
local ok_wk_t, wk_t = pcall(require, "which-key")
if ok_wk_t then
  wk_t.add({ { "<leader>t", group = "터미널/terraform", icon = { icon = "★", color = "yellow" } } })
end

