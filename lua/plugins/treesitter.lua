-- terraform/hcl 은 LazyVim 기본 목록에 없어서 .tf 가 정규식 문법(syntax)으로만 칠해졌다. 트리시터 파서를 설치하고 켠다.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "terraform", "hcl" })
    end,
    init = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("pairvim_ts_terraform", { clear = true }),
        pattern = { "terraform", "hcl", "terraform-vars" },
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
  },
}
