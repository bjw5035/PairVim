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
        claude:toggle()
      end

      local function toggle_codex()
        codex:toggle()
      end

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
