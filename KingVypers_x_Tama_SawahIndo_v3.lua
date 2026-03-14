--[[
╔══════════════════════════════════════════════════════════════╗
║         K I N G V Y P E R S  x  T A M A                     ║
║         Sawah Indo Script  |  v3.0  |  Hitam Glossy          ║
║         UI: Rayfield  |  sirius.menu/rayfield                ║
╚══════════════════════════════════════════════════════════════╝
]]

-- ============================================================
-- [0] LOAD RAYFIELD
-- ============================================================
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- ============================================================
-- [1] SERVICES
-- ============================================================
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer       = Players.LocalPlayer
local Camera            = Workspace.CurrentCamera

-- ============================================================
-- [2] CHARACTER REFERENCE (respawn-safe)
-- ============================================================
local Character, HRP, Humanoid

local function UpdateCharacter(char)
    Character = char
    HRP       = char:WaitForChild("HumanoidRootPart")
    Humanoid  = char:WaitForChild("Humanoid")
end

UpdateCharacter(LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait())
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    UpdateCharacter(char)
end)

-- ============================================================
-- [3] STATE TABLE
-- ============================================================
local S = {
    -- Buy Seed
    AutoBuySeed     = false,
    BuySeedThread   = nil,
    BuySeedDelay    = 2,
    SeedType        = "Padi",
    BuyAmount       = 1,

    -- Harvest
    AutoHarvest     = false,
    HarvestThread   = nil,
    HarvestDelay    = 2,
    HarvestRadius   = 50,

    -- Sell
    AutoSell        = false,
    SellThread      = nil,
    SellDelay       = 3,

    -- Fly
    FlyEnabled      = false,
    FlySpeed        = 60,
    FlyConn         = nil,
    BodyVel         = nil,
    BodyGyro        = nil,

    -- Jump
    JumpPower       = 50,
    InfiniteJump    = false,
    InfJumpConn     = nil,

    -- Speed
    WalkSpeed       = 16,
    NoClip          = false,
    NoClipConn      = nil,

    -- Locations
    Locations       = {},

    -- Stats
    TotalHarvested  = 0,
    TotalSold       = 0,
    TotalBought     = 0,
}

-- ============================================================
-- [4] UTILITY
-- ============================================================
local function Notif(title, body, dur)
    Rayfield:Notify({
        Title    = title,
        Content  = body,
        Duration = dur or 3,
        Image    = "rbxassetid://11963000108",
    })
end

-- Deep search by keyword
local function FindAll(keyword, root)
    root = root or Workspace
    local res = {}
    for _, v in ipairs(root:GetDescendants()) do
        if string.lower(v.Name):find(string.lower(keyword)) then
            table.insert(res, v)
        end
    end
    return res
end

-- Find nearest object from a list
local function Nearest(list, maxDist)
    local best, bestD = nil, maxDist or math.huge
    for _, obj in ipairs(list) do
        local pos
        if obj:IsA("Model") then
            local p = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if p then pos = p.Position end
        elseif obj:IsA("BasePart") then
            pos = obj.Position
        end
        if pos then
            local d = (HRP.Position - pos).Magnitude
            if d < bestD then best = obj; bestD = d end
        end
    end
    return best, bestD
end

-- Safe teleport
local function TpTo(pos)
    if HRP then
        HRP.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
        task.wait(0.15)
    end
end

local function TpCF(cf)
    if HRP then HRP.CFrame = cf; task.wait(0.15) end
end

-- Fire remote by name search
local function FireRemote(name, ...)
    local r = ReplicatedStorage:FindFirstChild(name, true)
           or Workspace:FindFirstChild(name, true)
    if r and r:IsA("RemoteEvent") then
        r:FireServer(...)
        return true
    end
    return false
end

-- Try proximity prompts & click detectors on an object
local function InteractObject(obj)
    if not obj then return end
    for _, d in ipairs(obj:GetDescendants()) do
        if d:IsA("ProximityPrompt") then
            pcall(fireproximityprompt, d)
        elseif d:IsA("ClickDetector") then
            pcall(fireclickdetector, d)
        end
    end
end

-- ============================================================
-- [5] AUTO BUY SEED
-- ============================================================
local SeedList = {
    "Padi","Jagung","Kacang","Singkong","Cabai",
    "Tomat","Bawang","Kangkung","Bayam","Semangka",
    "Wortel","Kentang","Timun","Terong","Labu"
}

