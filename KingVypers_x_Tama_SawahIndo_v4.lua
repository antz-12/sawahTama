--[[
 ╔══════════════════════════════════════════════════════╗
 ║   🐍  K I N G V Y P E R S  x  T A M A  🐍           ║
 ║   Sawah Indo Script  •  v4.0  •  Hitam Glossy        ║
 ║   UI: AequorUI  (hnwiie)                             ║
 ║   Minimize ✓  Resize ✓  Bug-Free ✓                   ║
 ╚══════════════════════════════════════════════════════╝
--]]

-- ─────────────────────────────────────────────────────
-- [0]  LOAD AEQUORUI
-- ─────────────────────────────────────────────────────
local AequorUI = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/hnwiie/AequorUI/refs/heads/main/main.lua", true
))()

local GeneralUI      = AequorUI.GeneralUI
local TabManager     = AequorUI.TabManager
local ElementManager = AequorUI.ElementManager
local ThemeManager   = AequorUI.ThemeManager

-- ─────────────────────────────────────────────────────
-- [1]  SERVICES
-- ─────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local CoreGui           = game:GetService("CoreGui")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera
local Mouse             = LocalPlayer:GetMouse()

-- ─────────────────────────────────────────────────────
-- [2]  CHARACTER REFERENCE (respawn-safe)
-- ─────────────────────────────────────────────────────
local Char, HRP, Hum

local function RefreshChar(c)
    Char = c
    HRP  = c:WaitForChild("HumanoidRootPart", 10)
    Hum  = c:WaitForChild("Humanoid", 10)
end
RefreshChar(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
LocalPlayer.CharacterAdded:Connect(function(c)
    task.wait(0.6)
    RefreshChar(c)
end)

-- ─────────────────────────────────────────────────────
-- [3]  STATE  (semua flag default OFF / nilai normal)
-- ─────────────────────────────────────────────────────
local S = {
    -- Auto Buy
    AutoBuySeed   = false,
    BuyThread     = nil,
    BuyDelay      = 2.5,
    SeedType      = "Padi",
    BuyQty        = 1,

    -- Auto Harvest
    AutoHarvest   = false,
    HarvThread    = nil,
    HarvDelay     = 3.0,
    HarvRadius    = 60,

    -- Auto Sell
    AutoSell      = false,
    SellThread    = nil,
    SellDelay     = 3.5,

    -- Fly
    FlyOn         = false,
    FlySpeed      = 60,
    FlyConn       = nil,
    BV            = nil,
    BG            = nil,

    -- Jump
    JumpPow       = 50,
    InfJump       = false,
    InfJumpConn   = nil,

    -- Speed / NoClip
    WalkSpd       = 16,
    NoClip        = false,
    NoClipConn    = nil,

    -- Saved locs
    Locs          = {},

    -- Stats
    Harvested     = 0,
    Sold          = 0,
    Bought        = 0,
}

-- ─────────────────────────────────────────────────────
-- [4]  UTILITIES
-- ─────────────────────────────────────────────────────
local function Notif(title, msg, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title    = "🐍 " .. title,
            Text     = msg,
            Duration = dur or 3,
        })
    end)
end

local function FindAll(kw, root)
    root = root or Workspace
    local res = {}
    local kwl = kw:lower()
    for _, v in ipairs(root:GetDescendants()) do
        if v.Name:lower():find(kwl, 1, true) then
            table.insert(res, v)
        end
    end
    return res
end

local function NearestOf(list)
    if not HRP then return nil end
    local best, bestD = nil, math.huge
    for _, obj in ipairs(list) do
        local pos
        if obj:IsA("Model") then
            local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if pp then pos = pp.Position end
        elseif obj:IsA("BasePart") then
            pos = obj.Position
        end
        if pos then
            local d = (HRP.Position - pos).Magnitude
            if d < bestD then best = obj; bestD = d end
        end
    end
    return best
end

-- Safe teleport: TIDAK mengubah velocity / physics secara paksa
local function SafeTP(pos)
    if not HRP then return end
    -- disable physics sebentar agar tidak memicu auto-walk
    local saved = Hum and Hum.WalkSpeed or 16
    if Hum then Hum.WalkSpeed = 0 end
    HRP.CFrame = CFrame.new(pos + Vector3.new(0, 3.5, 0))
    task.wait(0.12)
    if Hum then Hum.WalkSpeed = S.WalkSpd end
