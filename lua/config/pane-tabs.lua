-- 창(분할)마다 자기 탭 목록을 갖는 탭줄. VS Code의 에디터 그룹과 같은 방식이다.
--  - 각 파일 창 위쪽(winbar)에 그 창에서 연 파일들만 탭으로 보인다.
--  - 새로 분할한 창은 현재 파일 하나로 시작한다(VS Code 와 같다). split_move 가 옮긴 파일은 원래 창 목록에서 빠진다.
--  - 탭을 마우스로 누르면 이동, ✕를 누르면 그 창에서만 닫는다.
local M = {}

local function is_file_win(w)
  if not vim.api.nvim_win_is_valid(w) then return false end
  if vim.api.nvim_win_get_config(w).relative ~= "" then return false end
  local b = vim.api.nvim_win_get_buf(w)
  return vim.bo[b].buftype == "" and vim.bo[b].filetype ~= "snacks_dashboard"
end

local function is_tab_buf(b)
  return vim.api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "" and vim.fn.buflisted(b) == 1
end

local function get(w)
  local ok, t = pcall(vim.api.nvim_win_get_var, w, "pv_tabs")
  return ok and t or {}
end

local function set(w, list)
  vim.api.nvim_win_set_var(w, "pv_tabs", list)
end

-- 유효하지 않은 버퍼를 걸러낸 목록
local function clean(w)
  local out = {}
  for _, b in ipairs(get(w)) do
    if is_tab_buf(b) then table.insert(out, b) end
  end
  return out
end

function M.add(w, b)
  if not is_tab_buf(b) then return end
  local list = clean(w)
  if not vim.tbl_contains(list, b) then table.insert(list, b) end
  set(w, list)
end

function M.remove(w, b)
  local out = {}
  for _, x in ipairs(clean(w)) do
    if x ~= b then table.insert(out, x) end
  end
  set(w, out)
end

function M.list(w) return clean(w or vim.api.nvim_get_current_win()) end

-- 현재 창의 탭을 n칸 이동(순환)
function M.cycle(n)
  local w = vim.api.nvim_get_current_win()
  if not is_file_win(w) then return end
  local list = clean(w)
  if #list < 2 then return end
  local cur = vim.api.nvim_win_get_buf(w)
  local idx = 1
  for i, b in ipairs(list) do if b == cur then idx = i end end
  vim.api.nvim_win_set_buf(w, list[((idx - 1 + n) % #list) + 1])
end

local function in_other_windows(b, except)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if w ~= except and vim.tbl_contains(clean(w), b) then return true end
  end
  return false
end

-- 이 창에서 파일 탭 하나를 닫는다. 다른 창에도 없으면 버퍼 자체를 닫는다.
function M.close(w, b)
  w = w or vim.api.nvim_get_current_win()
  b = b or vim.api.nvim_win_get_buf(w)
  if not vim.api.nvim_win_is_valid(w) or not is_tab_buf(b) then return end
  if vim.bo[b].modified and not in_other_windows(b, w) then
    local ans = vim.fn.confirm(("저장하지 않은 변경이 있습니다: %s"):format(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")), "&저장\n&버리고 닫기\n&취소", 3)
    if ans == 1 then
      vim.api.nvim_buf_call(b, function() vim.cmd("write") end)
    elseif ans ~= 2 then
      return
    end
  end
  local list = clean(w)
  local idx = 1
  for i, x in ipairs(list) do if x == b then idx = i end end
  M.remove(w, b)
  local rest = clean(w)
  if vim.api.nvim_win_get_buf(w) == b then
    if #rest > 0 then
      vim.api.nvim_win_set_buf(w, rest[math.min(idx, #rest)])
    else
      -- 이 창의 마지막 탭: 창이 여럿이면 창을 닫고, 하나뿐이면 빈 버퍼로 둔다
      local n = 0
      for _, x in ipairs(vim.api.nvim_tabpage_list_wins(0)) do if is_file_win(x) then n = n + 1 end end
      if n > 1 then
        pcall(vim.api.nvim_win_close, w, true)
      else
        vim.api.nvim_win_call(w, function() vim.cmd("enew") end)
      end
    end
  end
  if not in_other_windows(b, -1) and vim.api.nvim_buf_is_valid(b) then
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
end

-- 마우스 처리
function _G.PairTabGo(bufnr)
  local pos = vim.fn.getmousepos()
  if pos.winid > 0 and vim.api.nvim_win_is_valid(pos.winid) and is_tab_buf(bufnr) then
    vim.api.nvim_set_current_win(pos.winid)
    vim.api.nvim_win_set_buf(pos.winid, bufnr)
  end
end
function _G.PairTabClose(bufnr)
  local pos = vim.fn.getmousepos()
  if pos.winid > 0 then M.close(pos.winid, bufnr) end
end

local function esc(s) return (s:gsub("%%", "%%%%")) end

-- winbar 문자열: 창 번호를 인자로 받아(창마다 winbar 값에 번호를 박아 둔다) 그 창의 탭 목록을 만든다
function _G.PairTabs(w)
  if not w or not vim.api.nvim_win_is_valid(w) then return "" end
  local cur = vim.api.nvim_win_get_buf(w)
  local parts = {}
  for _, b in ipairs(clean(w)) do
    local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t")
    if name == "" then name = "[이름 없음]" end
    local active = b == cur
    local icon = ""
    local okm, mini = pcall(require, "mini.icons")
    if okm then
      local ic = mini.get("file", name)
      if ic then icon = ic .. " " end
    end
    local hl = active and "%#TabLineSel#" or "%#TabLine#"
    local bar = active and "%#PairTabAccent#▎" or "%#TabLine# "
    local mod = vim.bo[b].modified and "%#PairTabModified# ●" or ""
    table.insert(parts, ("%s%%%d@v:lua.PairTabGo@%s%s%s%s %%X%%#PairTabClose#%%%d@v:lua.PairTabClose@✕%%X%s "):format(
      bar, b, hl, esc(icon .. name), mod, active and "%#TabLineSel#" or "", b, "%#TabLine#"))
  end
  return table.concat(parts) .. "%#TabLineFill#"
end

local function refresh()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_file_win(w) then
      M.add(w, vim.api.nvim_win_get_buf(w))
      vim.wo[w].winbar = ("%%{%%v:lua.PairTabs(%d)%%}"):format(w)
    elseif vim.api.nvim_win_get_config(w).relative == "" and vim.wo[w].winbar:find("PairTabs", 1, true) then
      vim.wo[w].winbar = ""
    end
  end
  vim.cmd("redrawstatus")
end

vim.api.nvim_create_autocmd({ "WinNew", "WinClosed", "WinEnter", "BufWinEnter", "BufEnter", "BufWritePost", "BufDelete", "BufModifiedSet" }, {
  group = vim.api.nvim_create_augroup("pairvim_pane_tabs", { clear = true }),
  callback = function() vim.schedule(refresh) end,
})
vim.schedule(refresh)

return M
