-- ====================================================================
-- Editor/Config.lua — 关卡编辑器全局配置
-- ====================================================================

local Config = {}

-- 设计分辨率
Config.DESIGN_W = 640
Config.DESIGN_H = 360

-- 瓦片
Config.TILE = 32

-- 默认地图尺寸
Config.DEFAULT_MAP_W = 70
Config.DEFAULT_MAP_H = 22

-- 缩放范围
Config.ZOOM_MIN = 0.25
Config.ZOOM_MAX = 4.0
Config.ZOOM_STEP = 1.15

-- 撤销历史上限
Config.MAX_HISTORY = 100

-- ====================================================================
-- 瓦片类型 (12种元素)
-- ====================================================================
Config.TILES = {
    EMPTY      = 0,   -- 空气
    WALL       = 1,   -- 墙体/实心平台
    SPAWN      = 2,   -- 起点
    EXIT       = 3,   -- 出口
    SWITCH_5   = 15,  -- 重力开关: 超轻 (青)
    SWITCH_4   = 14,  -- 重力开关: 轻 (绿)
    SWITCH_3   = 13,  -- 重力开关: 正常 (黄)
    SWITCH_2   = 12,  -- 重力开关: 重 (橙)
    SWITCH_1   = 11,  -- 重力开关: 超重 (红)
    CHECKPOINT = 30,  -- 检查点
    SPIKE      = 31,  -- 尖刺 (死亡区域)
    PLATFORM   = 32,  -- 单向平台 (可从下方穿过)
}

-- ====================================================================
-- 元素面板定义 (顺序即面板显示顺序)
-- ====================================================================
Config.ELEMENTS = {
    { id = Config.TILES.SWITCH_1,   name = "开关1",    key = "1", hotkey = KEY_1 },
    { id = Config.TILES.SWITCH_2,   name = "开关2",    key = "2", hotkey = KEY_2 },
    { id = Config.TILES.SWITCH_3,   name = "开关3",    key = "3", hotkey = KEY_3 },
    { id = Config.TILES.SWITCH_4,   name = "开关4",    key = "4", hotkey = KEY_4 },
    { id = Config.TILES.SWITCH_5,   name = "开关5",    key = "5", hotkey = KEY_5 },
    { id = Config.TILES.WALL,       name = "墙体",     key = "6", hotkey = KEY_6 },
    { id = Config.TILES.EMPTY,      name = "空气",     key = "7", hotkey = KEY_7 },
    { id = Config.TILES.SPAWN,      name = "起点",     key = "8", hotkey = KEY_8 },
    { id = Config.TILES.EXIT,       name = "出口",     key = "9", hotkey = KEY_9 },
    { id = Config.TILES.CHECKPOINT, name = "检查点",   key = "C", hotkey = KEY_C },
    { id = Config.TILES.SPIKE,      name = "尖刺",     key = "X", hotkey = KEY_X },
    { id = Config.TILES.PLATFORM,   name = "单向台",   key = "P", hotkey = KEY_P },
}

-- ====================================================================
-- 工具定义
-- ====================================================================
Config.TOOLS = {
    BRUSH   = "brush",
    ERASER  = "eraser",
    LINE    = "line",
    RECT    = "rect",
    FILL    = "fill",
    PICKER  = "picker",
}

Config.TOOL_LIST = {
    { id = Config.TOOLS.BRUSH,  name = "画笔",  key = "B", hotkey = KEY_B },
    { id = Config.TOOLS.ERASER, name = "橡皮",  key = "E", hotkey = KEY_E },
    { id = Config.TOOLS.LINE,   name = "直线",  key = "L", hotkey = KEY_L },
    { id = Config.TOOLS.RECT,   name = "矩形",  key = "R", hotkey = KEY_R },
    { id = Config.TOOLS.FILL,   name = "填充",  key = "F", hotkey = KEY_F },
    { id = Config.TOOLS.PICKER, name = "吸管",  key = "I", hotkey = KEY_I },
}

