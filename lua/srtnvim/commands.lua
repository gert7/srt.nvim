local vim            = vim
local c              = require("srtnvim.constants")
local config         = require("srtnvim.config")
local get_subs       = require("srtnvim.get_subs")
local subtitle       = require("srtnvim.subtitle")
local video          = require("srtnvim.video")
local util           = require("srtnvim.util")

local ParseErrorType = get_subs.ParseErrorType

local M              = {}

---@param t number[]
---@param s integer
---@param f integer
---@return number
local function sum_array(t, s, f)
  local sum = 0
  for i = s, f do
    sum = sum + t[i]
  end
  return sum
end


--- Arithmetic add a number to all indices in a table of subtitles
---@param lines string[] array of lines from the .srt file
---@param subs Subtitle[] array of subtitles
---@param start integer index of subtitle to start from
---@param n integer to add to the indices
---@return table lines modified table of lines to be placed into the buffer
local function add_to_indices(lines, subs, start, n)
  local offset = subs[start].line_pos - 1
  for i = start, #subs do
    local sub = subs[i]
    lines[sub.line_pos - offset] = tostring(sub.index + n)
  end
  return lines
end


--- Fix all indices in a file
---@param lines string[]
---@param subs Subtitle[]
---@return string[]
---@return boolean
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


---@param buf integer
---@param subs Subtitle[]
---@param sub_i integer
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


---@class NvimCommandOptions
---@field desc string
---@field range? boolean
---@field nargs? integer | string
---@field complete? function | string

---@class NvimCommandArgs
---@field line1 integer
---@field line2 integer
---@field args string

---@param name string
---@param func fun(args: NvimCommandArgs, data: Subdata)
---@param options NvimCommandOptions
---@return nil
local function define_command(name, func, options)
  local command = function(args)
    func(args, get_subs.get_data())
  end
  vim.api.nvim_create_user_command(name, command, options)
end


---@param name string
---@param func fun(args: NvimCommandArgs, data: Subdata, subs: Subtitle[])
---@param options NvimCommandOptions
---@return nil
local function define_command_subs(name, func, options)
  local command = function(args)
    local data = get_subs.get_data()
    local subs, err = get_subs.parse(data.lines)
    if err then
      get_subs.print_err(err)
      return
    end
    ---@cast subs Subtitle[]
    func(args, get_subs.get_data(), subs)
  end
  vim.api.nvim_create_user_command(name, command, options)
end


---@param name string
---@param func fun(args: NvimCommandArgs, data: Subdata, subs: Subtitle[], sub_i: integer)
---@param options NvimCommandOptions
---@return nil
local function define_command_subtitle(name, func, options)
  local command = function(args)
    local data = get_subs.get_data()
    local subs, err = get_subs.parse(data.lines)
    if err then
      get_subs.print_err(err)
      return
    end
    ---@cast subs Subtitle[]
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
    ---@cast subs Subtitle[]
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


