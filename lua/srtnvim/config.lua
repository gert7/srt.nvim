local M = {}

M.get_config = function()
  return {}
end

function M.set_config(cfg)
  M.get_config = cfg
end

return M
