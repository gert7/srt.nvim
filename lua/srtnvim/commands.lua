local vim = vim
local get_subs = require("srtnvim.get_subs")
local subtitle = require("srtnvim.subtitle")

local M = {}

local get_config = function()
  return {}
end

function M.set_config(cfg)
  get_config = cfg
end


local function sum_array(t, s, f)
  local sum = 0
  for i = s, f do
    sum = sum + t[i]
  end
  return sum
end


local function make_dur(h, m, s, mi)
  return string.format("%02d:%02d:%02d,%03d", h, m, s, mi)
end

local function make_dur_ms(ms)
  local h, m, s, mi = subtitle.from_ms(ms)
  return make_dur(h, m, s, mi)
end

local function make_dur_full(f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
  return string.format("%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d", f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
end

local function make_dur_full_ms(f_ms, t_ms)
  local f_h, f_m, f_s, f_mi = subtitle.from_ms(f_ms)
  local t_h, t_m, t_s, t_mi = subtitle.from_ms(t_ms)
  return make_dur_full(f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
end

--- Add a number to all indices in a table of subtitles
-- @param lines table of lines from the .srt file
-- @param subs table of subtitles
-- @param start index of subtitle to start from
-- @param n number to add to the indices
-- @return modified table of lines to be placed into the buffer
local function add_to_indices(lines, subs, start, n)
  local offset = subs[start].line_pos - 1
  for i = start, #subs do
    local sub = subs[i]
    lines[sub.line_pos - offset] = tostring(sub.index + n)
  end
  return lines
end


--- Fix all indices in a file
local function fix_indices(lines, subs)
  local changed = false
  for i, v in ipairs(subs) do
    if v.index ~= i then
      lines[v.line_pos] = tostring(i)
      changed = true
    end
  end
  return lines, changed
end


local function sub_merge(buf, subs, sub_i)
  local ind_lines = vim.api.nvim_buf_get_lines(buf, subs[sub_i + 1].line_pos - 1, -1, false)
  local new_lines = add_to_indices(ind_lines, subs, sub_i + 1, -1)
  vim.api.nvim_buf_set_lines(buf, subs[sub_i + 1].line_pos - 1, -1, false, new_lines)

  local sub = subs[sub_i]
  local next = subs[sub_i + 1]
  local del_from = next.line_pos - 2
  vim.api.nvim_buf_set_lines(buf, del_from, del_from + 3, false, {})

  local dur_line = make_dur_full_ms(sub.start_ms, next.end_ms)
  vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, { dur_line })
end


vim.api.nvim_create_user_command("SrtMerge", function(args)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err then
    get_subs.print_err(err)
    return
  end
  local sub_first = get_subs.find_subtitle(subs, args.line1)
  if not sub_first then
    print("Not in a subtitle")
    return
  end
  if sub_first == #subs then
    print("Can't merge the last subtitle")
    return
  end

  local sub_last = get_subs.find_subtitle(subs, args.line2)
  if sub_last > sub_first then
    sub_last = sub_last - 1
  end

  for _ = sub_first, sub_last do
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    subs, err = get_subs.parse(lines)
    if err then
      print("Unexpected error on line " .. err[2])
      return
    end
    sub_merge(buf, subs, sub_first)
  end
end, { desc = "Merge the subtitle down", range = true })


vim.api.nvim_create_user_command("SrtSplit", function(opts)
  local config = get_config()
  local split_mode = config.split_mode
  if opts.args ~= "" then
    split_mode = opts.args
  end
  if split_mode ~= "length" and split_mode ~= "half" then
    print("Invalid split mode")
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, line)

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

  local ind_lines = vim.api.nvim_buf_get_lines(buf, subs[sub_i + 1].line_pos - 1, -1, false)
  local new_lines = add_to_indices(ind_lines, subs, sub_i + 1, 1)
  vim.api.nvim_buf_set_lines(buf, subs[sub_i + 1].line_pos - 1, -1, false, new_lines)

  local split_point = sub.line_pos + 1 + line_count / 2

  local mp = 0
  if config.split_with_min_pause then
    mp = config.min_pause
  end

  local split_ms = 0

  if split_mode == "length" then
    local length_first = sum_array(sub.line_lengths, 1, line_count / 2)
    local length_second = sum_array(sub.line_lengths, line_count / 2 + 1, line_count)
    local p = length_first / (length_first + length_second)
    split_ms = sub.start_ms + sub.length_ms * p
  else -- split_mode == "half"
    split_ms = sub.start_ms + sub.length_ms / 2
  end

  local first_end = make_dur_ms(split_ms - mp)
  local last_start = make_dur_ms(split_ms + mp)
  local new_index = tostring(sub.index + 1)

  local first_start = lines[sub.line_pos + 1]:sub(1, 17)
  local last_end = lines[sub.line_pos + 1]:sub(13, 29)

  vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false,
    { first_start .. first_end })

  local new_header = {
    "",
    new_index,
    last_start .. last_end
  }

  vim.api.nvim_buf_set_lines(buf, split_point, split_point, false, new_header)
end, {
  desc = "Split the subtitle in two",
  nargs = "?",
  complete = function()
    return { "length", "half" }
  end
})


