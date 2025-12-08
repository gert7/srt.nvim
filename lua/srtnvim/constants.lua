local M = {}

M.SPLIT_HALF = "half"
M.SPLIT_LENGTH = "length"

---@enum SplitMode
M.SPLIT_MODE = {
    SPLIT_HALF = M.SPLIT_HALF,
    SPLIT_LENGTH = M.SPLIT_LENGTH
}

M.SYNC_MODE_NEVER = "never"
M.SYNC_MODE_SAVE = "on_save"
M.SYNC_MODE_CHANGE = "on_change"
M.SYNC_MODE_MOVE = "on_move"

---@enum SyncMode
M.SYNC_MODE = {
    SYNC_MODE_NEVER = M.SYNC_MODE_NEVER,
    SYNC_MODE_SAVE = M.SYNC_MODE_SAVE,
    SYNC_MODE_CHANGE = M.SYNC_MODE_CHANGE,
    SYNC_MODE_MOVE = M.SYNC_MODE_MOVE
}

M.ADD_AFTER = "after"
M.ADD_VIDEO = "video"

---@enum AddMode
M.ADD_MODE = {
    ADD_MODE_AFTER = M.ADD_AFTER,
    ADD_MODE_VIDEO = M.ADD_VIDEO,
}

return M
