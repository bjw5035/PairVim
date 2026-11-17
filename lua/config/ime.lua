-- WSL에서는 윈도우 쪽 IME(한/영) 상태를 nvim이 직접 못 바꾸기 때문에, 작은 윈도우용 도구(im-select.exe)를
-- 통해서 영문으로 강제 전환한다. nvim 시작할 때와 입력 모드에서 빠져나올 때(Insert -> Normal) 항상 영문으로.
-- (설치: terminal-setup.sh 가 %LOCALAPPDATA%\im-select\im-select.exe 에 받아 둔다)
local EN_US = "1033"

local function windows_localappdata()
  local out = vim.fn.system({ "cmd.exe", "/c", "echo %LOCALAPPDATA%" })
  out = out:gsub("[\r\n]+$", "")
  if out == "" then
    return nil
  end
  local ok, wsl_path = pcall(function()
    return vim.fn.system({ "wslpath", out }):gsub("[\r\n]+$", "")
  end)
  if not ok or wsl_path == "" then
    return nil
  end
  return wsl_path
end

local im_select_path -- nil = 아직 안 찾아봄, false = 없음, string = 경로
local function get_im_select()
  if im_select_path ~= nil then
    return im_select_path or nil
  end
  local appdata = windows_localappdata()
  local candidate = appdata and (appdata .. "/im-select/im-select.exe")
  if candidate and vim.fn.filereadable(candidate) == 1 then
    im_select_path = candidate
  else
    im_select_path = false
  end
  return im_select_path or nil
end

local function force_english()
  local path = get_im_select()
  if not path then
    return
  end
  vim.fn.jobstart({ path, EN_US }, { detach = true })
end

vim.api.nvim_create_autocmd({ "VimEnter", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("pairvim_ime_english", { clear = true }),
  callback = force_english,
})
