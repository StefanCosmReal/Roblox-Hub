-- Rayfield frontend for AervanixBot logic (ESP / Aimbot controls)
-- Paste-run in executor (assumes Rayfield is reachable)

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
   Name = "Multi tool | Made by StefanCosm_",
   Icon = 0, -- Icon in Topbar. Can use Lucide Icons (string) or Roblox Image (number). 0 to use no icon (default).
   LoadingTitle = "Getting scripts ready for you",
   LoadingSubtitle = "By StefanCosm_",
   ShowText = "Multitool", -- for mobile users to unhide rayfield, change if you'd like
   Theme = "Ocean", -- Check https://docs.sirius.menu/rayfield/configuration/themes

   ToggleUIKeybind = "K", -- The keybind to toggle the UI visibility (string like "K" or Enum.KeyCode)

   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false, -- Prevents Rayfield from warning when the script has a version mismatch with the interface

   ConfigurationSaving = {
      Enabled = true,
      FolderName = nil, -- Create a custom folder for your hub/game
      FileName = "Scripts"
   },

   Discord = {
      Enabled = false, -- Prompt the user to join your Discord server if their executor supports it
      Invite = "noinvitelink", -- The Discord invite code, do not include discord.gg/. E.g. discord.gg/ ABCD would be ABCD
      RememberJoins = true -- Set this to false to make them join the discord every time they load it up
   },

   KeySystem = true, -- Set this to true to use our key system
   KeySettings = {
      Title = "Cheita",
      Subtitle = "Key System",
      Note = "Dm StefanCosm_ on Discord.", -- Use this to tell the user how to get a key
      FileName = "Cheite", -- It is recommended to use something unique as other scripts using Rayfield may overwrite your key file
      SaveKey = true, -- The user's key will be saved, but if you change the key, they will be unable to use your script
      GrabKeyFromSite = true, -- If this is true, set Key below to the RAW site you would like Rayfield to get the key from
      Key = {"https://raw.githubusercontent.com/StefanCosmReal/Passwords/refs/heads/main/Password"} -- List of keys that will be accepted by the system, can be RAW file links (pastebin, github etc) or simple strings ("hello","key22")
   }
})

-- Services helper
local function svc(n)
    local S = (game.GetService)
    local R = (cloneref) or function(r) return r end
    return R(S(game, n))
end

local Players = svc("Players")
local RunService = svc("RunService")
local UIS = svc("UserInputService")
local TS = svc("TweenService")
local CAS = svc("ContextActionService")
local LS = svc("LocalizationService")
local MPS = svc("MarketplaceService")
local HS = svc("HttpService")
local GS = svc("GuiService")

local uiRoot = (gethui and gethui()) or (svc("CoreGui") or svc("Players").LocalPlayer:WaitForChild("PlayerGui"))
local plr = Players.LocalPlayer
local cam = workspace.CurrentCamera
local ms = plr:GetMouse()

-- minimal ScreenGui used only for ESP objects (no original UI)
local espGui = Instance.new("ScreenGui")
espGui.Name = "AervanixESP"
espGui.ResetOnSpawn = false
espGui.Parent = uiRoot

-- state
local conns = {}
local espMap = {}
local startUnix = DateTime.now().UnixTimestamp

_G.isEnabled      = _G.isEnabled      or false
_G.lockToHead     = _G.lockToHead     or false
_G.espEnabled     = _G.espEnabled     or false
_G.lockToNearest  = _G.lockToNearest  or false
_G.aliveCheck     = _G.aliveCheck     or false
_G.teamCheck      = _G.teamCheck      or false
_G.wallCheck      = _G.wallCheck      or false
_G.aimTween       = _G.aimTween       or false
_G.aimSmooth      = _G.aimSmooth      or 0.15
_G.fovEnabled     = _G.fovEnabled     or false
_G.fovValue       = _G.fovValue       or 70
_G.espShowName    = (_G.espShowName ~= nil) and _G.espShowName or true
_G.espShowHP      = (_G.espShowHP   ~= nil) and _G.espShowHP   or true
_G.espShowTeam    = (_G.espShowTeam ~= nil) and _G.espShowTeam or true
_G.espTeamColor   = (_G.espTeamColor~= nil) and _G.espTeamColor or true
_G.tbCPS          = _G.tbCPS          or 8
_G.aimPredict     = _G.aimPredict     or false
_G.aimLead        = _G.aimLead        or 0.12
_G.toggleKeys     = _G.toggleKeys     or {"RightAlt","LeftAlt","P","RightControl"}

