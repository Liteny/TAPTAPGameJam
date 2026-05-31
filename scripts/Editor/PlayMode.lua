-- ====================================================================
-- Editor/PlayMode.lua — 试玩模式 (关卡内嵌角色物理)
-- ====================================================================
-- 实现策划案中的完整角色控制:
--   五级重力、固定跳跃、土狼时间、跳跃缓冲
--   碰撞检测、重力开关交互、死亡/重生
-- ====================================================================

local Config = require("Editor.Config")

local PlayMode = {}

-- ====================================================================
-- 物理常量 (单位: 像素, 帧率无关)
-- ====================================================================
local TILE = Config.TILE

-- 运动
local GROUND_SPEED   = 200    -- 地面水平速度 px/s
local AIR_SPEED      = 150    -- 空中水平速度 px/s
local GROUND_ACCEL   = 2000   -- 地面加速度 px/s²
local AIR_ACCEL      = 1200   -- 空中加速度
local GROUND_DECEL   = 1600   -- 地面减速度
local AIR_DECEL      = 600    -- 空中减速度
local MAX_FALL_SPEED = 800    -- 最大下落速度

-- 跳跃
local JUMP_SPEED     = Config.JUMP_SPEED  -- 跳跃初速度 (从Config取)
local COYOTE_TIME    = 0.08   -- 土狼时间 (离开地面后仍可跳跃)
local JUMP_BUFFER    = 0.12   -- 跳跃缓冲 (提前按键记忆)

-- 角色碰撞盒 (相对于角色脚底中心, 像素)
local PLAYER_W       = 20     -- 宽度
local PLAYER_H       = 28     -- 高度

-- ====================================================================
-- 状态
-- ====================================================================
local state = {
    active = false,     -- 试玩模式是否激活

    -- 位置/速度 (像素坐标, 左上角为原点)
    x = 0, y = 0,      -- 脚底中心
    vx = 0, vy = 0,

    -- 重力
    gravityLevel = 3,   -- 当前重力等级 (1-5)
    gravity = 1570,     -- 当前重力加速度 px/s²

    -- 跳跃
    onGround = false,
    coyoteTimer = 0,
    jumpBufferTimer = 0,
    jumping = false,

    -- 出生点
    spawnX = 0,
    spawnY = 0,
    checkpointX = 0,
    checkpointY = 0,

    -- 游戏状态
    dead = false,
    won = false,
    deathTimer = 0,

    -- 开关交互CD (防止反复触发)
    switchCooldown = 0,
}

-- 地图引用
local mapRef = nil
local switchMapRef = nil  -- 开关覆盖层
local mapWRef = 0
local mapHRef = 0
local exitXRef = 0
local exitYRef = 0

-- ====================================================================
-- 公共接口
-- ====================================================================

function PlayMode.IsActive()
    return state.active
end

function PlayMode.GetState()
    return state
end

--- 进入试玩模式
function PlayMode.Enter(map, switchMapParam, mapW, mapH, spawnX, spawnY, exitX, exitY)
    mapRef = map
    switchMapRef = switchMapParam
    mapWRef = mapW
    mapHRef = mapH
    exitXRef = exitX
    exitYRef = exitY

    -- 初始化角色到起点 (瓦片坐标 → 像素坐标, 脚底中心)
    state.spawnX = (spawnX - 1) * TILE + TILE / 2
    state.spawnY = spawnY * TILE  -- 脚底在瓦片底部
    state.checkpointX = state.spawnX
    state.checkpointY = state.spawnY

    -- 重置
    state.x = state.spawnX
    state.y = state.spawnY
    state.vx = 0
    state.vy = 0
    state.gravityLevel = 3       -- 当前实际重力
    state.baseGravityLevel = 3   -- 基础重力 (离开按钮后恢复)
    state.gravity = Config.GRAVITY_LEVELS[3].gravity
    state.onGround = false
    state.coyoteTimer = 0
    state.jumpBufferTimer = 0
    state.jumping = false
    state.dead = false
    state.won = false
    state.deathTimer = 0
    state.switchCooldown = 0
    state.onSwitch = false       -- 当前是否站在开关上
    state.active = true
end

--- 退出试玩模式
function PlayMode.Exit()
    state.active = false
end

--- 重生
function PlayMode.Respawn()
    state.x = state.checkpointX
    state.y = state.checkpointY
    state.vx = 0
    state.vy = 0
    state.onGround = false
    state.coyoteTimer = 0
    state.jumpBufferTimer = 0
    state.jumping = false
    state.dead = false
    state.deathTimer = 0
