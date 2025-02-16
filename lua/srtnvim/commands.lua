local vim = vim
local c = require("srtnvim.constants")
local config = require("srtnvim.config")
local get_subs = require("srtnvim.get_subs")
local subtitle = require("srtnvim.subtitle")

local M = {}

local function sum_array(t, s, f)
  local sum = 0
  for i = s, f do
    sum = sum + t[i]
  end
  return sum
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

  local dur_line = subtitle.make_dur_full_ms(sub.start_ms, next.end_ms)
  vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false, { dur_line })
end


local function define_command(name, func, options)
  local command = function(args)
    func(args, get_subs.get_data())
  end
  vim.api.nvim_create_user_command(name, command, options)
end


local function define_command_subs(name, func, options)
  local command = function(args)
    local data = get_subs.get_data()
    local subs, err = get_subs.parse(data.lines)
    if err then
      get_subs.print_err(err)
      return
    end
    func(args, get_subs.get_data(), subs)
  end
  vim.api.nvim_create_user_command(name, command, options)
end


local function define_command_subtitle(name, func, options)
  local command = function(args)
    local data = get_subs.get_data()
    local subs, err = get_subs.parse(data.lines)
    if err then
      get_subs.print_err(err)
      return
    end
    local sub_i = get_subs.find_subtitle(subs, data.line)

    if not sub_i then
      print("Not in a subtitle")
      return
    end
    func(args, get_subs.get_data(), subs, sub_i)
  end
  vim.api.nvim_create_user_command(name, command, options)
end


M.define_command = define_command
M.define_command_subs = define_command_subs
M.define_command_subtitle = define_command_subtitle


define_command_subs("SrtMerge", function(args, data, subs)
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
    data.lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
    local err
    subs, err = get_subs.parse(data.lines)
    if err then
      print("Unexpected error on line " .. err[2] .. ": " .. err[1])
      return
    end
    sub_merge(data.buf, subs, sub_first)
  end
end, { desc = "Merge the subtitle down", range = true })


