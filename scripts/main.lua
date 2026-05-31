-- ====================================================================
-- 《五四三二一：重力倒计时》— 关卡编辑器 + 核心玩法验证
-- ====================================================================
--
-- 技术方案:
--   渲染: NanoVG (矢量几何图形)
--   物理: 自定义 AABB 碰撞 (半步积分防穿透)
--   UI:   urhox-libs/UI (工具栏/HUD)
--   分辨率: 设计分辨率 640×360 (模式 A)
--
-- 模式:
--   EDIT  - 关卡编辑 (放置瓦片/开关/出生点/出口)
--   PLAY  - 试玩验证 (核心重力机制)
--
-- 物理验证:
--   跳跃初速度 = 560 px/s (含 2% 时间步进补偿)
--   max_height = v² / (2g)
--   等级5: 560²/(2×942)  = 166px > 5格(160px) ✓
--   等级4: 560²/(2×1177) = 133px > 4格(128px) ✓
--   等级3: 560²/(2×1570) = 100px > 3格(96px)  ✓
--   等级2: 560²/(2×2355) = 67px  > 2格(64px)  ✓
--   等级1: 560²/(2×4709) = 33px  > 1格(32px)  ✓
--
-- ====================================================================

local UI = require("urhox-libs/UI")

-- ====================================================================
-- 常量
-- ====================================================================

-- 设计分辨率
local DESIGN_W = 640
local DESIGN_H = 360

-- 瓦片
local TILE = 32

-- 地图尺寸 (瓦片数)
local MAP_W = 60
local MAP_H = 22  -- 22格高 = 704px，提供充足的垂直编辑空间

-- 瓦片类型
local T_EMPTY = 0
local T_SOLID = 1   -- 实心平台

-- 重力开关: 10 + 等级
local T_SW1 = 11    -- 超重
local T_SW2 = 12    -- 重
local T_SW3 = 13    -- 正常
local T_SW4 = 14    -- 轻
local T_SW5 = 15    -- 超轻

-- 特殊标记 (仅编辑器用，不存入 map)
local T_SPAWN = 20
local T_EXIT  = 21

-- 重力等级参数
-- 跳跃初速度含 2% 补偿，确保离散时间步下能越过 N 格平台
local JUMP_SPEED = 560

local GRAVITY_LEVELS = {
    [5] = { name = "超轻", gravity = 942,  color = {0, 229, 255},   tiles = 5 },  -- 青
    [4] = { name = "轻",   gravity = 1177, color = {0, 230, 118},   tiles = 4 },  -- 绿
    [3] = { name = "正常", gravity = 1570, color = {255, 234, 0},   tiles = 3 },  -- 黄
    [2] = { name = "重",   gravity = 2355, color = {255, 145, 0},   tiles = 2 },  -- 橙
    [1] = { name = "超重", gravity = 4709, color = {255, 23, 68},   tiles = 1 },  -- 红
}

-- 玩家参数 (正方形碰撞箱)
local PLAYER_W = 24
local PLAYER_H = 24
local GROUND_SPEED = 200    -- px/s
local AIR_SPEED = 150       -- px/s (75% 地面速度)
local GROUND_ACCEL = 2000   -- px/s²
local AIR_ACCEL = 1200      -- px/s² (空中加速稍低)
local FRICTION = 12         -- 地面摩擦
local COYOTE_TIME = 0.08    -- 土狼时间
local JUMP_BUFFER = 0.12    -- 跳跃缓冲
local MAX_FALL_SPEED = 800  -- 最大下落速度 (防穿透)

-- 颜色
local C_BG       = {10, 14, 39}
local C_PLATFORM = {26, 32, 64}
local C_GRID     = {40, 50, 80, 80}
local C_PLAYER   = {220, 230, 255}
local C_EXIT     = {180, 255, 180}

-- ====================================================================
-- 游戏状态
-- ====================================================================

local MODE_EDIT = 0
local MODE_PLAY = 1

local gameMode = MODE_EDIT

-- 地图数据: map[y][x] (1-indexed)
local map = {}

-- 编辑器状态
local editor = {
    tool = T_SOLID,
    cameraX = 0,
    cameraY = 0,
    spawnX = 3,
    spawnY = 9,
    exitX = MAP_W - 3,
    exitY = 9,
}