---@param buf integer
---@return boolean
---@return [string, integer] | nil
function M.fix_indices_buf(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err then
    return false, err
  end
  ---@cast subs Subtitle[]
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


--- Parse a timing input.
-- Either in milliseconds
-- or at least some partial form of hh:mm:ss,mss.
---@param input string time string to parse
local function parse_time(input)
  local mul = 1
  if input:sub(1, 1) == "-" then
    mul = -1
    input = input:sub(2)
  elseif input:sub(1, 1) == "+" then
    input = input:sub(2)
  end

  local ms = tonumber(input)
  if ms then return ms * mul end

  local h, m, s, mi = input:match("(%d+):(%d+):(%d+)[.,](%d+)")
  if mi then
    return subtitle.to_ms(h, m, s, mi) * mul
  end
  m, s, mi = input:match("(%d+):(%d+)[.,](%d+)")
  if mi then
    return subtitle.to_ms(0, m, s, mi) * mul
  end
  s, mi = input:match("(%d+)[.,](%d+)")
  if mi then
    return subtitle.to_ms(0, 0, s, mi) * mul
  end

  h, m, s = input:match("(%d+):(%d+):(%d+)")
  if s then
    return subtitle.to_ms(h, m, s, 0) * mul
  end
  m, s = input:match("(%d+):(%d+)")
  if s then
    return subtitle.to_ms(0, m, s, 0) * mul
  end
  return nil
end

--- Parse a timing input with an optional 'S' or 'E' specifier at the end.
-- Defaults to 'S' (start) if no specifier is found.
---@param input string time string to parse
---@return number | nil
---@return 'start' | 'end'
local function parse_time_with_specifier(input)
  local time_str = input
  local specifier = 'start'

  local last_char = input:sub(-1):upper()

  if last_char == 'S' then
    time_str = input:sub(1, -2)
    specifier = 'start'
  elseif last_char == 'E' then
    time_str = input:sub(1, -2)
    specifier = 'end'
  end

  local ms = parse_time(time_str)
  if not ms then
    -- If parsing with the suffix removed fails, try parsing the original string
    return parse_time(input), 'start'
  end
  return ms, specifier
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
    sub_last = get_subs.find_subtitle(subs, args.line2) or sub_first
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
    local p_offset = parse_time(args[2])
    if not p_offset then
      print("Invalid time format")
      return
    end
    offset = p_offset
  end

  local new_lines = vim.fn.readfile(file)
  local new_subs, err_new = get_subs.parse(new_lines)
  if err_new then
    get_subs.print_err(err_new)
    return
  end
  ---@cast new_subs Subtitle[]

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
    local p_offset = parse_time(args.args)
    if not p_offset then
      print("Invalid time format")
      return
    end
    offset = p_offset
  end

  video.get_pit(data.buf, function(pit)
    local sub = subs[sub_i]
    local new_line = sub.line_pos + 1 + #sub.line_lengths
    local new_start = sub.end_ms
    if data.config.add_at_seek and pit then
      new_start = pit
    end
    new_start = new_start + offset
    local new_end = new_start + data.config.min_duration

    local new_header = {
      "",
      tostring(sub.index + 1),
      subtitle.make_dur_full_ms(new_start, new_end)
    }

    vim.schedule(function()
      vim.api.nvim_buf_set_lines(data.buf, new_line, new_line, false, new_header)

      local lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
      subs, _ = get_subs.parse(lines)
      sub_sort(data.buf, lines, subs)

      print("Added new subtitle at " .. subtitle.make_dur_ms(new_start))
    end)
  end)
end, { desc = "Add a subtitle after the current one with optional offset", nargs = "?" })


