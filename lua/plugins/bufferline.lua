-- 위쪽 전역 탭줄(bufferline)은 쓰지 않는다. 대신 lua/config/pane-tabs.lua 가 창마다 자기 탭을 보여 준다.
return {
  { "akinsho/bufferline.nvim", enabled = false },
}