-- 玩家状态
local player = {
    x = 0, y = 0,
    vx = 0, vy = 0,
    onGround = false,
    wasOnGround = false,    -- 上一帧是否在地面
    gravityLevel = 3,
    coyoteTimer = 0,
    jumpBufferTimer = 0,
    jumpConsumed = false,   -- 本次跳跃是否已消耗 (防连跳)
    facing = 1,
}

-- NanoVG
local nvgCtx = nil
local fontId = -1

-- 缩放
local scaleX = 1
local scaleY = 1

-- UI
local uiRoot = nil

-- ====================================================================
-- 辅助函数: 判断瓦片是否为实心 (平台 + 开关都可站立)
-- ====================================================================

local function IsSolidTile(tile)
    return tile == T_SOLID or (tile >= T_SW1 and tile <= T_SW5)
end

-- ====================================================================
-- 初始化
-- ====================================================================

function Start()
    graphics.windowTitle = "五四三二一：重力倒计时 - 关卡编辑器"

    nvgCtx = nvgCreate(1)
    if not nvgCtx then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    fontId = nvgCreateFont(nvgCtx, "sans", "Fonts/MiSans-Regular.ttf")

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    scaleX = physW / DESIGN_W
    scaleY = physH / DESIGN_H

    InitMap()
    InitUI()

    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(nvgCtx, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")

    print("=== 关卡编辑器启动 ===")
    print("[编辑] 1:平台 2-6:开关 7:出生点 8:出口 | 左键:放置 右键:删除")
    print("[试玩] Tab切换 | WASD/方向键移动 | 空格跳跃 | R重置")
end

function Stop()
    UI.Shutdown()
    if nvgCtx then
        nvgDelete(nvgCtx)
        nvgCtx = nil
    end
end

-- ====================================================================
-- 地图初始化 (含测试关卡)
-- ====================================================================

function InitMap()
    -- 清空
    for y = 1, MAP_H do
        map[y] = {}
        for x = 1, MAP_W do
            map[y][x] = T_EMPTY
        end
    end

    -- 底部地面 (最后两行)
    for x = 1, MAP_W do
        map[MAP_H][x] = T_SOLID
        map[MAP_H - 1][x] = T_SOLID
    end

    -- ====== 测试关卡: 验证各等级跳跃高度 ======
    -- 地面行 = MAP_H - 2 (玩家站在此行顶部)
    local groundRow = MAP_H - 2

    -- 区段1: 开关[5] + 5格高墙 (x=8-12)
    map[groundRow][8] = T_SW5
    for h = 0, 4 do
        map[groundRow - h][12] = T_SOLID
    end

    -- 区段2: 开关[4] + 4格高墙 (x=18-22)
    map[groundRow][18] = T_SW4
    for h = 0, 3 do
        map[groundRow - h][22] = T_SOLID
    end

    -- 区段3: 开关[3] + 3格高墙 (x=28-32)
    map[groundRow][28] = T_SW3
    for h = 0, 2 do
        map[groundRow - h][32] = T_SOLID
    end

    -- 区段4: 开关[2] + 2格高墙 (x=38-42)
    map[groundRow][38] = T_SW2
    for h = 0, 1 do
        map[groundRow - h][42] = T_SOLID
    end

    -- 区段5: 开关[1] + 1格高墙 (x=48-52)
    map[groundRow][48] = T_SW1
    map[groundRow][52] = T_SOLID

    -- 出生点/出口
    editor.spawnX = 3
    editor.spawnY = groundRow
    editor.exitX = MAP_W - 3
    editor.exitY = groundRow

    -- 编辑器初始相机对准地面区域
    editor.cameraY = math.max(0, MAP_H * TILE - DESIGN_H)

    print("[测试关卡] 5个区段，每个区段有对应等级开关+对应高度墙壁")
    print("  踩开关 → 跳过墙壁 = 该等级验证通过")
    print("  地图高度: " .. MAP_H .. " 格 (" .. MAP_H * TILE .. "px)，WASD滚动编辑")
end

-- ====================================================================
-- 一键清空地图 (保留地面)
-- ====================================================================

function ClearMap()
    for y = 1, MAP_H - 2 do
        for x = 1, MAP_W do
            map[y][x] = T_EMPTY
        end
    end
    print("[编辑器] 地图已清空（保留底部地面）")
end

-- ====================================================================
-- UI
-- ====================================================================

function InitUI()
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    uiRoot = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 顶部工具栏
            UI.Panel {
                id = "toolbar",
                width = "100%",
                height = 32,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 8,
                paddingRight = 8,
                gap = 6,
                backgroundColor = { 15, 20, 35, 230 },
                children = {
                    UI.Label {
                        id = "modeLabel",
                        text = "[编辑]",
                        fontSize = 12,
                        fontColor = { 100, 255, 200, 255 },
                    },
                    UI.Label {
                        id = "toolLabel",
                        text = "工具: 实心平台",
                        fontSize = 11,
                        fontColor = { 200, 210, 230, 255 },
                    },
                    UI.Label {
                        id = "gravityLabel",
                        text = "",
                        fontSize = 11,
                        fontColor = { 255, 234, 0, 255 },
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Button {
                        id = "clearBtn",
                        text = "清空地图",
                        fontSize = 10,
                        height = 22,
                        paddingLeft = 8,
                        paddingRight = 8,
                        variant = "danger",
                        onClick = function()
                            ClearMap()
                        end,
                    },
                    UI.Label {
                        id = "helpLabel",
                        text = "Tab:切换 | 1-8:工具 | 左键放置 右键删除 | WASD滚动",
                        fontSize = 9,
                        fontColor = { 130, 140, 160, 180 },
                    },
                },
            },
        },
    }

    UI.SetRoot(uiRoot)
