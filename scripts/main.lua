-- ====================================================================
-- 《五四三二一：重力倒计时》— 关卡编辑器 v3
-- ====================================================================
-- 功能:
--   网格画布 (缩放/WASD平移)、12种元素
--   左键放置、右键清除
--   撤销/重做 (Ctrl+Z/Y)、BFS物理验证
--   JSON导出、文件保存/加载
-- ====================================================================

local UI = require("urhox-libs/UI")
local Config = require("Editor.Config")
local History = require("Editor.History")
local Tools = require("Editor.Tools")
local Validator = require("Editor.Validator")
local Storage = require("Editor.Storage")
local PlayMode = require("Editor.PlayMode")

-- ====================================================================
-- 全局状态
-- ====================================================================

-- NanoVG
---@type any
local vg = nil
local fontId = -1

-- 屏幕
local physW, physH = 0, 0
local scaleX, scaleY = 1, 1

-- 地图 (双层: 基础地形 + 开关覆盖层)
local map = {}       -- 基础层 (WALL, EMPTY, PLATFORM, SPIKE, CHECKPOINT)
local switchMap = {} -- 覆盖层 (0=无开关, 11-15=对应重力开关)
local mapW = Config.DEFAULT_MAP_W
local mapH = Config.DEFAULT_MAP_H
local spawnX, spawnY = 3, 20
local exitX, exitY = 67, 20
local levelName = "新关卡"

-- 编辑器状态
local currentTile = Config.TILES.WALL
local zoom = 1.0
local panX, panY = 0, 0
local isDragging = false   -- 左键绘制中
local isErasing = false    -- 右键清除中

-- 光标
local cursorTX, cursorTY = 0, 0
local cursorValid = false

-- 历史
local history = History.New()

-- 验证结果
local validationResults = nil
local showValidation = false

-- 通知
local notification = nil
local notifTimer = 0

-- 编辑/试玩模式
local isPlayMode = false

-- UI引用
---@type any
local uiRoot = nil

-- UI 工具栏高度
local TOOLBAR_H = 36
local PANEL_W = 130

-- WASD 画布移动速度 (设计像素/秒)
local PAN_SPEED = 300

-- ====================================================================
-- 初始化
-- ====================================================================

function Start()
    graphics.windowTitle = "五四三二一 — 关卡编辑器 v3"

    physW = graphics:GetWidth()
    physH = graphics:GetHeight()
    scaleX = physW / Config.DESIGN_W
    scaleY = physH / Config.DESIGN_H

    -- NanoVG
    vg = nvgCreate(1)
    if not vg then
        print("ERROR: nvgCreate failed")
        return
    end
    fontId = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")

    -- UI
    UI.Init({
        fonts = { { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } } },
        scale = UI.Scale.DEFAULT,
    })
    BuildUI()

    -- 初始化空白地图
    InitEmptyMap()

    -- 事件
    SubscribeToEvent(vg, "NanoVGRender", "HandleNanoVGRender")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseDown")
    SubscribeToEvent("MouseButtonUp", "HandleMouseUp")
    SubscribeToEvent("MouseMove", "HandleMouseMove")
    SubscribeToEvent("MouseWheel", "HandleMouseWheel")

    -- 重置视图到居中
    ResetView()

    -- 初始高亮默认元素
    SetElement(currentTile)

    print("=== 关卡编辑器 v3 启动 ===")
    print("左键放置 右键清除 WASD移动画布 滚轮缩放")
    print("Ctrl+Z撤销 Ctrl+Y重做 Ctrl+S保存 Ctrl+E导出")
    print("Space重置视图 F5试玩")
end

function Stop()
    UI.Shutdown()
    if vg then nvgDelete(vg) end
end

-- ====================================================================
-- 地图初始化
-- ====================================================================

function InitEmptyMap()
    map = {}
    switchMap = {}
    for y = 1, mapH do
        map[y] = {}
        switchMap[y] = {}
        for x = 1, mapW do
            map[y][x] = Config.TILES.EMPTY
            switchMap[y][x] = 0
        end
    end
    -- 底部地面
    for x = 1, mapW do
        map[mapH][x] = Config.TILES.WALL
        map[mapH - 1][x] = Config.TILES.WALL
    end
    spawnX, spawnY = 3, mapH - 2
    exitX, exitY = mapW - 3, mapH - 2
    history:Clear()
    validationResults = nil
end

-- ====================================================================
-- 视图控制
-- ====================================================================

function ResetView()
    zoom = 1.0
    -- 居中显示地图
    local mapPixW = mapW * Config.TILE
    local mapPixH = mapH * Config.TILE
    local canvasW = Config.DESIGN_W - PANEL_W
    local canvasH = Config.DESIGN_H - TOOLBAR_H
    panX = (canvasW - mapPixW * zoom) / 2 + PANEL_W
    panY = (canvasH - mapPixH * zoom) / 2 + TOOLBAR_H
end

