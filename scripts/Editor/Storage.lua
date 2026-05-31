-- ====================================================================
-- Editor/Storage.lua — 存储系统 (JSON导出/保存/加载)
-- ====================================================================

local Config = require("Editor.Config")

local Storage = {}

-- ====================================================================
-- 序列化地图为JSON-ready table (双层: 基础层 + 开关覆盖层)
-- ====================================================================
function Storage.SerializeLevel(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY, levelName)
    -- 压缩存储: 只记录非空瓦片
    local tiles = {}
    for y = 1, mapH do
        for x = 1, mapW do
            if map[y][x] ~= Config.TILES.EMPTY then
                table.insert(tiles, { x = x, y = y, t = map[y][x] })
            end
        end
    end

    -- 开关覆盖层 (稀疏存储)
    local switches = {}
    if switchMap then
        for y = 1, mapH do
            for x = 1, mapW do
                if switchMap[y][x] ~= 0 then
                    table.insert(switches, { x = x, y = y, t = switchMap[y][x] })
                end
            end
        end
    end

    return {
        version = 3,
        name = levelName or "untitled",
        width = mapW,
        height = mapH,
        spawn = { x = spawnX, y = spawnY },
        exit = { x = exitX, y = exitY },
        tiles = tiles,
        switches = switches,
        -- Godot兼容元数据
        meta = {
            tileSize = Config.TILE,
            engine = "gravity_countdown",
            format = "sparse_dual_layer",
        }
    }
end

-- ====================================================================
-- 反序列化: 从data恢复地图
-- 返回 map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY
-- ====================================================================
function Storage.DeserializeLevel(data)
    local mapW = data.width or Config.DEFAULT_MAP_W
    local mapH = data.height or Config.DEFAULT_MAP_H

    -- 创建空地图
    local map = {}
    local switchMap = {}
    for y = 1, mapH do
        map[y] = {}
        switchMap[y] = {}
        for x = 1, mapW do
            map[y][x] = Config.TILES.EMPTY
            switchMap[y][x] = 0
        end
    end

    -- 填充基础层瓦片
    if data.tiles then
        for _, tile in ipairs(data.tiles) do
            local x = tile.x
            local y = tile.y
            local t = tile.t
            if x >= 1 and x <= mapW and y >= 1 and y <= mapH then
                -- 兼容旧版: 如果基础层中有开关瓦片，迁移到覆盖层
                if Config.IsSwitch(t) then
                    switchMap[y][x] = t
                else
                    map[y][x] = t
                end
            end
        end
    end

    -- 填充开关覆盖层 (v3格式)
    if data.switches then
        for _, sw in ipairs(data.switches) do
            local x = sw.x
            local y = sw.y
            local t = sw.t
            if x >= 1 and x <= mapW and y >= 1 and y <= mapH then
                switchMap[y][x] = t
            end
        end
    end

    local spawnX = (data.spawn and data.spawn.x) or 3
    local spawnY = (data.spawn and data.spawn.y) or mapH - 2
    local exitX = (data.exit and data.exit.x) or mapW - 3
    local exitY = (data.exit and data.exit.y) or mapH - 2

    return map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY
end

-- ====================================================================
-- 保存到文件 (JSON)
-- ====================================================================
function Storage.SaveToFile(filename, map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY, levelName)
    local data = Storage.SerializeLevel(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY, levelName)
    local json = cjson.encode(data)

    -- 确保目录存在
    fileSystem:CreateDir("levels")

    local path = "levels/" .. filename
    local file = File(path, FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(json)
        file:Close()
        return true, path
    end
    return false, "无法写入文件: " .. path
end

-- ====================================================================
-- 从文件加载
-- ====================================================================
function Storage.LoadFromFile(filename)
    local path = "levels/" .. filename
    if not fileSystem:FileExists(path) then
        return nil, "文件不存在: " .. path
    end

    local file = File(path, FILE_READ)
    if not file:IsOpen() then
        return nil, "无法打开文件: " .. path
    end

    local json = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, json)
    if not ok then
        return nil, "JSON解析失败: " .. tostring(data)
    end

    return data, nil
end

-- ====================================================================
-- 获取JSON字符串 (用于导出/复制)
-- ====================================================================
function Storage.ExportJSON(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY, levelName)
    local data = Storage.SerializeLevel(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY, levelName)
    return cjson.encode(data)
end

-- ====================================================================
-- 列出已保存的关卡
-- ====================================================================
function Storage.ListSaves()
    local saves = {}
    fileSystem:CreateDir("levels")
    -- 尝试加载索引文件
    local indexPath = "levels/index.json"
    if fileSystem:FileExists(indexPath) then
        local file = File(indexPath, FILE_READ)
        if file:IsOpen() then
            local json = file:ReadString()
            file:Close()
            local ok, data = pcall(cjson.decode, json)
            if ok and data.files then
                return data.files
            end
        end
    end
    return saves
end

-- ====================================================================
-- 更新索引文件
-- ====================================================================
function Storage.UpdateIndex(filename, levelName)
    local saves = Storage.ListSaves()

    -- 检查是否已存在
    local found = false
    for i, s in ipairs(saves) do
        if s.file == filename then
            saves[i].name = levelName
            found = true
            break
        end
    end
    if not found then
        table.insert(saves, { file = filename, name = levelName })
    end

    -- 写入索引
    local json = cjson.encode({ files = saves })
    local file = File("levels/index.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(json)
        file:Close()
    end
end

return Storage