end

-- ====================================================================
-- 更新
-- ====================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 限制最大 dt 防止物理爆炸
    dt = math.min(dt, 1 / 30)

    if gameMode == MODE_PLAY then
        UpdatePlayer(dt)
    else
        UpdateEditor(dt)
    end
end

-- ====================================================================
-- 编辑器
-- ====================================================================

function UpdateEditor(dt)
    local scrollSpeed = 300
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        editor.cameraX = math.max(0, editor.cameraX - scrollSpeed * dt)
    end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        local maxCam = math.max(0, MAP_W * TILE - DESIGN_W)
        editor.cameraX = math.min(maxCam, editor.cameraX + scrollSpeed * dt)
    end
    if input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) then
        editor.cameraY = math.max(0, editor.cameraY - scrollSpeed * dt)
    end
    if input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN) then
        local maxCamY = math.max(0, MAP_H * TILE - DESIGN_H)
        editor.cameraY = math.min(maxCamY, editor.cameraY + scrollSpeed * dt)
    end

    -- 持续绘制/擦除
    if input:GetMouseButtonDown(MOUSEB_LEFT) then
        PlaceTileAtMouse()
    end
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        EraseTileAtMouse()
    end
end

function PlaceTileAtMouse()
    local tx, ty = MouseToTile()
    if tx < 1 or tx > MAP_W or ty < 1 or ty > MAP_H then return end

    if editor.tool == T_SPAWN then
        editor.spawnX = tx
        editor.spawnY = ty
    elseif editor.tool == T_EXIT then
        editor.exitX = tx
        editor.exitY = ty
    else
        map[ty][tx] = editor.tool
    end
end

function EraseTileAtMouse()
    local tx, ty = MouseToTile()
    if tx < 1 or tx > MAP_W or ty < 1 or ty > MAP_H then return end
    map[ty][tx] = T_EMPTY
end

function MouseToTile()
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    local dx = mx / scaleX
    local dy = my / scaleY
    local tx = math.floor((dx + editor.cameraX) / TILE) + 1
    local ty = math.floor((dy + editor.cameraY) / TILE) + 1
    return tx, ty
end

-- ====================================================================
-- 玩家物理 (核心!)
-- ====================================================================

