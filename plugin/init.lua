local sub_read = require("sub_read")

local augroup = vim.api.nvim_create_augroup("HelloWorldGroup", { clear = true })

vim.api.nvim_create_autocmd({ "InsertLeave", "TextChanged", "BufEnter" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, vim.api.nvim_buf_line_count(ev.buf), false)
    sub_read.get_subs(ev.buf, lines)
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
