local vim = vim
local c = require("srtnvim.constants")
local commands = require("srtnvim.commands")
local get_subs = require("srtnvim.get_subs")
local shared_config = require("srtnvim.config")
local video = require("srtnvim.video")
local win_sync = require("srtnvim.win_sync")

local M = {}

local defaults = {
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
  seek_while_paused = true,
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

local config = vim.tbl_deep_extend("keep", defaults, {})

local data = {}

local function get_config()
  return config
end

function M.setup(user_opts)
  config = vim.tbl_deep_extend("force", defaults, user_opts or {})
  data = {
    pause_lines = get_subs.preproduce_pause_lines(config)
  }
  shared_config.set_config(get_config)

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

vim.api.nvim_create_user_command("SrtToggle", function()
  config.enabled = not config.enabled
  local in_srt_file = "Note: not currently editing a SubRip file."
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_option(buf, "filetype") == "srt" then
      in_srt_file = ""
      get_subs.annotate_subs(buf, config, data)
    end
  end
  if config.enabled then
    print("Srtnvim is now enabled. " .. in_srt_file)
  else
    print("Srtnvim is now disabled. " .. in_srt_file)
  end
end, { desc = "Toggle Srtnvim on or off" })

local augroup = vim.api.nvim_create_augroup("SrtauGroup", { clear = true })

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
    get_subs.annotate_subs(ev.buf, config, data, false)
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
    if config.sync_mode == c.SYNC_MODE_SAVE then
      video.notify_update(ev.buf)
    end
    notify_win_sync(config, c.SYNC_MODE_SAVE)
  end
})

vim.api.nvim_create_autocmd({ "CursorMoved" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    if config.sync_mode == c.SYNC_MODE_MOVE then
      video.notify_update(ev.buf)
    end
    notify_win_sync(config, c.SYNC_MODE_MOVE)
  end
})

M.parse = get_subs.parse

return M