function UpdatePlayer(dt)
    local grav = GRAVITY_LEVELS[player.gravityLevel].gravity

    -- ===== 输入 =====
    local moveDir = 0
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        moveDir = -1
    elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        moveDir = 1
    end

    -- ===== 水平移动 =====
    local maxSpeed = player.onGround and GROUND_SPEED or AIR_SPEED
    local accel = player.onGround and GROUND_ACCEL or AIR_ACCEL

    if moveDir ~= 0 then
        player.vx = player.vx + moveDir * accel * dt
        if math.abs(player.vx) > maxSpeed then
            player.vx = moveDir * maxSpeed
        end
        player.facing = moveDir
    else
        -- 摩擦
        local decay = player.onGround and FRICTION or (FRICTION * 0.3)
        player.vx = player.vx * math.max(0, 1 - decay * dt)
        if math.abs(player.vx) < 2 then player.vx = 0 end
    end

    -- ===== 跳跃 (边沿检测) =====
    -- 使用 GetKeyPress 实现单次触发
    local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP)
    if jumpPressed then
        player.jumpBufferTimer = JUMP_BUFFER
        player.jumpConsumed = false
    end
    player.jumpBufferTimer = math.max(0, player.jumpBufferTimer - dt)

    -- 土狼时间
    if player.onGround then
        player.coyoteTimer = COYOTE_TIME
    else
        player.coyoteTimer = math.max(0, player.coyoteTimer - dt)
    end

    -- 执行跳跃 (缓冲 + 土狼 + 未消耗)
    if player.jumpBufferTimer > 0 and player.coyoteTimer > 0 and not player.jumpConsumed then
        player.vy = -JUMP_SPEED
        player.onGround = false
        player.coyoteTimer = 0
        player.jumpBufferTimer = 0
        player.jumpConsumed = true
    end

    -- 落地时重置消耗标记
    if player.onGround then
        player.jumpConsumed = false
    end

    -- ===== 重力 (在地面时跳过，消除闲置抖动) =====
    if player.onGround then
        -- 在地面时不施加重力，但要检测脚下是否还有地面
        if not IsGroundBelow() then
            -- 走出边缘：开始下落
            player.onGround = false
            player.vy = 0
        else
            -- 确保垂直速度为零，防止残余速度累积
            player.vy = 0
        end
    else
        player.vy = player.vy + grav * dt
        -- 限制最大下落速度
        if player.vy > MAX_FALL_SPEED then
            player.vy = MAX_FALL_SPEED
        end
    end

    -- ===== 移动 + 碰撞检测 =====
    ResolveMovement(dt)

    -- ===== 开关检测 (站在开关上时触发) =====
    CheckGravitySwitches()

    -- ===== 出口 =====
    CheckExit()

    -- ===== 相机 (水平 + 垂直跟随) =====
    -- 水平
    local camTargetX = player.x - DESIGN_W / 2 + PLAYER_W / 2
    local maxCamX = math.max(0, MAP_W * TILE - DESIGN_W)
    editor.cameraX = math.max(0, math.min(maxCamX, camTargetX))

    -- 垂直 (允许负值跟随跳出地图顶部的玩家)
    local camTargetY = player.y - DESIGN_H / 2 + PLAYER_H / 2
    local maxCamY = math.max(0, MAP_H * TILE - DESIGN_H)
    editor.cameraY = math.max(-DESIGN_H / 2, math.min(maxCamY, camTargetY))
end

-- ====================================================================
-- 碰撞解算 (分轴 + 精确对齐)
-- ====================================================================

function ResolveMovement(dt)
    -- ===== 水平 =====
    local dx = player.vx * dt
    if dx ~= 0 then
        local newX = player.x + dx
        if not CheckCollision(newX, player.y) then
            player.x = newX
        else
            -- 贴墙对齐
            if dx > 0 then
                -- 向右: 对齐到碰撞瓦片左边
                local rightEdge = player.x + PLAYER_W
                local nextTileX = math.floor((rightEdge + dx) / TILE) * TILE
                player.x = nextTileX - PLAYER_W - 0.01
            else
                -- 向左: 对齐到碰撞瓦片右边
                local leftEdge = player.x + dx
                local nextTileX = (math.floor(leftEdge / TILE) + 1) * TILE
                player.x = nextTileX + 0.01
            end
            player.vx = 0
        end
    end

    -- ===== 垂直 =====
    local dy = player.vy * dt
    player.wasOnGround = player.onGround

    if dy ~= 0 then
        local newY = player.y + dy
        if not CheckCollision(player.x, newY) then
            player.y = newY
            player.onGround = false
        else
            if dy > 0 then
                -- 下落: 对齐到平台顶部
                local bottomEdge = player.y + PLAYER_H + dy
                local landTileY = math.floor(bottomEdge / TILE) * TILE
                player.y = landTileY - PLAYER_H
                player.onGround = true
            else
                -- 上升撞顶: 对齐到天花板底部
                local topEdge = player.y + dy
                local ceilTileY = (math.floor(topEdge / TILE) + 1) * TILE
                player.y = ceilTileY
            end
            player.vy = 0
        end
    end

    -- 掉出地图
    if player.y > MAP_H * TILE + 100 then
        ResetPlayer()
    end
