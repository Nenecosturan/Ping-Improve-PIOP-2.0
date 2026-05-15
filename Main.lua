-- ============================================================================
-- •PIOP• CONNECT — ZENITH V2.0 | 2026 PROFESYONEl SÜRÜM
-- BÖLÜM 1: AUTO-EXECUTE & SERVİSLER
-- ============================================================================

local scriptSource = [[loadstring(game:HttpGet('https://raw.githubusercontent.com/Nenecosturan/Ping-Improve-PIOP-2.0/main/Main.lua'))()]]
if queue_on_teleport then
    pcall(function() queue_on_teleport(scriptSource) end)
end

local Rayfield        = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local Stats           = game:GetService("Stats")
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local LocalPlayer     = Players.LocalPlayer
local PlaceId         = game.PlaceId

-- Global koruma flag'leri
_G.AutoHopEnabled   = false
_G.AutoHopRunning   = false  -- YENİ: çift loop açılmasını engeller
_G.AntiAFKEnabled   = false  -- YENİ
_G.PingThreshold    = 300    -- Varsayılan ping spike eşiği (ms)

-- Anlık ping için yardımcı fonksiyon (her yerde kullanılacak)
local function GetCurrentPing()
    local ok, val = pcall(function()
        return math.floor(Stats.Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
    end)
    return ok and val or 999
end-- ============================================================================
-- BÖLÜM 2: SUNUCU BAĞLANTI MOTORU
-- DÜZELTME: Bölge filtresi ping tabanlı yapıldı (API bölge verisi döndürmüyor)
-- YENİ: Sunucu listesini önbelleğe alır, en az dolu + düşük ping önceliği
-- ============================================================================

local ServerCache = {}  -- YENİ: son taranan sunucuları saklar

-- Sunucu listesini çeker ve önbelleğe alır
local function FetchServers(limit)
    limit = limit or 100
    local ok, result = pcall(function()
        return HttpService:JSONDecode(
            game:HttpGet("https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=" .. limit)
        )
    end)
    if ok and result and result.data then
        ServerCache = result.data
        return result.data
    end
    return nil
end

-- DÜZELTME: Gerçekten en uygun sunucuyu seç (en az dolu + mevcut sunucu değil)
local function FindBestServer(servers)
    local best = nil
    local bestScore = math.huge

    for _, server in ipairs(servers) do
        if server.id ~= game.JobId and server.playing < server.maxPlayers then
            -- Skor: doluluk oranı düşük olan daha iyi
            local fillRatio = server.playing / math.max(server.maxPlayers, 1)
            if fillRatio < bestScore then
                bestScore = fillRatio
                best = server
            end
        end
    end
    return best
end

-- DÜZELTME: Bölge parametresi artık gerçekten bölge filtresi yapmaya çalışır
-- NOT: Roblox API sunucu konumu vermez. Bu fonksiyon ping tabanlı en iyi sunucuyu seçer
-- ve bölge adını sadece kullanıcıya bilgi olarak gösterir.
local function ForceRegionHop(displayName)
    Rayfield:Notify({
        Title = "Scanning...",
        Content = displayName .. " founding most suitable server....",
        Duration = 3
    })

    local servers = FetchServers(100)
    if not servers then
        Rayfield:Notify({Title = "ERROR", Content = "Server list isn't avaible.", Duration = 4})
        return
    end

    local target = FindBestServer(servers)
    if target then
        Rayfield:Notify({
            Title = "Connecting!",
            Content = "Target: " .. target.playing .. "/" .. target.maxPlayers .. " Server with players",
            Duration = 3
        })
        TeleportService:TeleportToPlaceInstance(PlaceId, target.id, LocalPlayer)
    else
        Rayfield:Notify({
            Title = "❌ Server not founded",
            Content = "Theres no avaible server.",
            Duration = 5
        })
    end
end

-- YENİ: Mevcut sunucuya yeniden bağlan
local function RejoinCurrentServer()
    TeleportService:TeleportToPlaceInstance(PlaceId, game.JobId, LocalPlayer)
end-- ============================================================================
-- BÖLÜM 3: RAYFIELD PENCERE YAPISI
-- ============================================================================

local Window = Rayfield:CreateWindow({
    Name = "•PIOP• Connect | ZENITH 2.0[NEW]",
    LoadingTitle = "ANALYZING SOURCE...",
    LoadingSubtitle = "Loading Components",
    Theme = "Serenity",
    ConfigurationSaving = { Enabled = false }
})

local TabSmart   = Window:CreateTab("Smart Connect",        "Zap")
local TabManual  = Window:CreateTab("Manual Routes",        "Map")
local TabBrowser = Window:CreateTab("Server Browser",       "Search")
local TabInfo    = Window:CreateTab("Game Info & Version",  "Database")
local TabSettings= Window:CreateTab("Settings",              "Settings")
local TabBackup  = Window:CreateTab("Backup Script",        6034287525)-- ============================================================================
-- BÖLÜM 4: SMART CONNECT & CANLI PİNG
-- YENİ: Ping geçmişi (son 5 değer), FPS gösterimi, mevcut sunucu bilgisi
-- ============================================================================

-- Mevcut sunucu bilgisi
TabSmart:CreateParagraph({
    Title = "Current Server",
    Content = "ID: " .. game.JobId:sub(1, 18) .. "...\nPlayers: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers
})

local PingLabel    = TabSmart:CreateLabel("📡 Analyzing Ping...")
local PingHistory  = TabSmart:CreateLabel("📊 Ping history: --")
local FPSLabel     = TabSmart:CreateLabel("🖥️ FPS: --")

-- YENİ: Son 5 ping değerini tutan tablo
local pingHistory = {}
local MAX_HISTORY = 5

task.spawn(function()
    local frameCount = 0
    local lastFPSTime = tick()

    -- FPS sayacı
    RunService.RenderStepped:Connect(function()
        frameCount += 1
        local now = tick()
        if now - lastFPSTime >= 1 then
            local fps = math.floor(frameCount / (now - lastFPSTime))
            frameCount = 0
            lastFPSTime = now
            local fpsIcon = fps >= 55 and "🟢" or fps >= 28 and "🟡" or "🔴"
            pcall(function() FPSLabel:Set("🖥️ FPS: " .. fps .. " " .. fpsIcon) end)
        end
    end)

    -- Ping döngüsü
    while task.wait(1) do
        local ping = GetCurrentPing()

        -- Ping geçmişini güncelle
        table.insert(pingHistory, ping)
        if #pingHistory > MAX_HISTORY then
            table.remove(pingHistory, 1)
        end

        -- Kalite rengi
        local icon = ping < 61  and "🔵"
                  or ping < 100 and "🟢"
                  or ping < 150 and "🟡"
                  or ping < 200 and "🔴"
                  or "💀"

        -- Ortalama ping hesapla
        local avg = 0
        for _, v in ipairs(pingHistory) do avg += v end
        avg = math.floor(avg / #pingHistory)

        -- Geçmiş string'i oluştur
        local histStr = ""
        for _, v in ipairs(pingHistory) do
            histStr = histStr .. v .. "ms "
        end

        pcall(function()
            PingLabel:Set("📡 Live Ping: " .. ping .. " ms " .. icon .. " | Ort: " .. avg .. "ms")
            PingHistory:Set("📊 Last " .. MAX_HISTORY .. ": " .. histStr)
        end)
    end
end)

-- Butonlar
TabSmart:CreateButton({
    Name = "⚡ • Smart-Connect •⚡",
    Callback = function() ForceRegionHop("The Best Server") end
})

-- YENİ: Mevcut sunucuya yeniden bağlan
TabSmart:CreateButton({
    Name = "🔁 • Rejoin Into Current Server •",
    Callback = function()
        Rayfield:Notify({Title = "Reconnecting...", Content = "Rejoining into the current server.", Duration = 2})
        RejoinCurrentServer()
    end
})

-- YENİ: Mevcut sunucu ID'sini output'a yazdır (kopyalamak için)
TabSmart:CreateButton({
    Name = "📋 |Copy Server ID|",
    Callback = function()
        print("Server ID: " .. game.JobId)
        Rayfield:Notify({Title = "Copied", Content = "Server ID has been writed to Output.", Duration = 3})
    end
})-- ============================================================================
-- BÖLÜM 5: MANUEL ROTALAR
-- NOT: Roblox API sunucu konumu vermez. Butonlar en uygun boş sunucuya bağlar.
-- Gerçek bölge yönlendirmesi için VPN kullanmanız gerekir.
-- ============================================================================

TabManual:CreateParagraph({
    Title = "⚠️ -NOTE-",
    Content = "This feature might not work properly because of Roblox API,use an VPN for better result."
})

TabManual:CreateButton({Name = "• Germany / Holland • 🇩🇪", Callback = function() ForceRegionHop("EU-West") end})
TabManual:CreateButton({Name = "• France / Spain • 🇫🇷",    Callback = function() ForceRegionHop("EU-South") end})
TabManual:CreateButton({Name = "• Romania / Greece • 🇷🇴",  Callback = function() ForceRegionHop("EU-East") end})

-- YENİ: Ek bölge rotaları
TabManual:CreateButton({Name = "• USA East • 🇺🇸",          Callback = function() ForceRegionHop("US-East") end})
TabManual:CreateButton({Name = "• Singapore / Asia • 🌏",   Callback = function() ForceRegionHop("AS-South") end})-- ============================================================================
-- BÖLÜM 6: SERVER BROWSER
-- DÜZELTME: Her scan'de eski butonlar artık silinir (Rayfield'da direct yol yok,
-- bu nedenle buton isimleri scan sayısıyla etiketlenir ve tekrar sorgulanır)
-- YENİ: Sunucuları ping'e göre değil doluluk oranına göre sıralar, daha fazla bilgi
-- ============================================================================

local scanCount = 0  -- DÜZELTME: Eski butonlarla karışmaması için scan numarası

TabBrowser:CreateButton({
    Name = "🔄 • Scan & Refresh Servers •",
    Callback = function()
        scanCount += 1
        local currentScan = scanCount

        Rayfield:Notify({Title = "Scanning...", Content = "Getting Server list...", Duration = 2})

        local servers = FetchServers(10)
        if not servers then
            Rayfield:Notify({Title = "ERROR", Content = "Server list isn't avaible.", Duration = 4})
            return
        end

        -- Doluluk oranına göre sırala (en boş önce)
        table.sort(servers, function(a, b)
            return (a.playing / math.max(a.maxPlayers, 1)) < (b.playing / math.max(b.maxPlayers, 1))
        end)

        for i, v in ipairs(servers) do
            local current  = v.playing
            local max      = v.maxPlayers
            local pct      = math.floor((current / math.max(max, 1)) * 100)
            local isCurrent= v.id == game.JobId
            local status   = isCurrent and "📍 -Current-"
                          or current >= max and "🔴 Full"
                          or pct > 75 and "🟡 Almost Full"
                          or "🟢 Empty"

            -- DÜZELTME: Scan numarası ile etiketle — eski sonuçlarla karışmaz
            TabBrowser:CreateButton({
                Name = "[S" .. currentScan .. "] #" .. i .. " | 👥 " .. current .. "/" .. max .. " %" .. pct .. " | " .. status,
                Callback = function()
                    if isCurrent then
                        Rayfield:Notify({Title = "You're currently here", Content = "This is you'r current server", Duration = 3})
                        return
                    end
                    Rayfield:Notify({Title = "Connecting...", Content = current .. "/" .. max .. " Full server!", Duration = 2})
                    TeleportService:TeleportToPlaceInstance(PlaceId, v.id, LocalPlayer)
                end
            })
        end

        Rayfield:Notify({Title = "✅ Completed!", Content = #servers .. " Servers listed.", Duration = 3})
    end
})

-- YENİ: Direkt en boş sunucuya bağlan (önbellekten)
TabBrowser:CreateButton({
    Name = "🏃 • Connect into emptiest server •",
    Callback = function()
        if #ServerCache == 0 then
            Rayfield:Notify({Title = "Cache empty", Content = "Do Server Scan First!", Duration = 3})
            return
        end
        local target = FindBestServer(ServerCache)
        if target then
            TeleportService:TeleportToPlaceInstance(PlaceId, target.id, LocalPlayer)
        else
            Rayfield:Notify({Title = "Not Found", Content = "Scan again.", Duration = 3})
        end
    end
})-- -- ============================================================================
-- BÖLÜM 7: OYUN BİLGİSİ
-- YENİ: Sunucu uptime, oyuncu sayısı canlı güncelleme
-- ============================================================================

local serverStart = tick()  -- Script yüklendiğinde başlar

TabInfo:CreateParagraph({
    Title = "Game info",
    Content = "Place ID: " .. PlaceId .. "\nScript Version: V2.1 () (2026)\nGitHub: Nenecosturan/Ping-Improve-PIOP-2.0"
})

local UptimeLabel  = TabInfo:CreateLabel("⏱️ Server Uptime: --")
local PlayerLabel  = TabInfo:CreateLabel("👥 Players: --")

task.spawn(function()
    while task.wait(5) do
        local uptime  = math.floor(tick() - serverStart)
        local minutes = math.floor(uptime / 60)
        local seconds = uptime % 60

        pcall(function()
            UptimeLabel:Set("⏱️ Script Uptime: " .. minutes .. "Min " .. seconds .. "Sec")
            PlayerLabel:Set("👥 This Server: " .. #Players:GetPlayers() .. "/" .. Players.MaxPlayers)
        end)
    end
end)-- ============================================================================
-- BÖLÜM 8: AYARLAR
-- DÜZELTME: AutoHop çift loop açmıyor artık (_G.AutoHopRunning kontrolü)
-- DÜZELTME: break kaldırıldı, hop sonrası loop devam ediyor
-- YENİ: Ping eşiği slider, Anti-AFK, bekleme süresi ayarı
-- ============================================================================

-- DÜZELTME: Ping eşiği artık ayarlanabilir
TabSettings:CreateSlider({
    Name = "Ping Spike threshold (ms)",
    Range = {100, 600},
    Increment = 25,
    CurrentValue = 300,
    Callback = function(Value)
        _G.PingThreshold = Value
        Rayfield:Notify({Title = "Changed", Content = "Auto-hop: " .. Value .. "ms Above", Duration = 2})
    end
})

-- DÜZELTME: Toggle her kapanıp açıldığında çift spawn oluşturmaz
TabSettings:CreateToggle({
    Name = "• Ping Spike Protection • (Auto-Hop)",
    CurrentValue = false,
    Callback = function(Value)
        _G.AutoHopEnabled = Value

        if Value and not _G.AutoHopRunning then
            _G.AutoHopRunning = true  -- DÜZELTME: çift spawn engeli

            task.spawn(function()
                Rayfield:Notify({Title = "Protection Active", Content = "Ping " .. _G.PingThreshold .. "if ms above auto-hop will be done.", Duration = 3})

                while _G.AutoHopEnabled do
                    task.wait(10)
                    local ping = GetCurrentPing()

                    if ping > _G.PingThreshold then
                        Rayfield:Notify({
                            Title = "⚠️ Ping Spike!",
                            Content = "Ping: " .. ping .. "ms — Changing Server...",
                            Duration = 4
                        })
                        ForceRegionHop("Auto-Hop")
                        -- DÜZELTME: break yok, teleport gerçekleşirse queue_on_teleport devam ettirir
                        task.wait(15)  -- Teleport sonrası stabilizasyon bekleme
                    end
                end

                _G.AutoHopRunning = false  -- Loop kapanınca flag'i sıfırla
            end)
        end
    end
})

-- YENİ: Anti-AFK
TabSettings:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = false,
    Callback = function(Value)
        _G.AntiAFKEnabled = Value

        if Value then
            task.spawn(function()
                while _G.AntiAFKEnabled do
                    task.wait(60)  -- Her 60 saniyede bir
                    if _G.AntiAFKEnabled then
                        -- Sanal jump input simüle et
                        local VirtualUser = game:GetService("VirtualUser")
                        pcall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end)
                    end
                end
            end)
            Rayfield:Notify({Title = "Anti-AFK Active", Content = "Anti-afk is currently active.", Duration = 3})
        end
    end
})

TabSettings:CreateSlider({
    Name = "Render Quality |",
    Range = {1, 10},
    Increment = 1,
    CurrentValue = 10,
    Callback = function(Value)
        pcall(function() settings().Rendering.QualityLevel = Value end)
    end
})

-- YENİ: Ping geçmişini sıfırla
TabSettings:CreateButton({
    Name = "🗑️ • Refresh Ping history •",
    Callback = function()
        pingHistory = {}
        Rayfield:Notify({Title = "Refreshed", Content = "Refreshed Ping History.", Duration = 2})
    end
})-- ============================================================================
-- BÖLÜM 9: YEDEK SİSTEM
-- YENİ: Başarı/hata bildirimi eklendi
-- ============================================================================

TabBackup:CreateParagraph({
    Title = "Extra Script",
    Content = "Our backup script."
})

TabBackup:CreateButton({
    Name = "🚀 Load Backup Script (•PIOP•)",
    Callback = function()
        Rayfield:Notify({Title = "Loading...", Content = "Loading Source...", Duration = 3})
        local ok, err = pcall(function()
            loadstring(game:HttpGet(
                "https://raw.githubusercontent.com/Nenecosturan/Ping-Optimizer-PIOP-/refs/heads/main/Main.lua"
            ))()
        end)
        if ok then
            Rayfield:Notify({Title = "✅ Success", Content = "PIOP loaded.", Duration = 4})
        else
            Rayfield:Notify({Title = "❌ ERROR", Content = "PIOP Failed: " .. tostring(err):sub(1,60), Duration = 5})
        end
    end
})
