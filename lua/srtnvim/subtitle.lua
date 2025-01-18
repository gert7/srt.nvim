local M = {}

local Subtitle = {
  line_pos = 0,
  index = 0,
  length_ms = 1000,
  line_lengths = { 40, 39 }
}

function Subtitle.create(line_pos, index, length_ms, line_lengths)
  local t = {
    line_pos = line_pos,
    index = index,
    length_ms = length_ms,
    line_lengths = line_lengths
  }
  setmetatable(t, { __index = Subtitle })
  return t
end

M.Subtitle = Subtitle

return M
