local KO_DESC = {
  ["Find File"] = "파일 찾기",
  ["New File"] = "새 파일",
  ["Projects"] = "프로젝트",
  ["Find Text"] = "텍스트 찾기",
  ["Recent Files"] = "최근 파일",
  ["Config"] = "설정",
  ["Restore Session"] = "세션 복원",
  ["Lazy Extras"] = "확장 기능",
  ["Lazy"] = "플러그인 관리",
  ["Quit"] = "종료",
}

return {
  {
    "snacks.nvim",
    opts = function(_, opts)
      opts.dashboard = opts.dashboard or {}
      opts.dashboard.preset = opts.dashboard.preset or {}
      opts.dashboard.preset.header = [[
          ██████╗  █████╗  ██╗ ██████╗  ██╗   ██╗ ██╗ ███╗   ███╗
          ██╔══██╗ ██╔══██╗ ██║ ██╔══██╗ ██║   ██║ ██║ ████╗ ████║
          ██████╔╝ ███████║ ██║ ██████╔╝ ██║   ██║ ██║ ██╔████╔██║
          ██╔═══╝  ██╔══██║ ██║ ██╔══██╗ ╚██╗ ██╔╝ ██║ ██║╚██╔╝██║
          ██║      ██║  ██║ ██║ ██║  ██║  ╚████╔╝  ██║ ██║ ╚═╝ ██║
          ╚═╝      ╚═╝  ╚═╝ ╚═╝ ╚═╝  ╚═╝   ╚═══╝   ╚═╝ ╚═╝     ╚═╝
   ]]

      -- 시작 화면 키 목록에 "PairVim 업데이트"(u)를 종료(q) 앞에 끼워 넣는다. 그릴 때마다 목록을 새로 만들어서
      -- 새 커밋 개수가 바뀌면 시작 화면을 닫았다 열지 않고 다시 그리기만 하면 반영된다.
      opts.dashboard.sections = {
        { section = "header" },
        {
          gap = 1,
          padding = 1,
          function(self)
            local keys = vim.deepcopy(self.opts.preset.keys or {})
            local item = require("config.pair").dash_item()
            local pos = #keys + 1
            for i, k in ipairs(keys) do
              if k.key == "q" then
                pos = i
                break
              end
            end
            table.insert(keys, pos, item)
            return keys
          end,
        },
        { section = "startup" },
      }

      for _, item in ipairs(opts.dashboard.preset.keys or {}) do
        if KO_DESC[item.desc] then
          item.desc = KO_DESC[item.desc]
        end
      end
    end,
  },
}