function M.fix_indices_buf(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err then
    return false, err
  end
  local new_lines, changed = fix_indices(lines, subs)
  if changed then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
  end
  return true, nil
end


vim.api.nvim_create_user_command("SrtFixIndex", function()
  local buf = vim.api.nvim_get_current_buf()
  local _, err = M.fix_indices_buf(buf)
  if err then
    get_subs.print_err(err)
  end
end, { desc = "Fix the indices of the subtitles" })


local function sub_sort(buf, lines, subs)
  table.sort(subs, function(a, b)
    return a.start_ms < b.start_ms
  end)

  local new_lines = {}
  local index = 1
  for _, sub in ipairs(subs) do
    local start_line = sub.line_pos
    table.insert(new_lines, tostring(index))
    for i = start_line + 1, start_line + 1 + #sub.line_lengths do
      table.insert(new_lines, lines[i])
    end
    table.insert(new_lines, "")
    index = index + 1
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
end


vim.api.nvim_create_user_command("SrtSort", function()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err then
    get_subs.print_err(err)
    return
  end

  sub_sort(buf, lines, subs)
end, { desc = "Sort the subtitles by starting times" })


local function fix_timing(buf, lines, subs, i, config)
  local sub = subs[i]
  local next = subs[i + 1]
  if sub.start_ms > sub.end_ms then
    return false, "Subtitle " .. sub.index .. " has a negative duration"
  elseif sub.end_ms > next.start_ms or
      (config.fix_infringing_min_pause and sub.end_ms > next.start_ms - config.min_pause) then
    local mp = 0
    if config.fix_with_min_pause then
      mp = config.min_pause
    end
    local new_end = next.start_ms - mp

    if new_end - sub.start_ms >= config.min_duration then
      local first_start = lines[sub.line_pos + 1]:sub(1, 17)
      -- local fe_h, fe_m, fe_s, fe_mi = subtitle.from_ms(new_end)
      vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false,
        { first_start .. make_dur_ms(new_end) })
    else
      return false, "Can't shrink subtitle " .. sub.index .. ", would break min_duration"
    end
    return true, nil
  else
    return false, nil
  end
end


vim.api.nvim_create_user_command("SrtFixTiming", function()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, line)

  if sub_i ~= #subs then
    local fix, error = fix_timing(buf, lines, subs, sub_i, get_config())
    if fix then
      print("Fixed timing for subtitle " .. sub_i)
    elseif error then
      print(error)
    else
      print("Nothing to fix for subtitle " .. sub_i)
    end
  end
end, { desc = "Fix timing for the current subtitle" })


vim.api.nvim_create_user_command("SrtFixTimingAll", function()
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err then
    get_subs.print_err(err)
    return
  end

  local count = 0
  for i = 1, #subs - 1 do
    local fix, error = fix_timing(buf, lines, subs, i, get_config())
    if fix then
      count = count + 1
    elseif error then
      print(error)
    end
  end
  if count > 0 then
    print("Fixed timings for " .. count .. " subtitles")
  else
    print("No timings to fix")
  end
end, { desc = "Fix timing for all subtitles" })

--- Parse a timing input
-- Either in milliseconds
-- Or at least some partial form of hh:mm:ss,mss
-- @param input string to parse
local function parse_time(string)
  local mul = 1
  if string:sub(1, 1) == "-" then
    mul = -1
    string = string:sub(2)
  elseif string:sub(1, 1) == "+" then
    string = string:sub(2)
  end

  local ms = tonumber(string)
  if ms then return ms * mul end

  local h, m, s, mi = string:match("(%d+):(%d+):(%d+),(%d+)")
  if mi then
    return subtitle.to_ms(h, m, s, mi) * mul
  end
  m, s, mi = string:match("(%d+):(%d+),(%d+)")
  if mi then
    return subtitle.to_ms(0, m, s, mi) * mul
  end
  s, mi = string:match("(%d+),(%d+)")
  if mi then
    return subtitle.to_ms(0, 0, s, mi) * mul
  end

  h, m, s = string:match("(%d+):(%d+):(%d+)")
  if s then
    return subtitle.to_ms(h, m, s, 0) * mul
  end
  m, s = string:match("(%d+):(%d+)")
  if s then
    return subtitle.to_ms(0, m, s, 0) * mul
  end
  return nil
end


