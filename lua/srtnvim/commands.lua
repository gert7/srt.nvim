local get_subs = require("srtnvim.get_subs")
local subtitle = require("srtnvim.subtitle")

local function find_subtitle(subs, line)
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
  local bm_start = vim.loop.hrtime()
  -- first we get what line in what buffer we are
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  -- make sure we're in an srt file
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err then
    print("Error: " .. err[1] .. " on line " .. err[2])
    return
  end
  local sub_i = find_subtitle(subs, line)

  if not sub_i then
    print("Not in a subtitle")
    return
  end

  if sub_i == #subs then
    print("Can't merge the last subtitle")
    return
  end

  for i = sub_i + 1, #subs do
    local sub = subs[i]
    vim.api.nvim_buf_set_lines(buf, sub.line_pos - 1, sub.line_pos, false, {tostring(i - 1)})
  end

  local sub = subs[sub_i]
  local next = subs[sub_i + 1]
  local del_from = next.line_pos - 2
  vim.api.nvim_buf_set_lines(buf, del_from, del_from + 3, false, {})

  local f_h, f_m, f_s, f_mi = subtitle.from_ms(sub.start_ms)
  local t_h, t_m, t_s, t_mi = subtitle.from_ms(next.end_ms)
  local dur_line = string.format("%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d", f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
  vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, {dur_line})

  local bm_total = vim.loop.hrtime() - bm_start
  print("Merge took " .. bm_total / 1000000 .. "ms")
end, { desc = "Merge the subtitle down" })