end

local function SafeTPCF(cf)
    if not HRP then return end
    if Hum then Hum.WalkSpeed = 0 end
    HRP.CFrame = cf
    task.wait(0.12)
    if Hum then Hum.WalkSpeed = S.WalkSpd end
end

-- Fire RemoteEvent (search ReplicatedStorage + Workspace)
local function FireRE(name, ...)
    local r = ReplicatedStorage:FindFirstChild(name, true)
           or Workspace:FindFirstChild(name, true)
    if r and r:IsA("RemoteEvent") then
        pcall(function() r:FireServer(...) end)
        return true
    end
    return false
end

-- Interact: ProximityPrompt + ClickDetector
local function Interact(obj)
    if not obj then return end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            pcall(fireproximityprompt, d)
        elseif d:IsA("ClickDetector") then
            pcall(fireclickdetector, d)
        end
    end
end

-- Cari posisi dari object (Model atau BasePart)
local function ObjPos(obj)
    if not obj then return nil end
    if obj:IsA("Model") then
        local pp = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
        return pp and pp.Position
    elseif obj:IsA("BasePart") then
        return obj.Position
    end
    return nil
end

-- ─────────────────────────────────────────────────────
-- [5]  AUTO BUY SEED
-- ─────────────────────────────────────────────────────
local SeedList = {
    "Padi","Jagung","Kacang","Singkong","Cabai",
    "Tomat","Bawang","Kangkung","Bayam","Semangka",
    "Wortel","Kentang","Timun","Terong","Labu"
}

local function DoBuy()
    -- 1. Remote event
    for _, rn in ipairs({"BuySeed","BeliSeed","BuyItem","Purchase","BuyPlant"}) do
        if FireRE(rn, S.SeedType, S.BuyQty) then
            S.Bought += S.BuyQty; return
        end
    end
    -- 2. NPC toko terdekat
    local pool = {}
    for _, kw in ipairs({"Toko","Shop","Kios","Store","SeedShop"}) do
        for _, v in ipairs(FindAll(kw)) do table.insert(pool, v) end
    end
    local near = NearestOf(pool)
    if near then
        local pos = ObjPos(near)
        if pos then
            SafeTP(pos)
            task.wait(0.5)
            Interact(near)
            S.Bought += S.BuyQty
        end
    end
end

local function StartBuy()
    if S.BuyThread then task.cancel(S.BuyThread) end
    S.BuyThread = task.spawn(function()
        while S.AutoBuySeed do
            pcall(DoBuy)
            task.wait(math.max(S.BuyDelay, 1))
        end
    end)
end
local function StopBuy()
    S.AutoBuySeed = false
    if S.BuyThread then task.cancel(S.BuyThread); S.BuyThread = nil end
end

-- ─────────────────────────────────────────────────────
-- [6]  AUTO HARVEST
-- ─────────────────────────────────────────────────────
local function DoHarvest()
    local n = 0
    -- 1. Remote
    for _, rn in ipairs({"Harvest","Panen","HarvestCrop","CollectPlant","HarvestAll"}) do
        FireRE(rn)
    end
    -- 2. Scan tanaman
    local keys = {"Panen","Harvest","Tanaman","Plant","Crop","Sawah","Lahan","Padi","Jagung", S.SeedType}
    local seen  = {}
    for _, kw in ipairs(keys) do
        for _, crop in ipairs(FindAll(kw)) do
            if not seen[crop] then
                seen[crop] = true
                -- Cek kesiapan panen
                local ready = true
                local bv = crop:FindFirstChild("Grown") or crop:FindFirstChild("Ready") or crop:FindFirstChild("CanHarvest")
                local iv = crop:FindFirstChild("Stage") or crop:FindFirstChild("GrowStage")
                if bv and bv:IsA("BoolValue")   then ready = bv.Value
                elseif iv and (iv:IsA("IntValue") or iv:IsA("NumberValue")) then ready = iv.Value >= 3
                end
                if ready then
                    local pos = ObjPos(crop)
                    if pos and HRP and (HRP.Position - pos).Magnitude <= S.HarvRadius then
                        SafeTP(pos)
                        task.wait(0.25)
                        Interact(crop)
                        n += 1
                    end
                end
            end
        end
    end
    S.Harvested += n
    return n