vim.api.nvim_create_user_command("SrtShift", function(opts)
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, line)

  if not sub_i then
    print("Not in a subtitle")
    return
  end

  local sub = subs[sub_i]

  local shift = parse_time(opts.args)
  if not shift then
    print("Invalid time format")
    return
  end

  local new_start = sub.start_ms + shift
  local new_end = sub.end_ms + shift

  if new_start < 0 or new_end < 0 then
    local over = 0 - new_start
    local over_fmt = make_dur_ms(over)
    print("Can't shift subtitle before 0. Over by " .. over_fmt)
    return
  end

  vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, { make_dur_full_ms(new_start, new_end) })

  lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(buf, lines, subs)
end, { desc = "Shift the current subtitle", nargs = 1 })


vim.api.nvim_create_user_command("SrtShiftAll", function(opts)
  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end

  local shift = parse_time(opts.args)
  if not shift then
    print("Invalid time format")
    return
  end

  for _, sub in ipairs(subs) do
    local new_start = sub.start_ms + shift
    local new_end = sub.end_ms + shift

    if new_start < 0 or new_end < 0 then
      local over = 0 - new_start
      local over_fmt = make_dur_ms(over)
      print("Can't shift subtitle " .. sub.index .. " before 0. Over by " .. over_fmt)
      return
    end

    lines[sub.line_pos + 1] = make_dur_full_ms(new_start, new_end)
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(buf, lines, subs)
end, { desc = "Shift all subtitles", nargs = 1 })


vim.api.nvim_create_user_command("SrtImport", function(opts)
  local config = get_config()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, line)

  if not sub_i then
    print("Not in a subtitle")
    return
  end

  local sub = subs[sub_i]
  local args = vim.split(opts.args, " ")
  local file = args[1]
  local offset = config.min_pause
  if #args > 1 then
    offset = parse_time(args[2])
    if not offset then
      print("Invalid time format")
      return
    end
  end

  local new_lines = vim.fn.readfile(file)
  local new_subs, err_new = get_subs.parse(new_lines)
  if err_new or not new_subs then
    get_subs.print_err(err_new)
    return
  end

  for _, new_sub in ipairs(new_subs) do
    local new_start = new_sub.start_ms + sub.end_ms + offset
    local new_end = new_sub.end_ms + sub.end_ms + offset
    new_lines[new_sub.line_pos + 1] = make_dur_full_ms(new_start, new_end)
  end

  vim.api.nvim_buf_set_lines(buf, -1, -1, false, new_lines)

  lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(buf, lines, subs)
end, { desc = "Import subtitles from another file after min_pause or optional offset", nargs = "+", complete = "file" })


vim.api.nvim_create_user_command("SrtAdd", function(opts)
  local config = get_config()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, line)

  if not sub_i then
    print("Not in a subtitle")
    return
  end

  local offset = config.min_pause

  if opts.args ~= "" then
    offset = parse_time(opts.args)
    if not offset then
      print("Invalid time format")
      return
    end
  end

  local sub = subs[sub_i]
  local new_line = sub.line_pos + 1 + #sub.line_lengths
  local new_start = sub.end_ms + offset
  local new_end = new_start + config.min_duration

  local new_header = {
    "",
    tostring(sub.index + 1),
    make_dur_full_ms(new_start, new_end)
  }

  vim.api.nvim_buf_set_lines(buf, new_line, new_line, false, new_header)

  lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(buf, lines, subs)
  print("Subtitle added, subtitles sorted")
end, { desc = "Add a subtitle after the current one with optional offset", nargs = "?" })

vim.api.nvim_create_user_command("SrtShiftTime", function (opts)
  local config = get_config()
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, line)

  if not sub_i then
    print("Not in a subtitle")
    return
  end

  local sub = subs[sub_i]
  if line ~= sub.line_pos + 1 then
    print("Not on duration line")
    return
  end

  local offset = config.shift_ms

  if opts.args ~= "" then
    offset = parse_time(opts.args)
    if not offset then
      print("Invalid time format")
      return
    end
  end

  if col >= 0 and col <= 12 then
    local new_ms = sub.start_ms + offset
    if new_ms < 0 then
      print("Start time cannot be negative")
      return
    end

    local last_end = lines[sub.line_pos + 1]:sub(13, 29)

    local new_start = make_dur_ms(new_ms)
    vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, { new_start .. last_end })
  elseif col >= 16 and col <= 28 then
    local new_ms = sub.start_ms + offset
    if new_ms < 0 then
      print("End time cannot be negative")
      return
    end
    local first_start = lines[sub.line_pos + 1]:sub(1, 17)

    local new_end = make_dur_ms(new_ms)
    vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, { first_start .. new_end })
  else
    print("Hover over start or end time to shift")
  end
end, { desc = "Shift either the start or end time of a subtitle.", nargs = "?" })

return M