local cfgDir = "Aervanix-Aimbot"
local cfgFile = cfgDir.."/config.json"

-- Utility functions (kept from original, UI specifics removed)
local function goodPart(p)
    if not p or not p:IsA("BasePart") then return false end
    if p.Transparency >= 0.95 then return false end
    if p.CanQuery == false then return false end
    if p.CanCollide == false then return false end
    return true
end

local function clearLOS(targetPart)
    if not targetPart then return false end
    local origin = cam.CFrame.Position
    local dir = targetPart.Position - origin
    local ignore = {plr.Character, targetPart.Parent}
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    local maxHops = 10
    local curOrigin = origin
    local remaining = dir
    for _ = 1, maxHops do
        local r = workspace:Raycast(curOrigin, remaining, params)
        if not r then return true end
        local hit = r.Instance
        if not goodPart(hit) or hit:IsDescendantOf(targetPart.Parent) then
            table.insert(ignore, hit)
            params.FilterDescendantsInstances = ignore
            curOrigin = r.Position + remaining.Unit * 0.01
            remaining = origin + dir - curOrigin
        else
            return false
        end
    end
    return false
end

local UI = { fallback = Color3.fromRGB(128, 0, 255) } -- only fallback color used

local function getTeamColor(p)
    if _G.espTeamColor then
        if p.Team and p.Team.TeamColor then
            local bc = p.Team.TeamColor
            if typeof(bc) == "BrickColor" then return bc.Color end
        end
        if p.TeamColor then
            local bc = p.TeamColor
            if typeof(bc) == "BrickColor" then return bc.Color end
        end
    end
    return UI.fallback or UI.fallback
end

local function sanitizeNumber(txt, min, max, def)
    local s = tostring(txt or "")
    local out, dot = {}, false
    for i = 1, #s do
        local ch = s:sub(i,i)
        if ch:match("%d") then
            table.insert(out, ch)
        elseif ch == "." and not dot then
            table.insert(out, ch); dot = true
        end
    end
    local num = tonumber(table.concat(out, ""))
    if not num then num = def end
    if min then num = math.max(min, num) end
    if max then num = math.min(max, num) end
    return num
end

local function saveCfg()
    if not writefile or not HS then return end
    local okFolder = true
    if isfolder and not isfolder(cfgDir) then
        if makefolder then
            local s, e = pcall(makefolder, cfgDir)
            okFolder = s and e == nil or s
        else
            okFolder = false
        end
    end
    if not okFolder then return end
    local data = {
        isEnabled=_G.isEnabled,lockToHead=_G.lockToHead,espEnabled=_G.espEnabled,lockToNearest=_G.lockToNearest,
        aliveCheck=_G.aliveCheck,teamCheck=_G.teamCheck,wallCheck=_G.wallCheck,aimTween=_G.aimTween,aimSmooth=_G.aimSmooth,
        fovEnabled=_G.fovEnabled,fovValue=_G.fovValue,espShowName=_G.espShowName,espShowHP=_G.espShowHP,espShowTeam=_G.espShowTeam,
        espTeamColor=_G.espTeamColor,tbCPS=_G.tbCPS,aimPredict=_G.aimPredict,aimLead=_G.aimLead,
        toggleKeys=_G.toggleKeys
    }
    local ok, enc = pcall(function() return HS:JSONEncode(data) end)
    if ok and enc then pcall(writefile, cfgFile, enc) end