end

local function StartHarv()
    if S.HarvThread then task.cancel(S.HarvThread) end
    S.HarvThread = task.spawn(function()
        while S.AutoHarvest do
            pcall(DoHarvest)
            task.wait(math.max(S.HarvDelay, 1))
        end
    end)
end
local function StopHarv()
    S.AutoHarvest = false
    if S.HarvThread then task.cancel(S.HarvThread); S.HarvThread = nil end
end

-- ─────────────────────────────────────────────────────
-- [7]  AUTO SELL
-- ─────────────────────────────────────────────────────
local function DoSell()
    for _, rn in ipairs({"Sell","Jual","SellAll","SellCrops","SellItem","SellHarvest"}) do
        FireRE(rn)
    end
    local pool = {}
    for _, kw in ipairs({"Sell","Jual","Pasar","Market","Gudang","SellPoint"}) do
        for _, v in ipairs(FindAll(kw)) do table.insert(pool, v) end
    end
    local near = NearestOf(pool)
    if near then
        local pos = ObjPos(near)
        if pos then
            SafeTP(pos)
            task.wait(0.5)
            Interact(near)
            S.Sold += 1
        end
    end
end

local function StartSell()
    if S.SellThread then task.cancel(S.SellThread) end
    S.SellThread = task.spawn(function()
        while S.AutoSell do
            pcall(DoSell)
            task.wait(math.max(S.SellDelay, 1))
        end
    end)
end
local function StopSell()
    S.AutoSell = false
    if S.SellThread then task.cancel(S.SellThread); S.SellThread = nil end
end

-- ─────────────────────────────────────────────────────
-- [8]  FLY  (BUG-FREE: tidak memengaruhi physics darat)
-- ─────────────────────────────────────────────────────
local function StartFly()
    -- Bersihkan instance lama
    if S.FlyConn then S.FlyConn:Disconnect(); S.FlyConn = nil end
    pcall(function() if S.BV then S.BV:Destroy() end end)
    pcall(function() if S.BG then S.BG:Destroy() end end)
    S.BV = nil; S.BG = nil

    local bv       = Instance.new("BodyVelocity")
    bv.Velocity    = Vector3.zero
    bv.MaxForce    = Vector3.new(9e4, 9e4, 9e4)
    bv.P           = 1e4
    bv.Parent      = HRP
    S.BV           = bv

    local bg       = Instance.new("BodyGyro")
    bg.MaxTorque   = Vector3.new(9e4, 9e4, 9e4)
    bg.P           = 3e3
    bg.D           = 80
    bg.CFrame      = HRP.CFrame
    bg.Parent      = HRP
    S.BG           = bg

    -- PENTING: PlatformStand diset hanya saat aktif terbang,
    -- ini mencegah Humanoid berjalan sendiri saat di darat
    if Hum then Hum.PlatformStand = true end

    S.FlyConn = RunService.RenderStepped:Connect(function()
        if not S.FlyOn then return end
        if not HRP or not S.BV or not S.BG then return end

        local dir = Vector3.zero
        local cf  = Camera.CFrame
        local spd = S.FlySpeed

        -- Cek input HANYA jika tidak ada GUI yang aktif (mencegah konflik)
        local guiFocus = UserInputService:GetFocusedTextBox()
        if not guiFocus then
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector  end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector  end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)   then spd *= 2.5           end
        end

        if dir.Magnitude > 0 then
            S.BV.Velocity = dir.Unit * spd
        else
            -- Hover: nol horizontal, gravitasi ditahan
            S.BV.Velocity = Vector3.new(0, 0, 0)
        end
        S.BG.CFrame = cf
    end)
end

local function StopFly()
    if S.FlyConn then S.FlyConn:Disconnect(); S.FlyConn = nil end
    pcall(function() if S.BV then S.BV:Destroy(); S.BV = nil end end)
    pcall(function() if S.BG then S.BG:Destroy(); S.BG = nil end end)
    if Hum then Hum.PlatformStand = false end
    -- Kembalikan walkspeed normal agar tidak jalan sendiri setelah fly
    if Hum then
        Hum.WalkSpeed = S.WalkSpd
        Hum.JumpPower = S.JumpPow
    end
