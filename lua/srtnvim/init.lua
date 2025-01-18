local sub_read = require("srtnvim/get_subs")

local M = {}

local defaults = {
  min_pause = 100,
  max_duration = -1
}

local config = vim.tbl_deep_extend("keep", defaults, {})

local data = {}

function M.setup(user_opts)
  config = vim.tbl_deep_extend("force", defaults, user_opts or {})
  data = {
    pause_lines = sub_read.preproduce_pause_lines(config)
  }
end

local augroup = vim.api.nvim_create_augroup("SrtauGroup", { clear = true })

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufEnter" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, vim.api.nvim_buf_line_count(ev.buf), false)
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