end

--- 每帧更新
function PlayMode.Update(dt)
    if not state.active then return end

    -- 死亡动画
    if state.dead then
        state.deathTimer = state.deathTimer + dt
        if state.deathTimer > 0.6 then
            PlayMode.Respawn()
        end
        return
    end

    -- 通关则不更新
    if state.won then return end

    -- 开关冷却
    if state.switchCooldown > 0 then
        state.switchCooldown = state.switchCooldown - dt
    end

    -- 输入
    local moveDir = 0
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then moveDir = moveDir - 1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then moveDir = moveDir + 1 end

    local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP)
    local jumpHeld = input:GetKeyDown(KEY_SPACE) or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP)

    -- 跳跃缓冲
    if jumpPressed then
        state.jumpBufferTimer = JUMP_BUFFER
    end
    if state.jumpBufferTimer > 0 then
        state.jumpBufferTimer = state.jumpBufferTimer - dt
    end

    -- 水平移动
    local maxSpeed = state.onGround and GROUND_SPEED or AIR_SPEED
    local accel = state.onGround and GROUND_ACCEL or AIR_ACCEL
    local decel = state.onGround and GROUND_DECEL or AIR_DECEL

    if moveDir ~= 0 then
        state.vx = state.vx + moveDir * accel * dt
        if math.abs(state.vx) > maxSpeed then
            state.vx = moveDir * maxSpeed
        end
    else
        -- 减速
        if state.vx > 0 then
            state.vx = math.max(0, state.vx - decel * dt)
        elseif state.vx < 0 then
            state.vx = math.min(0, state.vx + decel * dt)
        end
    end

    -- 跳跃
    local canJump = state.onGround or (state.coyoteTimer > 0)
    if state.jumpBufferTimer > 0 and canJump then
        state.vy = -JUMP_SPEED
        state.jumping = true
        state.onGround = false
        state.coyoteTimer = 0
        state.jumpBufferTimer = 0
    end

    -- 重力
    state.vy = state.vy + state.gravity * dt
    if state.vy > MAX_FALL_SPEED then
        state.vy = MAX_FALL_SPEED
    end

    -- 土狼时间
    if state.onGround then
        state.coyoteTimer = COYOTE_TIME
    else
        if state.coyoteTimer > 0 then
            state.coyoteTimer = state.coyoteTimer - dt
        end
    end

    -- 移动 + 碰撞
    MoveAndCollide(dt)

    -- 检测交互 (开关、出口、检查点、尖刺)
    CheckInteractions()
end

-- ====================================================================
-- 碰撞检测 (AABB vs 瓦片网格)
-- ====================================================================

--- 获取角色AABB (基于脚底中心)
local function GetAABB(px, py)
    local left = px - PLAYER_W / 2
    local top  = py - PLAYER_H
    local right = px + PLAYER_W / 2
    local bottom = py
    return left, top, right, bottom
end

--- 检查像素点对应的瓦片是否为实心 (开关为覆盖层，不参与碰撞)
local function IsSolidAt(px, py)
    local tx = math.floor(px / TILE) + 1
    local ty = math.floor(py / TILE) + 1
    if tx < 1 or tx > mapWRef or ty < 1 or ty > mapHRef then
        return true  -- 边界视为实心
    end
    return mapRef[ty][tx] == Config.TILES.WALL
end

--- 检查像素点是否为单向平台 (仅从上方碰撞)
local function IsPlatformAt(px, py)
    local tx = math.floor(px / TILE) + 1
    local ty = math.floor(py / TILE) + 1
    if tx < 1 or tx > mapWRef or ty < 1 or ty > mapHRef then
        return false
    end
    return mapRef[ty][tx] == Config.TILES.PLATFORM
end

--- 检查某AABB是否与实心瓦片重叠 (开关不参与碰撞)
local function AABBOverlapsSolid(left, top, right, bottom)
    -- 遍历AABB覆盖的所有瓦片
    local tx1 = math.floor(left / TILE) + 1
    local ty1 = math.floor(top / TILE) + 1
    local tx2 = math.floor((right - 0.01) / TILE) + 1
    local ty2 = math.floor((bottom - 0.01) / TILE) + 1

    for ty = ty1, ty2 do
        for tx = tx1, tx2 do
            if tx >= 1 and tx <= mapWRef and ty >= 1 and ty <= mapHRef then
                if mapRef[ty][tx] == Config.TILES.WALL then
                    return true
                end
            elseif tx < 1 or tx > mapWRef or ty < 1 or ty > mapHRef then
                return true  -- 边界
            end
        end
    end
    return false