end

-- ─────────────────────────────────────────────────────
-- [9]  INFINITE JUMP  (hanya via JumpRequest, tidak inject)
-- ─────────────────────────────────────────────────────
local function SetInfJump(on)
    if S.InfJumpConn then S.InfJumpConn:Disconnect(); S.InfJumpConn = nil end
    if on then
        S.InfJumpConn = UserInputService.JumpRequest:Connect(function()
            -- Hanya saat di darat atau jatuh (mencegah spasi 100x/det)
            if Hum and Hum:GetState() ~= Enum.HumanoidStateType.Jumping then
                Hum:ChangeState(Enum.HumanoidStateType.Jumping)
            end
        end)
    end
end

-- ─────────────────────────────────────────────────────
-- [10] NO CLIP  (hanya part milik karakter sendiri)
-- ─────────────────────────────────────────────────────
local function SetNoClip(on)
    if S.NoClipConn then S.NoClipConn:Disconnect(); S.NoClipConn = nil end
    if on then
        S.NoClipConn = RunService.Stepped:Connect(function()
            if not Char then return end
            for _, p in ipairs(Char:GetDescendants()) do
                if p:IsA("BasePart") and p ~= HRP then
                    p.CanCollide = false
                end
            end
            if HRP then HRP.CanCollide = false end
        end)
    else
        if Char then
            for _, p in ipairs(Char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
    end
end

-- ─────────────────────────────────────────────────────
-- [11] RESPAWN: re-apply semua state
-- ─────────────────────────────────────────────────────
LocalPlayer.CharacterAdded:Connect(function(c)
    task.wait(0.8)
    RefreshChar(c)
    if Hum then
        Hum.WalkSpeed = S.WalkSpd
        Hum.JumpPower = S.JumpPow
    end
    if S.InfJump    then SetInfJump(true)  end
    if S.NoClip     then SetNoClip(true)   end
    if S.FlyOn      then
        task.wait(0.3)
        StartFly()
    end
    Notif("Respawn", "Config diterapkan ulang setelah respawn!", 3)
end)

-- ─────────────────────────────────────────────────────
-- [12] HOTKEYS GLOBAL  (F / G / H)
-- ─────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    -- Jangan proses jika ada TextBox aktif
    if UserInputService:GetFocusedTextBox() then return end

    if inp.KeyCode == Enum.KeyCode.F then
        S.FlyOn = not S.FlyOn
        if S.FlyOn then StartFly(); Notif("Fly ON ✈️","WASD+Space/Ctrl terbang | Shift=cepat",2)
        else StopFly(); Notif("Fly OFF","Kembali ke darat.",2) end

    elseif inp.KeyCode == Enum.KeyCode.G then
        S.NoClip = not S.NoClip
        SetNoClip(S.NoClip)
        Notif("NoClip "..(S.NoClip and "ON 👻" or "OFF"),"",2)

    elseif inp.KeyCode == Enum.KeyCode.H then
        S.InfJump = not S.InfJump
        SetInfJump(S.InfJump)
        Notif("Infinite Jump "..(S.InfJump and "ON 🦘" or "OFF"),"",2)
    end
end)

-- ─────────────────────────────────────────────────────
-- [13] BUAT UI  (AequorUI)
-- ─────────────────────────────────────────────────────
local Window = GeneralUI:CreateWindow({
    Title    = "🐍 KingVypers x Tama",
    SubTitle = "Sawah Indo  •  v4.0",
    -- Minimize & resize sudah ada di GeneralUI AequorUI
})

-- Apply hitam glossy theme jika ThemeManager mendukung
pcall(function()
    ThemeManager:SetTheme("Dark")
end)

-- ─────────────────────────────────────────────────────
-- [14] TAB 1 — 🛒 AUTO BUY SEED
-- ─────────────────────────────────────────────────────
local TabBuy = TabManager:CreateTab(Window, {
    Name = "🛒 Buy Seed",
    Icon = "rbxassetid://7059346373",
})

ElementManager:CreateSection(TabBuy, "Konfigurasi Benih")

