--[[
 ╔══════════════════════════════════════════════════════╗
 ║   🐍  K I N G V Y P E R S  x  T A M A  🐍           ║
 ║   Sawah Indo Script  •  v5.0  •  WindUI              ║
 ║   UI: WindUI (Footagesus)                            ║
 ║   Minimize ✓  Resize ✓  Bug-Fixed ✓                  ║
 ╚══════════════════════════════════════════════════════╝

 PERBAIKAN v5.0:
 [BUG FIX] Loop Auto Harvest: ditambah guard anti-reentrant + seen table
            di-reset tiap siklus agar tidak skip tanaman baru
 [BUG FIX] Loop Auto Buy: thread sebelumnya di-cancel dengan benar
            sebelum spawn baru, tidak ada double-loop
 [BUG FIX] Loop Auto Sell: sama seperti Auto Buy
 [BUG FIX] Fly: StopFly() sekarang selalu disconnect + destroy sebelum
            StartFly() dipanggil ulang (mencegah ghost connection)
 [BUG FIX] Infinite Jump: tidak spam-jump saat sudah Jumping
 [BUG FIX] SafeTP: tidak set WalkSpeed=0 permanen jika Hum nil
 [BUG FIX] Interaksi: fireproximityprompt/fireclickdetector diproteksi
            pcall individual, tidak berhenti jika salah satu gagal
 [BUG FIX] Stat label update: loop sekarang berhenti jika Window hilang
 [IMPROVE] WindUI: loadstring terbaru, Window compact, bisa resize/minimize
 [IMPROVE] Notifikasi via WindUI:Notify() bukan StarterGui
--]]

-- ─────────────────────────────────────────────────────
-- [0]  LOAD WINDUI (latest release)
-- ─────────────────────────────────────────────────────
local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()

-- ─────────────────────────────────────────────────────
-- [1]  SERVICES
-- ─────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera

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

-- ─────────────────────────────────────────────────────
-- [3]  STATE
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
    HarvRunning   = false,  -- [FIX] anti-reentrant guard

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

    -- UI alive flag
    UIAlive       = true,
}