end

function MoveAndCollide(dt)
    local dx = state.vx * dt
    local dy = state.vy * dt

    -- 水平移动
    local newX = state.x + dx
    local left, top, right, bottom = GetAABB(newX, state.y)
    if AABBOverlapsSolid(left, top, right, bottom) then
        -- 水平碰撞 - 推出
        if dx > 0 then
            -- 向右碰墙
            local wallTX = math.floor(right / TILE) + 1
            newX = (wallTX - 1) * TILE - PLAYER_W / 2 - 0.01
        else
            -- 向左碰墙
            local wallTX = math.floor(left / TILE) + 1
            newX = wallTX * TILE + PLAYER_W / 2 + 0.01
        end
        state.vx = 0
    end
    state.x = newX

    -- 垂直移动
    local oldOnGround = state.onGround
    state.onGround = false

    local newY = state.y + dy
    left, top, right, bottom = GetAABB(state.x, newY)

    if dy >= 0 then
        -- 下落 - 检查实心和单向平台
        if AABBOverlapsSolid(left, top, right, bottom) then
            -- 撞地面
            local groundTY = math.floor(bottom / TILE) + 1
            newY = (groundTY - 1) * TILE
            state.vy = 0
            state.onGround = true
            state.jumping = false
        else
            -- 检查单向平台 (仅在下落且脚底刚越过平台顶部时)
            local feetTY_old = math.floor(state.y / TILE) + 1
            local feetTY_new = math.floor(newY / TILE) + 1
            if feetTY_new > feetTY_old then
                -- 检查是否穿过了平台
                for ty = feetTY_old + 1, feetTY_new do
                    local checkLeft = math.floor((state.x - PLAYER_W / 2) / TILE) + 1
                    local checkRight = math.floor((state.x + PLAYER_W / 2 - 0.01) / TILE) + 1
                    for tx = checkLeft, checkRight do
                        if tx >= 1 and tx <= mapWRef and ty >= 1 and ty <= mapHRef then
                            if mapRef[ty][tx] == Config.TILES.PLATFORM then
                                -- 站在平台上
                                newY = (ty - 1) * TILE
                                state.vy = 0
                                state.onGround = true
                                state.jumping = false
                                break
                            end
                        end
                    end
                    if state.onGround then break end
                end
            end
        end
    else
        -- 上升 - 只检查实心
        if AABBOverlapsSolid(left, top, right, bottom) then
            -- 撞头
            local ceilTY = math.floor(top / TILE) + 1
            newY = ceilTY * TILE + PLAYER_H + 0.01
            state.vy = 0
        end
    end

    state.y = newY

    -- 掉出地图底部 → 死亡
    if state.y > mapHRef * TILE + TILE * 2 then
        state.dead = true
    end
end

-- ====================================================================
-- 交互检测
-- ====================================================================

function CheckInteractions()
    -- 角色中心所在瓦片
    local cx = state.x
    local cy = state.y - PLAYER_H / 2  -- 角色中心
    local tx = math.floor(cx / TILE) + 1
    local ty = math.floor(cy / TILE) + 1

    -- === 按钮式重力开关 (覆盖层检测) ===
    -- 检测角色脚底区域覆盖的 switchMap 瓦片
    local left, top2, right, bottom2 = GetAABB(state.x, state.y)
    local stx1 = math.floor(left / TILE) + 1
    local sty1 = math.floor(top2 / TILE) + 1
    local stx2 = math.floor((right - 0.01) / TILE) + 1
    local sty2 = math.floor((bottom2 - 0.01) / TILE) + 1
    -- 也检查脚底正下方 (站在开关上的情况)
    local standTY = math.floor(state.y / TILE) + 1
    local sty2_ext = math.max(sty2, standTY)

    local foundSwitchLevel = nil
    for sty = sty1, sty2_ext do
        for stx = stx1, stx2 do
            if stx >= 1 and stx <= mapWRef and sty >= 1 and sty <= mapHRef then
                local sw = switchMapRef[sty][stx]
                if sw ~= 0 then
                    foundSwitchLevel = Config.GetSwitchLevel(sw)
                    break
                end
            end
        end
        if foundSwitchLevel then break end
    end

    if foundSwitchLevel then
        -- 踩到按钮: 永久切换重力等级
        if not state.onSwitch or state.gravityLevel ~= foundSwitchLevel then
            state.gravityLevel = foundSwitchLevel
            state.baseGravityLevel = foundSwitchLevel  -- 永久更新
            state.gravity = Config.GRAVITY_LEVELS[foundSwitchLevel].gravity
        end
        state.onSwitch = true
    else
        state.onSwitch = false
    end

    -- 检查点
    if tx >= 1 and tx <= mapWRef and ty >= 1 and ty <= mapHRef then
        if mapRef[ty][tx] == Config.TILES.CHECKPOINT then
            state.checkpointX = state.x
            state.checkpointY = state.y
        end
    end

    -- 尖刺 (碰撞盒内任何瓦片)
    local left2, top3, right2, bottom3 = GetAABB(state.x, state.y)
    local tx1 = math.floor(left2 / TILE) + 1
    local ty1 = math.floor(top3 / TILE) + 1
    local tx2 = math.floor((right2 - 0.01) / TILE) + 1
    local ty2 = math.floor((bottom3 - 0.01) / TILE) + 1
    for tty = ty1, ty2 do
        for ttx = tx1, tx2 do
            if ttx >= 1 and ttx <= mapWRef and tty >= 1 and tty <= mapHRef then
                if mapRef[tty][ttx] == Config.TILES.SPIKE then
                    state.dead = true
                    return
                end
            end
        end
    end

    -- 出口
    if math.abs(state.x - ((exitXRef - 1) * TILE + TILE / 2)) < TILE and
       math.abs((state.y - PLAYER_H / 2) - ((exitYRef - 1) * TILE + TILE / 2)) < TILE then
        state.won = true
    end
