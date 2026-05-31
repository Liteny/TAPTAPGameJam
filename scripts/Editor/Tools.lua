-- ====================================================================
-- Editor/Tools.lua — 6种绘制工具
-- ====================================================================

local Config = require("Editor.Config")

local Tools = {}

-- ====================================================================
-- 画笔: 单格放置
-- ====================================================================
function Tools.Brush(map, x, y, tileId, mapW, mapH)
    local changes = {}
    if x >= 1 and x <= mapW and y >= 1 and y <= mapH then
        local old = map[y][x]
        if old ~= tileId then
            table.insert(changes, { x = x, y = y, oldTile = old, newTile = tileId })
            map[y][x] = tileId
        end
    end
    return changes
end

-- ====================================================================
-- 橡皮: 单格清除
-- ====================================================================
function Tools.Eraser(map, x, y, mapW, mapH)
    return Tools.Brush(map, x, y, Config.TILES.EMPTY, mapW, mapH)
end

-- ====================================================================
-- 直线: Bresenham 算法
-- ====================================================================
function Tools.Line(map, x1, y1, x2, y2, tileId, mapW, mapH)
    local changes = {}
    local points = Tools.BresenhamLine(x1, y1, x2, y2)
    for _, p in ipairs(points) do
        if p.x >= 1 and p.x <= mapW and p.y >= 1 and p.y <= mapH then
            local old = map[p.y][p.x]
            if old ~= tileId then
                table.insert(changes, { x = p.x, y = p.y, oldTile = old, newTile = tileId })
                map[p.y][p.x] = tileId
            end
        end
    end
    return changes
end

-- ====================================================================
-- 矩形: 填充矩形区域
-- ====================================================================
function Tools.Rect(map, x1, y1, x2, y2, tileId, mapW, mapH, filled)
    local changes = {}
    local minX = math.max(1, math.min(x1, x2))
    local maxX = math.min(mapW, math.max(x1, x2))
    local minY = math.max(1, math.min(y1, y2))
    local maxY = math.min(mapH, math.max(y1, y2))

    for py = minY, maxY do
        for px = minX, maxX do
            local draw = false
            if filled then
                draw = true
            else
                -- 仅绘制边框
                draw = (px == minX or px == maxX or py == minY or py == maxY)
            end
            if draw then
                local old = map[py][px]
                if old ~= tileId then
                    table.insert(changes, { x = px, y = py, oldTile = old, newTile = tileId })
                    map[py][px] = tileId
                end
            end
        end
    end
    return changes
end

-- ====================================================================
-- 填充: Flood Fill (BFS)
-- ====================================================================
function Tools.Fill(map, x, y, tileId, mapW, mapH)
    local changes = {}
    if x < 1 or x > mapW or y < 1 or y > mapH then return changes end

    local targetTile = map[y][x]
    if targetTile == tileId then return changes end  -- 同色不填充

    local queue = { { x = x, y = y } }
    local visited = {}
    local function key(px, py) return py * 10000 + px end

    visited[key(x, y)] = true

    local dirs = { {0, -1}, {0, 1}, {-1, 0}, {1, 0} }
    local maxFill = 5000  -- 安全限制

    while #queue > 0 and #changes < maxFill do
        local cur = table.remove(queue, 1)
        local old = map[cur.y][cur.x]
        if old == targetTile then
            table.insert(changes, { x = cur.x, y = cur.y, oldTile = old, newTile = tileId })
            map[cur.y][cur.x] = tileId

            for _, d in ipairs(dirs) do
                local nx = cur.x + d[1]
                local ny = cur.y + d[2]
                if nx >= 1 and nx <= mapW and ny >= 1 and ny <= mapH then
                    local k = key(nx, ny)
                    if not visited[k] and map[ny][nx] == targetTile then
                        visited[k] = true
                        table.insert(queue, { x = nx, y = ny })
                    end
                end
            end
        end
    end

    return changes
end

-- ====================================================================
-- 吸管: 返回指定位置的瓦片ID
-- ====================================================================
function Tools.Picker(map, x, y, mapW, mapH)
    if x >= 1 and x <= mapW and y >= 1 and y <= mapH then
        return map[y][x]
    end
    return nil
end

-- ====================================================================
-- Bresenham 直线算法
-- ====================================================================
function Tools.BresenhamLine(x1, y1, x2, y2)
    local points = {}
    local dx = math.abs(x2 - x1)
    local dy = math.abs(y2 - y1)
    local sx = x1 < x2 and 1 or -1
    local sy = y1 < y2 and 1 or -1
    local err = dx - dy

    while true do
        table.insert(points, { x = x1, y = y1 })
        if x1 == x2 and y1 == y2 then break end
        local e2 = err * 2
        if e2 > -dy then
            err = err - dy
            x1 = x1 + sx
        end
        if e2 < dx then
            err = err + dx
            y1 = y1 + sy
        end
    end
    return points
end

-- ====================================================================
-- 获取直线预览点列表 (不修改地图)
-- ====================================================================
function Tools.GetLinePreview(x1, y1, x2, y2, mapW, mapH)
    local points = Tools.BresenhamLine(x1, y1, x2, y2)
    local result = {}
    for _, p in ipairs(points) do
        if p.x >= 1 and p.x <= mapW and p.y >= 1 and p.y <= mapH then
            table.insert(result, p)
        end
    end
    return result
end

-- ====================================================================
-- 获取矩形预览点列表 (不修改地图)
-- ====================================================================
function Tools.GetRectPreview(x1, y1, x2, y2, mapW, mapH, filled)
    local result = {}
    local minX = math.max(1, math.min(x1, x2))
    local maxX = math.min(mapW, math.max(x1, x2))
    local minY = math.max(1, math.min(y1, y2))
    local maxY = math.min(mapH, math.max(y1, y2))

    for py = minY, maxY do
        for px = minX, maxX do
            local draw = false
            if filled then
                draw = true
            else
                draw = (px == minX or px == maxX or py == minY or py == maxY)
            end
            if draw then
                table.insert(result, { x = px, y = py })
            end
        end
    end
    return result
end

return Tools