function ScreenToTile(sx, sy)
    -- 屏幕坐标 → 设计坐标 → 瓦片坐标
    local dx = sx / scaleX
    local dy = sy / scaleY
    local worldX = (dx - panX) / zoom
    local worldY = (dy - panY) / zoom
    local tx = math.floor(worldX / Config.TILE) + 1
    local ty = math.floor(worldY / Config.TILE) + 1
    return tx, ty
end

-- ====================================================================
-- UI构建
-- ====================================================================

function BuildUI()
    local elementButtons = {}
    for _, e in ipairs(Config.ELEMENTS) do
        table.insert(elementButtons, UI.Button {
            id = "elem_" .. e.id,
            text = e.name .. "[" .. e.key .. "]",
            fontSize = 9,
            height = 20,
            paddingLeft = 4, paddingRight = 4,
            onClick = function() SetElement(e.id) end,
        })
    end

    local root = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 顶部工具栏
            UI.Panel {
                id = "toolbar",
                width = "100%", height = TOOLBAR_H,
                flexDirection = "row",
                alignItems = "center",
                paddingLeft = 6, paddingRight = 6, gap = 4,
                backgroundColor = { 20, 25, 45, 240 },
                children = {
                    -- 操作按钮
                    UI.Button { text = "验证[V]", fontSize = 9, height = 22, paddingLeft = 5, paddingRight = 5,
                        onClick = function() RunValidation() end },
                    UI.Button { text = "保存", fontSize = 9, height = 22, paddingLeft = 5, paddingRight = 5,
                        onClick = function() SaveCurrentLevel() end },
                    UI.Button { text = "导出JSON", fontSize = 9, height = 22, paddingLeft = 5, paddingRight = 5,
                        onClick = function() ExportLevel() end },
                    UI.Button { text = "清空", fontSize = 9, height = 22, paddingLeft = 5, paddingRight = 5,
                        variant = "danger",
                        onClick = function() ClearCurrentMap() end },
                    -- 分隔
                    UI.Panel { width = 1, height = 20, backgroundColor = { 60, 70, 100, 150 } },
                    -- 试玩按钮
                    UI.Button { id = "playBtn", text = "试玩[F5]", fontSize = 9, height = 22,
                        paddingLeft = 6, paddingRight = 6,
                        variant = "primary",
                        onClick = function() TogglePlayMode() end },
                    -- 弹性空间
                    UI.Panel { flexGrow = 1 },
                    -- 状态信息
                    UI.Label { id = "statusLabel", text = "...", fontSize = 9,
                        fontColor = { 180, 190, 210, 220 } },
                }
            },
            -- 左侧面板
            UI.Panel {
                id = "leftPanel",
                width = PANEL_W, height = Config.DESIGN_H - TOOLBAR_H,
                position = "absolute",
                left = 0, top = TOOLBAR_H,
                backgroundColor = { 15, 20, 38, 230 },
                paddingTop = 6, paddingLeft = 6, paddingRight = 6,
                gap = 4,
                children = {
                    UI.Label { text = "元素 (左键放置 右键清除)", fontSize = 9, fontColor = { 0, 229, 255, 255 } },
                    UI.Panel {
                        flexDirection = "row", flexWrap = "wrap", gap = 2,
                        children = elementButtons,
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Label { id = "infoLabel", text = "缩放:1.0x", fontSize = 8,
                        fontColor = { 100, 110, 130, 180 } },
                }
            },
        }
    }
    uiRoot = root
    UI.SetRoot(root)
    UpdateStatusUI()
end

-- ====================================================================
-- UI 更新
-- ====================================================================

function UpdateStatusUI()
    if not uiRoot then return end
    local label = uiRoot:FindById("statusLabel")
    if label then
        if isPlayMode then
            local ps = PlayMode.GetState()
            local gInfo = Config.GRAVITY_LEVELS[ps.gravityLevel]
            label:SetText(string.format("试玩中 | %s | 重力%d(%s)",
                levelName, ps.gravityLevel, gInfo.name))
        else
            local text = string.format("%s | %dx%d | %s | 撤销:%d 重做:%d",
                levelName, mapW, mapH,
                GetTileName(currentTile),
                history:GetUndoCount(), history:GetRedoCount())
            label:SetText(text)
        end
    end
    -- 更新试玩按钮文本
    local playBtn = uiRoot:FindById("playBtn")
    if playBtn then
        playBtn:SetText(isPlayMode and "返回编辑[F5]" or "试玩[F5]")
    end
end

function UpdateInfoLabel()
    if not uiRoot then return end
    local label = uiRoot:FindById("infoLabel")
    if label then
        label:SetText(string.format("缩放:%.1fx 格:%d,%d", zoom, cursorTX, cursorTY))
    end
end

function GetTileName(tileId)
    for _, e in ipairs(Config.ELEMENTS) do
        if e.id == tileId then return e.name end
    end
    return "未知"
end

function ShowNotification(msg)
    notification = msg
    notifTimer = 3.0
end

-- ====================================================================
-- 元素选择
-- ====================================================================

function SetElement(tileId)
    currentTile = tileId
    UpdateStatusUI()
    -- 高亮选中的元素按钮
    if uiRoot then
        for _, e in ipairs(Config.ELEMENTS) do
            local btn = uiRoot:FindById("elem_" .. e.id)
            if btn then
                if e.id == tileId then
                    btn:SetVariant("primary")
                else
                    btn:SetVariant("default")
                end
            end
        end
    end