end

function CheckCollision(x, y)
    -- AABB vs 瓦片地图碰撞
    -- 收缩 2px 避免卡角
    local shrink = 2
    local left   = math.floor((x + shrink) / TILE) + 1
    local right  = math.floor((x + PLAYER_W - shrink) / TILE) + 1
    local top    = math.floor((y + shrink) / TILE) + 1
    local bottom = math.floor((y + PLAYER_H - shrink) / TILE) + 1

    for ty = top, bottom do
        for tx = left, right do
            if tx >= 1 and tx <= MAP_W and ty >= 1 and ty <= MAP_H then
                if IsSolidTile(map[ty][tx]) then
                    return true
                end
            end
        end
    end
    return false
end

-- ====================================================================
-- 地面持续检测 (玩家脚下 1px 是否还有实心瓦片)
-- ====================================================================

function IsGroundBelow()
    -- 检查玩家底部向下 1px 位置是否有实心瓦片
    local shrink = 2
    local checkY = player.y + PLAYER_H + 1  -- 脚下 1px
    local left  = math.floor((player.x + shrink) / TILE) + 1
    local right = math.floor((player.x + PLAYER_W - shrink) / TILE) + 1
    local row   = math.floor(checkY / TILE) + 1

    for tx = left, right do
        if tx >= 1 and tx <= MAP_W and row >= 1 and row <= MAP_H then
            if IsSolidTile(map[row][tx]) then
                return true
            end
        end
    end
    return false
end

-- ====================================================================
-- 重力开关检测 (玩家站在开关瓦片顶部时触发)
-- ====================================================================

function CheckGravitySwitches()
    if not player.onGround then return end

    -- 检查玩家正下方的瓦片 (脚下一行)
    local footRow = math.floor((player.y + PLAYER_H + 1) / TILE) + 1
    local leftCol = math.floor((player.x + 4) / TILE) + 1
    local rightCol = math.floor((player.x + PLAYER_W - 4) / TILE) + 1

    for tx = leftCol, rightCol do
        if tx >= 1 and tx <= MAP_W and footRow >= 1 and footRow <= MAP_H then
            local tile = map[footRow][tx]
            if tile >= T_SW1 and tile <= T_SW5 then
                local level = tile - 10
                if player.gravityLevel ~= level then
                    player.gravityLevel = level
                    UpdateGravityUI()
                end
                return
            end
        end
    end
end

-- ====================================================================
-- 出口检测
-- ====================================================================

function CheckExit()
    -- 玩家中心与出口瓦片中心的距离判定
    local px = player.x + PLAYER_W / 2
    local py = player.y + PLAYER_H / 2
    local ex = (editor.exitX - 1) * TILE + TILE / 2
    local ey = (editor.exitY - 1) * TILE + TILE / 2
    local dist = math.sqrt((px - ex) ^ 2 + (py - ey) ^ 2)
    if dist < TILE * 0.6 then
        print("=== 到达出口! ===")
        ResetPlayer()
    end
end

-- ====================================================================
-- 重置玩家
-- ====================================================================

function ResetPlayer()
    player.x = (editor.spawnX - 1) * TILE + (TILE - PLAYER_W) / 2
    player.y = (editor.spawnY - 1) * TILE - PLAYER_H
    player.vx = 0
    player.vy = 0
    player.onGround = false
    player.wasOnGround = false
    player.gravityLevel = 3
    player.coyoteTimer = 0
    player.jumpBufferTimer = 0
    player.jumpConsumed = false
    UpdateGravityUI()
end

-- ====================================================================
-- 模式切换
-- ====================================================================

function SwitchToPlay()
    gameMode = MODE_PLAY
    ResetPlayer()
    local label = uiRoot:FindById("modeLabel")
    if label then label:SetText("[试玩]") end
    local help = uiRoot:FindById("helpLabel")
    if help then help:SetText("WASD移动 | 空格跳跃 | R重置 | Tab返回编辑") end
    UpdateGravityUI()
end