local function DoBuySeed()
    -- 1. Coba remote event
    local remotes = {"BuySeed","BeliSeed","BuyItem","Purchase","BuyPlant","BuySeedEvent"}
    for _, rn in ipairs(remotes) do
        if FireRemote(rn, S.SeedType, S.BuyAmount) then
            S.TotalBought = S.TotalBought + S.BuyAmount
            return true
        end
    end

    -- 2. Cari NPC / objek Toko
    local keywords = {"Toko","Shop","Kios","Store","BeliSeed","SeedShop","BeniKios"}
    local found = {}
    for _, kw in ipairs(keywords) do
        for _, v in ipairs(FindAll(kw)) do table.insert(found, v) end
    end

    local nearest = Nearest(found, 500)
    if nearest then
        local pos
        if nearest:IsA("Model") then
            local p = nearest.PrimaryPart or nearest:FindFirstChildWhichIsA("BasePart")
            if p then pos = p.Position end
        elseif nearest:IsA("BasePart") then
            pos = nearest.Position
        end
        if pos then
            TpTo(pos)
            task.wait(0.4)
            InteractObject(nearest)
            S.TotalBought = S.TotalBought + S.BuyAmount
            return true
        end
    end
    return false
end

local function StartAutoBuy()
    if S.BuySeedThread then task.cancel(S.BuySeedThread) end
    S.BuySeedThread = task.spawn(function()
        while S.AutoBuySeed do
            pcall(DoBuySeed)
            task.wait(S.BuySeedDelay)
        end
    end)
end

local function StopAutoBuy()
    S.AutoBuySeed = false
    if S.BuySeedThread then task.cancel(S.BuySeedThread); S.BuySeedThread = nil end
end

-- ============================================================
-- [6] AUTO HARVEST
-- ============================================================
local function DoHarvest()
    local count = 0
    local cropKeys = {
        "Panen","Harvest","Tanaman","Plant","Crop","Lahan",
        "Sawah","Kebun","Field","Padi","Jagung",
        string.lower(S.SeedType)
    }

    -- 1. Coba remote
    for _, rn in ipairs({"Harvest","Panen","HarvestCrop","CollectPlant","HarvestAll"}) do
        FireRemote(rn)
    end

    -- 2. Scan workspace
    for _, kw in ipairs(cropKeys) do
        local crops = FindAll(kw)
        for _, crop in ipairs(crops) do
            -- Cek apakah sudah siap panen
            local ready = true
            local stageVal = crop:FindFirstChild("Stage") or crop:FindFirstChild("GrowStage")
            local grownVal = crop:FindFirstChild("Grown") or crop:FindFirstChild("Ready") or crop:FindFirstChild("CanHarvest")

            if grownVal and grownVal:IsA("BoolValue") then
                ready = grownVal.Value
            elseif stageVal and stageVal:IsA("IntValue") then
                ready = stageVal.Value >= 3
            elseif stageVal and stageVal:IsA("NumberValue") then
                ready = stageVal.Value >= 3
            end

            if ready then
                local pos
                if crop:IsA("Model") then
                    local p = crop.PrimaryPart or crop:FindFirstChildWhichIsA("BasePart")
                    if p then pos = p.Position end
                elseif crop:IsA("BasePart") then
                    pos = crop.Position
                end

                if pos then
                    local dist = (HRP.Position - pos).Magnitude
                    if dist <= S.HarvestRadius then
                        TpTo(pos)
                        task.wait(0.2)
                        InteractObject(crop)
                        count = count + 1
                    end
                end
            end
        end
    end

    S.TotalHarvested = S.TotalHarvested + count
    return count
end

local function StartAutoHarvest()
    if S.HarvestThread then task.cancel(S.HarvestThread) end
    S.HarvestThread = task.spawn(function()
        while S.AutoHarvest do
            pcall(DoHarvest)
            task.wait(S.HarvestDelay)
        end
    end)
end

local function StopAutoHarvest()
    S.AutoHarvest = false
    if S.HarvestThread then task.cancel(S.HarvestThread); S.HarvestThread = nil end
end