end

-- ====================================================================
-- 试玩模式切换
-- ====================================================================

function TogglePlayMode()
    if isPlayMode then
        -- 退出试玩
        PlayMode.Exit()
        isPlayMode = false
        ShowNotification("编辑模式")
    else
        -- 进入试玩
        isPlayMode = true
        PlayMode.Enter(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY)
        ShowNotification("试玩模式 — ESC退出")
    end
    UpdateStatusUI()
end

-- ====================================================================
-- 绘制操作
-- ====================================================================

--- 放置当前元素
function PlaceTile(tx, ty)
    if tx < 1 or tx > mapW or ty < 1 or ty > mapH then return end

    -- 起点/出口特殊处理(只能有一个)
    if currentTile == Config.TILES.SPAWN then
        spawnX, spawnY = tx, ty
        print(string.format("[编辑器] 起点设置为 (%d,%d)", tx, ty))
        ShowNotification(string.format("起点已设置 (%d,%d)", tx, ty))
        UpdateStatusUI()
        return
    elseif currentTile == Config.TILES.EXIT then
        exitX, exitY = tx, ty
        print(string.format("[编辑器] 出口设置为 (%d,%d)", tx, ty))
        ShowNotification(string.format("出口已设置 (%d,%d)", tx, ty))
        UpdateStatusUI()
        return
    end

    -- 开关类型: 写入覆盖层 (不改变基础层)
    if Config.IsSwitch(currentTile) then
        local oldSwitch = switchMap[ty][tx]
        if oldSwitch ~= currentTile then
            local changes = { { x = tx, y = ty, oldTile = oldSwitch, newTile = currentTile, layer = "switch" } }
            switchMap[ty][tx] = currentTile
            history:Push(changes)
            UpdateStatusUI()
        end
        return
    end

    -- 普通瓦片: 写入基础层
    local changes = Tools.Brush(map, tx, ty, currentTile, mapW, mapH)
    if #changes > 0 then
        history:Push(changes)
        UpdateStatusUI()
    end
end

--- 清除瓦片（右键）— 优先清除覆盖层，若无覆盖则清基础层
function EraseTile(tx, ty)
    if tx < 1 or tx > mapW or ty < 1 or ty > mapH then return end

    -- 优先清除覆盖层的开关
    if switchMap[ty][tx] ~= 0 then
        local oldSwitch = switchMap[ty][tx]
        switchMap[ty][tx] = 0
        local changes = { { x = tx, y = ty, oldTile = oldSwitch, newTile = 0, layer = "switch" } }
        history:Push(changes)
        UpdateStatusUI()
        return
    end

    -- 覆盖层为空，清除基础层
    local changes = Tools.Eraser(map, tx, ty, mapW, mapH)
    if #changes > 0 then
        history:Push(changes)
        UpdateStatusUI()
    end
end

-- ====================================================================
-- 撤销/重做
-- ====================================================================

function Undo()
    local action = history:Undo()
    if action then
        for _, ch in ipairs(action) do
            if ch.x >= 1 and ch.x <= mapW and ch.y >= 1 and ch.y <= mapH then
                if ch.layer == "switch" then
                    switchMap[ch.y][ch.x] = ch.oldTile
                else
                    map[ch.y][ch.x] = ch.oldTile
                end
            end
        end
        UpdateStatusUI()
        ShowNotification("撤销")
    end
end

function Redo()
    local action = history:Redo()
    if action then
        for _, ch in ipairs(action) do
            if ch.x >= 1 and ch.x <= mapW and ch.y >= 1 and ch.y <= mapH then
                if ch.layer == "switch" then
                    switchMap[ch.y][ch.x] = ch.newTile
                else
                    map[ch.y][ch.x] = ch.newTile
                end
            end
        end
        UpdateStatusUI()
        ShowNotification("重做")
    end
end

-- ====================================================================
-- 验证
-- ====================================================================

function RunValidation()
    validationResults = Validator.Validate(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY)
    showValidation = true
    if validationResults.passed then
        ShowNotification("验证通过!")
    else
        ShowNotification("验证失败 — 查看详情")
    end
end

-- ====================================================================
-- 保存/导出
-- ====================================================================

function SaveCurrentLevel()
    local filename = "level_" .. os.time() .. ".json"
    local ok, path = Storage.SaveToFile(filename, map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY, levelName)
    if ok then
        Storage.UpdateIndex(filename, levelName)
        ShowNotification("已保存: " .. path)
    else
        ShowNotification("保存失败: " .. path)
    end
end

function ExportLevel()
    local json = Storage.ExportJSON(map, switchMap, mapW, mapH, spawnX, spawnY, exitX, exitY, levelName)
    -- 写入导出文件
    local file = File("export_level.json", FILE_WRITE)
    if file:IsOpen() then
        file:WriteString(json)
        file:Close()
        ShowNotification("已导出: export_level.json (可复制)")
        print("=== 导出JSON ===")
        print(json)
    else
        ShowNotification("导出失败")
    end