function SwitchToEdit()
    gameMode = MODE_EDIT
    local label = uiRoot:FindById("modeLabel")
    if label then label:SetText("[编辑]") end
    local help = uiRoot:FindById("helpLabel")
    if help then help:SetText("Tab:切换 | 1-8:工具 | 左键放置 右键删除 | AD滚动") end
    local gLabel = uiRoot:FindById("gravityLabel")
    if gLabel then gLabel:SetText("") end
end

function UpdateGravityUI()
    local gLabel = uiRoot:FindById("gravityLabel")
    if gLabel then
        local g = GRAVITY_LEVELS[player.gravityLevel]
        gLabel:SetText("重力: " .. g.name .. " [" .. player.gravityLevel .. "]")
    end
end

-- ====================================================================
-- 输入
-- ====================================================================

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    if key == KEY_TAB then
        if gameMode == MODE_EDIT then
            SwitchToPlay()
        else
            SwitchToEdit()
        end
        return
    end

    if key == KEY_R and gameMode == MODE_PLAY then
        ResetPlayer()
        return
    end

    -- 编辑器工具
    if gameMode == MODE_EDIT then
        if key == KEY_1 then editor.tool = T_SOLID
        elseif key == KEY_2 then editor.tool = T_SW5
        elseif key == KEY_3 then editor.tool = T_SW4
        elseif key == KEY_4 then editor.tool = T_SW3
        elseif key == KEY_5 then editor.tool = T_SW2
        elseif key == KEY_6 then editor.tool = T_SW1
        elseif key == KEY_7 then editor.tool = T_SPAWN
        elseif key == KEY_8 then editor.tool = T_EXIT
        end
        UpdateToolLabel()
    end
end

function UpdateToolLabel()
    local names = {
        [T_SOLID] = "实心平台",
        [T_SW5]   = "开关:超轻(5)青",
        [T_SW4]   = "开关:轻(4)绿",
        [T_SW3]   = "开关:正常(3)黄",
        [T_SW2]   = "开关:重(2)橙",
        [T_SW1]   = "开关:超重(1)红",
        [T_SPAWN] = "出生点",
        [T_EXIT]  = "出口",
    }
    local label = uiRoot:FindById("toolLabel")
    if label then
        label:SetText("工具: " .. (names[editor.tool] or "未知"))
    end
end

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    if gameMode ~= MODE_EDIT then return end
    local button = eventData["Button"]:GetInt()
    if button == MOUSEB_LEFT then
        PlaceTileAtMouse()
    elseif button == MOUSEB_RIGHT then
        EraseTileAtMouse()
    end
end

-- ====================================================================
-- NanoVG 渲染
-- ====================================================================

function HandleNanoVGRender(eventType, eventData)
    if not nvgCtx then return end

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    scaleX = physW / DESIGN_W
    scaleY = physH / DESIGN_H

    nvgBeginFrame(nvgCtx, physW, physH, 1.0)

    -- 设计分辨率缩放
    nvgSave(nvgCtx)
    nvgScale(nvgCtx, scaleX, scaleY)

    -- 背景
    DrawBackground()

    -- 相机空间
    nvgSave(nvgCtx)
    nvgTranslate(nvgCtx, -editor.cameraX, -editor.cameraY)

    -- 网格 (仅编辑模式)
    if gameMode == MODE_EDIT then
        DrawGrid()
    end

    -- 地图
    DrawMap()

    -- 出生点 & 出口
    DrawSpawnAndExit()

    -- 玩家 (仅试玩)
    if gameMode == MODE_PLAY then
        DrawPlayer()
    end

    nvgRestore(nvgCtx)  -- 相机

    -- HUD 层 (不跟随相机)
    if gameMode == MODE_EDIT then
        DrawEditorCursor()
    end
    if gameMode == MODE_PLAY then
        DrawGravityHUD()
    end

    nvgRestore(nvgCtx)  -- 缩放
    nvgEndFrame(nvgCtx)
end

-- ====================================================================
-- 绘制
-- ====================================================================

function DrawBackground()
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, 0, 0, DESIGN_W, DESIGN_H)
    nvgFillColor(nvgCtx, nvgRGBA(C_BG[1], C_BG[2], C_BG[3], 255))
    nvgFill(nvgCtx)
end

