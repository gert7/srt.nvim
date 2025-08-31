local vim = vim
local commands = require('srtnvim.commands')
local get_config = require("srtnvim.config")
local get_subs = require('srtnvim.get_subs')

local M = {}

local sync_wins = {}

function M.notify_update()
  local config = get_config.get_config()

  local cur_win = vim.api.nvim_get_current_win()
  if not sync_wins[cur_win] then
    return
  end

  local cur_buf = vim.api.nvim_win_get_buf(cur_win)
  local data = get_subs.get_data(cur_buf)
  local subs, err = get_subs.parse(data.lines)
  if err or not subs then
    print("get_subs error in window " .. cur_win)
    return
  end

  local sub_i = get_subs.find_subtitle(subs, data.line)
  if not sub_i then
    return
  end

  local sub = subs[sub_i]
  local start_ms = sub.start_ms

  local orig_win = vim.api.nvim_get_current_win()
  local wins = vim.api.nvim_list_wins()
  for _, win in ipairs(wins) do
    if win ~= orig_win and sync_wins[win] then
      local buf = vim.api.nvim_win_get_buf(win)
      local buf_data = get_subs.get_data(buf)
      local buf_subs, buf_err = get_subs.parse(buf_data.lines)
      if buf_err or not buf_subs then
        print("Subordinate window parsing error in window " .. win)
        return
      end

      local buf_sub_i = get_subs.find_subtitle_by_ms(buf_subs, start_ms)
      if not buf_sub_i then
        print("Unable to find subtitle by ms in window " .. win)
        return
      end

      local buf_sub = buf_subs[buf_sub_i]
      local buf_line = buf_sub.line_pos

      if buf_line ~= buf_data.line then
        vim.api.nvim_win_set_cursor(win, { buf_line, 0 })
        vim.api.nvim_set_current_win(win)
        vim.cmd("normal! zz")
        vim.api.nvim_set_current_win(orig_win)
      end
    end
  end

  if config.sync_jump_cur_window then
    vim.cmd("normal! zz")
  end
end

commands.define_command("SrtSyncWindow", function (args, data)
  local win = vim.api.nvim_get_current_win()
  local new_val = not sync_wins[win]
  sync_wins[win] = new_val
  if new_val then
    print("Window " .. win .. " tracking subtitle")
  else
    print("Window " .. win .. " no longer tracking subtitle")
  end
end, { desc = "Toggle .srt window mark for synchronization" })

return M
