local KO_DESC = {
  ["Find File"] = "파일 찾기",
  ["New File"] = "새 파일",
  ["Projects"] = "프로젝트",
  ["Find Text"] = "텍스트 찾기",
  ["Recent Files"] = "최근 파일",
  ["Config"] = "설정",
  ["Restore Session"] = "세션 복원",
  ["Lazy Extras"] = "Lazy 추가 기능",
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

      for _, item in ipairs(opts.dashboard.preset.keys or {}) do
        if KO_DESC[item.desc] then
          item.desc = KO_DESC[item.desc]
        end
      end
    end,
  },
}