function DrawGrid()
    nvgStrokeWidth(nvgCtx, 0.5)
    nvgStrokeColor(nvgCtx, nvgRGBA(C_GRID[1], C_GRID[2], C_GRID[3], C_GRID[4]))

    local startX = math.floor(editor.cameraX / TILE) * TILE
    local startY = math.floor(editor.cameraY / TILE) * TILE
    for x = startX, startX + DESIGN_W + TILE, TILE do
        nvgBeginPath(nvgCtx)
        nvgMoveTo(nvgCtx, x, editor.cameraY)
        nvgLineTo(nvgCtx, x, editor.cameraY + DESIGN_H)
        nvgStroke(nvgCtx)
    end
    for y = startY, startY + DESIGN_H + TILE, TILE do
        nvgBeginPath(nvgCtx)
        nvgMoveTo(nvgCtx, editor.cameraX, y)
        nvgLineTo(nvgCtx, editor.cameraX + DESIGN_W, y)
        nvgStroke(nvgCtx)
    end
end

function DrawMap()
    local startTX = math.max(1, math.floor(editor.cameraX / TILE))
    local endTX = math.min(MAP_W, math.floor((editor.cameraX + DESIGN_W) / TILE) + 2)

    for ty = 1, MAP_H do
        for tx = startTX, endTX do
            local tile = map[ty][tx]
            if tile ~= T_EMPTY then
                local px = (tx - 1) * TILE
                local py = (ty - 1) * TILE

                if tile == T_SOLID then
                    DrawSolidTile(px, py)
                elseif tile >= T_SW1 and tile <= T_SW5 then
                    DrawSwitch(px, py, tile - 10)
                end
            end
        end
    end
end

function DrawSolidTile(x, y)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, x, y, TILE, TILE)
    nvgFillColor(nvgCtx, nvgRGBA(C_PLATFORM[1], C_PLATFORM[2], C_PLATFORM[3], 255))
    nvgFill(nvgCtx)
    nvgStrokeWidth(nvgCtx, 1)
    nvgStrokeColor(nvgCtx, nvgRGBA(50, 60, 100, 180))
    nvgStroke(nvgCtx)
end

function DrawSwitch(x, y, level)
    local c = GRAVITY_LEVELS[level].color

    -- 实心底色 (表示可站立)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, x, y, TILE, TILE)
    nvgFillColor(nvgCtx, nvgRGBA(C_PLATFORM[1], C_PLATFORM[2], C_PLATFORM[3], 255))
    nvgFill(nvgCtx)

    -- 六边形发光层
    local cx = x + TILE / 2
    local cy = y + TILE / 2
    local r = TILE / 2 - 4
    nvgBeginPath(nvgCtx)
    for i = 0, 5 do
        local angle = math.rad(60 * i - 30)
        local hx = cx + r * math.cos(angle)
        local hy = cy + r * math.sin(angle)
        if i == 0 then nvgMoveTo(nvgCtx, hx, hy)
        else nvgLineTo(nvgCtx, hx, hy) end
    end
    nvgClosePath(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 50))
    nvgFill(nvgCtx)
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStrokeColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 200))
    nvgStroke(nvgCtx)

    -- 数字
    if fontId ~= -1 then
        nvgFontFaceId(nvgCtx, fontId)
        nvgFontSize(nvgCtx, 14)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 255))
        nvgText(nvgCtx, cx, cy, tostring(level), nil)
    end
end

function DrawSpawnAndExit()
    -- 出生点三角
    local sx = (editor.spawnX - 1) * TILE + TILE / 2
    local sy = (editor.spawnY - 1) * TILE + TILE / 2
    nvgBeginPath(nvgCtx)
    nvgMoveTo(nvgCtx, sx, sy - 10)
    nvgLineTo(nvgCtx, sx - 8, sy + 6)
    nvgLineTo(nvgCtx, sx + 8, sy + 6)
    nvgClosePath(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(0, 255, 150, 200))
    nvgFill(nvgCtx)

    -- 出口 (单瓦片)
    local ex = (editor.exitX - 1) * TILE
    local ey = (editor.exitY - 1) * TILE
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, ex, ey, TILE, TILE)
    nvgStrokeWidth(nvgCtx, 2)
    nvgStrokeColor(nvgCtx, nvgRGBA(C_EXIT[1], C_EXIT[2], C_EXIT[3], 200))
    nvgStroke(nvgCtx)
    nvgFillColor(nvgCtx, nvgRGBA(C_EXIT[1], C_EXIT[2], C_EXIT[3], 40))
    nvgFill(nvgCtx)

    if fontId ~= -1 then
        nvgFontFaceId(nvgCtx, fontId)
        nvgFontSize(nvgCtx, 10)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(C_EXIT[1], C_EXIT[2], C_EXIT[3], 255))
        nvgText(nvgCtx, ex + TILE / 2, ey + TILE / 2, "EXIT", nil)
    end
