-- ====================================================================
-- Editor/History.lua — 撤销/重做系统
-- ====================================================================

local Config = require("Editor.Config")

local History = {}
History.__index = History

function History.New()
    local self = setmetatable({}, History)
    self.undoStack = {}   -- {action, ...}
    self.redoStack = {}
    return self
end

-- ====================================================================
-- 记录一次操作 (操作 = 一组瓦片变更)
-- action = { {x=, y=, oldTile=, newTile=}, ... }
-- ====================================================================
function History:Push(action)
    if #action == 0 then return end
    table.insert(self.undoStack, action)
    -- 新操作清空重做栈
    self.redoStack = {}
    -- 限制历史上限
    while #self.undoStack > Config.MAX_HISTORY do
        table.remove(self.undoStack, 1)
    end
end

-- ====================================================================
-- 撤销: 返回需要恢复的瓦片列表
-- ====================================================================
function History:Undo()
    if #self.undoStack == 0 then return nil end
    local action = table.remove(self.undoStack)
    table.insert(self.redoStack, action)
    return action
end

-- ====================================================================
-- 重做: 返回需要重新应用的瓦片列表
-- ====================================================================
function History:Redo()
    if #self.redoStack == 0 then return nil end
    local action = table.remove(self.redoStack)
    table.insert(self.undoStack, action)
    return action
end

function History:CanUndo()
    return #self.undoStack > 0
end

function History:CanRedo()
    return #self.redoStack > 0
end

function History:Clear()
    self.undoStack = {}
    self.redoStack = {}
end

function History:GetUndoCount()
    return #self.undoStack
end

function History:GetRedoCount()
    return #self.redoStack
end

return History
