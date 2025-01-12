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

function M.get_subs(buf, lines)
  local state = State.index

  local nsid = vim.api.nvim_create_namespace("srtsubdiag")

  vim.api.nvim_buf_clear_namespace(buf, nsid, 0, -1)

  local diagnostics = {}

  local last_end = 0
  local cur_start = 0
  local cur_end = 0

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
        
      local last_f = f_mi + f_s * 1000 + f_m * 60000 + f_h * 3600000
      local last_t = t_mi + t_s * 1000 + t_m * 60000 + t_h * 3600000
      local timing = last_t - last_f

      local opts = {
        id = k,
        virt_text = {{string.format(" =  %s", fmt_s(timing)), "Srt"}},
        virt_text_pos = 'eol'
      }
      local mark_id = vim.api.nvim_buf_set_extmark(buf, nsid, k - 1, 0, opts)

      last_end = cur_end
      cur_start = last_f
      cur_end = last_t

      local distance = cur_start - last_end

      if k - 3 > 0 then
        local opts = {
          id = k - 2,
          virt_text = {{string.format("                                 (%s)", fmt_s(distance)), "Srt"}},
          virt_text_pos = 'eol'
        }
        local mark_id = vim.api.nvim_buf_set_extmark(buf, nsid, k - 3, 0, opts)
      end
      state = State.subtitle
    elseif state == State.subtitle then
      if v == "" then
        state = State.index
      end
    end
  end

  vim.diagnostic.set(nsid, buf, diagnostics, {})
end

return M