end

function ClearCurrentMap()
    -- 保存当前状态到历史 (整个地图作为一次操作)
    local changes = {}
    for y = 1, mapH do
        for x = 1, mapW do
            if map[y][x] ~= Config.TILES.EMPTY then
                table.insert(changes, { x = x, y = y, oldTile = map[y][x], newTile = Config.TILES.EMPTY })
            end
            if switchMap[y][x] ~= 0 then
                table.insert(changes, { x = x, y = y, oldTile = switchMap[y][x], newTile = 0, layer = "switch" })
            end
        end
    end
    if #changes > 0 then
        history:Push(changes)
    end
    -- 清空基础层和覆盖层
    for y = 1, mapH do
        for x = 1, mapW do
            map[y][x] = Config.TILES.EMPTY
            switchMap[y][x] = 0
        end
    end
    -- 重建地面
    for x = 1, mapW do
        map[mapH][x] = Config.TILES.WALL
        map[mapH - 1][x] = Config.TILES.WALL
    end
    ShowNotification("地图已清空")
    UpdateStatusUI()
end

-- ====================================================================
-- 事件: Update
-- ====================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 通知倒计时
    if notifTimer > 0 then
        notifTimer = notifTimer - dt
        if notifTimer <= 0 then
            notification = nil
        end
    end

    -- 更新屏幕尺寸
    physW = graphics:GetWidth()
    physH = graphics:GetHeight()
    scaleX = physW / Config.DESIGN_W
    scaleY = physH / Config.DESIGN_H

    -- 试玩模式物理更新
    if isPlayMode then
        PlayMode.Update(dt)

        -- 试玩时相机跟随角色
        local ps = PlayMode.GetState()
        if ps.active then
            local canvasW = Config.DESIGN_W - PANEL_W
            local canvasH = Config.DESIGN_H - TOOLBAR_H
            local targetPanX = PANEL_W + canvasW / 2 - ps.x * zoom
            local targetPanY = TOOLBAR_H + canvasH / 2 - ps.y * zoom
            -- 平滑跟随
            panX = panX + (targetPanX - panX) * math.min(1, dt * 6)
            panY = panY + (targetPanY - panY) * math.min(1, dt * 6)
        end
    else
        -- 编辑模式: WASD 移动画布
        local speed = PAN_SPEED * dt
        if input:GetKeyDown(KEY_W) then panY = panY + speed end
        if input:GetKeyDown(KEY_S) then panY = panY - speed end
        if input:GetKeyDown(KEY_A) then panX = panX + speed end
        if input:GetKeyDown(KEY_D) then panX = panX - speed end
    end
end

-- ====================================================================
-- 事件: 键盘
-- ====================================================================

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()
    local qual = eventData["Qualifiers"]:GetInt()
    local ctrl = (qual & QUAL_CTRL) ~= 0

    -- F5: 切换试玩模式 (任何时候可用)
    if key == KEY_F5 then
        TogglePlayMode()
        return
    end

    -- 试玩模式按键
    if isPlayMode then
        if key == KEY_ESCAPE then
            TogglePlayMode()  -- ESC退出试玩
        elseif key == KEY_R then
            PlayMode.Respawn()
            ShowNotification("重生")
        end
        return  -- 试玩模式下不处理编辑器快捷键
    end

    -- === 以下仅编辑模式 ===

    -- Ctrl 快捷键
    if ctrl then
        if key == KEY_Z then Undo() return end
        if key == KEY_Y then Redo() return end
        if key == KEY_S then SaveCurrentLevel() return end
        if key == KEY_E then ExportLevel() return end
    end

    -- 元素快捷键 (数字键等)
    for _, e in ipairs(Config.ELEMENTS) do
        if key == e.hotkey then
            SetElement(e.id)
            return
        end
    end

    -- 其他快捷键
    if key == KEY_SPACE then
        ResetView()
        ShowNotification("视图已重置")
    elseif key == KEY_V then
        RunValidation()
    elseif key == KEY_ESCAPE then
        showValidation = false
    end
end

-- ====================================================================
-- 事件: 鼠标
-- ====================================================================

---@param eventType string
---@param eventData MouseButtonDownEventData
function HandleMouseDown(eventType, eventData)
    if isPlayMode then return end

    local btn = eventData["Button"]:GetInt()
    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()

    -- 检查是否在画布区域 (排除工具栏和左侧面板)
    local dx = mx / scaleX
    local dy = my / scaleY
    if dy < TOOLBAR_H or dx < PANEL_W then return end

    local tx, ty = ScreenToTile(mx, my)
    cursorTX, cursorTY = tx, ty
    cursorValid = (tx >= 1 and tx <= mapW and ty >= 1 and ty <= mapH)

    if btn == MOUSEB_LEFT then
        -- 左键: 放置当前元素
        isDragging = true
        PlaceTile(tx, ty)
    elseif btn == MOUSEB_RIGHT then
        -- 右键: 清除
        isErasing = true
        EraseTile(tx, ty)
    end
end

