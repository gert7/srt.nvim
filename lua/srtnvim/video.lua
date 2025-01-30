local vim = vim
local uv = vim.uv
local base64 = require("srtnvim.base64")
local get_subs = require("srtnvim.get_subs")

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

local function set_buf_credentials(ip, port, password)
  vim.b.srtnvim_vlc_ip = ip
  vim.b.srtnvim_vlc_port = port
  vim.b.srtnvim_vlc_password = password
end

local function get_buf_credentials()
  if not vim.b.srtnvim_vlc_ip then
    return nil
  end
  return {
    ip = vim.b.srtnvim_vlc_ip,
    port = vim.b.srtnvim_vlc_port,
    password = vim.b.srtnvim_vlc_password
  }
end

local function get_status_full(ip, port, password, req, callback)
  local client = uv.new_tcp()
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
    local req = "GET /requests/status.xml" .. command .. " HTTP/1.1\n"
    -- print(req)
    client:write(req)
    client:write("Host: " .. ip .. ":" .. port .. "\n")
    client:write("Authorization: Basic " .. auth .. "\n")
    client:write("User-Agent: curl/8.11.1\n")
    client:write("Accept: */*\n")
    client:write("\n")
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

vim.api.nvim_create_user_command("SrtConnect", function(opts)
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
  
  get_status_full(ip, port, password, "addsubtitle&val=/tmp/srtnvim.srt", function(result)
    print("Subtitle added")
    
    set_buf_credentials(ip, port, password)
    local track = subtitle_track(result)
    print(track)
    get_status(get_buf_credentials(), "subtitle_track&val=" .. (track + 1), function()
      print("Subtitle track " .. track .. "set")
    end)
  end)
end, { desc = "Connect to VLC", nargs = "+" })

local function upload_subtitle(credentials)
  vim.cmd("write! /tmp/srtnvim.srt")
  
  get_status(
  credentials,
  "addsubtitle&val=/tmp/srtnvim.srt",
  function(result)
    set_buf_credentials(credentials.ip, credentials.port, credentials.password)
    local track = subtitle_track(result)
    print(track)
    get_status(credentials, "subtitle_track&val=" .. (track + 1), function()
      print("Subtitle track " .. track .. "set")
    end)
  end)
end

vim.api.nvim_create_user_command("SrtVideoPause", function()
  local credentials = get_buf_credentials()
  if not credentials then
    print("Not connected to a video")
    return
  end
  
  get_status(credentials, nil, function(xml)
    local playing = is_playing(xml)
    if playing then
      get_status(credentials, "pl_pause", function()
        print("Video paused")
      end)
    else
      print("Video already paused")
    end
  end)
end, { desc = "Pause the video" })

vim.api.nvim_create_user_command("SrtVideoPlay", function()
  local credentials = get_buf_credentials()
  if not credentials then
    print("Not connected to a video")
    return
  end
  
  get_status(credentials, nil, function(xml)
    local playing = is_playing(xml)
    if not playing then
      get_status(credentials, "pl_pause", function()
        print("Video playing")
      end)
    else
      print("Video already playing")
    end
  end)
end, { desc = "Play the video" })

vim.api.nvim_create_user_command("SrtVideoPlayToggle", function()
  local credentials = get_buf_credentials()
  if not credentials then
    print("Not connected to a video")
    return
  end
  
  get_status(credentials, nil, function(xml)
    local playing = is_playing(xml)
    get_status(credentials, "pl_pause", function()
      if playing then
        print("Video paused")
      else
        print("Video playing")
      end
    end)
  end)
end, { desc = "Play the video" })

vim.api.nvim_create_user_command("SrtVideoJump", function()
  local credentials = get_buf_credentials()
  if not credentials then
    print("Not connected to a video")
    return
  end
  
  local buf = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local subs, err = get_subs.parse(lines)
  if err or not subs then
    get_subs.print_err(err)
    return
  end
  local sub_i = get_subs.find_subtitle(subs, line)
  local sub = subs[sub_i]
  
  local seconds = math.floor(sub.start_ms / 1000)
  
  get_status(credentials, "seek&val=" .. seconds, function()
    print("Jumped to " .. seconds .. " seconds")
  end)
end, { desc = "Jump to a specific time in the video" })