define_command_subtitle("SrtShiftTime", function(args, data, subs, sub_i)
  local sub = subs[sub_i]
  if data.line ~= sub.line_pos + 1 then
    print("Not on duration line")
    return
  end

  local offset = data.config.shift_ms

  if args.args ~= "" then
    local p_offset = parse_time(args.args)
    if not p_offset then
      print("Invalid time format")
      return
    end
    offset = p_offset
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
    local p_offset = parse_time(args.args)
    if not p_offset then
      print("Invalid time format")
      return
    end
    offset = p_offset
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


define_command_subs("SrtJump", function(args, data, subs)
  local arg = args.args

  local arg_n = tonumber(arg)
  if not arg_n then
    print("Can't understand index number")
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


define_command("SrtDeleteEmptyLines", function(args, data)
  local count = 0
  local limit = 1000

  -- Assume we won't fix more than limit of these gaps
  for i = 1, limit do
    if i >= limit then
      print("Stopping after fail-safe limit of " .. limit .. " iterations. Consider running this command again.")
    end
    local line_count = #data.lines
    if line_count < 3 then
      -- Too few lines for this to even happen or the first index is missing.
      print("Too few lines to continue")
      break
    end
    local _, err = get_subs.parse(data.lines)
    if err then
      -- Obviously we can't tell if this is an "other kind" of index reading error.
      -- But since an index can only ever be a number, there really isn't any "other
      -- kind" of index reading error. We must tell the user to consider this.
      if err.error_type == ParseErrorType.ErrorAtIndex then
        local line = err.line
        -- Delete the *previous* line
        vim.api.nvim_buf_set_lines(data.buf, line - 2, line - 1, false, {})
        count = count + 1
        data.lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
        if #data.lines == line_count then
          -- Something has gone horribly wrong and we aren't deleting lines anymore.
          print("Error: Line deletion had no effect!")
          break
        end
      else
        print("Error other than reading index found on line " .. err.line)
        get_subs.print_err(err)
        break
      end
    else
      break
    end
  end
  print("Deleted " .. count .. " empty lines")
end, { desc = "Delete empty lines that cause syntax errors" })


define_command_subtitle("SrtExtendForward", function(args, data, subs, sub_i)
  local sub = subs[sub_i]
  if sub_i == #subs then
    print("Can't extend the last subtitle forward")
    return
  end

  local next_sub = subs[sub_i + 1]
  local new_end_ms = next_sub.start_ms - data.config.min_pause

  if new_end_ms <= sub.start_ms then
    print("Cannot extend: new end time would be before or equal to start time")
    return
  end

  if new_end_ms <= sub.end_ms then
    -- it's not our job to enforce min_pause here
    print("Cannot extend: would be less than min_pause")
    return
  end

  local new_timing = subtitle.amend_end(data.lines[sub.line_pos + 1], new_end_ms)
  vim.api.nvim_buf_set_lines(
    data.buf,
    sub.line_pos,
    sub.line_pos + 1,
    false,
    { new_timing }
  )
end, { desc = "Extend subtitle forward up to next subtitle" })


define_command_subtitle("SrtExtendBackward", function(args, data, subs, sub_i)
  local sub = subs[sub_i]
  local new_start_ms
  if sub_i == 1 then
    new_start_ms = 0
  else
    local prev_sub = subs[sub_i - 1]
    new_start_ms = prev_sub.end_ms + data.config.min_pause
  end

  if new_start_ms >= sub.end_ms then
    print("Cannot extend: new start time would be after or equal to end time")
    return
  end

  if new_start_ms >= sub.start_ms then
    print("Cannot extend: would be less than min_pause")
    return
  end

  local new_timing = subtitle.amend_start(data.lines[sub.line_pos + 1], new_start_ms)
  vim.api.nvim_buf_set_lines(
    data.buf,
    sub.line_pos,
    sub.line_pos + 1,
    false,
    { new_timing }
  )
end, { desc = "Extend subtitle backward up to previous subtitle or zero time" })


define_command_subtitle("SrtStretchTime", function(args, data, subs, sub_i)
  local sub_first = get_subs.find_subtitle(subs, args.line1)
  local sub_last = get_subs.find_subtitle(subs, args.line2) or sub_first

  -- This function naturally requires a range, so no range implies everything
  -- from start to end, even if the range is present but only over the same
  -- subtitle
  if sub_first == sub_last then
    sub_first = 1
    sub_last = #subs
  end

  local split = util.split(args.args, " ")
  if #split == 0 then
    print("Specify start time for first and last subtitle, e.g. 00:01:20,100 01:32:10,500")
    return
  end
  local new_first_time, first_spec = parse_time_with_specifier(split[1])
  if not new_first_time then
    print("Unable to parse start time")
    return
  end
  local new_last_time, last_spec
  if #split == 1 then
    -- use the last start_ms as the end handle
    new_last_time = subs[#subs].start_ms
    last_spec = 'start'
  else
    new_last_time, last_spec = parse_time_with_specifier(split[#split])
  end
  if not new_last_time then
    print("Unable to parse end time")
    return
  end
  if new_last_time < new_first_time then
    print("New last time cannot be less than new first time")
    return
  end

  local old_first_time
  if first_spec == 'start' then
    old_first_time = subs[sub_first].start_ms
  else -- 'end'
    old_first_time = subs[sub_first].end_ms
  end

  local old_last_time
  if last_spec == 'start' then
    old_last_time = subs[sub_last].start_ms
  else -- 'end'
    old_last_time = subs[sub_last].end_ms
  end

  local old_length = old_last_time - old_first_time
  if old_length == 0 then
    print("Cannot stretch a range with zero duration.")
    return
  end
  local new_length = new_last_time - new_first_time
  local difference = new_length / old_length

  local new_lines = vim.deepcopy(data.lines)

  for i = sub_first, sub_last do
    local sub = subs[i]

    local old_rel_start = sub.start_ms - old_first_time
    local old_rel_end = sub.end_ms - old_first_time

    local new_start_ms = (old_rel_start * difference) + new_first_time
    local new_end_ms = (old_rel_end * difference) + new_first_time

    if new_start_ms < 0 then
      print("Error: Stretch operation would result in a negative start time for subtitle " .. sub.index)
      return
    end

    if new_start_ms > new_end_ms then
      print("Error: Stretch operation would result in a negative duration for subtitle " .. sub.index)
      return
    end

    new_lines[sub.line_pos + 1] = subtitle.make_dur_full_ms(new_start_ms, new_end_ms)
  end

  vim.api.nvim_buf_set_lines(data.buf, 0, -1, false, new_lines)

  local lines = vim.api.nvim_buf_get_lines(data.buf, 0, -1, false)
  subs, _ = get_subs.parse(lines)
  sub_sort(data.buf, lines, subs)
end, { desc = "Stretch time based on start times", range = true, nargs = "?" })


return M