---@param eventType string
---@param eventData MouseButtonUpEventData
function HandleMouseUp(eventType, eventData)
    if isPlayMode then return end

    local btn = eventData["Button"]:GetInt()
    if btn == MOUSEB_LEFT then
        isDragging = false
    elseif btn == MOUSEB_RIGHT then
        isErasing = false
    end
end

---@param eventType string
---@param eventData MouseMoveEventData
function HandleMouseMove(eventType, eventData)
    if isPlayMode then return end

    local mx = eventData["X"]:GetInt()
    local my = eventData["Y"]:GetInt()

    -- 更新光标瓦片位置
    local tx, ty = ScreenToTile(mx, my)
    cursorTX, cursorTY = tx, ty
    cursorValid = (tx >= 1 and tx <= mapW and ty >= 1 and ty <= mapH)
    UpdateInfoLabel()

    if isDragging then
        -- 持续放置
        PlaceTile(tx, ty)
    elseif isErasing then
        -- 持续清除
        EraseTile(tx, ty)
    end
end

---@param eventType string
---@param eventData MouseWheelEventData
function HandleMouseWheel(eventType, eventData)
    if isPlayMode then return end

    local wheel = eventData["Wheel"]:GetInt()
    local mx = input.mousePosition.x
    local my = input.mousePosition.y

    -- 检查是否在画布区域
    local dx = mx / scaleX
    local dy = my / scaleY
    if dy < TOOLBAR_H or dx < PANEL_W then return end

    local prevZoom = zoom
    if wheel > 0 then
        zoom = math.min(Config.ZOOM_MAX, zoom * Config.ZOOM_STEP)
    else
        zoom = math.max(Config.ZOOM_MIN, zoom / Config.ZOOM_STEP)
    end

    -- 缩放到鼠标位置
    local worldMX = dx - panX
    local worldMY = dy - panY
    panX = panX + worldMX * (1 - zoom / prevZoom)
    panY = panY + worldMY * (1 - zoom / prevZoom)

    UpdateInfoLabel()
end

-- ====================================================================
-- NanoVG 渲染
-- ====================================================================

function HandleNanoVGRender(eventType, eventData)
    if not vg then return end

    nvgBeginFrame(vg, physW, physH, 1.0)
    nvgSave(vg)
    nvgScale(vg, scaleX, scaleY)

    -- 背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, Config.DESIGN_W, Config.DESIGN_H)
    nvgFillColor(vg, nvgRGBA(Config.COLORS.BG[1], Config.COLORS.BG[2], Config.COLORS.BG[3], 255))
    nvgFill(vg)

    -- 画布区域裁剪
    nvgSave(vg)
    nvgScissor(vg, PANEL_W, TOOLBAR_H, Config.DESIGN_W - PANEL_W, Config.DESIGN_H - TOOLBAR_H)

    -- 应用画布变换 (平移+缩放)
    nvgSave(vg)
    nvgTranslate(vg, panX, panY)
    nvgScale(vg, zoom, zoom)

    -- 绘制网格
    DrawGrid()
    -- 绘制地图
    DrawMap()
    -- 绘制跳跃范围预览
    if isPlayMode then
        DrawJumpPreviewPlay()
    else
        DrawJumpPreview()
    end
    -- 绘制起点/出口
    DrawSpawnExit()

    if not isPlayMode then
        -- 绘制光标
        DrawCursor()
    end

    -- 试玩模式: 绘制角色 (在画布变换空间内)
    if isPlayMode then
        PlayMode.Draw(vg)
    end

    nvgRestore(vg)  -- 画布变换
    nvgResetScissor(vg)
    nvgRestore(vg)  -- 裁剪

    -- HUD层 (不受画布变换影响)
    if isPlayMode then
        PlayMode.DrawHUD(vg, fontId, Config.DESIGN_W, Config.DESIGN_H)
    end
    DrawNotification()
    if not isPlayMode then
        DrawValidationPanel()
    end

    nvgRestore(vg)  -- 缩放
    nvgEndFrame(vg)
end

-- ====================================================================
-- 绘制: 网格
-- ====================================================================

function DrawGrid()
    local TILE = Config.TILE
    local gc = Config.COLORS.GRID
    local gmc = Config.COLORS.GRID_MAJOR

    nvgStrokeWidth(vg, 0.5)

    -- 计算可见范围
    local visLeft = -panX / zoom
    local visTop = -panY / zoom
    local visW = (Config.DESIGN_W - PANEL_W) / zoom
    local visH = (Config.DESIGN_H - TOOLBAR_H) / zoom

    local startX = math.max(0, math.floor(visLeft / TILE) * TILE)
    local startY = math.max(0, math.floor(visTop / TILE) * TILE)
    local endX = math.min(mapW * TILE, startX + visW + TILE * 2)
    local endY = math.min(mapH * TILE, startY + visH + TILE * 2)

    for x = startX, endX, TILE do
        local col = math.floor(x / TILE)
        if col % 5 == 0 then
            nvgStrokeColor(vg, nvgRGBA(gmc[1], gmc[2], gmc[3], gmc[4]))
        else
            nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], gc[4]))
        end
        nvgBeginPath(vg)
        nvgMoveTo(vg, x, startY)
        nvgLineTo(vg, x, endY)
        nvgStroke(vg)
    end
    for y = startY, endY, TILE do
        local row = math.floor(y / TILE)
        if row % 5 == 0 then
            nvgStrokeColor(vg, nvgRGBA(gmc[1], gmc[2], gmc[3], gmc[4]))
        else
            nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], gc[4]))
        end
        nvgBeginPath(vg)
        nvgMoveTo(vg, startX, y)
        nvgLineTo(vg, endX, y)
        nvgStroke(vg)
    end

    -- 地图边界
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, mapW * TILE, mapH * TILE)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(100, 120, 180, 150))
    nvgStroke(vg)