end

local function loadCfg()
    if not readfile or not isfile or not HS then return end
    if not isfile(cfgFile) then return end
    local ok, txt = pcall(readfile, cfgFile)
    if not ok or not txt or txt == "" then return end
    local ok2, obj = pcall(function() return HS:JSONDecode(txt) end)
    if not ok2 or type(obj) ~= "table" then return end
    for k,v in pairs(obj) do
        if _G[k] ~= nil then _G[k] = v end
    end
end

loadCfg()

-- camera FOV binding
local camFOVCon, camSwapCon
local function bindFOV()
    if camFOVCon then camFOVCon:Disconnect() camFOVCon = nil end
    if not cam then return end
    camFOVCon = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
        if _G.fovEnabled and math.abs((cam.FieldOfView or 70) - (_G.fovValue or 70)) > 0.01 then
            cam.FieldOfView = _G.fovValue
        end
    end)
end

local function hookCamera()
    cam = workspace.CurrentCamera
    if camSwapCon then camSwapCon:Disconnect() end
    camSwapCon = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        cam = workspace.CurrentCamera
        bindFOV()
        if _G.fovEnabled and cam then cam.FieldOfView = _G.fovValue end
    end)
    bindFOV()
end
hookCamera()

-- general utilities
local function getHumanoid(m)
    if not m then return nil end
    local h = m:FindFirstChildOfClass("Humanoid")
    if h then return h end
    for _, d in ipairs(m:GetDescendants()) do
        if d:IsA("Humanoid") then return d end
    end
    return nil
end

local function getPart(m, name)
    if not m then return nil end
    local p = m:FindFirstChild(name, true)
    if p and p:IsA("BasePart") then return p end
    local h = getHumanoid(m)
    if h and h.RootPart and (name == "HumanoidRootPart" or name == "RootPart") then return h.RootPart end
    local fallback = {"HumanoidRootPart","UpperTorso","LowerTorso","Torso","Head"}
    for _, n in ipairs(fallback) do
        local q = m:FindFirstChild(n, true)
        if q and q:IsA("BasePart") then
            if name == "Head" and q.Name ~= "Head" then
            else
                return q
            end
        end
    end
    return nil
end

local function topAimPart(m)
    if _G.lockToHead then
        local h = getPart(m,"Head")
        if h then return h end
    end
    local hrp = getPart(m,"HumanoidRootPart")
    if hrp then return hrp end
    local h = getPart(m,"Head")
    if h then return h end
    return nil
end

local mode = "FFA"
local lastMode = nil

local function isEnemy(op)
    if not _G.teamCheck then return true end
    if mode == "FFA" then
        return true
    else
        return op.Team ~= nil and plr.Team ~= nil and op.Team ~= plr.Team
    end
end

local function isAlive(ch)
    if not _G.aliveCheck then return true end
    if not ch then return false end
    local hum = getHumanoid(ch)
    return hum and hum.Health > 0
end

-- target finding
local function findTarget()
    local near = nil
    local minD = math.huge
    for _, op in pairs(Players:GetPlayers()) do
        if op ~= plr and op.Character and isEnemy(op) then
            local ch = op.Character
            if not isAlive(ch) then
                continue
            end
            local part = topAimPart(ch)
            local hum = getHumanoid(ch)
            if part and hum and hum.Health > 0 then
                local scr, on = cam:WorldToScreenPoint(part.Position)
                if on then
                    if _G.wallCheck and not clearLOS(part) then
                        continue
                    end
                    local dist = (part.Position - cam.CFrame.Position).Magnitude
                    local mp = Vector2.new(ms.X, ms.Y)
                    local sdist = (Vector2.new(scr.X, scr.Y) - mp).Magnitude
                    if _G.lockToNearest then
                        if dist < minD then
                            minD = dist
                            near = ch
                        end
                    else
                        if sdist < 150 and sdist < minD then
                            minD = sdist
                            near = ch
                        end
                    end
                end
            end
        end
    end
    return near