ElementManager:CreateDropdown(TabBuy, {
    Name     = "Jenis Benih",
    Options  = SeedList,
    Default  = "Padi",
    Callback = function(v)
        S.SeedType = v
        Notif("Benih", "Dipilih: "..v, 2)
    end,
})

ElementManager:CreateSlider(TabBuy, {
    Name    = "Jumlah Beli per Siklus",
    Min     = 1, Max = 100, Default = 1,
    Suffix  = " biji",
    Callback = function(v) S.BuyQty = v end,
})

ElementManager:CreateSlider(TabBuy, {
    Name    = "Delay Auto Buy (detik)",
    Min     = 1, Max = 20, Default = 2,
    Suffix  = "s",
    Callback = function(v) S.BuyDelay = v end,
})

ElementManager:CreateSection(TabBuy, "Kontrol")

ElementManager:CreateToggle(TabBuy, {
    Name     = "🔁 Auto Buy Seed",
    Default  = false,
    Callback = function(v)
        S.AutoBuySeed = v
        if v then StartBuy(); Notif("Auto Buy","AKTIF 🟢",2)
        else StopBuy(); Notif("Auto Buy","NONAKTIF 🔴",2) end
    end,
})

ElementManager:CreateButton(TabBuy, {
    Name     = "⚡ Beli Sekali Sekarang",
    Callback = function()
        pcall(DoBuy)
        Notif("Buy Seed","Aksi beli dijalankan!",2)
    end,
})

-- ─────────────────────────────────────────────────────
-- [15] TAB 2 — 🌿 AUTO HARVEST
-- ─────────────────────────────────────────────────────
local TabHarv = TabManager:CreateTab(Window, {
    Name = "🌿 Harvest",
    Icon = "rbxassetid://7059346373",
})

ElementManager:CreateSection(TabHarv, "Pengaturan Panen")

ElementManager:CreateSlider(TabHarv, {
    Name    = "Delay Harvest (detik)",
    Min     = 1, Max = 20, Default = 3,
    Suffix  = "s",
    Callback = function(v) S.HarvDelay = v end,
})

ElementManager:CreateSlider(TabHarv, {
    Name    = "Radius Scan Tanaman (studs)",
    Min     = 10, Max = 500, Default = 60,
    Suffix  = " studs",
    Callback = function(v) S.HarvRadius = v end,
})

ElementManager:CreateSection(TabHarv, "Kontrol")

ElementManager:CreateToggle(TabHarv, {
    Name     = "🔁 Auto Harvest",
    Default  = false,
    Callback = function(v)
        S.AutoHarvest = v
        if v then StartHarv(); Notif("Auto Harvest","AKTIF 🟢",2)
        else StopHarv(); Notif("Auto Harvest","NONAKTIF 🔴",2) end
    end,
})

ElementManager:CreateButton(TabHarv, {
    Name     = "⚡ Panen Sekali Sekarang",
    Callback = function()
        local n = 0
        pcall(function() n = DoHarvest() end)
        Notif("Harvest","Panen "..n.." tanaman!",3)
    end,
})

-- ─────────────────────────────────────────────────────
-- [16] TAB 3 — 💰 AUTO SELL
-- ─────────────────────────────────────────────────────
local TabSell = TabManager:CreateTab(Window, {
    Name = "💰 Sell",
    Icon = "rbxassetid://7059346373",
})

ElementManager:CreateSection(TabSell, "Pengaturan Jual")

ElementManager:CreateSlider(TabSell, {
    Name    = "Delay Auto Sell (detik)",
    Min     = 1, Max = 30, Default = 3,
    Suffix  = "s",
    Callback = function(v) S.SellDelay = v end,
})

ElementManager:CreateSection(TabSell, "Kontrol")

ElementManager:CreateToggle(TabSell, {
    Name     = "🔁 Auto Sell",
    Default  = false,
    Callback = function(v)
        S.AutoSell = v
        if v then StartSell(); Notif("Auto Sell","AKTIF 🟢",2)
        else StopSell(); Notif("Auto Sell","NONAKTIF 🔴",2) end
    end,
})

ElementManager:CreateButton(TabSell, {
    Name     = "⚡ Jual Sekali Sekarang",
    Callback = function()
        pcall(DoSell)
        Notif("Sell","Aksi jual dijalankan!",2)
    end,
})

