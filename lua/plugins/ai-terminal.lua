return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    opts = {
      size = 100,
      direction = "vertical",
      persist_size = true,
      close_on_exit = false,
      start_in_insert = true,
      shade_terminals = false,
    },
    config = function(_, opts)
      require("toggleterm").setup(opts)

      -- npm 전역 설치 경로가 PATH에 없는 새 환경에서도 codex/claude를 바로 찾도록 보정
      local npm_bin = vim.fn.expand("~/.npm-global/bin")
      if not string.find(vim.env.PATH or "", npm_bin, 1, true) then
        vim.env.PATH = npm_bin .. ":" .. (vim.env.PATH or "")
      end

      -- 새 머신에서 이 설정을 받아 nvim을 처음 켰을 때, CLI가 없으면 자동으로 설치
      local function ensure_cli(bin, install_cmd)
        if vim.fn.executable(bin) == 1 then
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

      vim.fn.system("npm config set prefix " .. npm_bin:gsub("/bin$", ""))
      ensure_cli("codex", { "npm", "install", "-g", "@openai/codex" })
      ensure_cli("claude", { "npm", "install", "-g", "@anthropic-ai/claude-code" })

      local Terminal = require("toggleterm.terminal").Terminal

      local claude = Terminal:new({
        cmd = "claude",
        direction = "vertical",
        size = 100,
        close_on_exit = false,
        start_in_insert = true,
      })

      local codex = Terminal:new({
        cmd = "codex",
        direction = "vertical",
        size = 100,
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

      vim.keymap.set({ "n", "t" }, "<leader>aa", pick_ai, { desc = "Select AI tool (Claude/Codex)" })
      vim.keymap.set({ "n", "t" }, "<leader>ac", toggle_claude, { desc = "Toggle Claude Code" })
      vim.keymap.set({ "n", "t" }, "<leader>ax", toggle_codex, { desc = "Toggle Codex" })

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          local term_opts = { buffer = 0 }
          vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], term_opts)
          vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], term_opts)
          vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], term_opts)
          vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], term_opts)
          vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], term_opts)
        end,
      })
    end,
  },
}
