-- 서버 접속 선택기: ~/.ssh/config 의 Host 목록을 고르면 하단 터미널 패널에서 ssh 로 접속한다.
-- 읽는 것은 Host / HostName / User / Include 줄뿐이고 키 파일 내용은 읽지 않는다.
local M = {}

local function read_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or {}
end

local function parse(path, hosts, depth)
  if depth > 3 then return end
  local cur
  for _, line in ipairs(read_lines(path)) do
    local key, val = line:match("^%s*(%a+)%s+(.-)%s*$")
    if key then
      key = key:lower()
      if key == "include" then
        for _, pat in ipairs(vim.split(val, "%s+")) do
          if not pat:match("^[/~]") then pat = vim.fn.expand("~/.ssh/") .. pat end
          for _, f in ipairs(vim.fn.glob(vim.fn.expand(pat), false, true)) do
            parse(f, hosts, depth + 1)
          end
        end
      elseif key == "host" then
        cur = {}
        for _, h in ipairs(vim.split(val, "%s+")) do
          if not h:find("[*?!]") then
            local e = { name = h }
            table.insert(hosts, e)
            table.insert(cur, e)
          end
        end
      elseif cur and (key == "hostname" or key == "user") then
        for _, e in ipairs(cur) do e[key] = val end
      end
    end
  end
end

function M.hosts()
  local hosts = {}
  parse(vim.fn.expand("~/.ssh/config"), hosts, 0)
  return hosts
end

local terms = {}

function M.connect(name)
  local t = terms[name]
  if not t then
    local Terminal = require("toggleterm.terminal").Terminal
    t = Terminal:new({
      cmd = "ssh " .. vim.fn.shellescape(name),
      direction = "horizontal",
      size = 20,
      close_on_exit = false,
      start_in_insert = true,
      display_name = "ssh " .. name,
      on_exit = function() terms[name] = nil end,
    })
    terms[name] = t
  end
  t:open()
end

function M.pick()
  local hosts = M.hosts()
  if #hosts == 0 then
    vim.notify("~/.ssh/config 에서 접속할 Host 를 찾지 못했습니다.", vim.log.levels.WARN)
    return
  end
  vim.ui.select(hosts, {
    prompt = "서버 접속 (ssh)",
    format_item = function(e)
      local extra = {}
      if e.user then table.insert(extra, e.user .. "@") end
      local tail = (e.user and (e.user .. "@") or "") .. (e.hostname or "")
      return e.name .. (tail ~= "" and ("   " .. tail) or "") .. (terms[e.name] and "   ● 열려 있음" or "")
    end,
  }, function(choice)
    if choice then M.connect(choice.name) end
  end)
end

return M
