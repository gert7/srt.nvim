local M = {}

M.get_config = function()
  return {}
end

function M.set_config(config_fn)
  M.get_config = config_fn
  local config = config_fn()
  for _, v in pairs(config.rules_by_line_count) do
    v.min_duration = v.min_duration or config.min_duration
    v.max_duration = v.max_duration or config.max_duration
    v.max_length = v.max_length or config.max_length
    v.max_length_sub = v.max_length_sub or config.max_length_sub
  end
end

function M.get_by_line_count(cfg, line_count)
  if not cfg.rules_by_line_count[line_count] then
    return cfg, false
  end
  return cfg.rules_by_line_count[line_count], true
end

return M
