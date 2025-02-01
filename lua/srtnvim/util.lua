local vim = vim

local M = {}

function M.write_buffer_to_file(buffer_number, filename)
  local lines = vim.api.nvim_buf_get_lines(buffer_number, 0, -1, false)

  local file = io.open(filename, "w")
  if file then
    for _, line in ipairs(lines) do
      file:write(line .. "\n")
    end
    file:close()
    print("Wrote buffer to " .. filename)
  else
    print("Error opening file for writing: " .. filename)
  end
end

return M
