-- :Pair — PairVim 전용 관리 명령. 설정(git)과 플러그인(lazy)을 한 곳에서 다룬다.
--   :Pair update   설정을 git pull --ff-only 로 받고, 플러그인을 잠금 파일(lazy-lock.json)에 맞춘다
--   :Pair check    새 커밋이 있는지만 확인(받지 않음)
--   :Pair status   브랜치·뒤처진 커밋·로컬 수정 상태
--   :Pair log      최근 커밋
--   :Pair restore  플러그인을 잠금 파일에 맞춤(:Lazy restore)
--   :Pair plugins  플러그인 화면(:Lazy)    :Pair health  상태 점검
-- 시작 화면의 "PairVim 업데이트"(u)는 :Pair update 를 부른다. 시작할 때 새 커밋이 있는지 조용히 확인한다(네트워크가 안 되면 아무 말 없이 넘어감).
local M = {}

M.behind = nil -- 마지막 확인에서 뒤처진 커밋 수(모르면 nil)

local function cfg() return vim.fn.stdpath("config") end
local function is_repo() return vim.uv.fs_stat(cfg() .. "/.git") ~= nil end
local function notify(msg, level) vim.notify(msg, level or vim.log.levels.INFO, { title = "PairVim" }) end

-- 비동기 git. 비밀번호 입력을 기다리며 멈추지 않도록 터미널 프롬프트를 끄고, 시간 제한을 둔다.
local function git(args, cb, timeout)
  local out, err, done = {}, {}, false
  local id = vim.fn.jobstart(vim.list_extend({ "git", "-C", cfg() }, args), {
    stdout_buffered = true,
    stderr_buffered = true,
    env = { GIT_TERMINAL_PROMPT = "0", GIT_ASKPASS = "true" },
    on_stdout = function(_, d) out = d end,
    on_stderr = function(_, d) err = d end,
    on_exit = function(_, code)
      done = true
      vim.schedule(function() cb(code, vim.trim(table.concat(out, "\n")), vim.trim(table.concat(err, "\n"))) end)
    end,
  })
  if id <= 0 then
    vim.schedule(function() cb(-1, "", "git 을 실행하지 못했습니다") end)
    return
  end
  vim.defer_fn(function()
    if not done then pcall(vim.fn.jobstop, id) end
  end, timeout or 20000)
end

-- 시작 화면 항목(Snacks 대시보드). 그릴 때마다 현재 상태로 만든다: 새 커밋이 있으면 desc 에 개수가 붙는다.
function M.dash_item()
  local n = M.behind
  return {
    icon = "󰚰 ",
    key = "u",
    desc = (n and n > 0) and ("PairVim 업데이트  ● 새 커밋 " .. n .. "개") or "PairVim 업데이트",
    action = ":Pair update",
  }
end

-- 시작 화면 다시 그리기(섹션을 다시 계산할 뿐, 시작 화면을 닫았다 열지 않는다)
local function refresh_dash()
  local ok, snacks = pcall(function() return require("snacks") end)
  if ok and snacks.dashboard and snacks.dashboard.update then pcall(snacks.dashboard.update) end
end

-- 새 커밋 확인(받지 않음). silent=true 면 실패해도 아무 말 하지 않는다.
function M.check(silent, cb)
  if not is_repo() then
    if not silent then notify("~/.config/nvim 이 git 저장소가 아니라 확인할 수 없습니다.", vim.log.levels.WARN) end
    return
  end
  git({ "fetch", "--quiet" }, function(code, _, err)
    if code ~= 0 then
      if not silent then notify("원격을 확인하지 못했습니다(네트워크/권한): " .. (err ~= "" and err or "알 수 없음"), vim.log.levels.WARN) end
      return
    end
    git({ "rev-list", "--count", "HEAD..@{u}" }, function(c2, out)
      if c2 ~= 0 then return end
      M.behind = tonumber(out) or 0
      refresh_dash()
      if M.behind > 0 then
        if not silent then notify(("새 커밋 %d개가 있습니다. 시작 화면의 u 또는 :Pair update 로 받으세요."):format(M.behind)) end
        if silent and not M._told then
          M._told = true
          notify(("PairVim 업데이트 %d개가 있습니다. (시작 화면 u 또는 :Pair update)"):format(M.behind))
        end
      elseif not silent then
        notify("이미 최신입니다.")
      end
      if cb then cb(M.behind) end
    end)
  end)
end

local function finish()
  local ok = pcall(vim.cmd, "Lazy! restore")
  if not ok then notify("플러그인 맞추기(:Lazy restore)에 실패했습니다. :Pair plugins 에서 확인하세요.", vim.log.levels.WARN) end
  M.behind = 0
  refresh_dash()
  local ans = vim.fn.confirm("업데이트를 적용하려면 nvim 을 다시 시작해야 합니다.", "&Quit 지금 종료\n&Later 나중에", 2)
  if ans == 1 then vim.cmd("confirm qall") end
