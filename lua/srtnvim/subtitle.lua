local M = {}

---@class Subtitle
---@field line_pos integer
---@field index integer
---@field start_ms integer
---@field end_ms integer
---@field length_ms integer
---@field line_lengths integer[]
local Subtitle = {
  line_pos = 0,
  index = 0,
  start_ms = 0,
  end_ms = 0,
  length_ms = 0,
  line_lengths = { 0, 0 },
}

---@param line_pos integer
---@param index integer
---@param length_ms integer
---@param line_lengths integer[]
---@param start_ms integer
---@param end_ms integer
---@return Subtitle
function Subtitle.create(line_pos, index, length_ms, line_lengths, start_ms, end_ms)
  local t = {
    line_pos = line_pos,
    index = index,
    start_ms = start_ms,
    end_ms = end_ms,
    length_ms = length_ms,
    line_lengths = line_lengths
  }
  -- setmetatable(t, { __index = Subtitle })
  return t
end

function Subtitle.blank() return Subtitle.create(0, 0, 0, {}, 0, 0) end

---@param h integer
---@param m integer
---@param s integer
---@param mi integer
---@return integer
function M.to_ms(h, m, s, mi)
  return mi + s * 1000 + m * 60000 + h * 3600000
end

---@param ms integer
---@return integer
---@return integer
---@return integer
---@return integer
function M.from_ms(ms)
  local h = math.floor(ms / 3600000)
  ms = ms - h * 3600000
  local m = math.floor(ms / 60000)
  ms = ms - m * 60000
  local s = math.floor(ms / 1000)
  ms = ms - s * 1000
  return h, m, s, ms
end

---@param h integer
---@param m integer
---@param s integer
---@param mi integer
---@return string
function M.make_dur(h, m, s, mi)
  return string.format("%02d:%02d:%02d,%03d", h, m, s, mi)
end

---@param ms number
---@return string
function M.make_dur_ms(ms)
  local h, m, s, mi = M.from_ms(ms)
  return M.make_dur(h, m, s, mi)
end

---@param f_h integer
---@param f_m integer
---@param f_s integer
---@param f_mi integer
---@param t_h integer
---@param t_m integer
---@param t_s integer
---@param t_mi integer
---@return string
function M.make_dur_full(f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
  return string.format("%02d:%02d:%02d,%03d --> %02d:%02d:%02d,%03d",
    f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
end

---@param f_ms integer
---@param t_ms integer
---@return string
function M.make_dur_full_ms(f_ms, t_ms)
  local f_h, f_m, f_s, f_mi = M.from_ms(f_ms)
  local t_h, t_m, t_s, t_mi = M.from_ms(t_ms)
  return M.make_dur_full(f_h, f_m, f_s, f_mi, t_h, t_m, t_s, t_mi)
end

---Edit the start time of a duration line.
---@param line string
---@param new_ms integer
---@return string
function M.amend_start(line, new_ms)
  local end_time = line:sub(13, 29)
  local start_time = M.make_dur_ms(new_ms)
  return start_time .. end_time
end

---Edit the end time of a duration line.
---@param line string
---@param new_ms integer
---@return string
function M.amend_end(line, new_ms)
  local start_time = line:sub(1, 17)
  local end_time = M.make_dur_ms(new_ms)
  return start_time .. end_time
end

M.Subtitle = Subtitle

return M
