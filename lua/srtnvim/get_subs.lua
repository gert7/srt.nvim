local vim = vim

local M = {}

local subtitle = require("srtnvim.subtitle")

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
  local tl = config.tackle_left or config.tackle
  local tr = config.tackle_right or config.tackle
  local tm = config.tackle_middle
  local pause_lines = {}

  local extra_spaces = string.rep(" ", config.extra_spaces)

  local function format(sample)
    return (sample:gsub("%.", tl):gsub(",", tm):gsub(":", tr):gsub("&", extra_spaces))
  end

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
  return pause_lines
end

local function get_pause_line(pause, config, pause_lines)
  if not config.tackle_enabled then
    return "                                 (%s)"
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

function M.annotate_subs(buf, config, data, has_groups)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  local nsid = vim.api.nvim_create_namespace("srtsubdiag")

  vim.api.nvim_buf_clear_namespace(buf, nsid, 0, -1)

  if config.enabled == false then
    return
  end

  local state = State.index

  local diagnostics = {}

  local last_end = 0
  local cur_start = 0
  local cur_end = 0

  local line_count = 0
  local last_timing = 0
  local total_length = 0
  local last_timing_k = 0
  local extra_spaces = string.rep(" ", config.extra_spaces)
  local last_index = 0

  local cps_mark = " (%d%%)"

  if not config.length then
    cps_mark = "    (%d%%)"
  end

  for k, v in ipairs(lines) do
    if state == State.index and v ~= "" then
      local n = tonumber(v)
      if not n then
        table.insert(diagnostics, {
          lnum = k,
          col = 0,
          message = "Error reading subtitle index!"
        })
        vim.diagnostic.set(nsid, buf, diagnostics, {})
        return
      end

      if n ~= last_index + 1 then
        table.insert(diagnostics, {
          lnum = k - 1,
          col = 0,
          message = "Subtitle index is not sequential!"
        })
      end
      last_index = n
      state = State.timing
    elseif state == State.timing then
      local f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi = string.gmatch(v, matcher)()
      if not t_mi then
        table.insert(diagnostics, {
          lnum = k - 1,
          col = 0,
          message = "Error reading duration!"
        })
        vim.diagnostic.set(nsid, buf, diagnostics, {})
        return
      end

      last_timing_k = k

      local from = subtitle.to_ms(f_h, f_m, f_s, f_mi)
      local to = subtitle.to_ms(t_h, t_m, t_s, t_mi)
      last_timing = to - from

      if from < cur_start then
        table.insert(diagnostics, {
          lnum = k - 1,
          col = 0,
          message = "Subtitle appears before previous subtitle"
        })
      end

      last_end = cur_end
      cur_start = from
      cur_end = to

      local pause = cur_start - last_end

      local pauseline = k - 3

      if config.pause and pauseline > 0 then
        local opts = {
          id = pauseline,
          virt_text = { { string.format(get_pause_line(pause, config, data.pause_lines), fmt_s(pause)), "Srt" } },
          virt_text_pos = 'eol'
        }
        vim.api.nvim_buf_set_extmark(buf, nsid, pauseline, 0, opts)

        if pause < 0 then
          table.insert(diagnostics, {
            lnum = pauseline,
            col = 0,
            message = "Subtitle overlaps with previous subtitle"
          })
        elseif pause < config.min_pause then
          table.insert(diagnostics, {
            lnum = pauseline,
            col = 0,
            message = "Pause is too short"
          })
        end
      end
      state = State.subtitle
    elseif state == State.subtitle then
      v = v:gsub("^%s*(.-)%s*$", "%1")
      if v == "" then
        local cps = total_length / last_timing * 1000

        if config.min_duration ~= -1 and last_timing < config.min_duration then
          table.insert(diagnostics, {
            lnum = last_timing_k - 1,
            col = 0,
            message = "Subtitle is too short"
          })
        end

        local dur_bar = ""

        if config.length then
          dur_bar = dur_bar .. extra_spaces .. " =  " .. fmt_s(last_timing)
        end

        if config.cps_warning and cps > config.max_cps then
          local percent = cps / config.max_cps * 100
          dur_bar = dur_bar .. string.format(cps_mark, percent)
        end

        local opts = {
          id = last_timing_k - 1,
          virt_text = { { dur_bar, "Srt" } },
          virt_text_pos = 'eol'
        }
        vim.api.nvim_buf_set_extmark(buf, nsid, last_timing_k - 1, 0, opts)

        state = State.index
        line_count = 0
        total_length = 0
      else
        local clean_s = remove_tags(v)
        total_length = total_length + clean_s:len()
        line_count = line_count + 1
      end
    end
  end

  if state == State.timing then
    table.insert(diagnostics, {
      lnum = #lines,
      col = 0,
      message = "Subtitle is not terminated"
    })
  end

  vim.diagnostic.set(nsid, buf, diagnostics, {})
end

function M.parse(lines)
  local state = State.index

  local subtitles = {}

  local next_subtitle = subtitle.Subtitle.blank()

  for k, v in ipairs(lines) do
    if state == State.index then
      if v == "" then
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

return M
