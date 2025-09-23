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
---@field sync_jump_cur_window boolean
---@field upload_on_video_jump boolean
---@field add_at_seek boolean
---@field rules_by_line_count table

---@return Config
M.get_config = function()
  return {}
end

---@param config_fn fun(): Config
function M.set_config(config_fn)
  M.get_config = config_fn
  local config = config_fn()
  for _, rule_set in pairs(config.rules_by_line_count) do
    setmetatable(rule_set, { __index = config })
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