end

-- ESP functions
local function updateESPText(p)
    local rec = espMap[p]
    if not rec or not rec.tx then return end
    local nameStr = _G.espShowName and p.Name or ""
    local hpStr = ""
    local ch = p.Character
    local hum = ch and getHumanoid(ch)
    if _G.espShowHP and hum then hpStr = "HP: " .. math.floor(hum.Health) end
    local teamStr = ""
    if _G.espShowTeam and p.Team then
        teamStr = p.Team.Name
    end
    local lines = {}
    if nameStr ~= "" then table.insert(lines, nameStr) end
    if hpStr ~= "" then table.insert(lines, hpStr) end
    if teamStr ~= "" then table.insert(lines, teamStr) end
    rec.tx.Text = table.concat(lines, "\n")
end

local function espDetach(p)
    local rec = espMap[p]
    if not rec then return end
    if rec.conns then
        for _, cc in ipairs(rec.conns) do
            if typeof(cc) == "RBXScriptConnection" and cc.Connected then cc:Disconnect() end
        end
    end
    if rec.hi and rec.hi.Parent then rec.hi:Destroy() end
    if rec.bb and rec.bb.Parent then rec.bb:Destroy() end
    espMap[p] = nil
end

local function getTeamColorSafe(p)
    if mode == "FFA" then
        return UI.fallback
    end
    return getTeamColor(p)
end

local function espAttach(p)
    if not _G.espEnabled then return end
    if p == plr then return end
    if espMap[p] then espDetach(p) end
    local ch = p.Character
    if not ch then return end
    local hum = getHumanoid(ch)
    if _G.teamCheck and not isEnemy(p) then return end
    if _G.aliveCheck and (not hum or hum.Health <= 0) then return end

    local hi = Instance.new("Highlight")
    local col = getTeamColorSafe(p)
    hi.FillColor = col
    hi.OutlineColor = col:lerp(Color3.new(1,1,1), 0.25)
    hi.FillTransparency = 0.3
    hi.OutlineTransparency = 0.1
    hi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hi.Adornee = ch
    hi.Parent = espGui -- parent to our minimal gui

    local head = getPart(ch,"Head") or getPart(ch,"HumanoidRootPart")
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.new(0, 140, 0, 50)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.Adornee = head
    bb.AlwaysOnTop = true
    bb.Parent = espGui

    local tx = Instance.new("TextLabel", bb)
    tx.Size = UDim2.new(1, 0, 1, 0)
    tx.BackgroundTransparency = 1
    tx.TextColor3 = Color3.fromRGB(255, 255, 255)
    tx.TextStrokeTransparency = 0.5
    tx.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    tx.Font = Enum.Font.GothamBold
    tx.TextSize = 14

    local rconns = {}
    if hum then
        local hc = hum.HealthChanged:Connect(function()
            updateESPText(p)
            if _G.aliveCheck and hum.Health <= 0 then
                espDetach(p)
            end
        end)
        table.insert(rconns, hc)
    end
    local teamC = p:GetPropertyChangedSignal("Team"):Connect(function()
        local c = getTeamColorSafe(p)
        if hi then
            hi.FillColor = c
            hi.OutlineColor = c:lerp(Color3.new(1,1,1), 0.25)
        end
        updateESPText(p)
    end)
    table.insert(rconns, teamC)
    espMap[p] = {hi = hi, bb = bb, tx = tx, conns = rconns}
    updateESPText(p)
end

