-- ====================================================================
-- Editor/Levels.lua — 6个预置官方关卡
-- 基于策划案设计
-- ====================================================================

local Config = require("Editor.Config")

local Levels = {}

local T = Config.TILES
local W = T.WALL
local E = T.EMPTY
local S5 = T.SWITCH_5
local S4 = T.SWITCH_4
local S3 = T.SWITCH_3
local S2 = T.SWITCH_2
local S1 = T.SWITCH_1
local CP = T.CHECKPOINT
local SP = T.SPIKE
local PL = T.PLATFORM

-- ====================================================================
-- 辅助: 从紧凑格式创建地图
-- ====================================================================
local function CreateMap(width, height)
    local map = {}
    for y = 1, height do
        map[y] = {}
        for x = 1, width do
            map[y][x] = E
        end
    end
    return map
end

local function SetRow(map, y, startX, tiles)
    for i, t in ipairs(tiles) do
        local x = startX + i - 1
        if x >= 1 and x <= #map[1] and y >= 1 and y <= #map then
            map[y][x] = t
        end
    end
end

local function FillRect(map, x1, y1, x2, y2, tile)
    for y = y1, y2 do
        for x = x1, x2 do
            if y >= 1 and y <= #map and x >= 1 and x <= #map[1] then
                map[y][x] = tile
            end
        end
    end
end

local function FillRow(map, y, x1, x2, tile)
    FillRect(map, x1, y, x2, y, tile)
end

local function FillCol(map, x, y1, y2, tile)
    FillRect(map, x, y1, x, y2, tile)
end

-- ====================================================================
-- 关卡 1-1: 观测穹顶 (引入重力5, 可用3和5)
-- 教学: 重力切换基础, 高跳越沟
-- ====================================================================
function Levels.GetLevel1()
    local width, height = 60, 20
    local map = CreateMap(width, height)

    -- 底部地面
    FillRect(map, 1, 19, 60, 20, W)

    -- 起始区: 平坦地面 + 初始重力3
    FillRow(map, 18, 1, 15, W)
    map[18][5] = S3  -- 初始重力3开关

    -- 第一个沟: 3格宽 (重力3可跨越)
    -- 地面: 1-15, 沟: 16-18, 对面: 19-30
    FillRow(map, 18, 19, 35, W)

    -- 引入开关5: 在对面平台上
    map[18][22] = S5

    -- 第二个沟: 5格宽 (只有重力5能跳过,跳5格高+水平速度)
    -- 地面: 19-35, 沟: 36-40, 对面: 41-55
    FillRow(map, 18, 41, 55, W)

    -- 高墙: 3格高 (重力5可越过, 重力3不行)
    FillCol(map, 40, 15, 18, W)

    -- 出口区
    FillRow(map, 18, 55, 60, W)

    -- 检查点
    map[18][30] = CP

    -- 装饰: 天花板
    FillRow(map, 1, 1, 60, W)

    return {
        name = "1-1 观测穹顶",
        width = width,
        height = height,
        map = map,
        spawn = { x = 3, y = 17 },
        exit = { x = 58, y = 17 },
    }
end

-- ====================================================================
-- 关卡 2-1: 生态环廊 (引入重力4, 可用3/4/5)
-- 教学: 中高度跳跃选择
-- ====================================================================
function Levels.GetLevel2()
    local width, height = 65, 20
    local map = CreateMap(width, height)

    -- 底部
    FillRect(map, 1, 19, 65, 20, W)
    FillRow(map, 1, 1, 65, W)

    -- 起始平台
    FillRow(map, 16, 1, 12, W)
    map[16][4] = S3

    -- 阶梯向上 (需要重力4的跳跃高度)
    FillRow(map, 14, 15, 20, W)
    map[14][17] = S4  -- 重力4开关

    FillRow(map, 12, 23, 28, W)
    FillRow(map, 10, 31, 36, W)
    map[10][33] = S5  -- 重力5开关

    -- 高空平台 (重力5才能到达)
    FillRow(map, 6, 39, 45, W)
    map[6][42] = CP

    -- 下降区: 需要切回重力3/4才能控制下落
    FillRow(map, 10, 48, 53, W)
    map[10][50] = S3

    -- 出口平台
    FillRow(map, 14, 56, 65, W)

    return {
        name = "2-1 生态环廊",
        width = width,
        height = height,
        map = map,
        spawn = { x = 3, y = 15 },
        exit = { x = 62, y = 13 },
    }
