-- ====================================================================
-- Editor/Validator.lua — 物理验证引擎
-- BFS可达性检测、沟宽校验、通道净高校验、软锁检测
-- ====================================================================

local Config = require("Editor.Config")

local Validator = {}

-- ====================================================================
-- 主验证函数: 返回 { passed=bool, results={...} }
-- ====================================================================
function Validator.Validate(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY)
    local results = {}

    -- 1. 基础检查: 起点和出口是否存在
    local hasSpawn = (spawnX >= 1 and spawnX <= mapW and spawnY >= 1 and spawnY <= mapH)
    local hasExit = (exitX >= 1 and exitX <= mapW and exitY >= 1 and exitY <= mapH)

    if not hasSpawn then
        table.insert(results, { level = "error", msg = "缺少起点" })
    end
    if not hasExit then
        table.insert(results, { level = "error", msg = "缺少出口" })
    end
    if not hasSpawn or not hasExit then
        return { passed = false, results = results }
    end

    -- 2. 起点/出口是否在空气中(非墙内)
    if Config.IsSolid(map[spawnY][spawnX]) then
        table.insert(results, { level = "error", msg = "起点被墙体包围" })
    end
    if Config.IsSolid(map[exitY][exitX]) then
        table.insert(results, { level = "error", msg = "出口被墙体包围" })
    end

    -- 3. BFS 可达性检测 (考虑所有重力等级的跳跃能力)
    local reachable = Validator.BFSReachability(map, switchMap, mapW, mapH, spawnX, spawnY)
    if not reachable[exitY * 10000 + exitX] then
        table.insert(results, { level = "error", msg = "出口不可达 — 从起点无法到达出口" })
    else
        table.insert(results, { level = "ok", msg = "可达性: 起点→出口 路径存在" })
    end

    -- 4. 沟宽检测 (超过5格宽的空隙无法跨越)
    local gapIssues = Validator.CheckGaps(map, mapW, mapH)
    for _, issue in ipairs(gapIssues) do
        table.insert(results, issue)
    end

    -- 5. 通道净高检测 (高度<1格的通道无法通过)
    local heightIssues = Validator.CheckPassageHeight(map, mapW, mapH)
    for _, issue in ipairs(heightIssues) do
        table.insert(results, issue)
    end

    -- 6. 软锁检测 (是否存在无法离开的区域)
    local softlockIssues = Validator.CheckSoftLocks(map, switchMap, mapW, mapH, spawnX, spawnY)
    for _, issue in ipairs(softlockIssues) do
        table.insert(results, issue)
    end

    -- 判断总体结果
    local passed = true
    for _, r in ipairs(results) do
        if r.level == "error" then
            passed = false
            break
        end
    end

    return { passed = passed, results = results }
end

