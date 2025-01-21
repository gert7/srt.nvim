local M = {}

local Subtitle = {
  line_pos = 0,
  index = 0,
  start_ms = 0,
  end_ms = 0,
  length_ms = 0,
  line_lengths = { 0, 0 },
}

function Subtitle.create(line_pos, index, length_ms, line_lengths, start_ms, end_ms)
  local t = {
    line_pos = line_pos,
    index = index,
    start_ms = start_ms,
    end_ms = end_ms,
    length_ms = length_ms,
    line_lengths = line_lengths
  }
  setmetatable(t, { __index = Subtitle })
  return t
end

function Subtitle.blank() return Subtitle.create(0, 0, 0, {}, 0, 0) end

function M.to_ms(h, m, s, mi)
  return mi + s * 1000 + m * 60000 + h * 3600000
end

function M.from_ms(ms)
  local h = math.floor(ms / 3600000)
  ms = ms - h * 3600000
  local m = math.floor(ms / 60000)
  ms = ms - m * 60000
  local s = math.floor(ms / 1000)
  ms = ms - s * 1000
  return h, m, s, ms
end

M.Subtitle = Subtitle

return M