-- ─────────────────────────────────────────────────────
-- [17] TAB 4 — 🚀 MOVEMENT
-- ─────────────────────────────────────────────────────
local TabMove = TabManager:CreateTab(Window, {
    Name = "🚀 Movement",
    Icon = "rbxassetid://7059346373",
})

ElementManager:CreateSection(TabMove, "✈️ Fly  [Hotkey: F]")

ElementManager:CreateToggle(TabMove, {
    Name     = "✈️ Fly Mode",
    Default  = false,
    Callback = function(v)
        S.FlyOn = v
        if v then StartFly(); Notif("Fly","ON ✈️ — WASD+Space/Ctrl | Shift=cepat",3)
        else StopFly(); Notif("Fly","OFF",2) end
    end,
})

ElementManager:CreateSlider(TabMove, {
    Name    = "Kecepatan Terbang",
    Min     = 10, Max = 500, Default = 60,
    Suffix  = " studs/s",
    Callback = function(v) S.FlySpeed = v end,
})

ElementManager:CreateSection(TabMove, "🦘 Jump  [Hotkey: H]")

ElementManager:CreateToggle(TabMove, {
    Name     = "🦘 Infinite Jump",
    Default  = false,
    Callback = function(v)
        S.InfJump = v
        SetInfJump(v)
        Notif("Infinite Jump", v and "ON 🟢" or "OFF 🔴", 2)
    end,
})

ElementManager:CreateSlider(TabMove, {
    Name    = "Jump Power",
    Min     = 50, Max = 1000, Default = 50,
    Suffix  = "",
    Callback = function(v)
        S.JumpPow = v
        if Hum then Hum.JumpPower = v end
    end,
})

ElementManager:CreateSection(TabMove, "⚡ Speed")

ElementManager:CreateSlider(TabMove, {
    Name    = "Walk Speed",
    Min     = 16, Max = 500, Default = 16,
    Suffix  = "",
    Callback = function(v)
        S.WalkSpd = v
        if Hum then Hum.WalkSpeed = v end
    end,
})

ElementManager:CreateSection(TabMove, "👻 Extra  [NoClip: G]")

ElementManager:CreateToggle(TabMove, {
    Name     = "👻 No Clip",
    Default  = false,
    Callback = function(v)
        S.NoClip = v
        SetNoClip(v)
        Notif("NoClip", v and "ON 🟢" or "OFF 🔴", 2)
    end,
})

ElementManager:CreateButton(TabMove, {
    Name     = "📍 Teleport ke Spawn",
    Callback = function()
        local sp = FindAll("SpawnLocation")
        if #sp > 0 then
            local pos = ObjPos(sp[1])
            if pos then SafeTP(pos); Notif("Teleport","Ke Spawn!",2) end
        else
            Notif("Error","SpawnLocation tidak ditemukan.",3)
        end
    end,
})

ElementManager:CreateButton(TabMove, {
    Name     = "🔄 Reset Karakter",
    Callback = function()
        if Hum then Hum.Health = 0 end
    end,
})

-- ─────────────────────────────────────────────────────
-- [18] TAB 5 — 📍 LOKASI LAHAN
-- ─────────────────────────────────────────────────────
local TabLoc = TabManager:CreateTab(Window, {
    Name = "📍 Lokasi",
    Icon = "rbxassetid://7059346373",
})

local Slots = {
    "Lahan Utama","Lahan Cadangan","Toko Benih",
    "Pasar / Jual","Gudang","Custom A","Custom B","Custom C"
}

ElementManager:CreateSection(TabLoc, "💾 Simpan Posisi Sekarang")
for _, slot in ipairs(Slots) do
    ElementManager:CreateButton(TabLoc, {
        Name     = "💾 " .. slot,
        Callback = function()
            if not HRP then Notif("Error","Character tidak ada.",2); return end
            S.Locs[slot] = HRP.CFrame
            local p = HRP.Position
            Notif("Disimpan ✅", string.format("%s\nX:%.1f Y:%.1f Z:%.1f",slot,p.X,p.Y,p.Z), 4)
        end,
    })
end