-- ====================================================================
-- BFS 可达性: 模拟玩家在各种重力等级下的移动能力
-- 返回所有可达格子的集合 {[key] = true}
-- ====================================================================
function Validator.BFSReachability(map, switchMap, mapW, mapH, startX, startY)
    local TILE = Config.TILE
    local visited = {}
    local function key(x, y) return y * 10000 + x end

    -- 从起点开始，玩家初始重力为3
    -- BFS 状态 = (gridX, gridY, gravityLevel)
    -- 简化: 不追踪精确重力状态，假设玩家能获得所有可达开关对应的重力
    -- 阶段式BFS: 先找当前重力下能到达的所有格子，找到新开关后扩展重力集合，重新搜索

    local availableGravity = { [3] = true }  -- 初始重力等级
    local globalReachable = {}

    -- 多轮BFS直到不再扩展
    local expanded = true
    while expanded do
        expanded = false

        -- 当前可用重力等级下最大跳跃高度(瓦片数)
        local maxJump = 0
        for level, _ in pairs(availableGravity) do
            local g = Config.GRAVITY_LEVELS[level]
            if g and g.tiles > maxJump then
                maxJump = g.tiles
            end
        end

        -- BFS: 水平移动 + 跳跃(上升maxJump格) + 下落(无限)
        local queue = { { x = startX, y = startY } }
        local bfsVisited = {}
        bfsVisited[key(startX, startY)] = true

        while #queue > 0 do
            local cur = table.remove(queue, 1)
            local cx, cy = cur.x, cur.y
            globalReachable[key(cx, cy)] = true

            -- 检查当前格覆盖层是否有开关
            local sw = switchMap[cy][cx]
            if sw ~= 0 then
                local switchLevel = Config.GetSwitchLevel(sw)
                if switchLevel and not availableGravity[switchLevel] then
                    availableGravity[switchLevel] = true
                    expanded = true  -- 获得新重力等级，需要重新搜索
                end
            end

            -- 邻居: 水平移动 (左右1格)
            for _, dx in ipairs({ -1, 1 }) do
                local nx = cx + dx
                if nx >= 1 and nx <= mapW then
                    -- 可以走到非实心格
                    if not Config.IsSolid(map[cy][nx]) then
                        local k = key(nx, cy)
                        if not bfsVisited[k] then
                            bfsVisited[k] = true
                            table.insert(queue, { x = nx, y = cy })
                        end
                    end
                end
            end

            -- 向上跳跃 (最多 maxJump 格)
            for dy = 1, maxJump do
                local ny = cy - dy
                if ny >= 1 then
                    if Config.IsSolid(map[ny][cx]) then
                        break  -- 撞到天花板
                    end
                    local k = key(cx, ny)
                    if not bfsVisited[k] then
                        bfsVisited[k] = true
                        table.insert(queue, { x = cx, y = ny })
                    end
                end
            end

            -- 向下(自由落体/重力，无限)
            for dy = 1, mapH do
                local ny = cy + dy
                if ny > mapH then break end
                if Config.IsSolid(map[ny][cx]) then
                    break  -- 落在实心块上
                end
                local k = key(cx, ny)
                if not bfsVisited[k] then
                    bfsVisited[k] = true
                    table.insert(queue, { x = cx, y = ny })
                end
            end
        end
    end

    return globalReachable
end

-- ====================================================================
-- 沟宽检测: 查找地面上连续空隙 > 某个阈值
-- ====================================================================
function Validator.CheckGaps(map, mapW, mapH)
    local issues = {}
    -- 对每一行检查连续空气段
    -- 重点关注"地面附近的沟"——上方是空气、下方是实心或地图底部外
    for y = 1, mapH - 1 do
        local gapStart = nil
        for x = 1, mapW do
            local isAir = not Config.IsSolid(map[y][x])
            local hasFloorBelow = (y + 1 <= mapH and Config.IsSolid(map[y + 1][x]))
                               or (y + 1 > mapH)

            if isAir and not hasFloorBelow then
                -- 这是一个沟(上方空气,下方也没地面)
                if not gapStart then gapStart = x end
            else
                if gapStart then
                    local gapWidth = x - gapStart
                    -- 最大水平跳跃距离约 6-7 格 (200px/s * 1.17s / 32px ≈ 7.3格)
                    -- 但安全起见警告 > 8 格
                    if gapWidth > 8 then
                        table.insert(issues, {
                            level = "warn",
                            msg = string.format("沟宽 %d 格 (行%d, 列%d-%d) 可能无法跨越",
                                gapWidth, y, gapStart, x - 1)
                        })
                    end
                    gapStart = nil
                end
            end
        end
        -- 行末检查
        if gapStart then
            local gapWidth = mapW - gapStart + 1
            if gapWidth > 8 then
                table.insert(issues, {
                    level = "warn",
                    msg = string.format("沟宽 %d 格 (行%d, 列%d-末) 可能无法跨越",
                        gapWidth, y, gapStart)
                })
            end
        end
    end
    return issues
end

