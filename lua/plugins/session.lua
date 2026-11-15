-- 세션 저장/복원: 닫을 때 이 폴더의 상태(창 배치·열린 파일·창별 탭)를 저장하고, 시작 화면의 s(세션 복원)로 불러온다.
-- 시작할 때 자동으로 불러오지는 않는다(기본). 자동 복원은 vim.g.pairvim_auto_restore = true 로 켠다.
-- 파일을 인자로 주면(nvim a.tf) 자동 복원이 켜져 있어도 복원하지 않는다.
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
          -- 기본은 자동 복원 안 함(시작 화면이 갑자기 파일 화면으로 바뀌며 마지막 위치로 스크롤되는 것을 막는다).
          -- 이어서 작업하려면 시작 화면의 s(세션 복원). 예전처럼 자동 복원하려면 init 에서 vim.g.pairvim_auto_restore = true
          if not vim.g.pairvim_auto_restore then return end
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