end

-- ====================================================================
-- 绘制: 地图瓦片
-- ====================================================================

function DrawMap()
    local TILE = Config.TILE
    local T = Config.TILES

    -- 基础层
    for y = 1, mapH do
        for x = 1, mapW do
            local tile = map[y][x]
            if tile ~= T.EMPTY then
                local px = (x - 1) * TILE
                local py = (y - 1) * TILE
                DrawTile(px, py, tile)
            end
        end
    end

    -- 覆盖层: 开关装饰 (画在瓦片上方)
    for y = 1, mapH do
        for x = 1, mapW do
            local sw = switchMap[y][x]
            if sw ~= 0 then
                local px = (x - 1) * TILE
                local py = (y - 1) * TILE
                DrawSwitchOverlay(px, py, sw)
            end
        end
    end
end

function DrawTile(px, py, tileId)
    local TILE = Config.TILE
    local T = Config.TILES
    local C = Config.COLORS

    if tileId == T.WALL then
        nvgBeginPath(vg)
        nvgRect(vg, px, py, TILE, TILE)
        nvgFillColor(vg, nvgRGBA(C.WALL[1], C.WALL[2], C.WALL[3], 255))
        nvgFill(vg)
        nvgStrokeWidth(vg, 0.8)
        nvgStrokeColor(vg, nvgRGBA(C.WALL_STROKE[1], C.WALL_STROKE[2], C.WALL_STROKE[3], C.WALL_STROKE[4]))
        nvgStroke(vg)

    elseif tileId == T.CHECKPOINT then
        nvgBeginPath(vg)
        nvgRect(vg, px + 2, py + 2, TILE - 4, TILE - 4)
        nvgFillColor(vg, nvgRGBA(C.CHECKPOINT[1], C.CHECKPOINT[2], C.CHECKPOINT[3], 40))
        nvgFill(vg)
        nvgStrokeWidth(vg, 1.5)
        nvgStrokeColor(vg, nvgRGBA(C.CHECKPOINT[1], C.CHECKPOINT[2], C.CHECKPOINT[3], C.CHECKPOINT[4]))
        nvgStroke(vg)
        -- 旗帜图标
        if fontId >= 0 then
            nvgFontFaceId(vg, fontId)
            nvgFontSize(vg, 12)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgFillColor(vg, nvgRGBA(C.CHECKPOINT[1], C.CHECKPOINT[2], C.CHECKPOINT[3], 255))
            nvgText(vg, px + TILE/2, py + TILE/2, "CP", nil)
        end

    elseif tileId == T.SPIKE then
        -- 三角形尖刺
        nvgBeginPath(vg)
        nvgMoveTo(vg, px, py + TILE)
        nvgLineTo(vg, px + TILE/2, py + 4)
        nvgLineTo(vg, px + TILE, py + TILE)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(C.SPIKE[1], C.SPIKE[2], C.SPIKE[3], C.SPIKE[4]))
        nvgFill(vg)

    elseif tileId == T.PLATFORM then
        -- 单向平台 (顶部线条 + 虚线)
        nvgBeginPath(vg)
        nvgRect(vg, px, py, TILE, 4)
        nvgFillColor(vg, nvgRGBA(C.PLATFORM[1], C.PLATFORM[2], C.PLATFORM[3], C.PLATFORM[4]))
        nvgFill(vg)
        -- 虚线指示
        nvgStrokeWidth(vg, 1)
        nvgStrokeColor(vg, nvgRGBA(C.PLATFORM[1], C.PLATFORM[2], C.PLATFORM[3], 100))
        for i = 0, 2 do
            nvgBeginPath(vg)
            nvgMoveTo(vg, px + 4 + i * 10, py + 8)
            nvgLineTo(vg, px + 4 + i * 10, py + TILE - 4)
            nvgStroke(vg)
        end
    end
end

-- ====================================================================
-- 绘制: 覆盖层开关装饰 (半透明六边形按钮)
-- ====================================================================