-- ====================================================================
-- 通道净高检测: 小于1格(32px)的通道无法通过
-- ====================================================================
function Validator.CheckPassageHeight(map, mapW, mapH)
    local issues = {}
    -- 查找被夹在两个实心块之间、间距 < 1 格的水平通道
    for x = 1, mapW do
        local inGap = false
        local gapTop = 0
        for y = 1, mapH do
            if Config.IsSolid(map[y][x]) then
                if inGap then
                    local height = y - gapTop - 1
                    -- 小于1格高的通道(但大于0，即有空间但太矮)
                    -- 由于每格32px，玩家24px高，理论上1格能通过
                    -- 这里不会出现小于1格但>0的情况(因为是格子为单位)
                    -- 所以只检测 == 0 的情况(紧贴)不需要
                    inGap = false
                end
                gapTop = y
            else
                if not inGap and gapTop > 0 then
                    inGap = true
                end
            end
        end
    end
    -- 更实用: 检查"天花板与地面之间恰好1格"的低矮通道(重力5跳5格会撞头)
    for y = 2, mapH - 1 do
        local lowCount = 0
        for x = 1, mapW do
            local ceil = Config.IsSolid(map[y - 1][x])
            local floor = (y + 1 <= mapH) and Config.IsSolid(map[y + 1][x])
            local open = not Config.IsSolid(map[y][x])
            if ceil and floor and open then
                lowCount = lowCount + 1
            else
                if lowCount >= 3 then
                    table.insert(issues, {
                        level = "info",
                        msg = string.format("低矮通道 (行%d, 宽%d格) — 高重力开关才能通过", y, lowCount)
                    })
                end
                lowCount = 0
            end
        end
    end
    return issues
end

-- ====================================================================
-- 软锁检测: 是否存在玩家进入后无法离开的区域
-- 策略: 从每个可达开关出发, 检查是否能回到起点
-- ====================================================================
function Validator.CheckSoftLocks(map, switchMap, mapW, mapH, spawnX, spawnY)
    local issues = {}
    -- 找到所有开关位置(从覆盖层扫描)
    local switches = {}
    for y = 1, mapH do
        for x = 1, mapW do
            local sw = switchMap[y][x]
            if sw ~= 0 then
                table.insert(switches, { x = x, y = y, level = Config.GetSwitchLevel(sw) })
            end
        end
    end

    -- 简化版: 检查所有开关是否能从起点到达(已在BFS中完成)
    -- 更深入的检测: 检查从每个开关位置, 使用该开关提供的重力, 是否能回到起点
    -- 这里用简化版(全局BFS已覆盖可达性), 主要警告"死胡同"结构
    -- 死胡同 = 一个区域只有一个入口, 且入口需要特定重力才能离开

    -- 简单启发: 查找被墙围住的小区域(面积<10格, 只有1-2格开口)
    local visited = {}
    local function key(x, y) return y * 10000 + x end

    for y = 1, mapH do
        for x = 1, mapW do
            if not Config.IsSolid(map[y][x]) and not visited[key(x, y)] then
                -- Flood fill 统计区域大小和出口数
                local region = {}
                local queue = { { x = x, y = y } }
                local exits = 0
                visited[key(x, y)] = true

                while #queue > 0 do
                    local cur = table.remove(queue, 1)
                    table.insert(region, cur)
                    -- 检查四邻
                    local dirs = { {0,-1}, {0,1}, {-1,0}, {1,0} }
                    for _, d in ipairs(dirs) do
                        local nx = cur.x + d[1]
                        local ny = cur.y + d[2]
                        if nx < 1 or nx > mapW or ny < 1 or ny > mapH then
                            exits = exits + 1  -- 地图边界算出口
                        elseif not visited[key(nx, ny)] then
                            if not Config.IsSolid(map[ny][nx]) then
                                visited[key(nx, ny)] = true
                                table.insert(queue, { x = nx, y = ny })
                            end
                        end
                    end
                end

                -- 极小封闭区域警告 (面积 < 6 且无出口 且含有出生点/出口则报错)
                if #region < 6 and exits == 0 then
                    local hasImportant = false
                    for _, p in ipairs(region) do
                        if (p.x == spawnX and p.y == spawnY) then
                            hasImportant = true
                        end
                    end
                    if hasImportant then
                        table.insert(issues, {
                            level = "error",
                            msg = string.format("起点被封死 (区域仅%d格)", #region)
                        })
                    end
                end
            end
        end
    end

    return issues
end

return Validator
