local vim = vim
local base64 = require("srtnvim.base64")
local config = require("srtnvim.config")
local get_subs = require("srtnvim.get_subs")
local subtitle = require("srtnvim.subtitle")
local util = require("srtnvim.util")

local M = {}

local REQUEST_TIMER = 200
local CURSOR_TIMER = 200

local function subtitle_track(xml)
  local pattern = "<category%sname='Stream%s(%d+)'>"

  local iter = string.gmatch(xml, pattern)

  local max = nil

  for d in iter do
    local track = tonumber(d)
    if not max or track > max then
      max = track
    end
  end

  return max
end

local function is_playing(xml)
  local pattern = "<state>(%a+)</state>"
  local state = string.gmatch(xml, pattern)()
  return state == "playing"
end

local function get_position(xml)
  local pattern = "<position>(%d+%.%d+)</position>"
  return tonumber(string.gmatch(xml, pattern)())
end

local function get_length(xml)
  local pattern = "<length>(%d+)</length>"
  return tonumber(string.gmatch(xml, pattern)())
end

--- Get the current position in milliseconds and the length of the video
local function get_pit(xml)
  local pos = get_position(xml)
  local len = get_length(xml)
  return len * pos * 1000, len
end

local ips = {}
local ports = {}
local passwords = {}

local function set_buf_credentials(buf, ip, port, password)
  ips[buf] = ip
  ports[buf] = port
  passwords[buf] = password
end

local function get_buf_credentials(buf)
  local ip = ips[buf]
  if ip then
    return {
      ip = ip,
      port = ports[buf],
      password = passwords[buf]
    }
  else
    return nil
  end
end

local function get_status_full(ip, port, password, req, callback)
  local client = vim.uv.new_tcp()
  client:connect(ip, port, function(err)
    if err then
      print("Error connecting to VLC: " .. err)
      return
    end

    local command = ""

    if req then
      command = "?command=" .. req
    end

    local auth = base64.encode(":" .. password)
    local req_full = "GET /requests/status.xml" .. command .. " HTTP/1.1\n"
    client:write(req_full
      .. "Host: " .. ip .. ":" .. port .. "\n"
      .. "Authorization: Basic " .. auth .. "\n"
      .. "User-Agent: curl/8.11.1\n"
      .. "Accept: */*\n\n")
    local result = ""
    client:read_start(function(err, chunk)
      if err then
        print("Error is " .. err)
      end
      if chunk then
        result = result .. chunk
        if string.find(chunk, "</root>") then
          client:shutdown()
          client:close()
          if callback then
            callback(result)
          end
        end
      else
        client:shutdown()
        client:close()
        if callback then
          callback(result)
        end
      end
    end)
  end)
end

local function get_status(credentials, req, callback)
  get_status_full(credentials.ip,
    credentials.port,
    credentials.password,
    req,
    callback)
end


local function video_connect(opts)
  local buf = vim.api.nvim_get_current_buf()
  local args = vim.split(opts.args, " ")
  local ip = "127.0.0.1"
  local port = 8080

  local password = args[1]
  if #args >= 2 then
    ip = args[2]
  end
  if #args >= 3 then
    port = args[3]
  end

  vim.cmd("write! /tmp/srtnvim.srt")

  get_status_full(ip, port, password, "addsubtitle&val=/tmp/srtnvim.srt", function(xml)
    vim.schedule(function()
      set_buf_credentials(buf, ip, port, password)
    end)
    local track = subtitle_track(xml)
    get_status({
      ip = ip,
      port = port,
      password = password
    }, "subtitle_track&val=" .. (track + 1), function()
      print("Subtitle track " .. track .. "set")
    end)
  end)
end

vim.api.nvim_create_user_command("SrtConnect", video_connect, { desc = "Connect to VLC", nargs = "+" })
vim.api.nvim_create_user_command("SrtVideoConnect", video_connect, { desc = "Connect to VLC", nargs = "+" })


local function upload_subtitle(buf)
  util.write_buffer_to_file(buf, "/tmp/srtnvim.srt")
  local credentials = get_buf_credentials(buf)
  if not credentials then
    return false
  end

  get_status(
    credentials,
    "addsubtitle&val=/tmp/srtnvim.srt",
    function(xml)
      set_buf_credentials(credentials.ip, credentials.port, credentials.password)
      local track = subtitle_track(xml)
      print(track)
      get_status(credentials, "subtitle_track&val=" .. (track + 1), function()
        print("Subtitle track " .. track .. "set")
      end)
    end)
  return true
end

local function get_data(buf)
  return {
    config = config.get_config(),
    buf = buf,
    line = vim.api.nvim_win_get_cursor(0)[1],
    col = vim.api.nvim_win_get_cursor(0)[2],
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
    credentials = get_buf_credentials(buf)
  }
end

local function define_video_command(name, func, options)
  local command = function(args)
    local buf = vim.api.nvim_get_current_buf()
    local data = get_data(buf)

    if not data.credentials then
      print("Not connected to a video")
      return
    end
    func(args, data)
  end
  vim.api.nvim_create_user_command(name, command, options)
end

define_video_command("SrtVideoPause", function(args, data)
  get_status(data.credentials, nil, function(xml)
    local playing = is_playing(xml)
    if playing then
      get_status(data.credentials, "pl_pause", function()
        print("Video paused")
      end)
    else
      print("Video already paused")
    end
  end)
end, { desc = "Pause the video" })

