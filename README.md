# srt.nvim

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/N4N116CYI2)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Edit SubRip subtitles in NeoVim.

## Features

### Passive features

- Durations and pauses visible
- Characters per second warning
- Warnings for durations too long, too short, overlapping
- Warnings for pauses being too short
- Automatically corrects indices after edit

### Commands

- `SrtJump` - jump cursor to subtitle by index
- `SrtMerge` - merge subtitles, with optional range selection
- `SrtSplit` - split subtitles into two
- `SrtSort` - sort subtitles by start time
- `SrtFixTiming` - fix overlapping timings if possible
- `SrtFixTimingAll` - fix all overlapping timings
- `SrtShift` - shift an entire subtitle by a given offset, with optional range
selection
- `SrtShiftAll` - shift all subtitles by a given offset
- `SrtAdd` - add a subtitle
- `SrtShiftTime` - shift the beginning or end time of a duration (based on 
cursor position)
- `SrtEnforce` - enforce a subtitle's beginning or end (based on cursor
position)
  - On the start time, the end time of the previous subtitle will be pushed
  backward in time until min_pause is reached
  - On the end time, the start time of the next subtitle will be pushed
  forward in time until min_pause is reached
- `SrtShiftTimeStrict` - shift the beginning or end time of a duration and
enforce it on adjacent subtitles. A combination of `SrtShiftTime` and
`SrtEnforce`

### Video commands

srt.nvim can connect to VLC Media Player and automatically upload the current
subtitles on save or on edit.

- `SrtConnect` - connect to VLC via the HTTP interface, with password. The
interface can be enabled in VLC from Preferences -> Show settings: All -> Main
interfaces, and the password can be set from Main interfaces -> Lua
- `SrtVideoPause` - pause the video
- `SrtVideoPlay` - resume the video
- `SrtVideoPlayToggle` - play/pause the video
- `SrtVideoJump` - seek the video in the player to the subtitle under the cursor
- `SrtVideoTrack` - automatically move the cursor to the current subtitle when
the video is seeking or playing
- `SrtSetVideoTime` - set start or end of a subtitle to the current time in the video (based on
cursor position)

### Window sync

srt.nvim can also synchronize two windows marked with the `SrtSyncWindow`
command, moving the cursor and centering all other marked windows to the
subtitle that best matches with the current time. This is useful for keeping a
translation open in another window.

## Installation 

Lazy
```lua
{
  "gert7/srt.nvim", 
  branch = "main",
}
```

Plug
```lua
Plug "gert7/srt.nvim" , { 'branch': 'main' }
```

Vundle
```lua
Plugin 'gert7/srt.nvim', { 'branch': 'main' }
```

## Configuration

| Setting              | Default   | Description                                        |
| -------------------- | --------- | -------------------------------------------------- |
| enabled              | true      | Passive features (HUD)                             |
| autofix_index        | true      | Automatically fix indices after edit               |
| length               | true      | Show subtitle duration                             |
| pause                | true      | Show pause duration                                |
| pause_warning        | true      | Warn if pause too short                            |
| overlap_warning      | true      | Warn if subtitle timings overlap                   |
| cps                  | false     | Always show characters per second %                |
| cps_warning          | true      | Show characters per second % if over CPS           |
| cps_diagnostic       | false     | Treat being over-CPS as an error                   |
| tack_enabled         | true      | Show pause indicators between subtitles            |
| min_pause            | 100       | Minimum pause between subtitles                    |
| min_duration*        | 1000      | Minimum duration for one subtitle                  |
| max_duration*        | -1        | Maximum duration                                   |
| tack                 | "."       | Character to use for the tack indicators           |
| tack_middle          | " "       | Character filling the area between tacks           |
| tack_left            | N/A       | Left-side tack override                            |
| tack_right           | N/A       | Right-side tack override                           |
| max_length*          | 40        | Maximum characters per line                        |
| max_length_sub*      | -1        | Maximum characters per subtitle                    |
| max_lines            | -1        | Maximum number of lines                            |
| max_cps              | 21        | Maximum characters per second                      |
| extra_spaces         | 0         | Added distance from subtitles to HUD               |
| split_mode           | "length"  | Mode to use for SrtSplit                           |
| split_with_min_pause | true      | Add min_pause when splitting                       |
| fix_with_min_pause   | true      | Add min_pause when fixing timings                  |
| fix_bad_min_pause    | true      | Fix non-overlapping subtitles if pause < min_pause |
| shift_ms             | 100       | SrtShiftTime default shift                         |
| seek_while_paused    | true      | Seek if video is paused for SrtVideoTrack          |
| sync_mode            | "on_save" | When to upload subtitles to VLC                    |
| sync_mode_buf        | N/A       | Override for when to sync when using SrtSyncWindow |
| upload_on_video_jump | true      | Upload subtitles to video on SrtVideoJump          |

Options marked with * can also be specified under `rules_by_line_count`

The options for `split_mode` are:
- "half" - exact split, not based on character count
- "length" - split time allocated on character count

The options for `sync_mode` are:
- "never" - never upload to VLC automatically (use `SrtVideoUpload` instead)
- "on_save" - upload after save
- "on_change" - upload after change

### Example configuration

A call to `setup` is required for configuring srt.nvim.

Note that you can also specify some rules based on line count:

```lua
require("srtnvim").setup({
  min_pause = 80,
  max_lines = 2,
  rules_by_line_count = {
    [1] = {
      max_duration = 3000,
      max_length = 40
    },
    [2] = {
      max_length = 50
    }
  }
})
```

### Example keymap configuration

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "srt",
  callback = function()
    -- set colorcolumn to 40, you don't need a plugin for this
    -- vim.opt_local.colorcolumn = "40"
    vim.keymap.set("n", "K", function()
      vim.cmd("SrtVideoJump")
    end, {silent = true})

    vim.keymap.set("n", "<C-space>", function()
      vim.cmd("SrtVideoPlayToggle")
    end, {silent = true})

    vim.keymap.set("n", "<C-j>", function()
      vim.cmd("SrtShiftTime -100")
    end, {silent = true})

    vim.keymap.set("n", "<C-k>", function()
      vim.cmd("SrtShiftTime 100")
    end, {silent = true})
  end,
})
```