local function updateESP()
    -- No gui gating here: use espGui for attachments
    if not _G.espEnabled then
        for p, _ in pairs(espMap) do espDetach(p) end
        espMap = {}
        return
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr then
            if _G.teamCheck and not isEnemy(p) then
                espDetach(p)
            else
                espAttach(p)
            end
        end
    end
    for p, _ in pairs(espMap) do
        if not table.find(Players:GetPlayers(), p) then espDetach(p) end
    end
end

-- geometry utilities for cursor/model
local function modelAABBOnScreen(m)
    local cf, sz = m:GetBoundingBox()
    local hx, hy, hz = sz.X/2, sz.Y/2, sz.Z/2
    local pts = {
        Vector3.new(-hx,-hy,-hz), Vector3.new(hx,-hy,-hz),
        Vector3.new(-hx,hy,-hz),  Vector3.new(hx,hy,-hz),
        Vector3.new(-hx,-hy,hz),  Vector3.new(hx,-hy,hz),
        Vector3.new(-hx,hy,hz),   Vector3.new(hx,hy,hz),
    }
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local any = false
    for i=1,8 do
        local wp = cf:PointToWorldSpace(pts[i])
        local v, on = cam:WorldToViewportPoint(wp)
        if v.Z > 0 then
            any = true
            if on then
                if v.X < minX then minX = v.X end
                if v.X > maxX then maxX = v.X end
                if v.Y < minY then minY = v.Y end
                if v.Y > maxY then maxY = v.Y end
            else
                if v.X < minX then minX = v.X end
                if v.X > maxX then maxX = v.X end
                if v.Y < minY then minY = v.Y end
                if v.Y > maxY then maxY = v.Y end
            end
        end
    end
    if not any then return nil end
    return minX, minY, maxX, maxY
end

local function cursorInsideModel(m, pad)
    local a,b,c,d = modelAABBOnScreen(m)
    if not a then return false end
    local inset = GS:GetGuiInset()
    local ml = UIS:GetMouseLocation()
    local x, y = ml.X - inset.X, ml.Y - inset.Y
    local p = pad or 2
    return x >= a - p and x <= c + p and y >= b - p and y <= d + p
end

-- aiming / locking
local lockActive = false
local isLock = false

function lockCamera()
    if lockActive then return end
    lockActive = true
    local loop
    loop = RunService.RenderStepped:Connect(function()
        if not isLock or not _G.isEnabled then
            loop:Disconnect()
            lockActive = false
            return
        end
        local ch = findTarget()
        if ch then
            local part = topAimPart(ch)
            if part then
                local tgtPos = part.Position
                if _G.aimPredict then
                    local v = part.AssemblyLinearVelocity or part.Velocity or Vector3.zero
                    tgtPos = part.Position + v * (_G.aimLead or 0.12)
                end
                local cf = CFrame.new(cam.CFrame.Position, tgtPos)
                if _G.aimTween then
                    TS:Create(cam, TweenInfo.new(math.clamp(_G.aimSmooth or 0.15, 0.05, 0.2)), {CFrame = cf}):Play()
                else
                    cam.CFrame = cf
                end
            end
        end
    end)
    table.insert(conns, loop)
end

-- binds (mouse / key handling used for locking and toggles)
local capMode = false
local capCooldownUntil = 0

local function binds()
    local bMouse = UIS.InputBegan:Connect(function(i, gp)
        if UIS:GetFocusedTextBox() then return end
        if i.UserInputType == Enum.UserInputType.MouseButton2 and _G.isEnabled then
            isLock = true
            if _G.fovEnabled and cam then cam.FieldOfView = _G.fovValue end
            lockCamera()
        end
    end)
    table.insert(conns, bMouse)
    local bMouseEnd = UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton2 then
            isLock = false
        end
    end)
    table.insert(conns, bMouseEnd)

    -- add toggle-UI keys handling: keep original toggle keys behaviour for open/minimize replacement:
    local bKeys = UIS.InputEnded:Connect(function(i, gp)
        if gp then return end
        if UIS:GetFocusedTextBox() then return end
        if capMode or time() < capCooldownUntil then return end
        if i.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local name = i.KeyCode.Name
        if table.find(_G.toggleKeys, name) then
            -- toggle main enabled flag
            _G.isEnabled = not _G.isEnabled
            print("AervanixBot isEnabled = ", _G.isEnabled)
        end
    end)
    table.insert(conns, bKeys)
