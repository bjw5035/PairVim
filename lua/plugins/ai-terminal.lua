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

      local function toggle_claude()
        if codex:is_open() then
          codex:close()
        end
        claude:toggle()
      end

      local function toggle_codex()
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
      vim.keymap.set("n", "<leader>aa", pick_ai, { desc = "AI 도구 선택 (Claude/Codex)" })
      vim.keymap.set("n", "<leader>ac", toggle_claude, { desc = "Claude Code 패널 토글" })
      vim.keymap.set("n", "<leader>ax", toggle_codex, { desc = "Codex 패널 토글" })

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          -- Esc 는 Claude Code(중단)·vi 가 쓰므로 가로채지 않는다. 노멀 모드로 나갈 때는 F4 (또는 기본 Ctrl-\ Ctrl-n)
          vim.keymap.set("t", "<F4>", [[<C-\><C-n>]], { buffer = 0, desc = "터미널 노멀 모드로 빠져나가기" })
          vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], { buffer = 0, desc = "왼쪽 창으로 이동" })
          vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], { buffer = 0, desc = "아래 창으로 이동" })
          vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], { buffer = 0, desc = "위 창으로 이동" })
          vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], { buffer = 0, desc = "오른쪽 창으로 이동" })
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
              if vim.bo.buftype == "terminal" and vim.fn.mode() == "n" then
                vim.cmd("startinsert")
              end
            end)
          end
        end,
      })
    end,
  },
}