end

-- ====================================================================
-- 关卡 3-1: 核心枢纽 — "高不成低不就"
-- 教学: 低矮通道需要高重力(跳不高), 高处需要低重力(跳得高)
-- ====================================================================
function Levels.GetLevel3()
    local width, height = 70, 20
    local map = CreateMap(width, height)

    -- 边界
    FillRect(map, 1, 19, 70, 20, W)
    FillRow(map, 1, 1, 70, W)

    -- 起始区 (重力3)
    FillRow(map, 16, 1, 15, W)
    map[16][4] = S3

    -- 左侧: 开关5在2格高平台
    FillRow(map, 14, 10, 14, W)
    map[14][12] = S5

    -- 低矮通道 (天花板2.5格≈2格间距, 重力5跳5格会撞头)
    -- 通道: x=18-35, 天花板y=14, 地面y=16, 净高=1格
    FillRow(map, 16, 18, 40, W)
    FillRow(map, 14, 18, 40, W)  -- 天花板(2格净高)

    -- 通道中间有开关2
    map[15][28] = S2

    -- 通道出口需要跳上高台
    FillRow(map, 10, 43, 50, W)
    map[15][42] = S5  -- 重力5恢复开关

    -- 高台上有出口
    FillRow(map, 8, 53, 60, W)
    map[8][55] = CP

    -- 终点平台
    FillRow(map, 12, 62, 70, W)

    return {
        name = "3-1 核心枢纽",
        width = width,
        height = height,
        map = map,
        spawn = { x = 3, y = 15 },
        exit = { x = 67, y = 11 },
    }
end

-- ====================================================================
-- 关卡 4-1: 能源舱段 (引入重力2, 可用2/3/4/5)
-- 教学: 高低组合谜题, 重力2跳得低但不会撞低天花板
-- ====================================================================
function Levels.GetLevel4()
    local width, height = 70, 20
    local map = CreateMap(width, height)

    FillRect(map, 1, 19, 70, 20, W)
    FillRow(map, 1, 1, 70, W)

    -- 起始
    FillRow(map, 16, 1, 12, W)
    map[16][4] = S3

    -- 压迫感区域: 天花板很低
    FillRow(map, 16, 15, 30, W)
    FillRow(map, 13, 15, 30, W)  -- 只有3格净高
    map[15][18] = S2  -- 重力2开关 (跳2格, 不会撞3格天花板)

    -- 挑战: 宽沟 (需要高重力跳远)
    -- 地面15-30后是4格宽沟
    FillRow(map, 16, 35, 50, W)
    map[16][36] = S4  -- 重力4

    -- 高墙4格
    FillCol(map, 50, 12, 16, W)

    -- 高空区
    FillRow(map, 8, 52, 60, W)
    map[16][52] = S5  -- 旁边的重力5
    map[8][55] = CP

    -- 下落到出口
    FillRow(map, 14, 62, 70, W)
    map[14][63] = S3

    return {
        name = "4-1 能源舱段",
        width = width,
        height = height,
        map = map,
        spawn = { x = 3, y = 15 },
        exit = { x = 68, y = 13 },
    }
end