-- ============================================================
-- [7] AUTO SELL
-- ============================================================
local function DoSell()
    -- 1. Coba remote
    for _, rn in ipairs({"Sell","Jual","SellAll","SellCrops","SellItem","JualHasil","SellHarvest"}) do
        FireRemote(rn)
    end

    -- 2. Cari titik jual
    local keywords = {"Sell","Jual","Pasar","Market","Gudang","SellPoint","JualPoin"}
    local found = {}
    for _, kw in ipairs(keywords) do
        for _, v in ipairs(FindAll(kw)) do table.insert(found, v) end
    end

    local nearest = Nearest(found, 600)
    if nearest then
        local pos
        if nearest:IsA("Model") then
            local p = nearest.PrimaryPart or nearest:FindFirstChildWhichIsA("BasePart")
            if p then pos = p.Position end
        elseif nearest:IsA("BasePart") then
            pos = nearest.Position
        end
        if pos then
            TpTo(pos)
            task.wait(0.5)
            InteractObject(nearest)
            S.TotalSold = S.TotalSold + 1
            return true
        end
    end
    return false
end

local function StartAutoSell()
    if S.SellThread then task.cancel(S.SellThread) end
    S.SellThread = task.spawn(function()
        while S.AutoSell do
            pcall(DoSell)
            task.wait(S.SellDelay)
        end
    end)
end

local function StopAutoSell()
    S.AutoSell = false
    if S.SellThread then task.cancel(S.SellThread); S.SellThread = nil end
end

-- ============================================================
-- [8] FLY
-- ============================================================
local function StartFly()
    -- Bersihkan instance lama
    if S.FlyConn then S.FlyConn:Disconnect(); S.FlyConn = nil end
    if S.BodyVel  then S.BodyVel:Destroy();  S.BodyVel  = nil end
    if S.BodyGyro then S.BodyGyro:Destroy(); S.BodyGyro = nil end

    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.zero
    bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    bv.Parent   = HRP
    S.BodyVel   = bv

    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
    bg.P         = 5e3
    bg.D         = 1e2
    bg.Parent    = HRP
    S.BodyGyro   = bg

    Humanoid.PlatformStand = true

    S.FlyConn = RunService.RenderStepped:Connect(function()
        if not S.FlyEnabled or not HRP then return end
        local dir = Vector3.zero
        local cf  = Camera.CFrame
        local spd = S.FlySpeed

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += cf.LookVector   end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= cf.LookVector   end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= cf.RightVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += cf.RightVector  end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)   then spd = spd * 2        end

        bv.Velocity = (dir.Magnitude > 0 and dir.Unit or Vector3.zero) * spd
        bg.CFrame   = cf
    end)
end

local function StopFly()
    if S.FlyConn then S.FlyConn:Disconnect(); S.FlyConn = nil end
    if S.BodyVel  then S.BodyVel:Destroy();  S.BodyVel  = nil end
    if S.BodyGyro then S.BodyGyro:Destroy(); S.BodyGyro = nil end
    if Humanoid   then Humanoid.PlatformStand = false           end
end