function DrawSwitchOverlay(px, py, switchId)
    local TILE = Config.TILE
    local C = Config.COLORS
    local level = Config.GetSwitchLevel(switchId)
    if not level then return end
    local gc = C.GRAVITY[level]

    -- 半透明圆形底色
    local cx, cy = px + TILE / 2, py + TILE / 2
    local r = TILE / 2 - 3
    nvgBeginPath(vg)
    nvgCircle(vg, cx, cy, r)
    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 50))
    nvgFill(vg)

    -- 六边形轮廓
    local hr = TILE / 2 - 5
    nvgBeginPath(vg)
    for i = 0, 5 do
        local angle = math.rad(60 * i - 30)
        local hx = cx + hr * math.cos(angle)
        local hy = cy + hr * math.sin(angle)
        if i == 0 then nvgMoveTo(vg, hx, hy) else nvgLineTo(vg, hx, hy) end
    end
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 40))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 200))
    nvgStroke(vg)

    -- 数字
    if fontId >= 0 then
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 240))
        nvgText(vg, cx, cy, tostring(level), nil)
    end
end

-- ====================================================================
-- 绘制: 跳跃范围预览 (选中开关时高亮该重力下可达瓦片)
-- ====================================================================

-- 试玩模式: 基于玩家当前位置和重力等级显示跳跃范围
function DrawJumpPreviewPlay()
    local ps = PlayMode.GetState()
    if not ps or ps.dead or ps.won then return end

    local TILE = Config.TILE
    local C = Config.COLORS
    local JUMP_SPEED = Config.JUMP_SPEED
    local AIR_SPEED = 150

    local level = ps.gravityLevel
    local gInfo = Config.GRAVITY_LEVELS[level]
    local jumpTiles = gInfo.tiles
    local gravity = gInfo.gravity
    local gc = C.GRAVITY[level]

    -- 玩家脚底所在瓦片
    local playerTX = math.floor(ps.x / TILE) + 1
    local playerTY = math.floor(ps.y / TILE) + 1  -- 脚底瓦片

    -- 向下找最近地面
    local groundY = nil
    for y = playerTY, mapH do
        if Config.IsSolid(map[y][playerTX]) then
            groundY = y
            break
        end
    end
    if not groundY then return end

    local standTileY = groundY - 1
    if standTileY < 1 then return end

    -- 计算水平可达距离
    local airTime = 2 * JUMP_SPEED / gravity
    local horizTiles = math.floor(AIR_SPEED * airTime / TILE)

    local topTileY = math.max(1, standTileY - jumpTiles)

    -- 高亮可达瓦片
    for ty = topTileY, standTileY do
        local heightAbove = standTileY - ty
        local vertRatio = heightAbove / jumpTiles
        local availHoriz = math.floor(horizTiles * math.sqrt(math.max(0, 1 - vertRatio * vertRatio)))

        local rowLeft = math.max(1, playerTX - availHoriz)
        local rowRight = math.min(mapW, playerTX + availHoriz)

        for tx = rowLeft, rowRight do
            if not Config.IsSolid(map[ty][tx]) then
                local px = (tx - 1) * TILE
                local py = (ty - 1) * TILE
                nvgBeginPath(vg)
                nvgRect(vg, px + 1, py + 1, TILE - 2, TILE - 2)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 35))
                nvgFill(vg)
            end
        end
    end
end

-- 编辑模式: 基于光标位置和选中开关显示跳跃范围
function DrawJumpPreview()
    if not cursorValid then return end
    -- 仅当选中开关元素时显示对应重力的跳跃范围
    local level = Config.GetSwitchLevel(currentTile)
    if not level then return end

    local TILE = Config.TILE
    local C = Config.COLORS
    local JUMP_SPEED = Config.JUMP_SPEED
    local AIR_SPEED = 150

    local gInfo = Config.GRAVITY_LEVELS[level]
    local jumpTiles = gInfo.tiles
    local gravity = gInfo.gravity
    local gc = C.GRAVITY[level]

    -- 从光标位置向下找最近地面
    local groundY = nil
    for y = cursorTY, mapH do
        if Config.IsSolid(map[y][cursorTX]) then
            groundY = y
            break
        end
    end
    if not groundY then return end

    local standTileY = groundY - 1
    if standTileY < 1 then return end

    -- 计算水平可达距离
    local airTime = 2 * JUMP_SPEED / gravity
    local horizTiles = math.floor(AIR_SPEED * airTime / TILE)

    local topTileY = math.max(1, standTileY - jumpTiles)

    -- 高亮可达瓦片
    for ty = topTileY, standTileY do
        local heightAbove = standTileY - ty
        local vertRatio = heightAbove / jumpTiles
        local availHoriz = math.floor(horizTiles * math.sqrt(math.max(0, 1 - vertRatio * vertRatio)))

        local rowLeft = math.max(1, cursorTX - availHoriz)
        local rowRight = math.min(mapW, cursorTX + availHoriz)

        for tx = rowLeft, rowRight do
            if not Config.IsSolid(map[ty][tx]) then
                local px = (tx - 1) * TILE
                local py = (ty - 1) * TILE
                nvgBeginPath(vg)
                nvgRect(vg, px + 1, py + 1, TILE - 2, TILE - 2)
                nvgFillColor(vg, nvgRGBA(gc[1], gc[2], gc[3], 35))
                nvgFill(vg)
            end
        end
    end
end

-- ====================================================================
-- 绘制: 起点/出口
-- ====================================================================