end

function M.update()
  if not is_repo() then
    notify("~/.config/nvim 이 git 저장소가 아니라 업데이트할 수 없습니다. (install.sh 로 설치한 경우에만 지원)", vim.log.levels.ERROR)
    return
  end
  git({ "status", "--porcelain" }, function(code, out)
    if code ~= 0 then notify("git 상태를 읽지 못했습니다.", vim.log.levels.ERROR) return end
    local files = vim.tbl_filter(function(l) return l ~= "" end, vim.split(out, "\n"))
    local function proceed()
      notify("원격에서 받는 중...")
      git({ "fetch", "--quiet" }, function(c1, _, e1)
        if c1 ~= 0 then notify("원격을 받지 못했습니다(네트워크/권한): " .. e1, vim.log.levels.ERROR) return end
        git({ "log", "--oneline", "--no-decorate", "HEAD..@{u}" }, function(_, log)
          if log == "" then
            notify("이미 최신입니다. 플러그인만 잠금 파일에 맞춥니다.")
            finish()
            return
          end
          git({ "pull", "--ff-only", "--quiet" }, function(c3, _, e3)
            if c3 ~= 0 then
              notify("받지 못했습니다(--ff-only): " .. (e3 ~= "" and e3 or "로컬 커밋이 있어 갈라졌을 수 있습니다"), vim.log.levels.ERROR)
              return
            end
            local lines = vim.split(log, "\n")
            local shown = vim.list_slice(lines, 1, 8)
            notify(("%d개 반영:\n%s%s"):format(#lines, table.concat(shown, "\n"), #lines > 8 and "\n…" or ""))
            finish()
          end)
        end)
      end)
    end
    if #files == 0 then return proceed() end
    local only_lock = true
    for _, l in ipairs(files) do
      if not l:find("lazy%-lock%.json$") then only_lock = false end
    end
    if only_lock then
      local ans = vim.fn.confirm("lazy-lock.json 이 이 PC 에서 바뀌었습니다.\n플러그인 버전은 저장소 기준이라 되돌리고 업데이트할까요?", "&Yes 되돌리고 진행\n&No 취소", 2)
      if ans ~= 1 then notify("취소했습니다.") return end
      git({ "checkout", "--", "lazy-lock.json" }, function(cc, _, ee)
        if cc ~= 0 then notify("되돌리지 못했습니다: " .. ee, vim.log.levels.ERROR) return end
        proceed()
      end)
    else
      local shown = vim.list_slice(files, 1, 6)
      notify("이 PC 에서 수정한 파일이 있어 업데이트를 중단했습니다:\n" .. table.concat(shown, "\n") .. (#files > 6 and "\n…" or "") .. "\n(커밋하거나 되돌린 뒤 다시 시도하세요)", vim.log.levels.WARN)
    end
  end)
end

function M.status()
  if not is_repo() then notify("git 저장소가 아닙니다.", vim.log.levels.WARN) return end
  git({ "status", "-sb" }, function(_, out)
    git({ "log", "-1", "--format=%h %s (%cr)" }, function(_, last)
      notify("설정 위치: " .. cfg() .. "\n" .. out .. "\n마지막 커밋: " .. last)
    end)
  end)
end

function M.log()
  if not is_repo() then notify("git 저장소가 아닙니다.", vim.log.levels.WARN) return end
  git({ "log", "-12", "--oneline", "--no-decorate" }, function(_, out) notify("최근 커밋:\n" .. out) end)
end

local subs = {
  update = M.update, check = function() M.check(false) end, status = M.status, log = M.log,
  restore = function() vim.cmd("Lazy! restore") end,
  plugins = function() vim.cmd("Lazy") end,
  health = function() vim.cmd("checkhealth lazy") end,
}

function M.setup()
  vim.api.nvim_create_user_command("Pair", function(o)
    local f = subs[o.args ~= "" and o.args or "status"]
    if f then f() else notify("알 수 없는 하위 명령: " .. o.args .. "  (update, check, status, log, restore, plugins, health)", vim.log.levels.WARN) end
  end, {
    nargs = "?",
    complete = function() local r = vim.tbl_keys(subs); table.sort(r); return r end,
    desc = "PairVim 관리 (update/check/status/log/restore/plugins/health)",
  })
  vim.api.nvim_create_user_command("PairUpdate", M.update, { desc = "PairVim 업데이트" })
  -- 시작 후 새 커밋이 있는지 조용히 확인
  if not vim.g.pairvim_no_update_check then
    local delay = tonumber(vim.env.PAIRVIM_CHECK_DELAY_MS) or 2500 -- (시험에서 시작 직후 경쟁 상태를 만들 때만 환경변수로 바꾼다)
    vim.defer_fn(function() M.check(true) end, delay)
  end
end

return M