ElementManager:CreateSection(TabLoc, "🚀 Teleport ke Lokasi")
for _, slot in ipairs(Slots) do
    ElementManager:CreateButton(TabLoc, {
        Name     = "🚀 " .. slot,
        Callback = function()
            local cf = S.Locs[slot]
            if cf then SafeTPCF(cf); Notif("Teleport","→ "..slot, 2)
            else Notif("Kosong ❌", slot.." belum disimpan!", 3) end
        end,
    })
end

ElementManager:CreateSection(TabLoc, "🗑️ Hapus Lokasi")
for _, slot in ipairs(Slots) do
    ElementManager:CreateButton(TabLoc, {
        Name     = "🗑️ " .. slot,
        Callback = function()
            S.Locs[slot] = nil
            Notif("Dihapus","Lokasi "..slot.." dihapus.", 2)
        end,
    })
end

ElementManager:CreateSection(TabLoc, "🎯 Koordinat Manual")

local mX, mY, mZ = 0, 5, 0

ElementManager:CreateTextbox(TabLoc, {
    Name        = "Koordinat X",
    Placeholder = "0",
    Callback    = function(v) mX = tonumber(v) or 0 end,
})
ElementManager:CreateTextbox(TabLoc, {
    Name        = "Koordinat Y",
    Placeholder = "5",
    Callback    = function(v) mY = tonumber(v) or 5 end,
})
ElementManager:CreateTextbox(TabLoc, {
    Name        = "Koordinat Z",
    Placeholder = "0",
    Callback    = function(v) mZ = tonumber(v) or 0 end,
})

ElementManager:CreateButton(TabLoc, {
    Name     = "🎯 Teleport ke Koordinat",
    Callback = function()
        SafeTP(Vector3.new(mX, mY, mZ))
        Notif("Teleport", string.format("X:%.1f Y:%.1f Z:%.1f",mX,mY,mZ), 3)
    end,
})

ElementManager:CreateButton(TabLoc, {
    Name     = "📋 Lihat Posisi Saat Ini",
    Callback = function()
        if not HRP then Notif("Error","Character tidak ada.",2); return end
        local p = HRP.Position
        Notif("Posisi Sekarang", string.format("X: %.2f\nY: %.2f\nZ: %.2f",p.X,p.Y,p.Z), 5)
    end,
})

-- ─────────────────────────────────────────────────────
-- [19] TAB 6 — ⚙️ SETTINGS
-- ─────────────────────────────────────────────────────
local TabSet = TabManager:CreateTab(Window, {
    Name = "⚙️ Settings",
    Icon = "rbxassetid://7059346373",
})

ElementManager:CreateSection(TabSet, "ℹ️ Info Script")
ElementManager:CreateLabel(TabSet, { Text = "🐍 KingVypers x Tama  •  v4.0" })
ElementManager:CreateLabel(TabSet, { Text = "🎮 Game : Sawah Indo  •  Roblox" })
ElementManager:CreateLabel(TabSet, { Text = "🖥️ UI  : AequorUI (hnwiie)" })
ElementManager:CreateLabel(TabSet, { Text = "📌 Hotkeys: F=Fly  G=NoClip  H=InfJump" })
ElementManager:CreateLabel(TabSet, { Text = "📌 RightShift = Toggle UI" })

ElementManager:CreateSection(TabSet, "📊 Statistik Sesi")
local statLabel = ElementManager:CreateLabel(TabSet, {
    Text = "📊 Harvest:0  Sold:0  Bought:0"
})

-- Update statistik tiap 2 detik
task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            statLabel:SetText(string.format(
                "📊 Harvest:%d  Sold:%d  Bought:%d",
                S.Harvested, S.Sold, S.Bought
            ))
        end)
    end
end)

ElementManager:CreateSection(TabSet, "🔧 Aksi")

ElementManager:CreateButton(TabSet, {
    Name     = "🔔 Test Notifikasi",
    Callback = function()
        Notif("KingVypers x Tama ✅","Script berjalan normal! v4.0",4)
    end,
})