end

function DrawPlayer()
    local px = player.x
    local py = player.y
    local c = GRAVITY_LEVELS[player.gravityLevel].color

    -- 身体 (正方形)
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, px, py, PLAYER_W, PLAYER_H)
    nvgFillColor(nvgCtx, nvgRGBA(C_PLAYER[1], C_PLAYER[2], C_PLAYER[3], 240))
    nvgFill(nvgCtx)

    -- 脚底重力光晕
    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, px, py + PLAYER_H - 3, PLAYER_W, 3)
    nvgFillColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 180))
    nvgFill(nvgCtx)

    -- 眼睛
    local eyeX = px + PLAYER_W / 2 + player.facing * 3
    local eyeY = py + PLAYER_H / 2 - 2
    nvgBeginPath(nvgCtx)
    nvgCircle(nvgCtx, eyeX, eyeY, 2.5)
    nvgFillColor(nvgCtx, nvgRGBA(30, 40, 70, 255))
    nvgFill(nvgCtx)
end

function DrawEditorCursor()
    local tx, ty = MouseToTile()
    if tx < 1 or tx > MAP_W or ty < 1 or ty > MAP_H then return end

    local px = (tx - 1) * TILE - editor.cameraX
    local py = (ty - 1) * TILE - editor.cameraY

    nvgBeginPath(nvgCtx)
    nvgRect(nvgCtx, px + 1, py + 1, TILE - 2, TILE - 2)
    nvgStrokeWidth(nvgCtx, 1.5)
    nvgStrokeColor(nvgCtx, nvgRGBA(255, 255, 255, 120))
    nvgStroke(nvgCtx)

    -- 工具预览色
    if editor.tool == T_SOLID then
        nvgFillColor(nvgCtx, nvgRGBA(C_PLATFORM[1], C_PLATFORM[2], C_PLATFORM[3], 80))
    elseif editor.tool >= T_SW1 and editor.tool <= T_SW5 then
        local c = GRAVITY_LEVELS[editor.tool - 10].color
        nvgFillColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 50))
    elseif editor.tool == T_SPAWN then
        nvgFillColor(nvgCtx, nvgRGBA(0, 255, 150, 50))
    elseif editor.tool == T_EXIT then
        nvgFillColor(nvgCtx, nvgRGBA(C_EXIT[1], C_EXIT[2], C_EXIT[3], 50))
    end
    nvgFill(nvgCtx)
end

function DrawGravityHUD()
    local g = GRAVITY_LEVELS[player.gravityLevel]
    local c = g.color
    local x = 8
    local y = DESIGN_H - 44

    -- 背景
    nvgBeginPath(nvgCtx)
    nvgRoundedRect(nvgCtx, x, y, 90, 36, 5)
    nvgFillColor(nvgCtx, nvgRGBA(0, 0, 0, 180))
    nvgFill(nvgCtx)
    nvgStrokeWidth(nvgCtx, 1)
    nvgStrokeColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 100))
    nvgStroke(nvgCtx)

    if fontId ~= -1 then
        -- 等级大数字
        nvgFontFaceId(nvgCtx, fontId)
        nvgFontSize(nvgCtx, 22)
        nvgTextAlign(nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(c[1], c[2], c[3], 255))
        nvgText(nvgCtx, x + 20, y + 18, tostring(player.gravityLevel), nil)

        -- 名称
        nvgFontSize(nvgCtx, 11)
        nvgTextAlign(nvgCtx, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvgCtx, nvgRGBA(200, 210, 230, 220))
        nvgText(nvgCtx, x + 35, y + 13, g.name, nil)

        -- 跳跃格数
        nvgFontSize(nvgCtx, 9)
        nvgFillColor(nvgCtx, nvgRGBA(160, 170, 190, 180))
        nvgText(nvgCtx, x + 35, y + 26, "跳 " .. g.tiles .. " 格", nil)
    end
end
