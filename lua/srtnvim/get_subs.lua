local M = {}

-- local Subtitle = require('subtitle').Subtitle

local State = {
  index = 1,
  timing = 2,
  subtitle = 3
}

local function pad_left(s, c, n)
  return string.rep(c, n - #s) .. s
end

local function fmt_s(ms)
  local timing_milli = ms % 1000
  local timing_secs = (ms - timing_milli) / 1000

  local tm_padded = pad_left(tostring(timing_milli), "0", 3)
  return string.format("%d.%ss", timing_secs, tm_padded)
end

local matcher = "(%d%d):(%d%d):(%d%d),(%d%d%d)%s%-%->%s(%d%d):(%d%d):(%d%d),(%d%d%d)"

function M.preproduce_pause_lines(config)
  local tl = config.tackle_left or config.tackle or "."
  local tr = config.tackle_right or config.tackle or "."
  local tm = config.tackle_middle or " "
  local pause_lines = {}

  local function format(sample)
    return (sample:gsub("%.", tl):gsub(",", tm):gsub(":", tr))
  end

  local sample1 = "                .:               (%s)"
  local sample2 = "               .,,:              (%s)"
  local sample3 = "              .,,,,:             (%s)"
  local sample4 = "             .,,,,,,:            (%s)"
  local sample5 = "            .,,,,,,,,:           (%s)"
  table.insert(pause_lines, format(sample1))
  table.insert(pause_lines, format(sample2))
  table.insert(pause_lines, format(sample3))
  table.insert(pause_lines, format(sample4))
  table.insert(pause_lines, format(sample5))
  return pause_lines
end

local function get_pause_line(pause, config, pause_lines)
  if pause < config.min_pause then
    return pause_lines[1]
  elseif pause >= config.min_pause and pause < 1000 then
    return pause_lines[2]
  elseif pause >= 1000 and pause < 2000 then
    return pause_lines[3]
  elseif pause >= 2000 and pause < 10000 then
    return pause_lines[4]
  else
    return pause_lines[5]
  end
end

function M.get_subs(buf, lines, config, data)
  local state = State.index

  local nsid = vim.api.nvim_create_namespace("srtsubdiag")

  vim.api.nvim_buf_clear_namespace(buf, nsid, 0, -1)

  local diagnostics = {}

  local last_end = 0
  local cur_start = 0
  local cur_end = 0

  local line_count = 0
  local last_timing = 0
  local last_lengths = {}
  local total_length = 1
  local last_timing_k = 0

  local start = vim.loop.hrtime()

  for k, v in ipairs(lines) do
    if state == State.index and v ~= "" then
      local n = tonumber(v)
      if not n then
        table.insert(diagnostics, {
          lnum = k,
          col = 0,
          message = "Error reading line number!"
        })
        vim.diagnostic.set(nsid, buf, diagnostics, {})
        return
      end
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

      local last_f = f_mi + f_s * 1000 + f_m * 60000 + f_h * 3600000
      local last_t = t_mi + t_s * 1000 + t_m * 60000 + t_h * 3600000
      last_timing = last_t - last_f

      last_end = cur_end
      cur_start = last_f
      cur_end = last_t

      local pause = cur_start - last_end

      if k - 3 > 0 then
        local opts = {
          id = k - 3,
          virt_text = { { string.format(get_pause_line(pause, config, data.pause_lines), fmt_s(pause)), "Srt" } },
          virt_text_pos = 'eol'
        }
        local mark_id = vim.api.nvim_buf_set_extmark(buf, nsid, k - 3, 0, opts)
        if pause < 0 then
          table.insert(diagnostics, {
            lnum = k - 3,
            col = 0,
            message = "Subtitle overlaps with previous subtitle!"
          })
        elseif pause < config.min_pause then
          table.insert(diagnostics, {
            lnum = k - 3,
            col = 0,
            message = "Pause is too short!"
          })
        end
      end
      state = State.subtitle
    elseif state == State.subtitle then
      v = v:gsub("^%s*(.-)%s*$", "%1")
      if v == "" then
        local mpc = last_timing / total_length

        local opts = {
          id = last_timing_k,
          virt_text = { { string.format(" =  %s [%d]", fmt_s(last_timing), mpc), "Srt" } },
          virt_text_pos = 'eol'
        }
        local mark_id = vim.api.nvim_buf_set_extmark(buf, nsid, last_timing_k - 1, 0, opts)

        state = State.index
        line_count = 0
        last_lengths = {}
        total_length = 1
      else
        table.insert(last_lengths, v:len())
        total_length = total_length + v:len()
        line_count = line_count + 1
      end
    end
  end

  local elapsed = vim.loop.hrtime() - start
  print(string.format("Elapsed time: %dmicros", elapsed / 1000))

  vim.diagnostic.set(nsid, buf, diagnostics, {})
end

return M
