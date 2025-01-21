local get_subs = require("srtnvim.get_subs")
local subtitle = require("srtnvim.subtitle")

local M = {}

local config = {}

function M.set_config(cfg)
  config = cfg
end

local function sum_table(t, s, f)
  local sum = 0
  for i = s, f do
    sum = sum + t[i]
  end
  return sum
end

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

local function make_dur(h, m, s, mi)
  return string.format("%02d:%02d:%02d,%03d", h, m, s, mi)
end

local function make_dur_full(f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
  return string.format("%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d", f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
end

vim.api.nvim_create_user_command("SrtMerge", function ()
  local bm_start = vim.loop.hrtime()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
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
  local dur_line = make_dur_full(f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
  vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, {dur_line})

  local bm_total = vim.loop.hrtime() - bm_start
  print("Merge took " .. bm_total / 1000000 .. "ms")
end, { desc = "Merge the subtitle down" })

vim.api.nvim_create_user_command("SrtSplit", function (opts)
  local split_mode = config.split_mode
  if opts.args ~= "" then
    split_mode = opts.args
  end
  if split_mode ~= "length" and split_mode ~= "half" then
    print("Invalid split mode")
    return
  end
  local bm_start = vim.loop.hrtime()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
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

  local sub = subs[sub_i]

  local line_count = #sub.line_lengths
  if line_count == 0 then
    print("Can't split a subtitle with no lines")
    return
  end

  if line_count % 2 ~= 0 then
    print("Can't split a subtitle with an odd number of lines")
    return
  end

  for i = sub_i + 1, #subs do
    local sub = subs[i]
    vim.api.nvim_buf_set_lines(buf, sub.line_pos - 1, sub.line_pos, false, {tostring(i + 1)})
  end

  local split_point = sub.line_pos + 1 + line_count / 2

  local mp = 0
  if config.split_with_min_pause then
    mp = config.min_pause
  end

  local split_ms = 0

  if split_mode == "length" then
    local length_first = sum_table(sub.line_lengths, 1, line_count / 2)
    local length_second = sum_table(sub.line_lengths, line_count / 2 + 1, line_count)
    local p = length_first / (length_first + length_second)
    split_ms = sub.start_ms + sub.length_ms * p
  else
    split_ms = sub.start_ms + sub.length_ms / 2
  end

  local fe_h, fe_m, fe_s, fe_mi = subtitle.from_ms(split_ms - mp)
  local ss_h, ss_m, ss_s, ss_mi = subtitle.from_ms(split_ms + mp)
  local new_index = tostring(sub.index + 1)

  local first_start = lines[sub.line_pos + 1]:sub(1, 17)
  local last_end = lines[sub.line_pos + 1]:sub(13, 29)

  vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, {first_start .. make_dur(fe_h, fe_m, fe_s, fe_mi)})

  local new_header = {
    "",
    new_index,
    make_dur(ss_h, ss_m, ss_s, ss_mi) .. last_end
  }

  vim.api.nvim_buf_set_lines(buf, split_point, split_point, false, new_header)

  local bm_total = vim.loop.hrtime() - bm_start
  print("Split took " .. bm_total / 1000000 .. "ms") 
end, { desc = "Split the subtitle in two", nargs = "?", complete = function()
  return { "length", "half" }
end})

return M
