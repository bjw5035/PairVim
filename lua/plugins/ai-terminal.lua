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

      -- 이전 히스토리가 있으면 이어서, 없으면(첫 실행) 코드베이스 분석/가이드를 자동 요청
      local analyze_prompt = "이 디렉토리의 코드베이스를 분석해서 핵심 구조와 시작 가이드를 요약해줘"

      local claude = Terminal:new({
        cmd = "claude --continue || claude '" .. analyze_prompt .. "'",
        direction = "vertical",
        size = panel_size,
        close_on_exit = false,
        start_in_insert = true,
      })

      local codex = Terminal:new({
        cmd = "codex resume --last || codex '" .. analyze_prompt .. "'",
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
        wk.add({ { "<leader>a", group = "AI 도구" } })
      end

      vim.keymap.set({ "n", "t" }, "<F2>", pick_ai, { desc = "AI 도구 선택 (Claude/Codex)" })
      vim.keymap.set({ "n", "t" }, "<leader>aa", pick_ai, { desc = "AI 도구 선택 (Claude/Codex)" })
      vim.keymap.set({ "n", "t" }, "<leader>ac", toggle_claude, { desc = "Claude Code 패널 토글" })
      vim.keymap.set({ "n", "t" }, "<leader>ax", toggle_codex, { desc = "Codex 패널 토글" })

      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*",
        callback = function()
          vim.keymap.set("t", "<esc>", [[<C-\><C-n>]], { buffer = 0, desc = "터미널 노멀 모드로 빠져나가기" })
          vim.keymap.set("t", "<C-h>", [[<Cmd>wincmd h<CR>]], { buffer = 0, desc = "왼쪽 창으로 이동" })
          vim.keymap.set("t", "<C-j>", [[<Cmd>wincmd j<CR>]], { buffer = 0, desc = "아래 창으로 이동" })
          vim.keymap.set("t", "<C-k>", [[<Cmd>wincmd k<CR>]], { buffer = 0, desc = "위 창으로 이동" })
          vim.keymap.set("t", "<C-l>", [[<Cmd>wincmd l<CR>]], { buffer = 0, desc = "오른쪽 창으로 이동" })
        end,
      })
    end,
  },
}