-- ====================================================================
-- 重力等级
-- ====================================================================
Config.GRAVITY_LEVELS = {
    [5] = { name = "超轻", gravity = 942,  tiles = 5 },
    [4] = { name = "轻",   gravity = 1177, tiles = 4 },
    [3] = { name = "正常", gravity = 1570, tiles = 3 },
    [2] = { name = "重",   gravity = 2355, tiles = 2 },
    [1] = { name = "超重", gravity = 3920, tiles = 1 },
}

Config.JUMP_SPEED = 560

-- ====================================================================
-- 颜色定义
-- ====================================================================
Config.COLORS = {
    BG           = { 10, 14, 39, 255 },
    GRID         = { 40, 50, 80, 60 },
    GRID_MAJOR   = { 60, 75, 110, 90 },
    WALL         = { 26, 32, 64, 255 },
    WALL_STROKE  = { 50, 60, 100, 180 },
    SPAWN        = { 0, 255, 150, 220 },
    EXIT         = { 180, 255, 180, 220 },
    CHECKPOINT   = { 255, 215, 0, 200 },
    SPIKE        = { 255, 50, 50, 220 },
    PLATFORM     = { 80, 120, 180, 200 },
    CURSOR       = { 255, 255, 255, 120 },
    -- 重力颜色
    GRAVITY = {
        [5] = { 0, 229, 255 },    -- 青
        [4] = { 0, 230, 118 },    -- 绿
        [3] = { 255, 234, 0 },    -- 黄
        [2] = { 255, 145, 0 },    -- 橙
        [1] = { 255, 23, 68 },    -- 红
    },
    -- UI
    TOOLBAR_BG     = { 20, 25, 45, 240 },
    PANEL_BG       = { 15, 20, 35, 230 },
    BUTTON_NORMAL  = { 40, 50, 75, 255 },
    BUTTON_HOVER   = { 55, 70, 100, 255 },
    BUTTON_ACTIVE  = { 0, 180, 255, 255 },
    TEXT_PRIMARY   = { 220, 230, 245, 255 },
    TEXT_SECONDARY = { 140, 150, 170, 200 },
    TEXT_ACCENT    = { 0, 229, 255, 255 },
    -- 验证
    VALID_OK       = { 0, 230, 118, 255 },
    VALID_WARN     = { 255, 234, 0, 255 },
    VALID_ERROR    = { 255, 50, 50, 255 },
}

-- ====================================================================
-- 辅助: 判断瓦片是否为实心(可站立)
-- 注意: 开关为覆盖层装饰，不参与碰撞
-- ====================================================================
function Config.IsSolid(tileId)
    return tileId == Config.TILES.WALL
        or tileId == Config.TILES.PLATFORM
end

-- 判断是否为开关
function Config.IsSwitch(tileId)
    return tileId >= Config.TILES.SWITCH_1 and tileId <= Config.TILES.SWITCH_5
end

-- 获取开关对应的重力等级
function Config.GetSwitchLevel(tileId)
    if Config.IsSwitch(tileId) then
        return tileId - 10
    end
    return nil
end

-- 获取瓦片颜色
function Config.GetTileColor(tileId)
    local C = Config.COLORS
    if tileId == Config.TILES.WALL then return C.WALL end
    if tileId == Config.TILES.SPAWN then return C.SPAWN end
    if tileId == Config.TILES.EXIT then return C.EXIT end
    if tileId == Config.TILES.CHECKPOINT then return C.CHECKPOINT end
    if tileId == Config.TILES.SPIKE then return C.SPIKE end
    if tileId == Config.TILES.PLATFORM then return C.PLATFORM end
    if Config.IsSwitch(tileId) then
        local level = Config.GetSwitchLevel(tileId)
        local gc = C.GRAVITY[level]
        return { gc[1], gc[2], gc[3], 255 }
    end
    return { 0, 0, 0, 0 }
end

return Config
