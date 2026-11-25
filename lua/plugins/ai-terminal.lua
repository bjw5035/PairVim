local function panel_size()
  return math.floor(vim.o.columns * 0.35)
end

return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    opts = {
      size = panel_size,
      direction = "vertical",
      persist_size = true,
      close_on_exit = false,
      start_in_insert = true,
      shade_terminals = false,
    },
    config = function(_, opts)
      require("toggleterm").setup(opts)

      -- npm 전역 설치 경로가 PATH에 없는 새 환경에서도 codex/claude를 바로 찾도록 보정
      local npm_prefix = vim.fn.expand("~/.npm-global")
      local npm_bin = npm_prefix .. "/bin"
      if not string.find(vim.env.PATH or "", npm_bin, 1, true) then
        vim.env.PATH = npm_bin .. ":" .. (vim.env.PATH or "")
      end

      -- 새 머신에서 이 설정을 받아 nvim을 처음 켰을 때, CLI가 없으면 자동으로 설치
      local function ensure_cli(bin, install_cmd)
        if vim.fn.executable(bin) == 1 then
          return
        end
        if vim.fn.executable("npm") ~= 1 then
          vim.notify(bin .. " CLI 자동 설치를 건너뜁니다: npm이 없습니다(node/npm 설치 후 다시 열어주세요)", vim.log.levels.WARN)
          return
        end
        vim.notify(bin .. " CLI 설치 중... (" .. table.concat(install_cmd, " ") .. ")", vim.log.levels.INFO)
        vim.fn.jobstart(install_cmd, {
          on_exit = function(_, code)
            vim.schedule(function()
              if code == 0 then
                vim.notify(bin .. " CLI 설치 완료", vim.log.levels.INFO)
              else
                vim.notify(
                  bin .. " CLI 자동 설치 실패 (code " .. code .. ") - 수동 설치 필요: " .. table.concat(install_cmd, " "),
                  vim.log.levels.WARN
                )
              end
            end)
          end,
        })
      end

      -- 전역 npm 설정(npm config)은 바꾸지 않고, 설치 명령에만 --prefix 를 지정한다
      ensure_cli("codex", { "npm", "install", "-g", "--prefix", npm_prefix, "@openai/codex" })
      ensure_cli("claude", { "npm", "install", "-g", "--prefix", npm_prefix, "@anthropic-ai/claude-code" })

      local Terminal = require("toggleterm.terminal").Terminal

      -- 이전 히스토리가 있으면 이어서, 없으면(첫 실행) 코드베이스 분석/가이드를 자동 요청
      -- (git 저장소가 아닌 곳, 예를 들어 홈 폴더에서는 분석 요청을 보내지 않고 그냥 연다)
      local analyze_prompt = "이 디렉토리의 코드베이스를 분석해서 핵심 구조와 시작 가이드를 요약해줘"
      local function fresh_cmd(bin)
        return "{ git rev-parse --is-inside-work-tree >/dev/null 2>&1 && " .. bin .. " '" .. analyze_prompt .. "'; } || " .. bin
      end

      local claude = Terminal:new({
        cmd = "claude --continue || " .. fresh_cmd("claude"),
        direction = "vertical",
        size = panel_size,
        close_on_exit = false,
        start_in_insert = true,
      })

      local codex = Terminal:new({
        cmd = "codex resume --last || " .. fresh_cmd("codex"),
        direction = "vertical",
        size = panel_size,
        close_on_exit = false,
        start_in_insert = true,
      })

      -- 파일 없이 켠 시작 화면은 화면 전체를 덮는 플로팅 창이라, 그 위에서 패널을 열면 패널이 가려져 "안 열린다"로 보인다.
      -- 패널을 열기 전에 시작 화면을 일반 창 안으로 옮긴다(Space \ 로 닫은 뒤 그리는 방식과 같다).
      local function dock_dashboard()
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

      -- 탐색기(Explorer)에 포커스가 있으면 현재 창이 플로팅이라, toggleterm 이 세로 분할을 못 열고
      -- "Invalid terminal direction" 오류를 낸다. 패널을 열기 전에 포커스를 일반 창(파일·시작 화면)으로 옮긴다.
      local function focus_main()
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

      local function toggle_claude()
        dock_dashboard()
        focus_main()
        if codex:is_open() then
          codex:close()
        end
        claude:toggle()
      end

      local function toggle_codex()
        dock_dashboard()
        focus_main()
        if claude:is_open() then
          claude:close()
        end
        codex:toggle()
      end

      local function pick_ai()
        vim.ui.select({ "Claude Code", "Codex" }, { prompt = "AI 도구 선택" }, function(choice)
          if choice == "Claude Code" then
            toggle_claude()
          elseif choice == "Codex" then
            toggle_codex()
          end
        end)
      end

      local ok_wk, wk = pcall(require, "which-key")
      if ok_wk then
        wk.add({ { "<leader>a", group = "AI 도구", icon = { icon = "★", color = "yellow" } } })
      end

      -- 터미널 모드에서는 <leader>(스페이스)를 매핑하지 않는다: 스페이스를 칠 때마다 다음 키를 기다려
      -- 입력이 지연되고, " ac" 같은 글자를 치면 패널이 토글된다. 터미널 안에서는 F2만 쓴다.
      vim.keymap.set({ "n", "t" }, "<F2>", pick_ai, { desc = "AI 도구 선택 (Claude/Codex)" })
      -- AI 패널 안(터미널 입력 모드)에서도 한 번에 닫는다. 열려 있는 쪽(Claude/Codex)만 닫고, 다시 열 때는 F2 또는 Space a c/x.
      local function close_ai()
        if claude:is_open() then claude:close() end
        if codex:is_open() then codex:close() end
      end
      vim.keymap.set({ "n", "t" }, "<F6>", close_ai, { desc = "AI 패널 닫기 (Claude/Codex)" })
      vim.keymap.set("n", "<leader>aa", pick_ai, { desc = "AI 도구 선택 (Claude/Codex)" })
      vim.keymap.set("n", "<leader>ac", toggle_claude, { desc = "Claude Code 패널 토글" })
      vim.keymap.set("n", "<leader>ax", toggle_codex, { desc = "Codex 패널 토글" })

      -- VS Code처럼 "지금 보는 파일"을 AI가 자동으로 알지는 못하지만, claude/codex CLI 모두
      -- "@경로" 를 입력창에 쓰면 그 파일을 읽어서 컨텍스트에 넣는 기능이 있다.
      -- 방금까지 보고 있던(=실제 편집 중인) 파일을 기억해 두고, 패널로 포커스를 옮기는 순간
      -- 자동으로 "@그파일 "을 채워준다. 엔터는 치지 않아 이어서 질문을 타이핑할 수 있다.
      -- 같은 파일을 그 패널에 이미 전달했으면 다시 보내지 않는다 — 안 그러면 패널과 편집 창을
      -- 왔다갔다 할 때마다, 또는 파일을 여러 개 스쳐 지나갈 때마다 입력창에 "@a @b @c ..."가
      -- 계속 쌓여서 질문하려던 내용 앞에 엉뚱한 파일들이 끼어들게 된다.
      local last_file = nil
      local sent_for = {}

      local function track_file(buf)
        if vim.bo[buf].buftype ~= "" then return end
        local name = vim.api.nvim_buf_get_name(buf)
        if name == "" then return end
        local ft = vim.bo[buf].filetype
        if ft:find("^snacks_") or ft == "help" or ft == "qf" then return end
        last_file = name
      end
      -- BufEnter만으로 충분하다(창을 옮기면 항상 같이 온다) — BufWinEnter까지 같이 걸면
      -- 거의 매번 둘 다 불려서 같은 파일을 두 번 기록하는 중복만 생긴다.
      vim.api.nvim_create_autocmd("BufEnter", {
        callback = function(a) track_file(a.buf) end,
      })

      local function attach_file(term, name)
        name = name or last_file
        if not name or sent_for[term] == name then return end
        if not term.job_id or term.job_id <= 0 then return end
        local rel = vim.fn.fnamemodify(name, ":~:.")
        -- 앞에 공백을 하나 둬서, 패널 입력창에 이미 커서/타이핑된 내용이 있어도 그 글자에
        -- "@file.lua"가 바로 이어붙지 않게 한다(빈 입력창이면 무해한 선행 공백만 남는다).
        vim.fn.chansend(term.job_id, " @" .. rel .. " ")
        sent_for[term] = name
      end

      -- 수동으로 즉시 전달하고 싶을 때(같은 파일을 다시 언급하고 싶을 때 등)를 위한 단축키는 남겨둔다.
      local function send_file_to_ai()
        local name = vim.api.nvim_buf_get_name(0)
        if name == "" or vim.bo.buftype ~= "" then
          vim.notify("파일이 아닌 창입니다.", vim.log.levels.WARN, { title = "PairVim" })
          return
        end
        local term = claude:is_open() and claude or (codex:is_open() and codex or nil)
        if not term then
          vim.notify("AI 패널이 열려 있지 않습니다. F2 또는 Space a c/x 로 먼저 여세요.", vim.log.levels.WARN, { title = "PairVim" })
          return
        end
        sent_for[term] = nil -- 수동 호출은 같은 파일이어도 강제로 다시 보낸다
        attach_file(term, name)
        term:focus()
        vim.cmd("startinsert")
      end
      vim.keymap.set("n", "<leader>af", send_file_to_ai, { desc = "현재 파일을 AI 패널에 전달 (@파일)" })

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          -- Esc 는 Claude Code(중단)·vi 가 쓰므로 가로채지 않는다. 노멀 모드로 나갈 때는 F8 (또는 기본 Ctrl-\ Ctrl-n)
          vim.keymap.set("t", "<F8>", [[<C-\><C-n>]], { buffer = 0, desc = "터미널 노멀 모드로 빠져나가기" })
          vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], { buffer = 0, desc = "왼쪽 창으로 이동" })
          vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], { buffer = 0, desc = "아래 창으로 이동" })
          vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], { buffer = 0, desc = "위 창으로 이동" })
          vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], { buffer = 0, desc = "오른쪽 창으로 이동" })
          -- 패널을 처음 열 때는(재진입이 아니라 새로 뜰 때) 아래 BufEnter/WinEnter 쪽이 아니라
          -- 여기서 한 번 붙여준다 — 처음 열릴 때는 버퍼가 term:// 이름을 갖기 전에 창 포커스가
          -- 먼저 옮겨져서 BufEnter/WinEnter(term://*) 쪽이 못 잡는다.
          -- job_id는 termopen()이 "반환"할 때 채워지는데 TermOpen은 그 호출 안에서(반환 전에)
          -- 터지므로, 지금 당장 읽으면 아직 nil이라 chansend가 "Invalid argument"로 죽는다.
          -- 한 틱 뒤로 미뤄서 termopen()이 다 끝난 뒤에 읽는다.
          local buf = vim.api.nvim_get_current_buf()
          vim.schedule(function()
            if buf == claude.bufnr then
              attach_file(claude)
            elseif buf == codex.bufnr then
              attach_file(codex)
            end
          end)
        end,
      })

      -- 다른 창으로 갔다가 터미널 창으로 돌아오면 노멀 모드로 남아 키가 Claude/Codex에 전달되지 않는다.
      -- 터미널 버퍼에 들어올 때마다 입력 모드로 되돌린다. (Esc로 일부러 노멀 모드에 간 경우는 창 이동 전까지 유지)
      vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
        pattern = "term://*",
        callback = function()
          if vim.bo.buftype == "terminal" then
            -- 이벤트 안에서 바로 호출하면 창 이동 명령이 끝나면서 무시되므로 다음 틱에 실행한다
            vim.schedule(function()
              if vim.bo.buftype ~= "terminal" then return end
              local buf = vim.api.nvim_get_current_buf()
              if buf == claude.bufnr then
                attach_file(claude)
              elseif buf == codex.bufnr then
                attach_file(codex)
              end
              if vim.fn.mode() == "n" then
                vim.cmd("startinsert")
              end
            end)
          end
        end,
      })
    end,
  },
}