function DrawSpawnExit()
    local TILE = Config.TILE
    local C = Config.COLORS

    -- 起点 (三角箭头)
    local sx = (spawnX - 1) * TILE + TILE / 2
    local sy = (spawnY - 1) * TILE + TILE / 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy - 12)
    nvgLineTo(vg, sx - 9, sy + 6)
    nvgLineTo(vg, sx + 9, sy + 6)
    nvgClosePath(vg)
    nvgFillColor(vg, nvgRGBA(C.SPAWN[1], C.SPAWN[2], C.SPAWN[3], C.SPAWN[4]))
    nvgFill(vg)
    if fontId >= 0 then
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 8)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg, nvgRGBA(C.SPAWN[1], C.SPAWN[2], C.SPAWN[3], 255))
        nvgText(vg, sx, sy + 8, "START", nil)
    end

    -- 出口
    local ex = (exitX - 1) * TILE
    local ey = (exitY - 1) * TILE
    nvgBeginPath(vg)
    nvgRect(vg, ex + 2, ey + 2, TILE - 4, TILE - 4)
    nvgStrokeWidth(vg, 2)
    nvgStrokeColor(vg, nvgRGBA(C.EXIT[1], C.EXIT[2], C.EXIT[3], C.EXIT[4]))
    nvgStroke(vg)
    nvgFillColor(vg, nvgRGBA(C.EXIT[1], C.EXIT[2], C.EXIT[3], 40))
    nvgFill(vg)
    if fontId >= 0 then
        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 10)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(C.EXIT[1], C.EXIT[2], C.EXIT[3], 255))
        nvgText(vg, ex + TILE/2, ey + TILE/2, "EXIT", nil)
    end
end

-- ====================================================================
-- 绘制: 光标
-- ====================================================================

function DrawCursor()
    if not cursorValid then return end
    local TILE = Config.TILE
    local px = (cursorTX - 1) * TILE
    local py = (cursorTY - 1) * TILE

    nvgBeginPath(vg)
    nvgRect(vg, px + 1, py + 1, TILE - 2, TILE - 2)
    nvgStrokeWidth(vg, 1.5)
    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 150))
    nvgStroke(vg)

    -- 当前瓦片预览色
    local tc = Config.GetTileColor(currentTile)
    if tc[1] then
        nvgFillColor(vg, nvgRGBA(tc[1], tc[2], tc[3], 40))
        nvgFill(vg)
    end
end

-- ====================================================================
-- 绘制: 通知
-- ====================================================================

function DrawNotification()
    if not notification then return end

    local alpha = math.min(255, math.floor(notifTimer * 255))
    local nx = Config.DESIGN_W / 2
    local ny = Config.DESIGN_H - 30

    if fontId >= 0 then
        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, nx - 120, ny - 12, 240, 24, 5)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.7)))
        nvgFill(vg)

        nvgFontFaceId(vg, fontId)
        nvgFontSize(vg, 12)
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(vg, nvgRGBA(220, 230, 255, alpha))
        nvgText(vg, nx, ny, notification, nil)
    end
end

-- ====================================================================
-- 绘制: 验证面板
-- ====================================================================

function DrawValidationPanel()
    if not showValidation or not validationResults then return end

    local x = Config.DESIGN_W - 220
    local y = TOOLBAR_H + 10
    local w = 210
    local lineH = 14
    local results = validationResults.results
    local h = 30 + #results * lineH

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, 6)
    nvgFillColor(vg, nvgRGBA(10, 15, 30, 230))
    nvgFill(vg)
    nvgStrokeWidth(vg, 1)
    local borderC = validationResults.passed and Config.COLORS.VALID_OK or Config.COLORS.VALID_ERROR
    nvgStrokeColor(vg, nvgRGBA(borderC[1], borderC[2], borderC[3], 150))
    nvgStroke(vg)

    if fontId >= 0 then
        nvgFontFaceId(vg, fontId)
        -- 标题
        nvgFontSize(vg, 11)
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local titleC = validationResults.passed and Config.COLORS.VALID_OK or Config.COLORS.VALID_ERROR
        nvgFillColor(vg, nvgRGBA(titleC[1], titleC[2], titleC[3], 255))
        local title = validationResults.passed and "验证通过" or "验证失败"
        nvgText(vg, x + 8, y + 6, title .. " (ESC关闭)", nil)

        -- 结果列表
        nvgFontSize(vg, 9)
        for i, r in ipairs(results) do
            local c
            if r.level == "ok" then c = Config.COLORS.VALID_OK
            elseif r.level == "warn" then c = Config.COLORS.VALID_WARN
            elseif r.level == "info" then c = Config.COLORS.TEXT_SECONDARY
            else c = Config.COLORS.VALID_ERROR end
            nvgFillColor(vg, nvgRGBA(c[1], c[2], c[3], c[4] or 255))
            local prefix = r.level == "ok" and "OK " or (r.level == "warn" and "!! " or (r.level == "error" and "XX " or "-- "))
            nvgText(vg, x + 8, y + 22 + (i - 1) * lineH, prefix .. r.msg, nil)
        end
    end
end