-- ====================================================================
-- 关卡 5-1: 反应堆底层 (引入重力1, 全5种可用)
-- 教学: 五重重力复合谜题, 超重=几乎无法跳跃
-- ====================================================================
function Levels.GetLevel5()
    local width, height = 75, 20
    local map = CreateMap(width, height)

    FillRect(map, 1, 19, 75, 20, W)
    FillRow(map, 1, 1, 75, W)

    -- 起始 (重力3)
    FillRow(map, 16, 1, 10, W)
    map[16][3] = S3

    -- 第一段: 重力1区域 (几乎无法跳跃, 但地形平坦)
    FillRow(map, 16, 12, 25, W)
    map[16][13] = S1  -- 超重开关

    -- 极低跳跃的精密平台 (每格递升1格)
    map[15][18] = W  -- 阶梯
    map[14][21] = W
    map[13][24] = W
    map[13][25] = S3  -- 恢复正常重力

    -- 第二段: 混合区
    FillRow(map, 13, 28, 38, W)
    map[13][30] = S5
    -- 高墙需要重力5
    FillCol(map, 38, 8, 13, W)

    -- 高空平台
    FillRow(map, 6, 40, 48, W)
    map[6][43] = CP
    map[6][45] = S2  -- 切换重力2

    -- 低矮通道 (重力2不会撞头)
    FillRow(map, 10, 50, 62, W)
    FillRow(map, 8, 50, 62, W)  -- 2格净高
    map[9][55] = S4

    -- 终点前的宽沟 (重力4可跨)
    FillRow(map, 12, 64, 75, W)

    return {
        name = "5-1 反应堆底层",
        width = width,
        height = height,
        map = map,
        spawn = { x = 3, y = 15 },
        exit = { x = 72, y = 11 },
    }
end

-- ====================================================================
-- 关卡 6-1: 终局 — 最终挑战
-- 全部5种重力, 综合运用
-- ====================================================================
function Levels.GetLevel6()
    local width, height = 80, 20
    local map = CreateMap(width, height)

    FillRect(map, 1, 19, 80, 20, W)
    FillRow(map, 1, 1, 80, W)
    -- 左右墙
    FillCol(map, 1, 1, 20, W)
    FillCol(map, 80, 1, 20, W)

    -- 起始平台
    FillRow(map, 16, 2, 10, W)
    map[16][4] = S3

    -- 区域1: 向上攀爬 (需要重力5)
    FillRow(map, 14, 12, 16, W)
    map[14][13] = S5
    FillRow(map, 10, 14, 20, W)
    FillRow(map, 6, 18, 25, W)
    map[6][20] = CP

    -- 区域2: 高空水平移动 + 下落控制
    FillRow(map, 6, 28, 35, W)
    map[6][30] = S1  -- 超重(快速下落)
    FillRow(map, 16, 32, 40, W)  -- 下方接住平台
    map[16][35] = S4

    -- 区域3: 精密跳跃
    map[14][42] = W
    map[12][45] = W
    map[10][48] = W
    map[10][49] = S3
    FillRow(map, 10, 51, 58, W)
    map[10][53] = CP

    -- 区域4: 低矮通道 + 宽沟组合
    FillRow(map, 14, 58, 70, W)
    FillRow(map, 12, 58, 70, W)  -- 天花板
    map[13][60] = S2
    -- 通道末端沟
    FillRow(map, 14, 73, 79, W)
    map[14][74] = S5  -- 重力5飞跃终点

    -- 终点高台
    FillRow(map, 8, 75, 79, W)

    return {
        name = "6-1 终局挑战",
        width = width,
        height = height,
        map = map,
        spawn = { x = 4, y = 15 },
        exit = { x = 77, y = 7 },
    }
end

-- ====================================================================
-- 获取所有预置关卡列表
-- ====================================================================
function Levels.GetAll()
    return {
        Levels.GetLevel1,
        Levels.GetLevel2,
        Levels.GetLevel3,
        Levels.GetLevel4,
        Levels.GetLevel5,
        Levels.GetLevel6,
    }
end

function Levels.GetCount()
    return 6
end

function Levels.GetName(index)
    local names = {
        "1-1 观测穹顶",
        "2-1 生态环廊",
        "3-1 核心枢纽",
        "4-1 能源舱段",
        "5-1 反应堆底层",
        "6-1 终局挑战",
    }
    return names[index] or ("关卡 " .. index)
end

return Levels
