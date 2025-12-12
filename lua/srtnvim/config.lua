local c = require("srtnvim.constants")

local M = {}

---@class Config
---@field enabled boolean
---@field autofix_index boolean
---@field length boolean
---@field pause boolean
---@field pause_warning boolean
---@field overlap_warning boolean
---@field cps boolean
---@field cps_warning boolean
---@field cps_diagnostic boolean
---@field tack_enabled boolean
---@field min_pause number
---@field min_duration number
---@field max_duration number
---@field tack string
---@field tack_middle string
---@field tack_left? string
---@field tack_right? string
---@field max_length number
---@field max_length_sub number
---@field max_lines number
---@field max_cps number
---@field extra_spaces number
---@field split_mode SplitMode
---@field split_with_min_pause boolean
---@field fix_with_min_pause boolean
---@field fix_bad_min_pause boolean
---@field shift_ms number
---@field seek_while_paused boolean
---@field sync_mode SyncMode
---@field sync_mode_buf? SyncMode
---@field sync_jump_cur_window boolean
---@field upload_on_video_jump boolean
---@field add_at_seek boolean
---@field rules_by_line_count table


---@type Config
M.defaults = {
  enabled = true,
  autofix_index = true,
  length = true,
  pause = true, -- pause will still be shown if pause warning is shown
  pause_warning = true,
  overlap_warning = true,
  cps = false,
  cps_warning = true,
  cps_diagnostic = false,
  tack_enabled = true,
  min_pause = 100,
  min_duration = 1000,
  max_duration = -1,
  tack = ".",
  tack_middle = " ",
  max_length = 40,
  max_length_sub = -1,
  max_lines = -1,
  max_cps = 21,
  extra_spaces = 0,
  -- modes:
  -- "half" - split in half precisely
  -- "length" - allocate time based on the length of the resulting text
  split_mode = c.SPLIT_LENGTH,
  split_with_min_pause = true,
  -- whether fixing overlapping subtitles should add a minimum pause
  fix_with_min_pause = true,
  -- whether subtitles with a pause that is too short should also be fixed
  fix_bad_min_pause = true,
  shift_ms = 100,
  seek_while_paused = false,
  -- when to upload subtitles to VLC
  -- "never" - never
  -- "on_save" - when the buffer is saved
  -- "on_change" - when the buffer is changed
  sync_mode = c.SYNC_MODE_SAVE,
  sync_jump_cur_window = true,
  upload_on_video_jump = true,
  add_at_seek = true,
  rules_by_line_count = {},
}

---@type Config
local config = M.defaults

---@return Config
M.get_config = function()
  return config
end

---@param new_config Config
function M.set_config(new_config)
  config = new_config
  for _, rule_set in pairs(new_config.rules_by_line_count) do
    setmetatable(rule_set, { __index = new_config })
  end
end

--- Returns either the actual config, or a partial config
--- containing only relevant masked options
---@param cfg Config
---@param line_count integer
---@return Config
---@return boolean
function M.get_by_line_count(cfg, line_count)
  if not cfg.rules_by_line_count[line_count] then
    return cfg, false
  end
  return cfg.rules_by_line_count[line_count], true
end

return M
