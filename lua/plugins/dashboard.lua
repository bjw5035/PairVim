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

      -- 시작 화면에 "PairVim 업데이트"(u) 항목을 끝(종료) 앞에 넣는다. 새 커밋이 있으면 개수가 붙는다.
      local keys = opts.dashboard.preset.keys
      if type(keys) == "table" and #keys > 0 then -- 기본 항목이 있을 때만 끼워 넣는다(없으면 기본 목록을 덮어쓰게 되므로)
        local pos = #keys
        for i, item in ipairs(keys) do
          if item.key == "q" then
            pos = i - 1
            break
          end
        end
        table.insert(keys, pos + 1, require("config.pair").dash_entry)
      end

      for _, item in ipairs(opts.dashboard.preset.keys or {}) do
        if KO_DESC[item.desc] then
          item.desc = KO_DESC[item.desc]
        end
      end
    end,
  },
}
