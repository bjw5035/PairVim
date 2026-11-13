-- 세션 복원: 인자 없이 nvim 을 켜면 이 폴더에서 마지막에 닫은 상태(창 배치·열린 파일·창별 탭)로 돌아온다.
-- 파일을 인자로 주면(nvim a.tf) 복원하지 않는다.
return {
  {
    "folke/persistence.nvim",
    event = "BufReadPre",
    opts = {},
    init = function()
      local group = vim.api.nvim_create_augroup("pairvim_session", { clear = true })

      -- 저장 직전: 창별 탭 목록(파일 경로)을 전역 변수에 담는다. 세션 파일의 globals 로 함께 저장된다.
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "PersistenceSavePre",
        callback = function()
          local ok, pt = pcall(require, "config.pane-tabs")
          if not ok then return end
          local data = {}
          for i, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local names = {}
            for _, b in ipairs(pt.list(w)) do
              local n = vim.api.nvim_buf_get_name(b)
              if n ~= "" then table.insert(names, n) end
            end
            data[i] = names
          end
          vim.g.PairvimTabs = vim.json.encode(data)
        end,
      })

      -- 복원 직후: 같은 순서의 창에 탭 목록을 되돌린다.
      vim.api.nvim_create_autocmd("SessionLoadPost", {
        group = group,
        callback = function()
          local raw = vim.g.PairvimTabs
          if type(raw) ~= "string" or raw == "" then return end
          local ok, data = pcall(vim.json.decode, raw)
          if not ok or type(data) ~= "table" then return end
          local pt = require("config.pane-tabs")
          for i, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            for _, name in ipairs(data[i] or {}) do
              if vim.uv.fs_stat(name) then
                pt.add(w, vim.fn.bufadd(name))
                vim.bo[vim.fn.bufadd(name)].buflisted = true
              end
            end
          end
        end,
      })

      -- 시작할 때 자동 복원
      vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        nested = true,
        callback = function()
          if vim.fn.argc() ~= 0 or vim.g.pairvim_no_restore then return end
          if vim.fn.line2byte("$") ~= -1 then return end -- 표준입력으로 들어온 내용이 있으면 복원 안 함
          vim.schedule(function()
            local ok, p = pcall(require, "persistence")
            if ok then p.load() end
          end)
        end,
      })
    end,
  },
}