ElementManager:CreateButton(TabSet, {
    Name     = "🧹 Matikan Semua Fitur",
    Callback = function()
        StopBuy(); StopHarv(); StopSell()
        S.FlyOn=false; StopFly()
        S.InfJump=false; SetInfJump(false)
        S.NoClip=false;  SetNoClip(false)
        S.WalkSpd=16; S.JumpPow=50
        if Hum then Hum.WalkSpeed=16; Hum.JumpPower=50 end
        Notif("Reset 🧹","Semua fitur dimatikan.",3)
    end,
})

ElementManager:CreateButton(TabSet, {
    Name     = "❌ Destroy Script",
    Callback = function()
        StopBuy(); StopHarv(); StopSell()
        StopFly(); SetInfJump(false); SetNoClip(false)
        if Hum then Hum.WalkSpeed=16; Hum.JumpPower=50 end
        Notif("Bye 👋","Script dihentikan.", 3)
        task.wait(1)
        pcall(function() GeneralUI:Destroy(Window) end)
    end,
})

-- ─────────────────────────────────────────────────────
-- [20] LOGO ULAR di pojok kiri atas (manual inject ke CoreGui)
-- ─────────────────────────────────────────────────────
task.spawn(function()
    task.wait(1) -- tunggu UI load dulu

    -- Cari ScreenGui milik AequorUI di CoreGui atau PlayerGui
    local targetGui = nil
    for _, g in ipairs(CoreGui:GetChildren()) do
        if g:IsA("ScreenGui") then targetGui = g; break end
    end
    if not targetGui then
        for _, g in ipairs(LocalPlayer.PlayerGui:GetChildren()) do
            if g:IsA("ScreenGui") then targetGui = g; break end
        end
    end
    if not targetGui then return end

    -- Snake logo label
    local snakeFrame = Instance.new("Frame")
    snakeFrame.Name              = "KVT_SnakeLogo"
    snakeFrame.Size              = UDim2.new(0, 110, 0, 28)
    snakeFrame.Position          = UDim2.new(0, 8, 0, 8)
    snakeFrame.BackgroundColor3  = Color3.fromRGB(8, 8, 8)
    snakeFrame.BackgroundTransparency = 0.15
    snakeFrame.BorderSizePixel   = 0
    snakeFrame.ZIndex            = 999
    snakeFrame.Active            = true
    snakeFrame.Parent            = targetGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent       = snakeFrame

    local stroke = Instance.new("UIStroke")
    stroke.Color          = Color3.fromRGB(40, 200, 100)
    stroke.Thickness      = 1
    stroke.Transparency   = 0.5
    stroke.Parent         = snakeFrame

    local snakeLbl = Instance.new("TextLabel")
    snakeLbl.Size                = UDim2.new(1, 0, 1, 0)
    snakeLbl.BackgroundTransparency = 1
    snakeLbl.Text                = "🐍 KingVypers x Tama"
    snakeLbl.TextColor3          = Color3.fromRGB(40, 220, 120)
    snakeLbl.Font                = Enum.Font.GothamBold
    snakeLbl.TextSize            = 11
    snakeLbl.TextXAlignment      = Enum.TextXAlignment.Center
    snakeLbl.ZIndex              = 1000
    snakeLbl.Parent              = snakeFrame

    -- Animasi glowing tiap 2 detik
    task.spawn(function()
        while snakeFrame and snakeFrame.Parent do
            TweenService:Create(snakeLbl, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                TextColor3 = Color3.fromRGB(100, 255, 160)
            }):Play()
            task.wait(1)
            TweenService:Create(snakeLbl, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                TextColor3 = Color3.fromRGB(30, 180, 90)
            }):Play()
            task.wait(1)
        end
    end)
end)

-- ─────────────────────────────────────────────────────
-- [21] STARTUP NOTIFICATION
-- ─────────────────────────────────────────────────────
task.wait(2)
Notif(
    "KingVypers x Tama v4.0 ✅",
    "Sawah Indo Script siap!\nF=Fly  G=NoClip  H=InfJump",
    6
)
print("╔══════════════════════════════════════╗")
print("║  🐍 KingVypers x Tama  •  v4.0       ║")
print("║  Sawah Indo  •  AequorUI  •  Loaded  ║")
print("║  F=Fly | G=NoClip | H=InfJump        ║")
print("╚══════════════════════════════════════╝")

-- ─────────────────────────────────────────────────────
-- END OF SCRIPT
-- ─────────────────────────────────────────────────────