end

-- player monitoring to keep ESP updated
local function setupPlayerMonitoring()
    local function hook(pp)
        local ca = pp.CharacterAdded:Connect(function()
            task.wait(0.1)
            if _G.espEnabled then espAttach(pp) end
        end)
        table.insert(conns, ca)
    end
    for _, pp in ipairs(Players:GetPlayers()) do
        if pp ~= plr then hook(pp) end
    end
    local a = Players.PlayerAdded:Connect(function(pp)
        hook(pp)
        if _G.espEnabled then task.defer(function() espAttach(pp) end) end
    end)
    table.insert(conns, a)
    local r = Players.PlayerRemoving:Connect(function(pp)
        espDetach(pp)
    end)
    table.insert(conns, r)
    local c = plr.CharacterAdded:Connect(function()
        if _G.espEnabled then updateESP() end
    end)
    table.insert(conns, c)
end

-- init
binds()
setupPlayerMonitoring()

-- keep team/FFA checking updated
local function chkMode()
    local newMode
    if #Players:GetPlayers() > 0 and Players.LocalPlayer.Team == nil then
        newMode = "FFA"
    else
        newMode = "Team"
    end
    if newMode ~= mode then
        mode = newMode
        lastMode = mode
        updateESP()
    end
end

local teamCon = RunService.RenderStepped:Connect(function() chkMode() end)
table.insert(conns, teamCon)

-- If ESP initially turned on
if _G.espEnabled then updateESP() end

-- Rayfield UI: single main tab with sections for AimBot / ESP / Settings
local mainTab = Window:CreateTab("Aimbot", 118557891041313)

-- create visual sections inside the single tab
mainTab:CreateSection("AimBot")
-- AIM section controls (same callbacks as before)
mainTab:CreateToggle({
    Name = "Enable Aimbot",
    CurrentValue = _G.isEnabled,
    Flag = "aim_enable",
    Callback = function(val)
        _G.isEnabled = val
    end,
})

mainTab:CreateToggle({
    Name = "Lock To Head",
    CurrentValue = _G.lockToHead,
    Callback = function(v) _G.lockToHead = v end,
})
mainTab:CreateToggle({
    Name = "Lock To Nearest",
    CurrentValue = _G.lockToNearest,
    Callback = function(v) _G.lockToNearest = v end,
})
mainTab:CreateToggle({
    Name = "Wall Check",
    CurrentValue = _G.wallCheck,
    Callback = function(v) _G.wallCheck = v end,
})
mainTab:CreateToggle({
    Name = "Tween Aim (smooth)",
    CurrentValue = _G.aimTween,
    Callback = function(v) _G.aimTween = v end,
})
mainTab:CreateSlider({
    Name = "Aim Smooth",
    Range = {0.05, 0.4},
    Increment = 0.01,
    Suffix = "",
    CurrentValue = _G.aimSmooth,
    Callback = function(v) _G.aimSmooth = v end,
})
mainTab:CreateToggle({
    Name = "Predict (lead)",
    CurrentValue = _G.aimPredict,
    Callback = function(v) _G.aimPredict = v end,
})
mainTab:CreateSlider({
    Name = "Aim Lead",
    Range = {0.01, 1},
    Increment = 0.01,
    CurrentValue = _G.aimLead,
    Callback = function(v) _G.aimLead = v end,
})
mainTab:CreateToggle({
    Name = "Lock FOV",
    CurrentValue = _G.fovEnabled,
    Callback = function(v)
        _G.fovEnabled = v
        if v and cam then cam.FieldOfView = _G.fovValue end
        bindFOV()
    end,
})
mainTab:CreateSlider({
    Name = "FOV Value",
    Range = {1, 120},
    Increment = 1,
    CurrentValue = _G.fovValue,
    Callback = function(v)
        _G.fovValue = v
        if _G.fovEnabled and cam then cam.FieldOfView = v end
    end,
})