define_video_command("SrtVideoPlay", function(args, data)
  get_status(data.credentials, nil, function(xml)
    local playing = is_playing(xml)
    if not playing then
      get_status(data.credentials, "pl_pause", function()
        print("Video playing")
      end)
    else
      print("Video already playing")
    end
  end)
end, { desc = "Play the video" })

define_video_command("SrtVideoPlayToggle", function(args, data)
  get_status(data.credentials, nil, function(xml)
    local playing = is_playing(xml)
    get_status(data.credentials, "pl_pause", function()
      if playing then
        print("Video paused")
      else
        print("Video playing")
      end
    end)
  end)
end, { desc = "Play the video" })

define_video_command("SrtVideoJump", function(args, data)
  local subs, err = get_subs.parse(data.lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, data.line)
  local sub = subs[sub_i]

  local seconds = math.floor(sub.start_ms / 1000)

  if data.config.upload_on_video_jump then
    -- print("Uploaded")
    upload_subtitle(data.buf)
  end

  get_status(data.credentials, "seek&val=" .. seconds, function()
    print("Jumped to " .. seconds .. " seconds")
  end)
end, { desc = "Seek the video to the subtitle under the cursor (affects video)" })


local timers = {}


local function clear_timers(buf)
  if timers[buf] then
    for _, timer in ipairs(timers[buf]) do
      timer:stop()
    end
    timers[buf] = nil
    return true
  end
  return false
end

local pits = {}
local playings = {}

define_video_command("SrtVideoTrack", function(args, data)
  if clear_timers(data.buf) then
    pits[data.buf] = -1
    playings[data.buf] = false
    return
  end

  pits[data.buf] = -1
  playings[data.buf] = false

  local timer = vim.uv.new_timer()
  local cursor_timer = vim.uv.new_timer()
  timers[data.buf] = { timer, cursor_timer }

  local function start_req_timer()
    timer:start(REQUEST_TIMER, 0, vim.schedule_wrap(function()
      timer:stop()
      get_status(data.credentials, nil, function(xml)
        local success, pos = pcall(get_position, xml) -- ????
        if not success then
          print("Error getting position")
          return
        end
        local len = get_length(xml)
        -- local point = math.floor(len * pos)
        local point = len * pos
        vim.schedule(function()
          pits[data.buf] = point * 1000
          playings[data.buf] = is_playing(xml)
        end)
        start_req_timer()
      end)
    end))
  end

  local function start_cursor_timer()
    cursor_timer:start(CURSOR_TIMER, 0, vim.schedule_wrap(function()
      cursor_timer:stop()
      if get_buf_credentials(data.buf) == nil then
        return
      end
      local pit = pits[data.buf]
      local playing = playings[data.buf]
      local cur_buf = vim.api.nvim_get_current_buf()
      if cur_buf == data.buf and pit ~= -1 and (data.config.seek_while_paused or playing) then
        local new_data = get_data(data.buf)
        local subs, err = get_subs.parse(new_data.lines)
        if err or not subs then
          get_subs.print_err(err)
          return
        end
        local sub_i = get_subs.find_subtitle_by_ms(subs, pit)
        local sub = subs[sub_i]
        local line = sub.line_pos + 2
        if line > #new_data.lines then
          line = #new_data.lines
        end
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        vim.cmd("normal! zz")
      end
      start_cursor_timer()
    end))
  end

  start_req_timer()
  start_cursor_timer()
end, { desc = "Toggle following the current subtitle in the buffer (affects text editor)" })

define_video_command("SrtVideoUpload", function(args, data)
  upload_subtitle(data.buf)
end, { desc = "Upload subtitles to VLC" })

define_video_command("SrtVideoDisconnect", function(args, data)
  set_buf_credentials(data.buf, nil, nil, nil)
end, { desc = "Disconnect from VLC" })

define_video_command("SrtVideoSetTime", function(args, data)
  -- set time under cursor to current point in video
  local subs, err = get_subs.parse(data.lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, data.line)

  if not sub_i then
    print("Not in a subtitle")
    return
  end

  local sub = subs[sub_i]
  if data.line ~= sub.line_pos + 1 then
    print("Not on duration line")
    return
  end

  local side

  if data.col >= 0 and data.col <= 12 then
    side = "start"
  elseif data.col >= 16 and data.col <= 28 then
    side = "end"
  else
    print("Hover over start or end time to shift")
    return
  end

  get_status(data.credentials, nil, function(xml)
    local new_ms = get_pit(xml)
    if new_ms < 0 then
      print("Error getting position")
      return
    end
    if side == "start" then
      local new_timing = subtitle.amend_start(data.lines[sub.line_pos + 1], new_ms)
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(
          data.buf,
          sub.line_pos,
          sub.line_pos + 1,
          false,
          { new_timing }
        )
      end)
    else
      local new_timing = subtitle.amend_end(data.lines[sub.line_pos + 1], new_ms)
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(
          data.buf,
          sub.line_pos,
          sub.line_pos + 1,
          false,
          { new_timing }
        )
      end)
    end
  end)
end, { desc = "Set start or end of a subtitle to the current time in the video" })

function M.notify_update(buf)
  return upload_subtitle(buf)
end

function M.get_pit(buf, callback)
  local data = get_data(buf)
  if data.credentials then
    get_status(data.credentials, nil, function(xml)
      local pit = get_pit(xml)
      callback(pit)
    end)
  else
    callback(nil)
  end
end

return M
