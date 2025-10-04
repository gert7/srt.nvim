local vim = vim

local M = {}

---@param buffer_number integer
---@param filename string
function M.write_buffer_to_file(buffer_number, filename)
  local lines = vim.api.nvim_buf_get_lines(buffer_number, 0, -1, false)

  local file = io.open(filename, "w")
  if file then
    for _, line in ipairs(lines) do
      file:write(line .. "\n")
    end
    file:close()
    -- print("Wrote buffer to " .. filename)
  else
    print("Error opening file for writing: " .. filename)
  end
end

---@param inputstr string
---@param sep string
---@return string[]
function M.split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    table.insert(t, str)
  end
  return t
end

return M
