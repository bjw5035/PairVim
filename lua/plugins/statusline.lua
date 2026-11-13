-- 상태줄: AWS 프로필과 terraform 워크스페이스를 보여 준다. (git 브랜치는 LazyVim 기본에 있다)
local cache = { dir = nil, at = 0, val = "" }

local function tf_workspace()
  local ft = vim.bo.filetype
  if ft ~= "terraform" and ft ~= "hcl" and ft ~= "terraform-vars" then return "" end
  local dir = vim.fn.expand("%:p:h")
  local now = vim.uv.now()
  if cache.dir == dir and now - cache.at < 3000 then return cache.val end
  local val = ""
  local found = vim.fs.find(".terraform", { upward = true, path = dir, type = "directory" })[1]
  if found then
    local env = vim.fn.readfile(found .. "/environment")
    val = " " .. ((env and env[1] and env[1] ~= "") and env[1] or "default")
  end
  cache = { dir = dir, at = now, val = val }
  return val
end

local function aws_profile()
  local p = vim.env.AWS_PROFILE
  if p and p ~= "" then return "󰸏 " .. p end
  return ""
end

return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local nonempty = function(f) return function() return f() ~= "" end end
      table.insert(opts.sections.lualine_x, 1, { tf_workspace, cond = nonempty(tf_workspace), color = { fg = "#bb9af7" } })
      table.insert(opts.sections.lualine_x, 1, { aws_profile, cond = nonempty(aws_profile), color = { fg = "#ff9e64" } })
    end,
  },
}
