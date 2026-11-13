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

-- 접속 후보를 여러 곳에서 모은다: ~/.ssh/config, (WSL이면) Windows 쪽 .ssh/config, tailscale 피어
function M.hosts()
  local hosts, sources = {}, {}
  local function from_config(path, label)
    if vim.uv.fs_stat(path) then
      local before = #hosts
      parse(path, hosts, 0)
      if #hosts > before then table.insert(sources, label) end
    end
  end
  from_config(vim.fn.expand("~/.ssh/config"), "~/.ssh/config")
  for _, f in ipairs(vim.fn.glob("/mnt/c/Users/*/.ssh/config", false, true)) do
    from_config(f, "Windows " .. f:match("/Users/([^/]+)/"))
  end
  if vim.fn.executable("tailscale") == 1 then
    local ok, out = pcall(vim.fn.system, { "tailscale", "status", "--json" })
    if ok and vim.v.shell_error == 0 then
      local ok2, data = pcall(vim.json.decode, out)
      if ok2 and type(data) == "table" and type(data.Peer) == "table" then
        local before = #hosts
        for _, peer in pairs(data.Peer) do
          local name = (peer.DNSName or peer.HostName or ""):gsub("%.$", "")
          if name ~= "" then
            table.insert(hosts, { name = name, hostname = (peer.TailscaleIPs or {})[1], tag = "tailscale" })
          end
        end
        if #hosts > before then table.insert(sources, "tailscale") end
      end
    end
  end
  table.sort(hosts, function(x, y) return x.name < y.name end)
  return hosts, sources
end

local terms = {}

function M.connect(name)
  local t = terms[name]
  if not t then
    local Terminal = require("toggleterm.terminal").Terminal
    t = Terminal:new({
      cmd = "ssh " .. (name:find("%s") and name or vim.fn.shellescape(name)),
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
  local hosts, sources = M.hosts()
  local items = vim.list_extend({}, hosts)
  table.insert(items, { name = "직접 입력...", manual = true })
  vim.ui.select(items, {
    prompt = "서버 접속 (ssh)" .. (#sources > 0 and ("  ─ " .. table.concat(sources, ", ")) or "  ─ 등록된 Host 없음"),
    format_item = function(e)
      if e.manual then return "✎ " .. e.name end
      local tail = (e.user and (e.user .. "@") or "") .. (e.hostname or "")
      return e.name .. (tail ~= "" and ("   " .. tail) or "") .. (e.tag and ("   [" .. e.tag .. "]") or "") .. (terms[e.name] and "   ● 열려 있음" or "")
    end,
  }, function(choice)
    if not choice then return end
    if choice.manual then
      vim.ui.input({ prompt = "접속 대상 (예: user@host 또는 -p 22 user@host): " }, function(input)
        if input and input ~= "" then M.connect(input) end
      end)
    else
      M.connect(choice.name)
    end
  end)
end

return M
