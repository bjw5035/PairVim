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
      -- 시작 화면의 세로 위치: 처음 그릴 때 창 높이로 가운데를 한 번만 계산해 고정한다(아래 섹션 함수).
      -- Snacks 기본값(row = nil)은 다시 그릴 때마다 가운데를 새로 계산해서, 탐색기(Space e)를 열어 창 크기가 바뀌면
      -- 시작 화면이 아래로 밀려 내려갔다. (가로는 창이 좁아지면 가운데를 다시 잡는 것이 정상이다.)
      local DASH_HEIGHT = 22 -- 시작 화면 전체 줄 수(헤더 6 + 메뉴 10 + 빈 줄/시작 정보). 섹션을 바꾸면 이 값도 맞춘다.
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
          gap = 0, -- 메뉴 항목 사이 빈 줄 없음(시작 화면 높이를 줄여 낮은 터미널에서도 잘리지 않게)
          padding = 1,
          function(self)
            if not self._pairvim_row then
              self._pairvim_row = math.max(math.floor((self._size.height - DASH_HEIGHT) / 2), 0)
            end
            self.opts.row = self._pairvim_row
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
