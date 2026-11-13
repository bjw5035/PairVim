-- 창별 탭(lua/config/pane-tabs.lua) 단위 시험. 플러그인 없이 돈다:
--   nvim --headless -u NONE -l tests/test_pane_tabs.lua
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. package.path
vim.o.hidden = true
local pt = require("config.pane-tabs")

local fails, total = 0, 0
local function check(name, cond)
  total = total + 1
  if cond then
    print("PASS  " .. name)
  else
    fails = fails + 1
    print("FAIL  " .. name)
  end
end
local function names(w)
  return vim.tbl_map(function(b) return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t") end, pt.list(w))
end
local function eq(a, b) return vim.deep_equal(a, b) end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
for _, n in ipairs({ "a.txt", "b.txt", "c.txt" }) do vim.fn.writefile({ n }, dir .. "/" .. n) end

vim.cmd("edit " .. dir .. "/a.txt")
local w1 = vim.api.nvim_get_current_win()
pt.add(w1, vim.api.nvim_get_current_buf())
vim.cmd("edit " .. dir .. "/b.txt"); pt.add(w1, vim.api.nvim_get_current_buf())
vim.cmd("edit " .. dir .. "/c.txt"); pt.add(w1, vim.api.nvim_get_current_buf())
check("탭 3개 등록", eq(names(w1), { "a.txt", "b.txt", "c.txt" }))

pt.add(w1, vim.api.nvim_get_current_buf())
check("같은 파일 중복 등록 안 함", #pt.list(w1) == 3)

pt.cycle(1)
check("cycle +1 은 처음으로 순환", vim.fn.expand("%:t") == "a.txt")
pt.cycle(-1)
check("cycle -1 은 끝으로 순환", vim.fn.expand("%:t") == "c.txt")

-- 분할: 새 창은 현재 파일 하나로 시작하고, 한쪽에서 닫아도 다른 쪽 탭은 그대로
vim.cmd("vsplit")
local w2 = vim.api.nvim_get_current_win()
pt.add(w2, vim.api.nvim_get_current_buf())
check("분할 창은 현재 파일 하나로 시작", eq(names(w2), { "c.txt" }))
pt.add(w2, vim.fn.bufnr(dir .. "/b.txt"))
pt.close(w2, vim.fn.bufnr(dir .. "/c.txt"))
check("한 창에서 닫으면 그 창 목록에서만 빠짐", eq(names(w2), { "b.txt" }))
check("다른 창엔 남아 있어 버퍼는 유지", eq(names(w1), { "a.txt", "b.txt", "c.txt" }) and vim.fn.bufexists(dir .. "/c.txt") == 1)

pt.close(w1, vim.fn.bufnr(dir .. "/c.txt"))
check("어느 창에도 없으면 버퍼 삭제", vim.fn.buflisted(dir .. "/c.txt") == 0)

-- 수정된 버퍼는 확인 없이 닫히지 않는다(confirm 을 취소로 대체)
vim.cmd("edit " .. dir .. "/b.txt")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
local old = vim.fn.confirm
vim.fn.confirm = function() return 3 end
pt.close(vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf())
vim.fn.confirm = old
check("수정 중이고 취소하면 닫히지 않음", vim.fn.buflisted(dir .. "/b.txt") == 1)

vim.fn.delete(dir, "rf")
print(("TOTAL %d, FAIL %d"):format(total, fails))
vim.cmd(fails == 0 and "qa!" or "cq!")
