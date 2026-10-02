-- miniKicia v2 — walk + slide speed, independent sliders with type-in
-- Walk multiplier only touches walking. Slide multiplier only touches sliding.
-- Same KiciaHook hygiene: env probe, capability stubs, cloneref, upvalue proxy.

(function()

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

local __fireProto = Instance.new('RemoteEvent')
local cleanFire   = clonefunction(__fireProto.FireServer)

local Players           = cloneref(game:GetService('Players'))
local RunService        = cloneref(game:GetService('RunService'))
local UserInputService  = cloneref(game:GetService('UserInputService'))
local ReplicatedStorage = cloneref(game:GetService('ReplicatedStorage'))

local LP = Players.LocalPlayer

local State = {
    Enabled    = true,
    WalkMult   = 1,
    SlideMult  = 1,
    HookLoaded = false,
    HookGet    = nil,
    HookIdx    = nil,
    HookOld    = nil,
}

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

local function isSlidingNow()
    local m = MechanicsCache
    if type(m) ~= 'table' then return false end
    if rawget(m, 'IsSliding') == true then return true end
    if rawget(m, '_is_sliding') == true then return true end
    if rawget(m, 'Sliding') == true then return true end
    return false
end

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
            if not State.Enabled then return base end

            -- Slide detection: state flag first, stack name as fallback.
            local sliding = isSlidingNow()
            if not sliding then
                for level = 2, 5 do
                    local name = debug.info(level, 'n')
                    if type(name) == 'string' and name:lower():find('slide', 1, true) then
                        sliding = true
                        break
                    end
                end
            end

            if sliding then
                return base * State.SlideMult
            end
            return base * State.WalkMult
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
    frame.Size = UDim2.fromOffset(260, 156)
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
    title.Size = UDim2.new(1, -12, 0, 20)
    title.Position = UDim2.fromOffset(6, 4)
    title.BackgroundTransparency = 1
    title.Text = 'miniKicia  ·  speed'
    title.TextColor3 = Color3.fromRGB(200, 200, 210)
    title.Font = Enum.Font.Code
    title.TextSize = 14
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local toggle = Instance.new('TextButton')
    toggle.Size = UDim2.new(1, -12, 0, 22)
    toggle.Position = UDim2.fromOffset(6, 26)
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

    -- helper: build one slider row (label + textbox + track)
    local MIN, MAX = 0, 10

    local function buildRow(yOffset, labelText, initial, onChange)
        local rowLabel = Instance.new('TextLabel')
        rowLabel.Size = UDim2.new(1, -90, 0, 18)
        rowLabel.Position = UDim2.fromOffset(6, yOffset)
        rowLabel.BackgroundTransparency = 1
        rowLabel.Text = string.format('%s  ·  %.2f', labelText, initial)
        rowLabel.TextColor3 = Color3.fromRGB(180, 180, 190)
        rowLabel.Font = Enum.Font.Code
        rowLabel.TextSize = 12
        rowLabel.TextXAlignment = Enum.TextXAlignment.Left
        rowLabel.Parent = frame

        local input = Instance.new('TextBox')
        input.Size = UDim2.fromOffset(56, 18)
        input.Position = UDim2.fromOffset(198, yOffset)
        input.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
        input.BorderSizePixel = 0
        input.Text = string.format('%.2f', initial)
        input.TextColor3 = Color3.fromRGB(220, 220, 230)
        input.Font = Enum.Font.Code
        input.TextSize = 12
        input.ClearTextOnFocus = true
        input.Parent = frame
        local iCorner = Instance.new('UICorner')
        iCorner.CornerRadius = UDim.new(0, 3)
        iCorner.Parent = input

        local track = Instance.new('TextButton')
        track.Size = UDim2.new(1, -12, 0, 10)
        track.Position = UDim2.fromOffset(6, yOffset + 20)
        track.BackgroundColor3 = Color3.fromRGB(34, 34, 42)
        track.BorderSizePixel = 0
        track.Text = ''
        track.Parent = frame
        local trCorner = Instance.new('UICorner')
        trCorner.CornerRadius = UDim.new(1, 0)
        trCorner.Parent = track

        local fill = Instance.new('Frame')
        fill.Size = UDim2.new(initial / MAX, 0, 1, 0)
        fill.BackgroundColor3 = Color3.fromRGB(120, 160, 240)
        fill.BorderSizePixel = 0
        fill.Parent = track
        local fCorner = Instance.new('UICorner')
        fCorner.CornerRadius = UDim.new(1, 0)
        fCorner.Parent = fill

        local function render(v)
            fill.Size = UDim2.new(math.clamp(v / MAX, 0, 1), 0, 1, 0)
            rowLabel.Text = string.format('%s  ·  %.2f', labelText, v)
            if not input:IsFocused() then
                input.Text = string.format('%.2f', v)
            end
        end

        local function setFromX(absX)
            local rel = (absX - track.AbsolutePosition.X) / track.AbsoluteSize.X
            rel = math.clamp(rel, 0, 1)
            local v = MIN + (MAX - MIN) * rel
            v = math.floor(v * 100 + 0.5) / 100
            onChange(v)
            render(v)
        end

        local dragging = false
        track.InputBegan:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                setFromX(inp.Position.X)
            end
        end)
        track.InputChanged:Connect(function(inp)
            if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement
                or inp.UserInputType == Enum.UserInputType.Touch) then
                setFromX(inp.Position.X)
            end
        end)
        UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1
                or inp.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)

        input.FocusLost:Connect(function(enter)
            local n = tonumber(input.Text)
            if n == nil then
                input.Text = string.format('%.2f', onChange and 1 or 1)
                return
            end
            n = math.clamp(n, MIN, MAX)
            n = math.floor(n * 100 + 0.5) / 100
            onChange(n)
            render(n)
        end)

        render(initial)
        return render
    end

    local renderWalk  = buildRow(52, 'walk',  State.WalkMult,  function(v) State.WalkMult = v end)
    local renderSlide = buildRow(94, 'slide', State.SlideMult, function(v) State.SlideMult = v end)

    toggle.MouseButton1Click:Connect(function()
        State.Enabled = not State.Enabled
        toggle.Text = 'enabled  ·  ' .. tostring(State.Enabled)
        toggle.TextColor3 = State.Enabled
            and Color3.fromRGB(120, 220, 140)
            or Color3.fromRGB(200, 100, 100)
    end)
end

buildUI()

task.spawn(function()
    while true do
        task.wait(0.5)
        if not State.HookLoaded then
            loadWalkHook()
        end
    end
end)

genv.__mk_unload = function()
    unloadWalkHook()
    genv.__mk_ran = nil
    pcall(function() _G.__mk_ran = nil end)
end

end)()
