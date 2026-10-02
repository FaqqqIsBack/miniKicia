-- miniKicia v1 — RIVALS walkspeed only (0..10 multiplier)
-- Slide speed is left untouched — walkspeed is the only thing scaled.
-- KiciaHook-derived: env probe, capability stubs, cloneref hygiene,
-- upvalue-proxy walkspeed hook with stack-inspection slide bypass.

(function()

-- ─── env resolution ─────────────────────────────────────────────────
local function resolveGenv()
    local candidates = {}
    if type(getgenv) == 'function' then
        local ok, env = pcall(getgenv)
        if ok and type(env) == 'table' then table.insert(candidates, env) end
    end
    if type(getfenv) == 'function' then
        local ok, env = pcall(getfenv, 0)
        if ok and type(env) == 'table' then table.insert(candidates, env) end
    end
    for _, env in ipairs(candidates) do
        local wrote = pcall(function() env.__mk_probe = true end)
        local seen = __mk_probe == true
        pcall(function() env.__mk_probe = nil end)
        if wrote and seen then return env end
    end
    return _G
end

local genv = resolveGenv()
if genv.__mk_ran or _G.__mk_ran then return end
genv.__mk_ran = true

-- ─── executor capability stubs ──────────────────────────────────────
do
    local noop = function() end
    local stubs = {
        cloneref          = function(o) return o end,
        clonefunction     = function(f) return f end,
        hookfunction      = function(o) return o end,
        newcclosure       = function(f) return f end,
        getnamecallmethod = function() return '' end,
        setthreadidentity = noop,
        getthreadidentity = function() return 0 end,
        isfunctionhooked  = function() return false end,
    }
    for name, stub in pairs(stubs) do
        if rawget(genv, name) == nil then genv[name] = stub end
    end
end

local cloneref      = genv.cloneref
local clonefunction = genv.clonefunction

if type(setthreadidentity) == 'function' then pcall(setthreadidentity, 8) end

-- ─── clean FireServer (Kicia primitive, kept for future expansion) ─
local __fireProto = Instance.new('RemoteEvent')
local cleanFire   = clonefunction(__fireProto.FireServer)

-- ─── services ───────────────────────────────────────────────────────
local Players           = cloneref(game:GetService('Players'))
local RunService        = cloneref(game:GetService('RunService'))
local UserInputService  = cloneref(game:GetService('UserInputService'))
local ReplicatedStorage = cloneref(game:GetService('ReplicatedStorage'))

local LP = Players.LocalPlayer

-- ─── state ──────────────────────────────────────────────────────────
local State = {
    Enabled    = true,
    Multiplier = 1,
    HookLoaded = false,
    HookGet    = nil,
    HookIdx    = nil,
    HookOld    = nil,
}

-- ─── mechanics controller resolution ────────────────────────────────
local MechanicsCache = nil
local function resolveMechanics()
    if MechanicsCache then return MechanicsCache end
    local ps   = LP:FindFirstChild('PlayerScripts')
    local ctrl = ps and ps:FindFirstChild('Controllers')
    local mod  = ctrl and ctrl:FindFirstChild('MechanicsController')
    if not mod then return nil end
    local ok, m = pcall(require, mod)
    if not ok or type(m) ~= 'table' then return nil end
    MechanicsCache = m
    return m
end

-- ─── walkspeed hook ─────────────────────────────────────────────────
local function loadWalkHook()
    if State.HookLoaded then return true end
    if type(debug.getupvalues) ~= 'function'
        or type(debug.setupvalue) ~= 'function'
        or type(debug.info) ~= 'function' then
        return false
    end

    local mech = resolveMechanics()
    if type(mech) ~= 'table' then return false end

    local mt  = getmetatable(mech)
    local idx = type(mt) == 'table' and rawget(mt, '__index') or nil
    local getWS = type(idx) == 'table' and rawget(idx, '_GetWalkSpeed') or nil
    if type(getWS) ~= 'function' then return false end

    local upIdx, oldTable
    for i, v in pairs(debug.getupvalues(getWS)) do
        if type(v) == 'table' and rawget(v, 'BASE_WALKSPEED') ~= nil then
            upIdx, oldTable = i, v
            break
        end
    end
    if upIdx == nil then return false end

    State.HookGet = getWS
    State.HookIdx = upIdx
    State.HookOld = oldTable

    debug.setupvalue(getWS, upIdx, setmetatable({}, {
        __index = function(_, key)
            if key ~= 'BASE_WALKSPEED' then
                pcall(function() LP:Kick('miniKicia: physics integrity') end)
                return nil
            end

            local base = rawget(oldTable, 'BASE_WALKSPEED')

            -- Slide path: hand back vanilla base, never scaled.
            if debug.info(3, 'n') == 'Slide' then
                return base
            end

            if State.Enabled then
                return base * State.Multiplier
            end
            return base
        end,
    }))

    State.HookLoaded = true
    return true
end

local function unloadWalkHook()
    if not State.HookLoaded then return end
    if State.HookGet and State.HookIdx and State.HookOld then
        pcall(debug.setupvalue, State.HookGet, State.HookIdx, State.HookOld)
    end
    State.HookLoaded = false
    State.HookGet, State.HookIdx, State.HookOld = nil, nil, nil
end

-- ─── UI ─────────────────────────────────────────────────────────────
local function buildUI()
    local screen = Instance.new('ScreenGui')
    screen.Name = 'miniKicia'
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local ok, parent = pcall(function()
        return gethui and gethui() or game:GetService('CoreGui')
    end)
    screen.Parent = ok and parent or LP:WaitForChild('PlayerGui')

    local frame = Instance.new('Frame')
    frame.Size = UDim2.fromOffset(240, 96)
    frame.Position = UDim2.fromOffset(40, 40)
    frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = screen

    local corner = Instance.new('UICorner')
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = frame

    local stroke = Instance.new('UIStroke')
    stroke.Color = Color3.fromRGB(60, 60, 70)
    stroke.Parent = frame

    local title = Instance.new('TextLabel')
    title.Size = UDim2.new(1, -12, 0, 24)
    title.Position = UDim2.fromOffset(6, 4)
    title.BackgroundTransparency = 1
    title.Text = 'miniKicia  ·  walkspeed'
    title.TextColor3 = Color3.fromRGB(200, 200, 210)
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local toggle = Instance.new('TextButton')
    toggle.Size = UDim2.new(1, -12, 0, 24)
    toggle.Position = UDim2.fromOffset(6, 32)
    toggle.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
    toggle.BorderSizePixel = 0
    toggle.Text = 'enabled  ·  true'
    toggle.TextColor3 = Color3.fromRGB(120, 220, 140)
    toggle.Font = Enum.Font.Code
    toggle.TextSize = 13
    toggle.Parent = frame
    local tCorner = Instance.new('UICorner')
    tCorner.CornerRadius = UDim.new(0, 4)
    tCorner.Parent = toggle

    local sliderLabel = Instance.new('TextLabel')
    sliderLabel.Size = UDim2.new(1, -12, 0, 16)
    sliderLabel.Position = UDim2.fromOffset(6, 60)
    sliderLabel.BackgroundTransparency = 1
    sliderLabel.Text = 'multiplier  ·  1.00'
    sliderLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
    sliderLabel.Font = Enum.Font.Code
    sliderLabel.TextSize = 12
    sliderLabel.TextXAlignment = Enum.TextXAlignment.Left
    sliderLabel.Parent = frame

    local track = Instance.new('TextButton')
    track.Size = UDim2.new(1, -12, 0, 12)
    track.Position = UDim2.fromOffset(6, 78)
    track.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
    track.BorderSizePixel = 0
    track.Text = ''
    track.Parent = frame
    local trackCorner = Instance.new('UICorner')
    trackCorner.CornerRadius = UDim.new(1, 0)
    trackCorner.Parent = track

    local fill = Instance.new('Frame')
    fill.Size = UDim2.new(0.1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(120, 160, 240)
    fill.BorderSizePixel = 0
    fill.Parent = track
    local fillCorner = Instance.new('UICorner')
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local MIN, MAX = 0, 10

    local function renderSlider()
        local pct = (State.Multiplier - MIN) / (MAX - MIN)
        fill.Size = UDim2.new(pct, 0, 1, 0)
        sliderLabel.Text = string.format('multiplier  ·  %.2f', State.Multiplier)
    end

    local function setFromX(absX)
        local rel = (absX - track.AbsolutePosition.X) / track.AbsoluteSize.X
        rel = math.clamp(rel, 0, 1)
        State.Multiplier = MIN + (MAX - MIN) * rel
        State.Multiplier = math.floor(State.Multiplier * 100 + 0.5) / 100
        renderSlider()
    end

    local dragging = false
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    track.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    toggle.MouseButton1Click:Connect(function()
        State.Enabled = not State.Enabled
        toggle.Text = 'enabled  ·  ' .. tostring(State.Enabled)
        toggle.TextColor3 = State.Enabled
            and Color3.fromRGB(120, 220, 140)
            or Color3.fromRGB(200, 100, 100)
    end)

    renderSlider()
end

buildUI()

-- ─── drive the hook ─────────────────────────────────────────────────
task.spawn(function()
    while true do
        task.wait(0.5)
        if not State.HookLoaded then
            loadWalkHook()
        end
    end
end)

-- ─── unload ─────────────────────────────────────────────────────────
genv.__mk_unload = function()
    unloadWalkHook()
    genv.__mk_ran = nil
    pcall(function() _G.__mk_ran = nil end)
end

end)()