-- ============================================================
-- [9] JUMP / NO-CLIP
-- ============================================================
local function SetInfJump(state)
    if S.InfJumpConn then S.InfJumpConn:Disconnect(); S.InfJumpConn = nil end
    if state then
        S.InfJumpConn = UserInputService.JumpRequest:Connect(function()
            if Humanoid then Humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

local function SetNoClip(state)
    if S.NoClipConn then S.NoClipConn:Disconnect(); S.NoClipConn = nil end
    if state then
        S.NoClipConn = RunService.Stepped:Connect(function()
            if Character then
                for _, p in ipairs(Character:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end)
    else
        if Character then
            for _, p in ipairs(Character:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = true end
            end
        end
    end
end

-- ============================================================
-- [10] KEYBINDS (GLOBAL)
-- ============================================================
UserInputService.InputBegan:Connect(function(inp, gpe)
    if gpe then return end
    -- F  = Toggle Fly
    if inp.KeyCode == Enum.KeyCode.F then
        S.FlyEnabled = not S.FlyEnabled
        if S.FlyEnabled then StartFly(); Notif("✈️ Fly","Terbang AKTIF  [F]",2)
        else StopFly(); Notif("✈️ Fly","Terbang NONAKTIF  [F]",2) end
    end
    -- G = Toggle NoClip
    if inp.KeyCode == Enum.KeyCode.G then
        S.NoClip = not S.NoClip
        SetNoClip(S.NoClip)
        Notif("👻 NoClip", S.NoClip and "NoClip ON [G]" or "NoClip OFF [G]", 2)
    end
    -- H = Toggle InfJump
    if inp.KeyCode == Enum.KeyCode.H then
        S.InfiniteJump = not S.InfiniteJump
        SetInfJump(S.InfiniteJump)
        Notif("🦘 InfJump", S.InfiniteJump and "Infinite Jump ON [H]" or "Infinite Jump OFF [H]", 2)
    end
end)

-- Respawn: terapkan ulang state
LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(1)
    UpdateCharacter(char)
    Humanoid.WalkSpeed = S.WalkSpeed
    Humanoid.JumpPower = S.JumpPower
    if S.InfiniteJump then SetInfJump(true) end
    if S.NoClip        then SetNoClip(true)  end
    if S.FlyEnabled    then
        S.FlyEnabled = false; task.wait(0.3)
        S.FlyEnabled = true; StartFly()
    end
    Notif("🔄 Respawn","Config diterapkan ulang!",3)
end)

-- ============================================================
-- [11] WINDOW RAYFIELD
-- ============================================================
local Window = Rayfield:CreateWindow({
    Name             = "KingVypers x Tama",
    Icon             = 0,
    LoadingTitle     = "  KingVypers x Tama  ",
    LoadingSubtitle  = "Sawah Indo Script  •  v3.0",
    Theme            = "Default",
    DisableRayfieldPrompts = false,
    DisableBuildWarnings   = true,
    ConfigurationSaving = {
        Enabled    = true,
        FolderName = "KVxTama",
        FileName   = "SawahIndo_v3",
    },
    KeySystem = false,
})

-- ============================================================
-- [12] TAB 1 — 🛒 AUTO BUY SEED
-- ============================================================
local TabBuy = Window:CreateTab("🛒 Auto Buy Seed", 4483345998)

TabBuy:CreateSection("Pilih Benih")

TabBuy:CreateDropdown({
    Name          = "Jenis Benih",
    Options       = SeedList,
    CurrentOption = { "Padi" },
    MultipleOptions = false,
    Flag          = "SeedType",
    Callback      = function(sel)
        S.SeedType = sel[1] or "Padi"
        Notif("🌱 Benih", "Benih dipilih: "..S.SeedType, 2)
    end,
})

TabBuy:CreateSlider({
    Name         = "Jumlah Beli per Aksi",
    Range        = {1, 100},
    Increment    = 1,
    Suffix       = " biji",
    CurrentValue = 1,
    Flag         = "BuyAmount",
    Callback     = function(v) S.BuyAmount = v end,
})

TabBuy:CreateSlider({
    Name         = "Delay Auto Buy (detik)",
    Range        = {1, 15},
    Increment    = 0.5,
    Suffix       = "s",
    CurrentValue = 2,
    Flag         = "BuySeedDelay",
    Callback     = function(v) S.BuySeedDelay = v end,
})

TabBuy:CreateSection("Kontrol")

TabBuy:CreateToggle({
    Name         = "🔁 Auto Buy Seed",
    CurrentValue = false,
    Flag         = "AutoBuySeed",
    Callback     = function(v)
        S.AutoBuySeed = v
        if v then StartAutoBuy(); Notif("🛒 Auto Buy","Auto Buy Seed AKTIF",3)
        else StopAutoBuy(); Notif("🛒 Auto Buy","Auto Buy Seed NONAKTIF",2) end
    end,
})

TabBuy:CreateButton({
    Name     = "⚡ Beli Seed Sekali Sekarang",
    Callback = function()
        local ok = pcall(DoBuySeed)
        Notif("🛒 Buy","Aksi beli seed dijalankan!", 3)
    end,
})

-- ============================================================
-- [13] TAB 2 — 🌿 AUTO HARVEST
-- ============================================================
local TabHarv = Window:CreateTab("🌿 Auto Harvest", 4483345998)

TabHarv:CreateSection("Pengaturan Panen")

TabHarv:CreateSlider({
    Name         = "Delay Harvest (detik)",
    Range        = {0.5, 15},
    Increment    = 0.5,
    Suffix       = "s",
    CurrentValue = 2,
    Flag         = "HarvestDelay",
    Callback     = function(v) S.HarvestDelay = v end,
})

TabHarv:CreateSlider({
    Name         = "Radius Scan Tanaman (studs)",
    Range        = {10, 500},
    Increment    = 5,
    Suffix       = " studs",
    CurrentValue = 50,
    Flag         = "HarvestRadius",
    Callback     = function(v) S.HarvestRadius = v end,
})

TabHarv:CreateSection("Kontrol")

TabHarv:CreateToggle({
    Name         = "🔁 Auto Harvest",
    CurrentValue = false,
    Flag         = "AutoHarvest",
    Callback     = function(v)
        S.AutoHarvest = v
        if v then StartAutoHarvest(); Notif("🌿 Harvest","Auto Harvest AKTIF",3)
        else StopAutoHarvest(); Notif("🌿 Harvest","Auto Harvest NONAKTIF",2) end
    end,
})

TabHarv:CreateButton({
    Name     = "⚡ Panen Sekarang (Sekali)",
    Callback = function()
        local count = 0
        pcall(function() count = DoHarvest() end)
        Notif("🌿 Panen","Berhasil panen "..count.." tanaman!", 3)
    end,
})

-- ============================================================
-- [14] TAB 3 — 💰 AUTO SELL
-- ============================================================
local TabSell = Window:CreateTab("💰 Auto Sell", 4483345998)

TabSell:CreateSection("Pengaturan Jual")

TabSell:CreateSlider({
    Name         = "Delay Auto Sell (detik)",
    Range        = {1, 20},
    Increment    = 0.5,
    Suffix       = "s",
    CurrentValue = 3,
    Flag         = "SellDelay",
    Callback     = function(v) S.SellDelay = v end,
})

TabSell:CreateSection("Kontrol")

TabSell:CreateToggle({
    Name         = "🔁 Auto Sell",
    CurrentValue = false,
    Flag         = "AutoSell",
    Callback     = function(v)
        S.AutoSell = v
        if v then StartAutoSell(); Notif("💰 Sell","Auto Sell AKTIF",3)
        else StopAutoSell(); Notif("💰 Sell","Auto Sell NONAKTIF",2) end
    end,
})

TabSell:CreateButton({
    Name     = "⚡ Jual Sekarang (Sekali)",
    Callback = function()
        pcall(DoSell)
        Notif("💰 Jual","Aksi jual dijalankan!",3)
    end,
})

-- ============================================================
-- [15] TAB 4 — 🚀 MOVEMENT
-- ============================================================
local TabMove = Window:CreateTab("🚀 Movement", 4483345998)

TabMove:CreateSection("✈️ Fly")

TabMove:CreateToggle({
    Name         = "✈️ Fly Mode  [Hotkey: F]",
    CurrentValue = false,
    Flag         = "FlyToggle",
    Callback     = function(v)
        S.FlyEnabled = v
        if v then StartFly(); Notif("✈️ Fly","Terbang AKTIF — WASD+Space/Ctrl | Shift=Fast",3)
        else StopFly(); Notif("✈️ Fly","Terbang NONAKTIF",2) end
    end,
})

TabMove:CreateSlider({
    Name         = "Kecepatan Terbang",
    Range        = {10, 500},
    Increment    = 5,
    Suffix       = " studs/s",
    CurrentValue = 60,
    Flag         = "FlySpeed",
    Callback     = function(v) S.FlySpeed = v end,
})

TabMove:CreateSection("🦘 Jump")

TabMove:CreateToggle({
    Name         = "🦘 Infinite Jump  [Hotkey: H]",
    CurrentValue = false,
    Flag         = "InfJump",
    Callback     = function(v)
        S.InfiniteJump = v
        SetInfJump(v)
        Notif("🦘 InfJump", v and "Infinite Jump AKTIF" or "Infinite Jump NONAKTIF", 2)
    end,
})

TabMove:CreateSlider({
    Name         = "Jump Power",
    Range        = {50, 1000},
    Increment    = 10,
    Suffix       = "",
    CurrentValue = 50,
    Flag         = "JumpPower",
    Callback     = function(v)
        S.JumpPower = v
        if Humanoid then Humanoid.JumpPower = v end
    end,
})

TabMove:CreateSection("⚡ Speed")

TabMove:CreateSlider({
    Name         = "Walk Speed",
    Range        = {16, 500},
    Increment    = 1,
    Suffix       = "",
    CurrentValue = 16,
    Flag         = "WalkSpeed",
    Callback     = function(v)
        S.WalkSpeed = v
        if Humanoid then Humanoid.WalkSpeed = v end
    end,
})

TabMove:CreateSection("👻 NoClip & Lainnya")

TabMove:CreateToggle({
    Name         = "👻 No Clip  [Hotkey: G]",
    CurrentValue = false,
    Flag         = "NoClip",
    Callback     = function(v)
        S.NoClip = v
        SetNoClip(v)
        Notif("👻 NoClip", v and "NoClip AKTIF" or "NoClip NONAKTIF", 2)
    end,
})

TabMove:CreateButton({
    Name     = "📍 Teleport ke Spawn",
    Callback = function()
        local spawns = FindAll("SpawnLocation")
        if #spawns > 0 then
            local sp = spawns[1]
            local pos = sp:IsA("BasePart") and sp.Position
            if pos then TpTo(pos); Notif("📍","Teleport ke Spawn!",2) end
        else
            Notif("❌","SpawnLocation tidak ditemukan.",3)
        end
    end,
})

TabMove:CreateButton({
    Name     = "🔄 Reset Character",
    Callback = function()
        if Humanoid then Humanoid.Health = 0 end
    end,
})

-- ============================================================
-- [16] TAB 5 — 📍 LOKASI LAHAN
-- ============================================================
local TabLoc = Window:CreateTab("📍 Lokasi Lahan", 4483345998)

-- Slot-slot lokasi
local LocSlots = {
    "Lahan Utama",
    "Lahan Cadangan",
    "Toko Benih",
    "Pasar / Jual",
    "Gudang",
    "Custom A",
    "Custom B",
    "Custom C",
}

TabLoc:CreateSection("💾 Simpan Lokasi Sekarang")
for _, slot in ipairs(LocSlots) do
    TabLoc:CreateButton({
        Name     = "💾  " .. slot,
        Callback = function()
            S.Locations[slot] = HRP.CFrame
            local p = HRP.Position
            Notif("📍 Disimpan", string.format("%s\nX:%.1f Y:%.1f Z:%.1f", slot, p.X, p.Y, p.Z), 4)
        end,
    })
end

TabLoc:CreateSection("🚀 Teleport ke Lokasi")
for _, slot in ipairs(LocSlots) do
    TabLoc:CreateButton({
        Name     = "🚀  " .. slot,
        Callback = function()
            local cf = S.Locations[slot]
            if cf then
                TpCF(cf)
                Notif("🚀 Teleport", "Teleport ke: " .. slot, 2)
            else
                Notif("❌ Kosong", slot .. " belum disimpan!", 3)
            end
        end,
    })
end

TabLoc:CreateSection("🗑️ Hapus Lokasi")
for _, slot in ipairs(LocSlots) do
    TabLoc:CreateButton({
        Name     = "🗑️  " .. slot,
        Callback = function()
            S.Locations[slot] = nil
            Notif("🗑️ Dihapus", slot .. " dihapus.", 2)
        end,
    })
end

TabLoc:CreateSection("🎯 Teleport Koordinat Manual")

local manX, manY, manZ = 0, 5, 0

TabLoc:CreateInput({
    Name            = "X",
    CurrentValue    = "0",
    PlaceholderText = "Koordinat X",
    NumbersOnly     = true,
    Flag            = "ManualX",
    Callback        = function(v) manX = tonumber(v) or 0 end,
})
TabLoc:CreateInput({
    Name            = "Y",
    CurrentValue    = "5",
    PlaceholderText = "Koordinat Y",
    NumbersOnly     = true,
    Flag            = "ManualY",
    Callback        = function(v) manY = tonumber(v) or 5 end,
})
TabLoc:CreateInput({
    Name            = "Z",
    CurrentValue    = "0",
    PlaceholderText = "Koordinat Z",
    NumbersOnly     = true,
    Flag            = "ManualZ",
    Callback        = function(v) manZ = tonumber(v) or 0 end,
})

TabLoc:CreateButton({
    Name     = "🎯 Teleport ke Koordinat",
    Callback = function()
        TpTo(Vector3.new(manX, manY, manZ))
        Notif("🎯 Teleport", string.format("X:%.1f Y:%.1f Z:%.1f", manX, manY, manZ), 3)
    end,
})

TabLoc:CreateButton({
    Name     = "📋 Lihat Posisi Sekarang",
    Callback = function()
        local p = HRP.Position
        Notif("📋 Posisi Saat Ini",
            string.format("X: %.2f\nY: %.2f\nZ: %.2f", p.X, p.Y, p.Z), 6)
    end,
})

-- ============================================================
-- [17] TAB 6 — ⚙️ SETTINGS & INFO
-- ============================================================
local TabSet = Window:CreateTab("⚙️ Settings", 4483345998)

TabSet:CreateSection("ℹ️ Informasi Script")
TabSet:CreateLabel("   Script : KingVypers x Tama")
TabSet:CreateLabel("   Game   : Sawah Indo  •  Roblox")
TabSet:CreateLabel("   Versi  : v3.0  |  UI: Rayfield")
TabSet:CreateLabel("   Theme  : Hitam Glossy ✨")
TabSet:CreateLabel("   ─────────────────────────────")
TabSet:CreateLabel("   Hotkeys:  F=Fly  G=NoClip  H=InfJump")

TabSet:CreateSection("📊 Statistik Sesi")
local statLbl = TabSet:CreateLabel("📊  Harvest: 0  |  Sold: 0  |  Bought: 0")

-- update label tiap 2 detik
task.spawn(function()
    while true do
        task.wait(2)
        pcall(function()
            statLbl:Set(string.format(
                "📊  Harvest: %d  |  Sold: %d  |  Bought: %d",
                S.TotalHarvested, S.TotalSold, S.TotalBought
            ))
        end)
    end
end)

TabSet:CreateSection("🎨 Tema Rayfield")

TabSet:CreateDropdown({
    Name          = "Pilih Tema",
    Options       = {"Default","Amethyst","DarkBlue","Green","Light","Ocean","Serenity"},
    CurrentOption = {"Default"},
    MultipleOptions = false,
    Flag          = "RayfieldTheme",
    Callback      = function(sel)
        pcall(function() Rayfield:SetTheme(sel[1] or "Default") end)
        Notif("🎨 Tema","Tema: "..(sel[1] or "Default"),2)
    end,
})

TabSet:CreateSection("🔔 Test & Reset")

TabSet:CreateButton({
    Name     = "🔔 Test Notifikasi",
    Callback = function()
        Notif("✅ KingVypers x Tama","Script berjalan normal! v3.0 Sawah Indo",4)
    end,
})

TabSet:CreateButton({
    Name     = "🧹 Matikan Semua Fitur",
    Callback = function()
        StopAutoBuy()
        StopAutoHarvest()
        StopAutoSell()
        S.FlyEnabled   = false; StopFly()
        S.InfiniteJump = false; SetInfJump(false)
        S.NoClip       = false; SetNoClip(false)
        if Humanoid then
            Humanoid.WalkSpeed = 16
            Humanoid.JumpPower = 50
        end
        Notif("🧹 Reset","Semua fitur dimatikan.",3)
    end,
})

TabSet:CreateButton({
    Name     = "❌ Destroy Script",
    Callback = function()
        StopAutoBuy(); StopAutoHarvest(); StopAutoSell()
        StopFly(); SetInfJump(false); SetNoClip(false)
        Notif("❌ Bye!","Script dihentikan. See you! 👋",3)
        task.wait(1)
        pcall(function() Rayfield:Destroy() end)
    end,
})

-- ============================================================
-- [18] STARTUP
-- ============================================================
task.wait(2.5)
Notif(
    "✅ KingVypers x Tama Loaded!",
    "Sawah Indo v3.0 siap digunakan\nF=Fly  •  G=NoClip  •  H=InfJump",
    6
)
print("╔══════════════════════════════════╗")
print("║  KingVypers x Tama  •  v3.0      ║")
print("║  Sawah Indo Script Loaded ✅     ║")
print("║  F=Fly | G=NoClip | H=InfJump   ║")
print("╚══════════════════════════════════╝")
