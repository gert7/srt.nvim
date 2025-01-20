local get_subs = require("srtnvim.get_subs")

local function find_subtitle(subs, line)
  print("Looking for line " .. line)
  local low = 1
  local high = #subs
  while low <= high do
    local mid = math.floor((low + high) / 2)
    local sub = subs[mid]
    local start = sub.line_pos
    local finish = start + 2 + #sub.line_lengths
    if line < start then
      high = mid - 1
    elseif line > finish then
      low = mid + 1
    else
      return mid
    end
  end
end

-- add a command to merge the subtitle down
vim.api.nvim_create_user_command("SrtMerge", function ()
  -- first we get what line in what buffer we are
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  -- make sure we're in an srt file
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if not subs then
    print("Error: " .. err[1] .. " on line " .. err[2])
    return
  end
  local sub_i = find_subtitle(subs, line)
  local sub = subs[sub_i]
  print(sub)
  print(sub.length_ms)
end, { desc = "Merge the subtitle down" })
