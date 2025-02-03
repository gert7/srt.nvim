local vim = vim
local shared_config = require("srtnvim.config")
local get_subs = require("srtnvim.get_subs")
local commands = require("srtnvim.commands")
local video = require("srtnvim.video")

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
  tackle_enabled = true,
  min_pause = 100,
  min_duration = 1000,
  max_duration = -1,
  tackle = ".",
  tackle_middle = " ",
  max_length = 40,
  max_length_sub = -1,
  max_cps = 21,
  extra_spaces = 0,
  -- modes:
  -- "half" - split in half precisely
  -- "length" - allocate time based on the length of the resulting text
  split_mode = "length",
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
  sync_mode = "on_save",
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

vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufEnter" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    if config.autofix_index then
      commands.fix_indices_buf(ev.buf)
    end
    get_subs.annotate_subs(ev.buf, config, data, false)
    if config.sync_mode == "on_change" then
      video.notify_update(ev.buf)
    end
  end
})

vim.api.nvim_create_autocmd({ "BufWritePost" }, {
  group = augroup,
  pattern = { "*.srt" },
  callback = function(ev)
    if config.sync_mode == "on_save" then
      video.notify_update(ev.buf)
    end
  end
})

M.parse = get_subs.parse

return M