define_command_subtitle("SrtSplit", function(args, data, subs, sub_i)
  local split_mode = data.config.split_mode
  if args.args ~= "" then
    split_mode = args.args
  end
  if split_mode ~= c.SPLIT_LENGTH and split_mode ~= c.SPLIT_HALF then
    print("Invalid split mode")
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

  local ind_lines = vim.api.nvim_buf_get_lines(data.buf, subs[sub_i + 1].line_pos - 1, -1, false)
  local new_lines = add_to_indices(ind_lines, subs, sub_i + 1, 1)
  vim.api.nvim_buf_set_lines(data.buf, subs[sub_i + 1].line_pos - 1, -1, false, new_lines)

  local split_point = sub.line_pos + 1 + line_count / 2

  local mp = 0
  if data.config.split_with_min_pause then
    mp = data.config.min_pause
  end

  local split_ms = 0

  if split_mode == c.SPLIT_LENGTH then
    local length_first = sum_array(sub.line_lengths, 1, line_count / 2)
    local length_second = sum_array(sub.line_lengths, line_count / 2 + 1, line_count)
    local p = length_first / (length_first + length_second)
    split_ms = sub.start_ms + sub.length_ms * p
  else -- split_mode == "half"
    split_ms = sub.start_ms + sub.length_ms / 2
  end

  local first_end = subtitle.make_dur_ms(split_ms - mp)
  local last_start = subtitle.make_dur_ms(split_ms + mp)
  local new_index = tostring(sub.index + 1)

  local first_start = data.lines[sub.line_pos + 1]:sub(1, 17)
  local last_end = data.lines[sub.line_pos + 1]:sub(13, 29)

  vim.api.nvim_buf_set_lines(data.buf, sub.line_pos, sub.line_pos + 1, false,
    { first_start .. first_end })

  local new_header = {
    "",
    new_index,
    last_start .. last_end
  }

  vim.api.nvim_buf_set_lines(data.buf, split_point, split_point, false, new_header)
end, {
  desc = "Split the subtitle in two",
  nargs = "?",
  complete = function()
    return { c.SPLIT_LENGTH, c.SPLIT_HALF }
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

define_command("SrtFixIndex", function(args, data)
  local _, err = M.fix_indices_buf(data.buf)
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


define_command_subs("SrtSort", function(args, data, subs)
  sub_sort(data.buf, data.lines, subs)
end, { desc = "Sort the subtitles by starting times" })


local function fix_timing(buf, lines, subs, i, config)
  local sub = subs[i]
  local next = subs[i + 1]
  if sub.start_ms > sub.end_ms then
    return false, "Subtitle " .. sub.index .. " has a negative duration"
  elseif sub.end_ms > next.start_ms or
      (config.fix_bad_min_pause and sub.end_ms > next.start_ms - config.min_pause) then
    local mp = 0
    if config.fix_with_min_pause then
      mp = config.min_pause
    end
    local new_end = next.start_ms - mp

    if new_end - sub.start_ms >= config.min_duration then
      local first_start = lines[sub.line_pos + 1]:sub(1, 17)
      -- local fe_h, fe_m, fe_s, fe_mi = subtitle.from_ms(new_end)
      vim.api.nvim_buf_set_lines(buf, sub.line_pos, sub.line_pos + 1, false,
        { first_start .. subtitle.make_dur_ms(new_end) })
    else
      return false, "Can't shrink subtitle " .. sub.index .. ", would break min_duration"
    end
    return true, nil
  else
    return false, nil
  end
end


define_command_subtitle("SrtFixTiming", function(args, data, subs, sub_i)
  if sub_i ~= #subs then
    local fix, error = fix_timing(data.buf, data.lines, subs, sub_i, data.config)
    if fix then
      print("Fixed timing for subtitle " .. sub_i)
    elseif error then
      print(error)
    else
      print("Nothing to fix for subtitle " .. sub_i)
    end
  end
end, { desc = "Fix timing for the current subtitle" })


define_command_subs("SrtFixTimingAll", function(args, data, subs)
  local count = 0
  for i = 1, #subs - 1 do
    local fix, error = fix_timing(data.buf, data.lines, subs, i, data.config)
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


local function srt_shift(subs, lines, from, to, shift)
  if to == -1 then
    to = #subs
  end
  for i = from, to do
    local sub = subs[i]
    local new_start = sub.start_ms + shift
    local new_end = sub.end_ms + shift

    if new_start < 0 or new_end < 0 then
      local over = 0 - new_start
      local over_fmt = subtitle.make_dur_ms(over)
      return lines, "Can't shift subtitle " .. sub.index .. " before 0. Over by " .. over_fmt
    end

    lines[sub.line_pos + 1] = subtitle.make_dur_full_ms(new_start, new_end)
  end
  return lines, nil
end


define_command_subs("SrtShift", function(args, data, subs)
  local sub_first = get_subs.find_subtitle(subs, args.line1)
  if not sub_first then
    print("Not in a subtitle")
    return
  end

  local sub_last = sub_first
  if args.line1 ~= args.line2 then
    sub_last = get_subs.find_subtitle(subs, args.line2)
  end

  local shift = parse_time(args.args)
  if not shift then
    print("Invalid time format")
    return
  end

  local lines, shift_err = srt_shift(subs, data.lines, sub_first, sub_last, shift)

  if shift_err then
    print(shift_err)
    return
  end

  vim.api.nvim_buf_set_lines(data.buf, 0, -1, false, lines)

  lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(data.buf, lines, subs)
end, { desc = "Shift the current subtitle", nargs = 1, range = true })


define_command_subs("SrtShiftAll", function(args, data, subs)
  local shift = parse_time(args.args)
  if not shift then
    print("Invalid time format")
    return
  end

  local lines, shift_err = srt_shift(subs, data.lines, 1, -1, shift)

  if shift_err then
    print(shift_err)
    return
  end

  vim.api.nvim_buf_set_lines(data.buf, 0, -1, false, lines)

  lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(data.buf, lines, subs)
end, { desc = "Shift all subtitles", nargs = 1 })


define_command_subtitle("SrtImport", function(args_in, data, subs, sub_i)
  local sub = subs[sub_i]
  local args = vim.split(args_in.args, " ")
  local file = args[1]
  local offset = data.config.min_pause
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

  local end_offset = sub.end_ms + offset

  for _, new_sub in ipairs(new_subs) do
    local new_start = new_sub.start_ms + end_offset
    local new_end = new_sub.end_ms + end_offset
    new_lines[new_sub.line_pos + 1] = subtitle.make_dur_full_ms(new_start, new_end)
  end

  vim.api.nvim_buf_set_lines(data.buf, -1, -1, false, new_lines)

  local lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(data.buf, lines, subs)
end, {
  desc = "Import subtitles from another file after min_pause or optional offset",
  nargs = "+",
  complete = "file"
})


define_command_subtitle("SrtAdd", function(args, data, subs, sub_i)
  local offset = data.config.min_pause

  if args.args ~= "" then
    offset = parse_time(args.args)
    if not offset then
      print("Invalid time format")
      return
    end
  end

  local sub = subs[sub_i]
  local new_line = sub.line_pos + 1 + #sub.line_lengths
  local new_start = sub.end_ms + offset
  local new_end = new_start + data.config.min_duration

  local new_header = {
    "",
    tostring(sub.index + 1),
    subtitle.make_dur_full_ms(new_start, new_end)
  }

  vim.api.nvim_buf_set_lines(data.buf, new_line, new_line, false, new_header)

  local lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(data.buf, lines, subs)
  print("Subtitle added, subtitles sorted")
end, { desc = "Add a subtitle after the current one with optional offset", nargs = "?" })


define_command_subtitle("SrtShiftTime", function(args, data, subs, sub_i)
  local sub = subs[sub_i]
  if data.line ~= sub.line_pos + 1 then
    print("Not on duration line")
    return
  end

  local offset = data.config.shift_ms

  if args.args ~= "" then
    offset = parse_time(args.args)
    if not offset then
      print("Invalid time format")
      return
    end
  end

  if data.col >= 0 and data.col <= 12 then
    local new_ms = sub.start_ms + offset
    if new_ms < 0 then
      print("Start time cannot be negative")
      return
    end

    local new_timing = subtitle.amend_start(data.lines[sub.line_pos + 1], new_ms)
    vim.api.nvim_buf_set_lines(
      data.buf,
      sub.line_pos,
      sub.line_pos + 1,
      false,
      { new_timing }
    )
  elseif data.col >= 16 and data.col <= 28 then
    local new_ms = sub.end_ms + offset
    if new_ms < 0 then
      print("End time cannot be negative")
      return
    end

    local new_timing = subtitle.amend_end(data.lines[sub.line_pos + 1], new_ms)
    vim.api.nvim_buf_set_lines(
      data.buf,
      sub.line_pos,
      sub.line_pos + 1,
      false,
      { new_timing }
    )
  else
    print("Hover over start or end time to shift")
  end
end, { desc = "Shift either the start or end time of a subtitle.", nargs = "?" })


define_command_subtitle("SrtEnforce", function(args, data, subs, sub_i)
  local sub = subs[sub_i]
  if data.line ~= sub.line_pos + 1 then
    print("Not on duration line")
    return
  end

  if data.col >= 0 and data.col <= 12 then
    if sub_i == 1 then
      print("Can't apply this on the first subtitle")
      return
    end
    local sub_prev = subs[sub_i - 1]

    local prev_end_ms = sub_prev.end_ms
    local curr_start_ms = sub.start_ms

    local new_ms = curr_start_ms - data.config.min_pause
    if new_ms >= prev_end_ms then
      print("Nothing to be done")
      return
    end
    if new_ms < sub_prev.start_ms then
      print("Would shrink previous subtitle beyond start time")
      return
    end

    local new_timing = subtitle.amend_end(data.lines[sub_prev.line_pos + 1], new_ms)
    vim.api.nvim_buf_set_lines(
      data.buf,
      sub_prev.line_pos,
      sub_prev.line_pos + 1,
      false,
      { new_timing }
    )
  elseif data.col >= 16 and data.col <= 28 then
    if sub_i == #subs then
      print("Can't apply this on the last subtitle")
      return
    end

    local sub_next = subs[sub_i + 1]

    local next_start_ms = sub_next.start_ms
    local curr_end_ms = sub.end_ms

    local new_ms = curr_end_ms + data.config.min_pause
    if new_ms <= next_start_ms then
      print("Nothing to be done")
      return
    end
    if new_ms > sub_next.end_ms then
      print("Would shrink next subtitle beyond end time")
      return
    end

    local new_timing = subtitle.amend_start(data.lines[sub_next.line_pos + 1], new_ms)
    vim.api.nvim_buf_set_lines(
      data.buf,
      sub_next.line_pos,
      sub_next.line_pos + 1,
      false,
      { new_timing }
    )
  end
end, { desc = "Enforce start or end of subtitle on adjacent subtitle, with min_pause" })


define_command_subtitle("SrtShiftTimeStrict", function(args, data, subs, sub_i)
  local sub = subs[sub_i]
  if data.line ~= sub.line_pos + 1 then
    print("Not on duration line")
    return
  end

  local offset = data.config.shift_ms

  if args.args ~= "" then
    offset = parse_time(args.args)
    if not offset then
      print("Invalid time format")
      return
    end
  end

  if data.col >= 0 and data.col <= 12 then
    local new_ms = sub.start_ms + offset
    if new_ms < 0 then
      print("Start time cannot be negative")
      return
    end

    if sub_i > 1 then
      local sub_prev = subs[sub_i - 1]

      local bleed = sub_prev.end_ms + data.config.min_pause

      if new_ms < bleed then
        local new_prev_ms = new_ms - data.config.min_pause
        if new_prev_ms < sub_prev.start_ms then
          print("Would shrink previous subtitle beyond start time")
          return
        end
        local new_timing = subtitle.amend_end(data.lines[sub_prev.line_pos + 1], new_prev_ms)
        vim.api.nvim_buf_set_lines(
          data.buf,
          sub_prev.line_pos,
          sub_prev.line_pos + 1,
          false,
          { new_timing }
        )
      end
    end
    local new_timing = subtitle.amend_start(data.lines[sub.line_pos + 1], new_ms)
    vim.api.nvim_buf_set_lines(
      data.buf,
      sub.line_pos,
      sub.line_pos + 1,
      false,
      { new_timing }
    )
  elseif data.col >= 16 and data.col <= 28 then
    local new_ms = sub.end_ms + offset

    if sub_i < #subs then
      local sub_next = subs[sub_i + 1]

      local bleed = sub_next.start_ms - data.config.min_pause

      if new_ms > bleed then
        local new_next_ms = new_ms + data.config.min_pause
        if new_next_ms > sub_next.end_ms then
          print("Would shrink next subtitle beyond end time")
          return
        end
        local new_timing = subtitle.amend_start(data.lines[sub_next.line_pos + 1], new_next_ms)
        vim.api.nvim_buf_set_lines(
          data.buf,
          sub_next.line_pos,
          sub_next.line_pos + 1,
          false,
          { new_timing }
        )
      end
    end

    local new_timing = subtitle.amend_end(data.lines[sub.line_pos + 1], new_ms)
    vim.api.nvim_buf_set_lines(
      data.buf,
      sub.line_pos,
      sub.line_pos + 1,
      false,
      { new_timing }
    )
  end
end, { desc = "Shift the start or end of a subtitle with enforcement", nargs = "?" })


define_command_subtitle("SrtSwap", function(args, data, subs, sub_i)
  if sub_i == #subs and #subs >= 2 then
    sub_i = sub_i - 1
  elseif #subs < 2 then
    print("Not enough subtitles to swap anything")
    return
  end

  local sub1 = subs[sub_i]
  local line1_from = sub1.line_pos + 2
  local line1_to = line1_from + #sub1.line_lengths

  local text1 = {}
  for i = line1_from, line1_to - 1 do
    table.insert(text1, data.lines[i])
  end
  table.insert(text1, "")

  local sub2 = subs[sub_i + 1]
  local line2_from = sub2.line_pos + 2
  local line2_to = line2_from + #sub2.line_lengths

  local text2 = {}
  for i = line2_from, line2_to - 1 do
    table.insert(text2, data.lines[i])
  end
  table.insert(text2, "")

  local start1 = sub1.line_pos + 1
  local start2 = sub2.line_pos + 1
  local finish1 = sub1.line_pos + #sub1.line_lengths + 2
  local finish2 = sub2.line_pos + #sub2.line_lengths + 2

  local diff = #sub2.line_lengths - #sub1.line_lengths

  vim.api.nvim_buf_set_lines(data.buf, start1, finish1, false, text2)
  vim.api.nvim_buf_set_lines(data.buf, start2 + diff, finish2 + diff, false, text1)
end, { desc = "Swap this subtitle with the one below it" })


define_command_subtitle("SrtJump", function(args, data, subs, sub_i)
  local arg = args.args

  local arg_n = tonumber(arg)
  if not arg_n then
    print("Can't understand line number")
    return
  end

  local sub = subs[arg_n]
  if not sub then
    print("No subtitle with index " .. arg_n)
    return
  end

  vim.api.nvim_win_set_cursor(0, { sub.line_pos, 0 })
  vim.cmd("normal! zz")
end, { desc = "Jump to subtitle by index", nargs = 1 })


return M