-- ESP section
mainTab:CreateSection("ESP")
mainTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = _G.espEnabled,
    Callback = function(v)
        _G.espEnabled = v
        updateESP()
        saveCfg()
    end,
})
mainTab:CreateToggle({
    Name = "Team Color",
    CurrentValue = _G.espTeamColor,
    Callback = function(v) _G.espTeamColor = v; updateESP(); saveCfg() end,
})
mainTab:CreateToggle({
    Name = "Show Name",
    CurrentValue = _G.espShowName,
    Callback = function(v) _G.espShowName = v; updateESP(); saveCfg() end,
})
mainTab:CreateToggle({
    Name = "Show Health",
    CurrentValue = _G.espShowHP,
    Callback = function(v) _G.espShowHP = v; updateESP(); saveCfg() end,
})
mainTab:CreateToggle({
    Name = "Show Team",
    CurrentValue = _G.espShowTeam,
    Callback = function(v) _G.espShowTeam = v; updateESP(); saveCfg() end,
})

-- Targeting settings (keep under ESP section for convenience)
mainTab:CreateToggle({
    Name = "Team Check",
    CurrentValue = _G.teamCheck,
    Callback = function(v) _G.teamCheck = v; updateESP(); saveCfg() end,
})
mainTab:CreateToggle({
    Name = "Alive Check",
    CurrentValue = _G.aliveCheck,
    Callback = function(v) _G.aliveCheck = v; updateESP(); saveCfg() end,
})

-- Settings section
mainTab:CreateSection("Settings")
mainTab:CreateInput({
    Name = "Toggle Keys (comma separated)",
    PlaceholderText = table.concat(_G.toggleKeys, ","),
    Value = table.concat(_G.toggleKeys, ","),
    Callback = function(text)
        local keys = {}
        for s in string.gmatch(text, "([^,]+)") do
            s = s:gsub("^%s*(.-)%s*$", "%1")
            table.insert(keys, s)
        end
        _G.toggleKeys = keys
        saveCfg()
    end,
})

mainTab:CreateSlider({
    Name = "Trigger CPS (tbCPS)",
    Range = {1, 30},
    Increment = 1,
    CurrentValue = _G.tbCPS,
    Callback = function(v) _G.tbCPS = v; saveCfg() end,
})

mainTab:CreateButton({
    Name = "Save Config Now",
    Callback = function()
        saveCfg()
        print("Aervanix: config saved")
    end,
})

mainTab:CreateButton({
    Name = "Unload Aervanix (disconnect)",
    Callback = function()
        -- disconnect all
        for _, c in pairs(conns) do
            if typeof(c) == "RBXScriptConnection" and c.Connected then
                c:Disconnect()
            end
        end
        conns = {}
        for p, _ in pairs(espMap) do espDetach(p) end
        espMap = {}
        if espGui and espGui.Parent then espGui:Destroy() end
        print("Aervanix: unloaded")
    end,
})

-- Helpful convenience bindings: immediate UI -> behavior sync
-- (ensures Rayfield toggles update internals immediately on load)
local function syncAll()
    if _G.espEnabled then updateESP() end
    if _G.fovEnabled and cam then cam.FieldOfView = _G.fovValue end
end
syncAll()

-- return a unload function if someone wants to capture it
return function()
    for _, c in pairs(conns) do
        if typeof(c) == "RBXScriptConnection" and c.Connected then c:Disconnect() end
    end
    for p, _ in pairs(espMap) do espDetach(p) end
    if espGui and espGui.Parent then espGui:Destroy() end
end