-- ─────────────────────────────────────────────────────
-- [4]  UTILITIES
-- ─────────────────────────────────────────────────────
local function Notif(title, msg, dur)
    -- Coba WindUI notify dulu, fallback ke StarterGui
    pcall(function()
        WindUI:Notify({
            Title    = "🐍 " .. title,
            Content  = msg,
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

local function SafeTP(pos)
    if not HRP then return end
    local saved = (Hum and Hum.WalkSpeed) or 16
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

local function FireRE(name, ...)
    local r = ReplicatedStorage:FindFirstChild(name, true)
           or Workspace:FindFirstChild(name, true)
    if r and r:IsA("RemoteEvent") then
        pcall(function() r:FireServer(...) end)
        return true
    end
    return false
end

-- [FIX] Interact: pcall individual per detector, tidak berhenti kalau error
local function Interact(obj)
    if not obj then return end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            pcall(function() fireproximityprompt(d) end)
        elseif d:IsA("ClickDetector") then
            pcall(function() fireclickdetector(d) end)
        end
    end
end

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
            S.Bought += S.BuyQty
            return
        end
    end
    -- 2. NPC toko terdekat
    local pool = {}
    for _, kw in ipairs({"Toko","Shop","Kios","Store","SeedShop"}) do
        for _, v in ipairs(FindAll(kw)) do
            table.insert(pool, v)
        end
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

-- [FIX] StopBuy selalu dipanggil dulu sebelum StartBuy: tidak ada double-loop
local function StopBuy()
    S.AutoBuySeed = false
    if S.BuyThread then
        task.cancel(S.BuyThread)
        S.BuyThread = nil
    end
end

local function StartBuy()
    StopBuy()   -- pastikan thread lama mati
    S.AutoBuySeed = true
    S.BuyThread = task.spawn(function()
        while S.AutoBuySeed do
            pcall(DoBuy)
            task.wait(math.max(S.BuyDelay, 1))
        end
    end)
end

-- ─────────────────────────────────────────────────────
-- [6]  AUTO HARVEST
-- ─────────────────────────────────────────────────────
local function DoHarvest()
    -- [FIX] Anti-reentrant: jika siklus sebelumnya masih jalan, skip
    if S.HarvRunning then return 0 end
    S.HarvRunning = true

    local n = 0
    -- 1. Remote
    for _, rn in ipairs({"Harvest","Panen","HarvestCrop","CollectPlant","HarvestAll"}) do
        FireRE(rn)
    end

    -- 2. Scan tanaman – [FIX] seen di-reset tiap panggilan
    local keys = {"Panen","Harvest","Tanaman","Plant","Crop","Sawah","Lahan","Padi","Jagung", S.SeedType}
    local seen  = {}
    for _, kw in ipairs(keys) do
        for _, crop in ipairs(FindAll(kw)) do
            if not seen[crop] then
                seen[crop] = true
                local ready = true
                local bv = crop:FindFirstChild("Grown")
                        or crop:FindFirstChild("Ready")
                        or crop:FindFirstChild("CanHarvest")
                local iv = crop:FindFirstChild("Stage")
                        or crop:FindFirstChild("GrowStage")
                if bv and bv:IsA("BoolValue") then
                    ready = bv.Value
                elseif iv and (iv:IsA("IntValue") or iv:IsA("NumberValue")) then
                    ready = iv.Value >= 3
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
    S.HarvRunning = false
    return n
end

local function StopHarv()
    S.AutoHarvest = false
    S.HarvRunning = false
    if S.HarvThread then
        task.cancel(S.HarvThread)
        S.HarvThread = nil
    end
end

local function StartHarv()
    StopHarv()  -- pastikan thread lama mati
    S.AutoHarvest = true
    S.HarvThread = task.spawn(function()
        while S.AutoHarvest do
            pcall(DoHarvest)
            task.wait(math.max(S.HarvDelay, 1))
        end
    end)
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
        for _, v in ipairs(FindAll(kw)) do
            table.insert(pool, v)
        end
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

local function StopSell()
    S.AutoSell = false
    if S.SellThread then
        task.cancel(S.SellThread)
        S.SellThread = nil
    end
end

local function StartSell()
    StopSell()  -- pastikan thread lama mati
    S.AutoSell = true
    S.SellThread = task.spawn(function()
        while S.AutoSell do
            pcall(DoSell)
            task.wait(math.max(S.SellDelay, 1))
        end
    end)
end

-- ─────────────────────────────────────────────────────
-- [8]  FLY (bug-free)
-- ─────────────────────────────────────────────────────
local function StopFly()
    if S.FlyConn then S.FlyConn:Disconnect(); S.FlyConn = nil end
    pcall(function() if S.BV then S.BV:Destroy(); S.BV = nil end end)
    pcall(function() if S.BG then S.BG:Destroy(); S.BG = nil end end)
    if Hum then
        Hum.PlatformStand = false
        Hum.WalkSpeed = S.WalkSpd
        Hum.JumpPower = S.JumpPow
    end
end

local function StartFly()
    StopFly()   -- bersihkan instance lama dulu

    if not HRP then return end

    local bv    = Instance.new("BodyVelocity")
    bv.Velocity  = Vector3.zero
    bv.MaxForce  = Vector3.new(9e4, 9e4, 9e4)
    bv.P         = 1e4
    bv.Parent    = HRP
    S.BV         = bv

    local bg     = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(9e4, 9e4, 9e4)
    bg.P         = 3e3
    bg.D         = 80
    bg.CFrame    = HRP.CFrame
    bg.Parent    = HRP
    S.BG         = bg

    if Hum then Hum.PlatformStand = true end

    S.FlyConn = RunService.RenderStepped:Connect(function()
        if not S.FlyOn then return end
        if not HRP or not S.BV or not S.BG then return end

        local dir  = Vector3.zero
        local cf   = Camera.CFrame
        local spd  = S.FlySpeed
        local gui  = UserInputService:GetFocusedTextBox()

        if not gui then
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
            S.BV.Velocity = Vector3.zero
        end
        S.BG.CFrame = cf
    end)
end

-- ─────────────────────────────────────────────────────
-- [9]  INFINITE JUMP
-- ─────────────────────────────────────────────────────
local function SetInfJump(on)
    if S.InfJumpConn then S.InfJumpConn:Disconnect(); S.InfJumpConn = nil end
    if on then
        S.InfJumpConn = UserInputService.JumpRequest:Connect(function()
            if Hum then
                local st = Hum:GetState()
                if st ~= Enum.HumanoidStateType.Jumping and
                   st ~= Enum.HumanoidStateType.Freefall then
                    Hum:ChangeState(Enum.HumanoidStateType.Jumping)
                end
            end
        end)
    end
end

-- ─────────────────────────────────────────────────────
-- [10] NO CLIP
-- ─────────────────────────────────────────────────────
local function SetNoClip(on)
    if S.NoClipConn then S.NoClipConn:Disconnect(); S.NoClipConn = nil end
    if on then
        S.NoClipConn = RunService.Stepped:Connect(function()
            if not Char then return end
            for _, p in ipairs(Char:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
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
    if S.InfJump then SetInfJump(true)  end
    if S.NoClip  then SetNoClip(true)   end
    if S.FlyOn   then task.wait(0.3); StartFly() end
    Notif("Respawn", "Config diterapkan ulang setelah respawn!", 3)
end)

-- ─────────────────────────────────────────────────────
-- [12] HOTKEYS GLOBAL  (F / G / H)
-- ─────────────────────────────────────────────────────
UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    if UserInputService:GetFocusedTextBox() then return end

    if inp.KeyCode == Enum.KeyCode.F then
        S.FlyOn = not S.FlyOn
        if S.FlyOn then
            StartFly()
            Notif("Fly ON ✈️", "WASD+Space/Ctrl | Shift=cepat", 2)
        else
            StopFly()
            Notif("Fly OFF", "Kembali ke darat.", 2)
        end

    elseif inp.KeyCode == Enum.KeyCode.G then
        S.NoClip = not S.NoClip
        SetNoClip(S.NoClip)
        Notif("NoClip " .. (S.NoClip and "ON 👻" or "OFF"), "", 2)

    elseif inp.KeyCode == Enum.KeyCode.H then
        S.InfJump = not S.InfJump
        SetInfJump(S.InfJump)
        Notif("Infinite Jump " .. (S.InfJump and "ON 🦘" or "OFF"), "", 2)
    end
end)

-- ─────────────────────────────────────────────────────
-- [13] BUAT WINDOW  (WindUI)
-- ─────────────────────────────────────────────────────
local Window = WindUI:CreateWindow({
    Title  = "🐍 KingVypers x Tama",
    Icon   = "sprout",
    Author = "Sawah Indo  •  v5.0",
    Folder = "KVT_SawahIndo",
    Size   = UDim2.fromOffset(520, 440),
    Theme  = "Dark",
    HidePanelBackground = false,
    NewElements = false,
})

-- ─────────────────────────────────────────────────────
-- [14] TAB 1 — 🛒 AUTO BUY SEED
-- ─────────────────────────────────────────────────────
local TabBuy = Window:Tab({
    Title = "🛒 Buy Seed",
    Icon  = "shopping-basket",
})

TabBuy:Section({ Title = "Konfigurasi Benih" })

TabBuy:Dropdown({
    Title   = "Jenis Benih",
    Desc    = "Pilih jenis benih yang akan dibeli",
    Icon    = "leaf",
    Options = SeedList,
    Value   = "Padi",
    Callback = function(v)
        S.SeedType = v
        Notif("Benih", "Dipilih: " .. v, 2)
    end,
})

TabBuy:Slider({
    Title    = "Jumlah Beli per Siklus",
    Desc     = "Berapa biji tiap auto-buy",
    Icon     = "layers",
    Min      = 1,
    Max      = 100,
    Default  = 1,
    Suffix   = " biji",
    Callback = function(v) S.BuyQty = v end,
})

TabBuy:Slider({
    Title    = "Delay Auto Buy (detik)",
    Desc     = "Jeda antara tiap pembelian",
    Icon     = "timer",
    Min      = 1,
    Max      = 20,
    Default  = 2,
    Suffix   = "s",
    Callback = function(v) S.BuyDelay = v end,
})

TabBuy:Section({ Title = "Kontrol" })

TabBuy:Toggle({
    Title    = "🔁 Auto Buy Seed",
    Desc     = "Beli benih secara otomatis",
    Icon     = "repeat",
    Value    = false,
    Callback = function(v)
        if v then
            StartBuy()
            Notif("Auto Buy", "AKTIF 🟢", 2)
        else
            StopBuy()
            Notif("Auto Buy", "NONAKTIF 🔴", 2)
        end
    end,
})

TabBuy:Button({
    Title    = "⚡ Beli Sekali Sekarang",
    Desc     = "Jalankan satu siklus beli",
    Icon     = "zap",
    Callback = function()
        pcall(DoBuy)
        Notif("Buy Seed", "Aksi beli dijalankan!", 2)
    end,
})

-- ─────────────────────────────────────────────────────
-- [15] TAB 2 — 🌿 AUTO HARVEST
-- ─────────────────────────────────────────────────────
local TabHarv = Window:Tab({
    Title = "🌿 Harvest",
    Icon  = "wheat",
})

TabHarv:Section({ Title = "Pengaturan Panen" })

TabHarv:Slider({
    Title    = "Delay Harvest (detik)",
    Desc     = "Jeda antar siklus panen",
    Icon     = "timer",
    Min      = 1,
    Max      = 20,
    Default  = 3,
    Suffix   = "s",
    Callback = function(v) S.HarvDelay = v end,
})

TabHarv:Slider({
    Title    = "Radius Scan (studs)",
    Desc     = "Jarak maksimal teleport ke tanaman",
    Icon     = "scan",
    Min      = 10,
    Max      = 500,
    Default  = 60,
    Suffix   = " studs",
    Callback = function(v) S.HarvRadius = v end,
})

TabHarv:Section({ Title = "Kontrol" })

TabHarv:Toggle({
    Title    = "🔁 Auto Harvest",
    Desc     = "Panen tanaman otomatis",
    Icon     = "repeat",
    Value    = false,
    Callback = function(v)
        if v then
            StartHarv()
            Notif("Auto Harvest", "AKTIF 🟢", 2)
        else
            StopHarv()
            Notif("Auto Harvest", "NONAKTIF 🔴", 2)
        end
    end,
})

TabHarv:Button({
    Title    = "⚡ Panen Sekali Sekarang",
    Desc     = "Jalankan satu siklus panen",
    Icon     = "zap",
    Callback = function()
        local n = 0
        pcall(function() n = DoHarvest() end)
        Notif("Harvest", "Panen " .. n .. " tanaman!", 3)
    end,
})

-- ─────────────────────────────────────────────────────
-- [16] TAB 3 — 💰 AUTO SELL
-- ─────────────────────────────────────────────────────
local TabSell = Window:Tab({
    Title = "💰 Sell",
    Icon  = "coins",
})

TabSell:Section({ Title = "Pengaturan Jual" })

TabSell:Slider({
    Title    = "Delay Auto Sell (detik)",
    Desc     = "Jeda antar siklus jual",
    Icon     = "timer",
    Min      = 1,
    Max      = 30,
    Default  = 3,
    Suffix   = "s",
    Callback = function(v) S.SellDelay = v end,
})

TabSell:Section({ Title = "Kontrol" })

TabSell:Toggle({
    Title    = "🔁 Auto Sell",
    Desc     = "Jual hasil panen otomatis",
    Icon     = "repeat",
    Value    = false,
    Callback = function(v)
        if v then
            StartSell()
            Notif("Auto Sell", "AKTIF 🟢", 2)
        else
            StopSell()
            Notif("Auto Sell", "NONAKTIF 🔴", 2)
        end
    end,
})

TabSell:Button({
    Title    = "⚡ Jual Sekali Sekarang",
    Desc     = "Jalankan satu siklus jual",
    Icon     = "zap",
    Callback = function()
        pcall(DoSell)
        Notif("Sell", "Aksi jual dijalankan!", 2)
    end,
})

-- ─────────────────────────────────────────────────────
-- [17] TAB 4 — 🚀 MOVEMENT
-- ─────────────────────────────────────────────────────
local TabMove = Window:Tab({
    Title = "🚀 Movement",
    Icon  = "rocket",
})

TabMove:Section({ Title = "✈️ Fly  [Hotkey: F]" })

TabMove:Toggle({
    Title    = "✈️ Fly Mode",
    Desc     = "WASD+Space/Ctrl terbang | Shift=cepat",
    Icon     = "plane",
    Value    = false,
    Callback = function(v)
        S.FlyOn = v
        if v then
            StartFly()
            Notif("Fly", "ON ✈️ — WASD+Space/Ctrl | Shift=cepat", 3)
        else
            StopFly()
            Notif("Fly", "OFF", 2)
        end
    end,
})

TabMove:Slider({
    Title    = "Kecepatan Terbang",
    Desc     = "Speed saat fly aktif",
    Icon     = "gauge",
    Min      = 10,
    Max      = 500,
    Default  = 60,
    Suffix   = " studs/s",
    Callback = function(v) S.FlySpeed = v end,
})

TabMove:Section({ Title = "🦘 Jump  [Hotkey: H]" })

TabMove:Toggle({
    Title    = "🦘 Infinite Jump",
    Desc     = "Lompat terus-menerus",
    Icon     = "arrow-up",
    Value    = false,
    Callback = function(v)
        S.InfJump = v
        SetInfJump(v)
        Notif("Infinite Jump", v and "ON 🟢" or "OFF 🔴", 2)
    end,
})

TabMove:Slider({
    Title    = "Jump Power",
    Desc     = "Kekuatan lompatan karakter",
    Icon     = "chevrons-up",
    Min      = 50,
    Max      = 1000,
    Default  = 50,
    Suffix   = "",
    Callback = function(v)
        S.JumpPow = v
        if Hum then Hum.JumpPower = v end
    end,
})

TabMove:Section({ Title = "⚡ Speed" })

TabMove:Slider({
    Title    = "Walk Speed",
    Desc     = "Kecepatan berjalan normal",
    Icon     = "footprints",
    Min      = 16,
    Max      = 500,
    Default  = 16,
    Suffix   = "",
    Callback = function(v)
        S.WalkSpd = v
        if Hum then Hum.WalkSpeed = v end
    end,
})

TabMove:Section({ Title = "👻 Extra  [NoClip: G]" })

TabMove:Toggle({
    Title    = "👻 No Clip",
    Desc     = "Tembus dinding",
    Icon     = "ghost",
    Value    = false,
    Callback = function(v)
        S.NoClip = v
        SetNoClip(v)
        Notif("NoClip", v and "ON 🟢" or "OFF 🔴", 2)
    end,
})

TabMove:Button({
    Title    = "📍 Teleport ke Spawn",
    Desc     = "TP ke SpawnLocation terdekat",
    Icon     = "map-pin",
    Callback = function()
        local sp  = FindAll("SpawnLocation")
        if #sp > 0 then
            local pos = ObjPos(sp[1])
            if pos then SafeTP(pos); Notif("Teleport", "Ke Spawn!", 2) end
        else
            Notif("Error", "SpawnLocation tidak ditemukan.", 3)
        end
    end,
})

TabMove:Button({
    Title    = "🔄 Reset Karakter",
    Desc     = "Matikan karakter lalu respawn",
    Icon     = "refresh-cw",
    Callback = function()
        if Hum then Hum.Health = 0 end
    end,
})

-- ─────────────────────────────────────────────────────
-- [18] TAB 5 — 📍 LOKASI LAHAN
-- ─────────────────────────────────────────────────────
local TabLoc = Window:Tab({
    Title = "📍 Lokasi",
    Icon  = "map",
})

local Slots = {
    "Lahan Utama","Lahan Cadangan","Toko Benih",
    "Pasar / Jual","Gudang","Custom A","Custom B","Custom C"
}

TabLoc:Section({ Title = "💾 Simpan Posisi" })
for _, slot in ipairs(Slots) do
    TabLoc:Button({
        Title    = "💾 " .. slot,
        Desc     = "Simpan posisi sekarang ke slot ini",
        Icon     = "bookmark",
        Callback = function()
            if not HRP then Notif("Error", "Character tidak ada.", 2); return end
            S.Locs[slot] = HRP.CFrame
            local p = HRP.Position
            Notif("Disimpan ✅", string.format("%s  X:%.1f Y:%.1f Z:%.1f", slot, p.X, p.Y, p.Z), 4)
        end,
    })
end

TabLoc:Section({ Title = "🚀 Teleport ke Lokasi" })
for _, slot in ipairs(Slots) do
    TabLoc:Button({
        Title    = "🚀 " .. slot,
        Desc     = "Teleport ke lokasi yang disimpan",
        Icon     = "navigation",
        Callback = function()
            local cf = S.Locs[slot]
            if cf then
                SafeTPCF(cf)
                Notif("Teleport", "→ " .. slot, 2)
            else
                Notif("Kosong ❌", slot .. " belum disimpan!", 3)
            end
        end,
    })
end

TabLoc:Section({ Title = "🎯 Koordinat Manual" })

local mX, mY, mZ = 0, 5, 0

TabLoc:Input({
    Title       = "Koordinat X",
    Desc        = "Masukkan nilai X",
    Icon        = "axis-x",
    Placeholder = "0",
    Callback    = function(v) mX = tonumber(v) or 0 end,
})
TabLoc:Input({
    Title       = "Koordinat Y",
    Desc        = "Masukkan nilai Y",
    Icon        = "axis-y",
    Placeholder = "5",
    Callback    = function(v) mY = tonumber(v) or 5 end,
})
TabLoc:Input({
    Title       = "Koordinat Z",
    Desc        = "Masukkan nilai Z",
    Icon        = "axis-z",
    Placeholder = "0",
    Callback    = function(v) mZ = tonumber(v) or 0 end,
})

TabLoc:Button({
    Title    = "🎯 Teleport ke Koordinat",
    Desc     = "TP ke X Y Z yang dimasukkan",
    Icon     = "crosshair",
    Callback = function()
        SafeTP(Vector3.new(mX, mY, mZ))
        Notif("Teleport", string.format("X:%.1f Y:%.1f Z:%.1f", mX, mY, mZ), 3)
    end,
})

TabLoc:Button({
    Title    = "📋 Lihat Posisi Saat Ini",
    Desc     = "Tampilkan koordinat karakter sekarang",
    Icon     = "locate",
    Callback = function()
        if not HRP then Notif("Error", "Character tidak ada.", 2); return end
        local p = HRP.Position
        Notif("Posisi", string.format("X: %.2f  Y: %.2f  Z: %.2f", p.X, p.Y, p.Z), 5)
    end,
})

-- ─────────────────────────────────────────────────────
-- [19] TAB 6 — ⚙️ SETTINGS
-- ─────────────────────────────────────────────────────
local TabSet = Window:Tab({
    Title = "⚙️ Settings",
    Icon  = "settings",
})

TabSet:Section({ Title = "ℹ️ Info Script" })

TabSet:Paragraph({
    Title   = "🐍 KingVypers x Tama  •  v5.0",
    Desc    = "Game: Sawah Indo  •  UI: WindUI (Footagesus)\nHotkeys: F=Fly  G=NoClip  H=InfJump\nRightShift = Toggle UI",
})

TabSet:Section({ Title = "📊 Statistik Sesi" })

local statParagraph = TabSet:Paragraph({
    Title = "📊 Statistik",
    Desc  = "Harvest: 0  |  Sold: 0  |  Bought: 0",
})

-- [FIX] Update loop berhenti kalau UIAlive = false
task.spawn(function()
    while S.UIAlive do
        task.wait(2)
        pcall(function()
            statParagraph:SetDesc(string.format(
                "Harvest: %d  |  Sold: %d  |  Bought: %d",
                S.Harvested, S.Sold, S.Bought
            ))
        end)
    end
end)

TabSet:Section({ Title = "🔧 Aksi" })

TabSet:Button({
    Title    = "🔔 Test Notifikasi",
    Desc     = "Cek apakah notifikasi berjalan",
    Icon     = "bell",
    Callback = function()
        Notif("KingVypers x Tama ✅", "Script berjalan normal! v5.0", 4)
    end,
})

TabSet:Button({
    Title    = "🧹 Matikan Semua Fitur",
    Desc     = "Reset semua toggle dan speed",
    Icon     = "power-off",
    Callback = function()
        StopBuy(); StopHarv(); StopSell()
        S.FlyOn = false; StopFly()
        S.InfJump = false; SetInfJump(false)
        S.NoClip  = false; SetNoClip(false)
        S.WalkSpd = 16; S.JumpPow = 50
        if Hum then Hum.WalkSpeed = 16; Hum.JumpPower = 50 end
        Notif("Reset 🧹", "Semua fitur dimatikan.", 3)
    end,
})

TabSet:Button({
    Title    = "❌ Destroy Script",
    Desc     = "Hentikan dan hapus UI sepenuhnya",
    Icon     = "trash-2",
    Callback = function()
        StopBuy(); StopHarv(); StopSell()
        StopFly(); SetInfJump(false); SetNoClip(false)
        if Hum then Hum.WalkSpeed = 16; Hum.JumpPower = 50 end
        S.UIAlive = false
        Notif("Bye 👋", "Script dihentikan.", 3)
        task.wait(1.5)
        pcall(function() Window:Destroy() end)
    end,
})

-- ─────────────────────────────────────────────────────
-- [20] STARTUP NOTIFICATION
-- ─────────────────────────────────────────────────────
task.wait(2)
WindUI:Notify({
    Title    = "🐍 KingVypers x Tama v5.0",
    Content  = "Sawah Indo siap!\nF=Fly  G=NoClip  H=InfJump",
    Duration = 6,
})
print("╔══════════════════════════════════════╗")
print("║  🐍 KingVypers x Tama  •  v5.0       ║")
print("║  Sawah Indo  •  WindUI  •  Loaded    ║")
print("║  F=Fly | G=NoClip | H=InfJump        ║")
print("╚══════════════════════════════════════╝")

-- ─────────────────────────────────────────────────────
-- END OF SCRIPT
-- ─────────────────────────────────────────────────────
