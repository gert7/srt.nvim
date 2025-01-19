local sub_read = require("srtnvim/get_subs")

local M = {}

local defaults = {
  enabled = true,
  min_pause = 100,
  max_duration = -1,
  tackle = ".",
  tackle_middle = " "
}

local config = vim.tbl_deep_extend("keep", defaults, {})

local data = {}

function M.setup(user_opts)
  config = vim.tbl_deep_extend("force", defaults, user_opts or {})
  data = {
    pause_lines = sub_read.preproduce_pause_lines(config)
  }
end

vim.api.nvim_create_user_command("SrtToggle", function ()
  config.enabled = not config.enabled
  if config.enabled then
    print("Srtnvim is now enabled")
  else
    print("Srtnvim is now disabled")
  end
  for k, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_option(buf, "filetype") == "srt" then
      local lines = vim.api.nvim_buf_get_lines(buf, 0, vim.api.nvim_buf_line_count(buf), false)
      sub_read.get_subs(buf, lines, config, data)
    end
  end
end, { desc = "Toggle Srtnvim on or off" })

local augroup = vim.api.nvim_create_augroup("SrtauGroup", { clear = true })

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufEnter" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, vim.api.nvim_buf_line_count(ev.buf), false)
    -- print(vim.inspect(config))
    sub_read.get_subs(ev.buf, lines, config, data)
  end
})

-- vim.api.nvim_create_autocmd({ "BufEnter" }, {
--   group = augroup,
--   pattern = { "*.srt"},
--   callback = function(ev)
--     print(string.format('event fired: %s', vim.inspect(ev)))
--     print(string.format('buffer number %d', ev.buf))
--   end
-- })

return M
