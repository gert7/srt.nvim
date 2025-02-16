local vim = vim

local M = {}

local subtitle = require("srtnvim.subtitle")
local get_config = require("srtnvim.config")

local State = {
  index = 1,
  timing = 2,
  subtitle = 3
}

local function pad_left(s, c, n)
  return string.rep(c, n - #s) .. s
end

local function fmt_s(ms)
  local neg = ""
  if ms < 0 then
    neg = "-"
    ms = -ms
  end
  local timing_milli = ms % 1000
  local timing_secs = (ms - timing_milli) / 1000

  local tm_padded = pad_left(tostring(timing_milli), "0", 3)
  return string.format("%s%d.%ss", neg, timing_secs, tm_padded)
end

local matcher = "(%d%d):(%d%d):(%d%d),(%d%d%d)%s%-%->%s(%d%d):(%d%d):(%d%d),(%d%d%d)"

function M.preproduce_pause_lines(config)
  local tl = config.tack_left or config.tack
  local tr = config.tack_right or config.tack
  local tm = config.tack_middle
  local pause_lines = {}

  local extra_spaces = string.rep(" ", config.extra_spaces)

  local function format(sample)
    return (sample:gsub("%.", tl):gsub(",", tm):gsub(":", tr):gsub("&", extra_spaces))
  end

  local sample0 = "                                 &(%s)"
  local sample1 = "                .:               &(%s)"
  local sample2 = "               .,,:              &(%s)"
  local sample3 = "              .,,,,:             &(%s)"
  local sample4 = "             .,,,,,,:            &(%s)"
  local sample5 = "            .,,,,,,,,:           &(%s)"
  table.insert(pause_lines, format(sample1))
  table.insert(pause_lines, format(sample2))
  table.insert(pause_lines, format(sample3))
  table.insert(pause_lines, format(sample4))
  table.insert(pause_lines, format(sample5))
  table.insert(pause_lines, format(sample0))
  return pause_lines, sample0
end

local function get_pause_line(pause, config, pause_lines)
  if not config.tack_enabled then
    return pause_lines[6]
  end
  if pause < config.min_pause then
    return pause_lines[1]
  elseif pause >= config.min_pause and pause < 1000 then
    return pause_lines[2]
  elseif pause >= 1000 and pause < 5000 then
    return pause_lines[3]
  elseif pause >= 5000 and pause < 10000 then
    return pause_lines[4]
  else
    return pause_lines[5]
  end
end

local function remove_tags(s)
  return s:gsub("<[^>]+>", "")
end

local nsid = vim.api.nvim_create_namespace("srtsubdiag")

function M.annotate_subs(buf, config, data, has_groups)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  vim.api.nvim_buf_clear_namespace(buf, nsid, 0, -1)

  if config.enabled == false then
    return
  end

  local state = State.index

  local diagnostics = {}
  local ext_marks = {}

  local last_end = 0
  local cur_start = 0
  local cur_end = 0

  local line_count = 0
  local line_lengths = {}
  local last_timing = 0
  local total_length = 0
  local last_timing_k = 0
  local extra_spaces = string.rep(" ", config.extra_spaces)
  local last_index = 0

  local cps_mark = " (%d%%)"

  if not config.length then
    cps_mark = "    (%d%%)"
  end

  local function add_diagnostic(lnum, message, col)
    table.insert(diagnostics, {
      lnum = lnum,
      col = col or 0,
      message = message
    })
  end

  local function add_ext_mark(row, col, opts)
    table.insert(ext_marks, { row, col, opts })
  end

  for k, v in ipairs(lines) do
    if state == State.index and v ~= "" then
      local n = tonumber(v)
      if not n then
        add_diagnostic(k - 1, "Error reading subtitle index!", 0)
        vim.diagnostic.set(nsid, buf, diagnostics, {})
        return
      end

      if n ~= last_index + 1 then
        add_diagnostic(k - 1, "Subtitle index is not sequential!", 0)
      end
      last_index = n
      state = State.timing
    elseif state == State.timing then
      local f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi = string.gmatch(v, matcher)()
      if not t_mi then
        add_diagnostic(k - 1, "Error reading duration!", 0)
        vim.diagnostic.set(nsid, buf, diagnostics, {})
        return
      end

      last_timing_k = k

      local from = subtitle.to_ms(f_h, f_m, f_s, f_mi)
      local to = subtitle.to_ms(t_h, t_m, t_s, t_mi)
      last_timing = to - from

      if from < cur_start then
        add_diagnostic(k - 1, "Subtitle appears before previous subtitle!", 0)
      end

      last_end = cur_end
      cur_start = from
      cur_end = to

      local pause = cur_start - last_end

      local pauseline = k - 3

      if config.pause and pauseline > 0 and last_index > 1 then
        local opts = {
          id = pauseline,
          virt_text = {
            {
              string.format(get_pause_line(pause, config, data.pause_lines), fmt_s(pause)), "Srt"
            }
          },
          virt_text_pos = 'eol'
        }
        add_ext_mark(pauseline, 0, opts)

        if config.overlap_warning and pause < 0 then
          add_diagnostic(pauseline, "Subtitle overlaps with previous subtitle", 0)
        elseif pause < config.min_pause and last_index > 1 then
          add_diagnostic(pauseline, "Pause is too short", 0)
        end
      end
      state = State.subtitle
    elseif state == State.subtitle then
      v = v:gsub("^%s*(.-)%s*$", "%1")
      if v ~= "" then
        local clean_s = remove_tags(v)
        local len = vim.fn.strchars(clean_s)
        total_length = total_length + len
        line_count = line_count + 1
        table.insert(line_lengths, len)
      else -- subtitle termination
        local dbz = last_timing == 0
        local cps = 0
        if not dbz then
          cps = total_length / last_timing * 1000
        else
          cps = math.huge
        end

        local cfg_mask, _ = get_config.get_by_line_count(config, line_count)

        -- minimum duration per subtitle
        if cfg_mask.min_duration ~= -1 and last_timing < cfg_mask.min_duration then
          add_diagnostic(
            last_timing_k - 1,
            "Duration is too short (<" .. cfg_mask.min_duration .. "ms)", 0)
        end

        -- maximum duration per subtitle
        if cfg_mask.max_duration ~= -1 and last_timing > cfg_mask.max_duration then
          add_diagnostic(
            last_timing_k - 1,
            "Duration is too long (>" .. cfg_mask.max_duration .. "ms)", 0)
        end

        -- maximum length per line
        for i, len in ipairs(line_lengths) do
          if cfg_mask.max_length ~= -1 and len > cfg_mask.max_length then
            add_diagnostic(
              last_timing_k - 1 + i,
              "Line is too long (>" .. cfg_mask.max_length .. ")", 0)
          end
        end

        -- maximum length per subtitle
        if cfg_mask.max_length_sub ~= -1 and total_length > cfg_mask.max_length_sub then
          add_diagnostic(
            last_timing_k - 1,
            "Subtitle has too many characters (>" .. cfg_mask.max_length_sub .. ")", 0)
        end

        -- maximum number of lines
        if config.max_lines ~= -1 and line_count > config.max_lines then
          add_diagnostic(
            last_timing_k - 1,
            "Subtitle has too many lines (>" .. config.max_lines .. ")", 0)
        end

        local dur_bar = ""

        if config.length then
          dur_bar = dur_bar .. extra_spaces .. " =  " .. fmt_s(last_timing)
        end

        if cps < math.huge and
            (config.cps or
              (config.cps_warning and cps > config.max_cps)) then
          local percent = cps / config.max_cps * 100
          dur_bar = dur_bar .. string.format(cps_mark, percent)
        end

        local opts = {
          id = last_timing_k - 1,
          virt_text = { { dur_bar, "Srt" } },
          virt_text_pos = 'eol'
        }
        add_ext_mark(last_timing_k - 1, 0, opts)

        state = State.index
        line_count = 0
        total_length = 0
        line_lengths = {}
      end
    end
  end

  if state == State.timing then
    add_diagnostic(#lines, "Subtitle is not terminated", 0)
  end

  vim.diagnostic.set(nsid, buf, diagnostics, {})

  for _, v in ipairs(ext_marks) do
    vim.api.nvim_buf_set_extmark(buf, nsid, v[1], v[2], v[3])
  end
end

function M.parse(lines)
  local state = State.index

  local subtitles = {}

  local next_subtitle = subtitle.Subtitle.blank()

  for k, v in ipairs(lines) do
    if state == State.index then
      if v == "" then
        -- TODO: check this out with lines before index 1
        -- we could add a check here if we're over the first
        table.insert(next_subtitle.line_lengths, 0)
      else
        local n = tonumber(v)
        if not n then
          return nil, { "Error reading subtitle index!", k }
        end
        next_subtitle.line_pos = k
        next_subtitle.index = n
        state = State.timing
      end
    elseif state == State.timing then
      local f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi = string.gmatch(v, matcher)()
      if not t_mi then
        return nil, { "Error reading duration!", k }
      end
      local last_f = subtitle.to_ms(f_h, f_m, f_s, f_mi)
      local last_t = subtitle.to_ms(t_h, t_m, t_s, t_mi)
      next_subtitle.start_ms = last_f
      next_subtitle.end_ms = last_t
      next_subtitle.length_ms = last_t - last_f

      state = State.subtitle
    elseif state == State.subtitle then
      v = v:gsub("^%s*(.-)%s*$", "%1")
      if v == "" then
        table.insert(subtitles, next_subtitle)
        next_subtitle = subtitle.Subtitle.blank()
        state = State.index
      else
        local clean_s = remove_tags(v)
        table.insert(next_subtitle.line_lengths, clean_s:len())
      end
    end
  end

  if state == State.subtitle then
    table.insert(subtitles, next_subtitle)
  end

  return subtitles, nil
end

function M.print_err(err)
  print("Error: " .. err[1] .. " on line " .. err[2])
end

function M.find_subtitle(subs, line)
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

function M.find_subtitle_by_ms(subs, ms)
  local low = 1
  local high = #subs
  while low <= high do
    local mid = math.floor((low + high) / 2)
    local sub = subs[mid]
    if sub.start_ms == ms then
      return mid
    end
    if sub.start_ms < ms then
      if mid == #subs or subs[mid + 1].start_ms > ms then
        return mid
      end
      low = mid + 1
    else
      high = mid - 1
    end
  end
end

function M.get_data(buf_i)
  local buf = buf_i or vim.api.nvim_get_current_buf()
  return {
    config = get_config.get_config(),
    buf = buf,
    line = vim.api.nvim_win_get_cursor(0)[1],
    col = vim.api.nvim_win_get_cursor(0)[2],
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  }
end

return M
