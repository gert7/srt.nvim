local vim = vim
local c = require("srtnvim.constants")
local commands = require("srtnvim.commands")
local get_subs = require("srtnvim.get_subs")
local shared_config = require("srtnvim.config")
local video = require("srtnvim.video")
local win_sync = require("srtnvim.win_sync")

local M = {}

local defaults = shared_config.defaults

---@type Config
local config = vim.tbl_deep_extend("keep", defaults, {})

---@class SetupData
---@field pause_lines? string[]

---@type SetupData
local data = {}

---@param user_opts Config
function M.setup(user_opts)
  config = vim.tbl_deep_extend("force", defaults, user_opts or {})
  data = {
    pause_lines = get_subs.preproduce_pause_lines(config)
  }
  shared_config.set_config(config)

  if config.split_mode ~= c.SPLIT_HALF and
      config.split_mode ~= c.SPLIT_LENGTH then
    print("srt.nvim configuration error: Unknown split mode '" .. config.split_mode .. "'")
  end

  if config.sync_mode ~= c.SYNC_MODE_NEVER and
      config.sync_mode ~= c.SYNC_MODE_SAVE and
      config.sync_mode ~= c.SYNC_MODE_CHANGE and
      config.sync_mode ~= c.SYNC_MODE_MOVE then
    print("srt.nvim configuration error: Unknown sync mode '" .. config.sync_mode .. "'")
  end
end

local function get_boolean_config_keys()
  local keys = {}
  for k, v in pairs(defaults) do
    if type(v) == "boolean" then
      table.insert(keys, k)
    end
  end
  table.sort(keys)
  return keys
end

vim.api.nvim_create_user_command("SrtToggle", function(opts)
    local setting = opts.args
    if setting == "" then
      setting = "enabled"
    end

    if type(config[setting]) ~= "boolean" then
      print("Srt.nvim: Cannot toggle non-boolean or unknown setting '" .. setting .. "'")
      return
    end

    config[setting] = not config[setting]

    local in_srt_file = "Note: not currently editing a SubRip file."
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_option(buf, "filetype") == "srt" then
        in_srt_file = ""
        get_subs.annotate_subs(buf, config, data)
      end
    end

    local new_state = config[setting] and "enabled" or "disabled"
    if setting == "enabled" then
      print("Srt.nvim is now " .. new_state .. ". " .. in_srt_file)
    else
      print("Srt.nvim: Toggled '" .. setting .. "' to " .. new_state .. ". " .. in_srt_file)
    end
  end,
  {
    desc = "Toggle Srtnvim or a specific boolean setting on or off",
    nargs = "?",
    complete = function()
      return get_boolean_config_keys()
    end
  }
)

local augroup = vim.api.nvim_create_augroup("SrtauGroup", { clear = true })

---@param cfg Config
---@param instance SyncMode
local function notify_win_sync(cfg, instance)
  local sync_mode = cfg.sync_mode_buf or cfg.sync_mode
  if sync_mode == instance then
    win_sync.notify_update()
  end
end

vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufEnter" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    if config.autofix_index then
      commands.fix_indices_buf(ev.buf)
    end
    get_subs.annotate_subs(ev.buf, config, data)
    if config.sync_mode == c.SYNC_MODE_CHANGE then
      video.notify_update(ev.buf)
    end
    notify_win_sync(config, c.SYNC_MODE_CHANGE)
  end
})

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    if config.sync_mode == c.SYNC_MODE_SAVE or
        config.sync_mode == c.SYNC_MODE_MOVE then
      video.notify_update(ev.buf)
    end
    notify_win_sync(config, c.SYNC_MODE_SAVE)
  end
})

vim.api.nvim_create_autocmd({ "CursorMoved" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    -- if config.sync_mode == c.SYNC_MODE_MOVE then
    --  video.notify_update(ev.buf)
    -- end
    notify_win_sync(config, c.SYNC_MODE_MOVE)
  end
})

M.parse = get_subs.parse

return M