end

-- ====================================================================
-- 渲染 (由 main.lua 的 NanoVG 渲染调用)
-- ====================================================================

function PlayMode.Draw(vg)
    if not state.active then return end

    local C = Config.COLORS
    local gc = C.GRAVITY[state.gravityLevel]

    -- 角色 (简单矩形 + 颜色指示当前重力)
    local left = state.x - PLAYER_W / 2
    local top = state.y - PLAYER_H

    if state.dead then
        -- 死亡闪烁
        local flash = math.floor(state.deathTimer * 10) % 2
        if flash == 0 then
            nvgBeginPath(vg)
            nvgRect(vg, left - 2, top - 2, PLAYER_W + 4, PLAYER_H + 4)
            nvgFillColor(vg, nvgRGBA(255, 50, 50, 150))
            nvgFill(vg)
        end
    else
        -- 身体
        nvgBeginPath(vg)
        nvgRoundedRect(vg, left, top, PLAYER_W, PLAYER_H, 3)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 200))
        nvgFill(vg)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
        nvgStroke(vg)

        -- "眼睛" (朝向指示)
        local eyeX = state.vx >= 0 and (state.x + 3) or (state.x - 7)
        local eyeY = top + 8
        nvgBeginPath(vg)
        nvgCircle(vg, eyeX, eyeY, 3)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, eyeX + 1, eyeY, 1.5)
        nvgFillColor(vg, nvgRGBA(20, 20, 40, 255))
        nvgFill(vg)

        -- 重力等级标识
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        nvgText(vg, state.x, top - 3, "G" .. state.gravityLevel, nil)
    end
end

--- 绘制HUD (不受画布变换影响)
function PlayMode.DrawHUD(vg, fontId, designW, designH)
    if not state.active then return end

    local C = Config.COLORS
    local gc = C.GRAVITY[state.gravityLevel]
    local gInfo = Config.GRAVITY_LEVELS[state.gravityLevel]

    -- 顶部HUD背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, designW, 28)
    nvgFillColor(vg, nvgRGBA(10, 15, 30, 220))
    nvgFill(vg)

    if fontId >= 0 then
        nvgFontFaceId(vg, fontId)

        -- 重力信息
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 255))
        nvgText(vg, 10, 14, string.format("重力 %d (%s) | 跳跃 %d 格",
            state.gravityLevel, gInfo.name, gInfo.tiles), nil)

        -- 操作提示
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(180, 190, 210, 180))
        nvgText(vg, designW / 2, 14, "A/D移动 Space跳跃 R重生 ESC退出试玩", nil)

        -- 状态
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        if state.won then
            nvgFillColor(vg, nvgRGBA(0, 255, 150, 255))
            nvgText(vg, designW - 10, 14, "通关!", nil)
        elseif state.dead then
            nvgFillColor(vg, nvgRGBA(255, 50, 50, 255))
            nvgText(vg, designW - 10, 14, "死亡...", nil)
        end
    end
end

return PlayMode
