-- Ride A Pet — Auto Farm
local Env = getgenv and getgenv() or _G
if game.PlaceId ~= 124216119978534 then error("Ride A Pet: unsupported game.") end
if Env.RideAPetCompact and Env.RideAPetCompact.Unload then Env.RideAPetCompact:Unload() end

-- ═══ STATE ═══
local A = {
    Alive=true, Epoch=0, Connections={}, Threads={}, Markers={}, Cooldowns={},
    FailedEggs={}, Errors={}, Collected=0, Hatched=0, Status="Ready", Cache={},
    Options={
        AntiAFK=true, EggESP=false, AutoCollect=false, AutoPlace=false, AutoHatch=false,
        TweenSpeed=180, ESPDistance=5000, ESPCount=40, ESPSize=15,
        ESPName=true, ESPWeight=true, MaxDistance=6000,
        EggPriority="Nearest", SelectedEgg=nil, MenuKey=Enum.KeyCode.RightControl,
    },
    Filter={
        Rarities={}, Types={}, Mutations={},
        MinLuck=0, MinWeight=0, MaxDistance=15000, Search="", MutatedOnly=false,
    },
    RarityNames={"Common","Rare","Epic","Legendary","Mythic","Divine","Ethereal"},
    RarityOrder={Common=1,Rare=2,Epic=3,Legendary=4,Mythic=5,Divine=6,Ethereal=7},
    RarityColors={
        Common=Color3.fromRGB(230,235,237), Rare=Color3.fromRGB(100,195,255),
        Epic=Color3.fromRGB(197,145,255), Legendary=Color3.fromRGB(255,213,104),
        Mythic=Color3.fromRGB(255,125,160), Divine=Color3.fromRGB(255,245,182),
        Ethereal=Color3.fromRGB(120,255,215),
    },
}
Env.RideAPetCompact = A

-- ═══ SERVICES & DATA ═══
A.Player = game:GetService("Players").LocalPlayer
A.RS = game:GetService("ReplicatedStorage")
A.Run = game:GetService("RunService")
A.Tween = game:GetService("TweenService")
A.UIS = game:GetService("UserInputService")
A.VU = game:GetService("VirtualUser")
A.GuiSvc = game:GetService("GuiService")
A.Remotes = A.RS:WaitForChild("Remotes",15):WaitForChild("Game",15)
A.Saved = A.Player:WaitForChild("SavedData",15)
A.ActiveEggs = A.RS:WaitForChild("ServerData",15):WaitForChild("ActiveEggs",15)

A.Data, A.Services = {}, {}
for _, n in ipairs({"Eggs","Pets","General","Mutations","EggBaskets"}) do
    A.Data[n] = require(A.RS.GameData:WaitForChild(n,10))
end
for _, n in ipairs({"PetAging","DayNight"}) do
    A.Services[n] = require(A.RS.GameServices:WaitForChild(n,10))
end

A.EggNames, A.MutationNames = {}, {"None"}
for n, d in pairs(A.Data.Eggs) do
    if type(d)=="table" and not d.Premium then table.insert(A.EggNames, n) end
end
table.sort(A.EggNames, function(a,b) return (A.Data.Eggs[a].Luck or 0) < (A.Data.Eggs[b].Luck or 0) end)
for n, d in pairs(A.Data.Mutations) do
    if type(d)=="table" then table.insert(A.MutationNames, n) end
end
table.sort(A.MutationNames)
for _, n in ipairs(A.RarityNames)   do A.Filter.Rarities[n]  = true end
for _, n in ipairs(A.EggNames)      do A.Filter.Types[n]     = true end
for _, n in ipairs(A.MutationNames) do A.Filter.Mutations[n] = true end

-- ═══ HELPERS ═══
function A:Connect(sig, cb)
    local c = sig:Connect(function(...) if self.Alive then cb(...) end end)
    table.insert(self.Connections, c); return c
end

function A:Value(name, default)
    local v = self.Saved:FindFirstChild(name)
    return v and v.Value or default
end

function A:Character()
    local c = self.Player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if h and r and h.Health > 0 then return c, h, r end
end

function A:Plot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end
    for _, p in ipairs(plots:GetChildren()) do
        local o = p:FindFirstChild("Data") and p.Data:FindFirstChild("Owner")
        if o and o.Value == self.Player then return p end
    end
end

function A:OnPlot()
    local _, _, r = self:Character()
    local p = self:Plot()
    local b = p and p:FindFirstChild("Baseplate")
    if not r or not b then return false end
    local pt = b.CFrame:PointToObjectSpace(r.Position)
    return math.abs(pt.X) < b.Size.X/2 and math.abs(pt.Z) < b.Size.Z/2 and math.abs(pt.Y) < 35
end

function A:Tools()
    local r = {}
    for _, root in ipairs({self.Player:FindFirstChild("Backpack"), self.Player.Character}) do
        if root then
            for _, t in ipairs(root:GetChildren()) do
                if t:IsA("Tool") then table.insert(r, t) end
            end
        end
    end
    return r
end

function A:Equip(t)
    local _, h = self:Character()
    if h and t and t.Parent then h:EquipTool(t); return true end
end

function A:Fire(name, ...)
    local r = self.Alive and self.Remotes:FindFirstChild(name)
    if r and r:IsA("RemoteEvent") then r:FireServer(...); return true end
end

function A:Ready(k, i)
    local n = os.clock()
    if n < (self.Cooldowns[k] or 0) then return false end
    self.Cooldowns[k] = n + i; return true
end

function A:Valid(t) return self.Alive and self.Epoch == t end

function A:WaitFor(fn, s, t)
    local d = os.clock() + s
    repeat
        if (t and not self:Valid(t)) or not self.Alive then return false end
        local v = fn(); if v then return v end
        task.wait(0.1)
    until os.clock() >= d
end

function A:Time(s)
    s = math.max(0, math.ceil(tonumber(s) or 0))
    if s >= 3600 then return string.format("%dh %02dm", s//3600, (s%3600)//60) end
    return string.format("%dm %02ds", s//60, s%60)
end

function A:Format(v)
    v = tonumber(v); if not v then return "?" end
    if v == math.huge then return "∞" end
    for _, u in ipairs({{1e12,"T"},{1e9,"B"},{1e6,"M"},{1e3,"K"}}) do
        if math.abs(v) >= u[1] then return string.format("%.1f%s", v/u[1], u[2]) end
    end
    return tostring(math.floor(v*100)/100)
end

function A:Err(ctx, msg)
    local v = ctx..": "..tostring(msg); self.Status = v
    if self.Errors[#self.Errors] ~= v then
        table.insert(self.Errors, v)
        if #self.Errors > 6 then table.remove(self.Errors, 1) end
        warn("[Ride A Pet] "..v)
    end
end

-- ═══ EGG HELPERS ═══
function A:Basket()
    local b = self.Player:FindFirstChild("Basket")
    return b and b:GetChildren() or {}
end

function A:EggTools()
    local r = {}
    for _, t in ipairs(self:Tools()) do
        if self.Data.Eggs[t.Name] and not t:GetAttribute("PetKey") then table.insert(r, t) end
    end
    table.sort(r, function(a,b) return (self.Data.Eggs[a.Name].Luck or 0) > (self.Data.Eggs[b.Name].Luck or 0) end)
    return r
end

function A:Capacity()
    local c = self.Data.EggBaskets[self:Value("EquippedEggBasket","Wooden")]
    return c and c.Capacity or 1
end

function A:FreeNests()
    local r = {}
    local p = self:Plot()
    local n = p and p:FindFirstChild("Nests")
    if n then
        for _, x in ipairs(n:GetChildren()) do
            if x:GetAttribute("Unlocked") and not x:GetAttribute("Occupied") then table.insert(r, x) end
        end
    end
    table.sort(r, function(a,b) return (tonumber(a.Name) or 0) < (tonumber(b.Name) or 0) end)
    return r
end

function A:EggTimers()
    local r = {}
    local p = self:Plot()
    local eggs = p and p:FindFirstChild("Eggs")
    if not eggs then return r end
    for _, e in ipairs(eggs:GetChildren()) do
        local info = e:FindFirstChild("EggData", true)
        local data = self.Data.Eggs[e.Name]
        local start = info and info:FindFirstChild("PlaceTime")
        local wt = info and info:FindFirstChild("Weight")
        if data and start then
            local total = self.Data.General.GrowthTimeFor(data.GrowthTime or 0, wt and wt.Value or 1)
            local rem = self.Services.DayNight.GrowthRealRemaining(start.Value, total)
            table.insert(r, {Object=e, Key=e:GetAttribute("EggKey"), Name=e.Name, Remaining=rem})
        end
    end
    table.sort(r, function(a,b) return a.Remaining < b.Remaining end)
    return r
end

function A:Matches(egg)
    local f = self.Filter
    local mut, mutOK = false, false
    for _, n in ipairs({egg.Mutation or "", egg.SpawnMutation or ""}) do
        if n ~= "" then mut = true; mutOK = mutOK or f.Mutations[n] == true end
    end
    if not mut then mutOK = f.Mutations.None == true end
    return f.Rarities[egg.Rarity] and f.Types[egg.Name] and mutOK
       and (not f.MutatedOnly or egg.MutationLabel ~= "None")
       and (egg.Luck or 0) >= f.MinLuck and egg.KG >= f.MinWeight
       and egg.Distance <= f.MaxDistance
       and string.find(string.lower(egg.Name), string.lower(f.Search), 1, true) ~= nil
end

function A:EggList(filtered)
    local out = {}
    local _, _, root = self:Character()
    local seen = ","..tostring(self.Player:GetAttribute("CollectedEggs") or "")..","
    for _, o in ipairs(self.ActiveEggs:GetChildren()) do
        local name = o:GetAttribute("Egg")
        local data = name and self.Data.Eggs[name]
        local pos = o:GetAttribute("Position")
        local priv = o:GetAttribute("PrivateTo")
        if data and typeof(pos) == "Vector3"
           and (not priv or priv == self.Player.UserId)
           and not string.find(seen, ","..o.Name..",", 1, true) then
            local w = o:GetAttribute("Weight") or 1
            local mu, sp = o:GetAttribute("Mutation"), o:GetAttribute("SpawnMutation")
            local row = {
                ID=o.Name, Object=o, Name=name, Position=pos,
                Distance=root and (root.Position-pos).Magnitude or math.huge,
                Rarity=data.Rarity or "Common", Mutation=mu, SpawnMutation=sp,
                KG=self.Data.General.ShownEggKG(w), Luck=data.Luck,
            }
            row.MutationLabel = (mu and mu ~= "" and mu) or "None"
            if sp and sp ~= "" and sp ~= mu then
                row.MutationLabel = row.MutationLabel == "None" and sp or row.MutationLabel.." + "..sp
            end
            if not filtered or self:Matches(row) then table.insert(out, row) end
        end
    end
    table.sort(out, function(a, b)
        local m = self.Options.EggPriority
        if m == "Highest luck" and a.Luck ~= b.Luck then return (a.Luck or 0) > (b.Luck or 0) end
        if m == "Rarest" and a.Rarity ~= b.Rarity then return (self.RarityOrder[a.Rarity] or 0) > (self.RarityOrder[b.Rarity] or 0) end
        if m == "Heaviest" and a.KG ~= b.KG then return a.KG > b.KG end
        if a.Distance == b.Distance then return a.ID < b.ID end
        return a.Distance < b.Distance
    end)
    return out
end

-- ═══ ANTI-AFK ═══
function A:SetAntiAFK(on)
    if self.AFKConn then self.AFKConn:Disconnect(); self.AFKConn = nil end
    if self.AFKRelease then
        pcall(function() self.VU:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame) end)
        self.AFKRelease = false
    end
    if on and self.Alive then
        self.AFKConn = self.Player.Idled:Connect(function()
            if not self.Alive or not self.Options.AntiAFK then return end
            pcall(function()
                self.VU:CaptureController()
                self.VU:Button2Down(Vector2.zero, workspace.CurrentCamera.CFrame)
                self.AFKRelease = true
            end)
            task.delay(0.2, function()
                if self.AFKRelease then
                    pcall(function() self.VU:Button2Up(Vector2.zero, workspace.CurrentCamera.CFrame) end)
                    self.AFKRelease = false
                end
            end)
        end)
    end
end

-- ═══ MOVEMENT ═══
function A:StopMovement()
    if self.FlyConn then self.FlyConn:Disconnect(); self.FlyConn = nil end
    if self.FlyTween then self.FlyTween:Cancel(); self.FlyTween:Destroy(); self.FlyTween = nil end
    local f = self.Fly; self.Fly = nil
    if f then
        for p, v in pairs(f.Collisions) do if p.Parent then p.CanCollide = v end end
        if f.Hum.Parent then f.Hum.PlatformStand = f.PS; f.Hum.AutoRotate = f.AR end
        if f.Root.Parent then f.Root.AssemblyLinearVelocity = Vector3.zero; f.Root.AssemblyAngularVelocity = Vector3.zero end
    end
end

function A:Dismount(t)
    if self.Player:GetAttribute("IsRiding") then
        self:Fire("PetDismount")
        return self:WaitFor(function() return not self.Player:GetAttribute("IsRiding") end, 3, t)
    end
    return true
end

function A:MoveTo(pos, t, radius)
    if not self:Valid(t) or not self:Dismount(t) then return false end
    local c, h, r = self:Character()
    if not r then return false end
    self:StopMovement(); h:UnequipTools()
    local target = pos + Vector3.new(0, math.max(3, h.HipHeight + r.Size.Y/2), 0)
    local col = {}
    for _, p in ipairs(c:QueryDescendants("BasePart")) do col[p] = p.CanCollide end
    self.Fly = {Root=r, Hum=h, Collisions=col, PS=h.PlatformStand, AR=h.AutoRotate}
    h.PlatformStand = true; h.AutoRotate = false
    local dur = math.max(0.1, (r.Position-target).Magnitude / math.clamp(self.Options.TweenSpeed, 40, 350))
    local tw = self.Tween:Create(r, TweenInfo.new(dur, Enum.EasingStyle.Linear), {CFrame=CFrame.new(target)*r.CFrame.Rotation})
    self.FlyTween = tw
    self.FlyConn = self.Run.Stepped:Connect(function()
        if r.Parent and h.Health > 0 then
            for p in pairs(col) do if p.Parent then p.CanCollide = false end end
            r.AssemblyLinearVelocity = Vector3.zero; r.AssemblyAngularVelocity = Vector3.zero
        end
    end)
    tw:Play()
    local dl = os.clock() + dur + 3
    while self:Valid(t) and r.Parent and h.Health > 0 and os.clock() < dl
          and tw.PlaybackState == Enum.PlaybackState.Playing do
        self.Status = "Flying · "..self:Format((r.Position-target).Magnitude).." studs"
        task.wait(0.05)
    end
    local ok = tw.PlaybackState == Enum.PlaybackState.Completed
    self:StopMovement()
    if not ok or not self:Valid(t) then return false end
    task.wait(0.25)
    local _, _, cur = self:Character()
    return cur == r and (r.Position-target).Magnitude <= math.max(radius or 9, 12)
end

-- ═══ JOBS ═══
function A:CancelJob()
    self.Epoch = self.Epoch + 1
    local th = self.JobThread
    self.JobThread = nil; self.Job = nil
    self:StopMovement()
    if th and th ~= coroutine.running() then pcall(task.cancel, th) end
end

function A:StartJob(name, cb)
    if not self.Alive or self.Job then self.Status = "Finish current action first"; return false end
    local t = self.Epoch
    self.Job = name; self.Status = name
    self.JobThread = task.defer(function()
        local ok, err = xpcall(function() cb(t) end, debug.traceback)
        if not ok and self:Valid(t) then self:Err(name, err) end
        if self:Valid(t) then self:StopMovement(); self.Job = nil; self.JobThread = nil end
    end)
    return true
end

-- ═══ FARM ACTIONS ═══
function A:ReturnWithEggs(t)
    if self.Paused then self.Status = "Delivery paused"; return false end
    local p = self:Plot(); if not p then self.Status = "Waiting for ranch"; return false end
    local before, expected = {}, {}
    for _, tool in ipairs(self:EggTools()) do before[tool] = true end
    for _, e in ipairs(self:Basket()) do
        local n = e:GetAttribute("Egg")
        if n then expected[n] = (expected[n] or 0) + 1 end
    end
    if not next(expected) then return false end
    local function done()
        if #self:Basket() > 0 then return false end
        local got = {}
        for _, tool in ipairs(self:EggTools()) do
            if not before[tool] then got[tool.Name] = (got[tool.Name] or 0) + 1 end
        end
        for n, c in pairs(expected) do if (got[n] or 0) < c then return false end end
        return true
    end
    self:MoveTo(p.Baseplate.Position + Vector3.new(0,3,0), t, 12)
    if not self:Valid(t) then return false end
    if self:WaitFor(done, 4, t) then self.Status = "Eggs delivered"; return true end
    self:SetOption("AutoCollect", false); self:SetOption("AutoPlace", false)
    self.Status = "Delivery not confirmed; automation stopped"
    return false
end

function A:Home(t)
    if not self:Valid(t) then return false end
    if #self:Basket() > 0 then return self:ReturnWithEggs(t) end
    if self:OnPlot() then return true end
    local p = self:Plot()
    return p and self:MoveTo(p.Baseplate.Position + Vector3.new(0,3,0), t, 12) or false
end

function A:PlaceEggs(t)
    if #self:Basket() == 0 and #self:EggTools() == 0 then return false end
    self.Status = "Returning with eggs"
    if not self:Home(t) then return false end
    local nests = self:FreeNests()
    if #nests == 0 then self.Status = "Waiting for free nest"; return false end
    self:WaitFor(function() return #self:EggTools() > 0 end, 2, t)
    for _, nest in ipairs(nests) do
        if not self:Valid(t) then break end
        local tool = self:EggTools()[1]; if not tool then break end
        self:Equip(tool); task.wait(0.15)
        if not self:Valid(t) then return false end
        self.Status = "Placing egg in nest "..nest.Name
        self:Fire("EggPlaced", {NestId = nest.Name})
        if not self:WaitFor(function() return nest:GetAttribute("Occupied") end, 3, t) then return false end
    end
    self.Status = "Eggs placed"; return true
end

function A:HatchReady(t)
    for _, egg in ipairs(self:EggTimers()) do
        if not self:Valid(t) then return end
        if egg.Remaining <= 0 and egg.Key and self:Ready("Hatch:"..egg.Key, 5) then
            local _, _, r = self:Character(); if not r then return end
            if (r.Position - egg.Object:GetPivot().Position).Magnitude > 12 then
                if not self:MoveTo(egg.Object:GetPivot().Position, t, 6) then return end
            end
            if not self:Valid(t) then return end
            self:Fire("Hatch", {EggKey = egg.Key})
            if self:WaitFor(function() return not egg.Object.Parent end, 8, t) then
                self.Hatched = self.Hatched + 1
                self.Status = "Hatched "..egg.Name
            end
        end
    end
end

function A:CollectEgg(egg, t)
    if not egg or not self:Valid(t) then return false end
    self.Paused = false
    if #self:Basket() >= self:Capacity() then
        if not self:ReturnWithEggs(t) then return false end
    end
    if egg.Object.Parent ~= self.ActiveEggs then return false end
    if not self:MoveTo(egg.Position, t, 9) then self.FailedEggs[egg.ID] = os.clock()+30; return false end
    if not self:Valid(t) or egg.Object.Parent ~= self.ActiveEggs then return false end
    local before = #self:Basket()
    self:Fire("EggPickup", egg.ID)
    if not self:WaitFor(function() return #self:Basket() > before end, 3, t) then
        self.FailedEggs[egg.ID] = os.clock()+30
        self.Status = "Pickup not confirmed; skipping egg 30s"
        return false
    end
    self.Collected = self.Collected + 1
    return self:ReturnWithEggs(t)
end

function A:CollectSelected(t)
    for _, egg in ipairs(self:EggList(false)) do
        if egg.ID == self.Options.SelectedEgg then self:CollectEgg(egg, t); return end
    end
    self.Status = "Selected egg unavailable"
end

function A:StopCollecting()
    local running = self.Job and (self.Job:sub(1,11) == "Collecting " or self.Job == "Delivering eggs")
    self.Options.AutoCollect = false
    if running or self.Options.AutoCollect then self.Paused = true end
    if running then self:CancelJob() end
    if self.ControlRefresh then self:ControlRefresh() end
    self.Status = "Collection stopped"
end

function A:SetOption(k, v)
    self.Options[k] = v
    if v == true and (k == "AutoCollect" or k == "AutoPlace") then self.Paused = false end
    if self.ControlRefresh then self:ControlRefresh() end
    if k == "AntiAFK" then self:SetAntiAFK(v) end
    if k == "EggESP" and not v then self:ClearESP() end
    if v == false and (k == "AutoCollect" or k == "AutoPlace" or k == "AutoHatch") then self:CancelJob() end
end

-- ═══ TICK ═══
function A:Tick()
    if self.Job or not self:Character() then return end
    local o = self.Options
    if o.AutoHatch and self:Ready("HatchScan", 2) then
        local e = self:EggTimers()
        if e[1] and e[1].Remaining <= 0 then
            self:StartJob("Hatching eggs", function(t) self:HatchReady(t) end); return
        end
    end
    if not self.Paused and (o.AutoCollect or o.AutoPlace) and #self:Basket() > 0 and self:Ready("Deliver", 2) then
        self:StartJob("Delivering eggs", function(t) self:ReturnWithEggs(t) end); return
    end
    if o.AutoPlace and (not self.Paused or #self:Basket() == 0)
       and #self:EggTools() > 0 and #self:FreeNests() > 0 and self:Ready("Place", 3) then
        self:StartJob("Placing eggs", function(t) self:PlaceEggs(t) end); return
    end
    if o.AutoCollect and self:Ready("Collect", 1) then
        for _, e in ipairs(self:EggList(true)) do
            if os.clock() >= (self.FailedEggs[e.ID] or 0) then
                self:StartJob("Collecting "..e.Name, function(t) self:CollectEgg(e, t) end); return
            end
        end
        self.Status = "Waiting for eggs matching filters"
    end
end

-- ═══ ESP ═══
function A:ClearESP()
    for id, m in pairs(self.Markers) do
        for _, d in pairs(m) do pcall(function() d.Visible = false; d:Remove() end) end
        self.Markers[id] = nil
    end
end

function A:UpdateESP()
    if not self.Options.EggESP then return end
    if not Drawing or type(Drawing.new) ~= "function" then
        self:SetOption("EggESP", false)
        self.Status = "Drawing API unavailable"
        return
    end
    local keep = {}
    for i, egg in ipairs(self:EggList(true)) do
        if i > self.Options.ESPCount then break end
        keep[egg.ID] = true
        local m = self.Markers[egg.ID]
        if not m then
            m = {Drawing.new("Text")}
            m[1].Center = true; m[1].Outline = true; m[1].OutlineColor = Color3.new(0,0,0)
            m[1].Font = 2; m[1].Visible = false; m[1].Transparency = 1
            self.Markers[egg.ID] = m
        end
        m.Egg = egg
        m[1].Color = self.RarityColors[egg.Rarity] or Color3.new(1,1,1)
        m[1].Size = self.Options.ESPSize
    end
    for id, m in pairs(self.Markers) do
        if not keep[id] then pcall(function() m[1]:Remove() end); self.Markers[id] = nil end
    end
end

function A:RenderESP()
    local cam = workspace.CurrentCamera
    local _, _, r = self:Character()
    local o = self.Options
    for _, m in pairs(self.Markers) do
        local egg, d = m.Egg, m[1]
        local vis = false
        if o.EggESP and cam and r and egg.Object.Parent == self.ActiveEggs then
            local dist = (r.Position - egg.Position).Magnitude
            local pt, on = cam:WorldToViewportPoint(egg.Position + Vector3.new(0,4,0))
            vis = on and pt.Z > 0 and dist <= o.ESPDistance
            if vis and self.Panel and self.Panel.Visible then
                local inset = self.GuiSvc:GetGuiInset()
                local pp, ps = self.Panel.AbsolutePosition + inset, self.Panel.AbsoluteSize
                if pt.X >= pp.X-95 and pt.X <= pp.X+ps.X+95 and pt.Y >= pp.Y-110 and pt.Y <= pp.Y+ps.Y then
                    vis = false
                end
            end
            if vis then
                local lines = {}
                if o.ESPName then table.insert(lines, egg.Name) end
                if o.ESPWeight then table.insert(lines, self:Format(egg.KG).." kg") end
                d.Text = table.concat(lines, "\n")
                d.Position = Vector2.new(pt.X, pt.Y)
            end
        end
        d.Visible = vis
    end
end

function A:Refresh()
    self.Cache.Eggs = self:EggList(false)
    self.Cache.Timers = self:EggTimers()
    self.Cache.Tools = #self:EggTools()
    self.Cache.Basket = #self:Basket()
    self.Cache.Nests = #self:FreeNests()
end

-- ═══ UI THEME ═══
A.C = {
    Bg=Color3.fromRGB(20,23,30), Surf=Color3.fromRGB(27,31,40), Card=Color3.fromRGB(32,37,48),
    Hover=Color3.fromRGB(40,45,58), Stroke=Color3.fromRGB(48,53,66), Soft=Color3.fromRGB(38,42,53),
    Text=Color3.fromRGB(232,236,244), Dim=Color3.fromRGB(150,158,175), Mute=Color3.fromRGB(105,113,130),
    Acc=Color3.fromRGB(74,123,200), AccD=Color3.fromRGB(52,88,148), Good=Color3.fromRGB(120,200,160),
}
A.F, A.FB = Enum.Font.Gotham, Enum.Font.GothamBold
A.RowH = A.UIS.TouchEnabled and 40 or 34
A.TitleH = A.UIS.TouchEnabled and 46 or 38
A.TabH = A.UIS.TouchEnabled and 38 or 32
A.Controls, A.Pages, A.FilterButtons = {}, {}, {}
A.PageNames = {"Farm","Eggs","ESP","Settings"}
A.Page = "Farm"

function A:Make(cls, parent, props)
    local o = Instance.new(cls)
    for k, v in pairs(props) do o[k] = v end
    o.Parent = parent; return o
end

function A:Corner(p, r) return self:Make("UICorner", p, {CornerRadius = UDim.new(0, r or 8)}) end
function A:Stroke(p, c, t, tr) return self:Make("UIStroke", p, {Color=c or self.C.Stroke, Thickness=t or 1, Transparency=tr or 0}) end
function A:Pad(p, l, r, t, b) return self:Make("UIPadding", p, {PaddingLeft=UDim.new(0,l or 0), PaddingRight=UDim.new(0,r or 0), PaddingTop=UDim.new(0,t or 0), PaddingBottom=UDim.new(0,b or 0)}) end

function A:Text(parent, txt, h, opts)
    opts = opts or {}
    return self:Make("TextLabel", parent, {
        Size = UDim2.new(1,0,0,h or 20), BackgroundTransparency=1, Text=txt,
        TextSize=opts.size or 13, Font=opts.font or self.F, TextColor3=opts.color or self.C.Text,
        TextXAlignment=opts.x or Enum.TextXAlignment.Left, TextWrapped=opts.wrap ~= false,
    })
end

function A:Section(parent, txt)
    local row = self:Make("Frame", parent, {Size=UDim2.new(1,0,0,26), BackgroundTransparency=1})
    local bar = self:Make("Frame", row, {Size=UDim2.new(0,3,0,12), Position=UDim2.new(0,2,0.5,-6), BackgroundColor3=self.C.Acc, BorderSizePixel=0})
    self:Corner(bar, 2)
    return self:Make("TextLabel", row, {
        Size=UDim2.new(1,-14,1,0), Position=UDim2.new(0,12,0,0), BackgroundTransparency=1,
        Text=string.upper(txt), TextSize=11, Font=self.FB, TextColor3=self.C.Dim,
        TextXAlignment=Enum.TextXAlignment.Left,
    })
end

function A:Button(parent, txt, cb, col)
    local b = self:Make("TextButton", parent, {
        Text=txt, Size=UDim2.new(1,0,0,self.RowH),
        BackgroundColor3=col or self.C.Card, BorderSizePixel=0,
        TextColor3=self.C.Text, Font=self.F, TextSize=13, AutoButtonColor=false,
    })
    self:Corner(b, 8); self:Stroke(b, self.C.Soft, 1, 0.4)
    b.MouseEnter:Connect(function() if A.Alive then A.Tween:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = col or A.C.Hover}):Play() end end)
    b.MouseLeave:Connect(function() if A.Alive then A.Tween:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = col or A.C.Card}):Play() end end)
    self:Connect(b.Activated, cb); return b
end

function A:Toggle(parent, key, label)
    local btn = self:Button(parent, "", function()
        if not A.Alive then return end
        A:SetOption(key, not A.Options[key])
    end)
    btn.Text = ""
    local box = self:Make("Frame", btn, {Size=UDim2.new(0,18,0,18), Position=UDim2.new(0,10,0.5,-9), BackgroundColor3=self.C.Surf, BorderSizePixel=0})
    self:Corner(box, 5)
    local st = self:Stroke(box, self.C.Stroke, 1, 0.2)
    local chk = self:Make("TextLabel", box, {Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text="✓", TextSize=13, Font=self.FB, TextColor3=Color3.new(1,1,1), TextTransparency=1})
    local lbl = self:Make("TextLabel", btn, {
        Size=UDim2.new(1,-46,1,0), Position=UDim2.new(0,38,0,0), BackgroundTransparency=1,
        Text=label, TextSize=13, Font=self.F, TextColor3=self.C.Text,
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    local function paint()
        local on = A.Options[key]
        A.Tween:Create(box, TweenInfo.new(0.12), {BackgroundColor3 = on and A.C.Acc or A.C.Surf}):Play()
        A.Tween:Create(st, TweenInfo.new(0.12), {Color = on and A.C.Acc or A.C.Stroke}):Play()
        A.Tween:Create(chk, TweenInfo.new(0.12), {TextTransparency = on and 0 or 1}):Play()
    end
    paint()
    self.Controls[key] = {Paint = paint}
end

function A:Number(parent, key, label, step, mn, mx, src, int)
    src = src or self.Options
    local grp = self:Make("Frame", parent, {Size=UDim2.new(1,0,0,self.RowH+18), BackgroundTransparency=1})
    local lbl = self:Text(grp, label, 16, {size=11, color=self.C.Dim})
    lbl.Position = UDim2.new(0,2,0,0)
    local hold = self:Make("Frame", grp, {Position=UDim2.new(0,0,0,18), Size=UDim2.new(1,0,0,self.RowH), BackgroundColor3=self.C.Card, BorderSizePixel=0})
    self:Corner(hold, 8); self:Stroke(hold, self.C.Soft, 1, 0.4)
    local minus = self:Make("TextButton", hold, {Size=UDim2.new(0,self.RowH,1,0), BackgroundColor3=self.C.Surf, BorderSizePixel=0, Text="−", Font=self.FB, TextSize=16, TextColor3=self.C.Dim, AutoButtonColor=false})
    self:Corner(minus, 8)
    local plus = self:Make("TextButton", hold, {AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1,0,0,0), Size=UDim2.new(0,self.RowH,1,0), BackgroundColor3=self.C.Surf, BorderSizePixel=0, Text="+", Font=self.FB, TextSize=16, TextColor3=self.C.Dim, AutoButtonColor=false})
    self:Corner(plus, 8)
    local inp = self:Make("TextBox", hold, {
        Position=UDim2.new(0,self.RowH,0,0), Size=UDim2.new(1,-self.RowH*2,1,0),
        BackgroundTransparency=1, Text=tostring(src[key]), ClearTextOnFocus=false,
        TextColor3=self.C.Text, Font=self.F, TextSize=13,
    })
    local function set(v)
        v = tonumber(v)
        if not v then inp.Text = tostring(src[key]); return end
        v = math.clamp(v, mn, mx); if int then v = math.floor(v) end
        src[key] = v; inp.Text = tostring(v)
    end
    minus.Activated:Connect(function() set(src[key] - step) end)
    plus.Activated:Connect(function() set(src[key] + step) end)
    self:Connect(inp.FocusLost, function() set(inp.Text) end)
end

function A:Choice(parent, key, label, values)
    local grp = self:Make("Frame", parent, {Size=UDim2.new(1,0,0,self.RowH+18), BackgroundTransparency=1})
    local lbl = self:Text(grp, label, 16, {size=11, color=self.C.Dim}); lbl.Position = UDim2.new(0,2,0,0)
    local btn = self:Make("TextButton", grp, {
        Position=UDim2.new(0,0,0,18), Size=UDim2.new(1,0,0,self.RowH),
        BackgroundColor3=self.C.Card, BorderSizePixel=0,
        Text="  "..tostring(self.Options[key]), Font=self.F, TextSize=13,
        TextColor3=self.C.Text, TextXAlignment=Enum.TextXAlignment.Left, AutoButtonColor=false,
    })
    self:Corner(btn, 8); self:Stroke(btn, self.C.Soft, 1, 0.4)
    btn.Activated:Connect(function()
        self:OpenPopup(btn, values, self.Options[key], function(v)
            self:SetOption(key, v); btn.Text = "  "..tostring(v)
        end)
    end)
end

-- ═══ POPUP (simple single-select) ═══
function A:ClosePopup()
    if self.Popup then self.Popup:Destroy(); self.Popup = nil end
end

function A:OpenPopup(anchor, items, selected, onPick)
    self:ClosePopup()
    local layer = self:Make("Frame", self.Bounds, {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=50})
    self.Popup = layer
    local back = self:Make("TextButton", layer, {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, Text="", AutoButtonColor=false, ZIndex=1})
    back.Activated:Connect(function() self:ClosePopup() end)

    local area = self.Bounds.AbsoluteSize
    local w = math.min(math.max(anchor.AbsoluteSize.X, 260), area.X-16)
    local h = math.min(340, area.Y-32)
    local pos = anchor.AbsolutePosition - self.Bounds.AbsolutePosition
    local x = math.clamp(pos.X, 8, area.X-w-8)
    local y = pos.Y + anchor.AbsoluteSize.Y + 4
    if y + h > area.Y - 8 then y = math.max(8, pos.Y - h - 4) end

    local box = self:Make("Frame", layer, {Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h), BackgroundColor3=self.C.Surf, BorderSizePixel=0, ZIndex=2})
    self:Corner(box, 10); self:Stroke(box, self.C.Stroke, 1, 0.1)
    local header = self:Make("TextLabel", box, {
        Size=UDim2.new(1,0,0,self.RowH), Text="  Options", TextSize=13, Font=self.FB,
        TextColor3=self.C.Text, BackgroundColor3=self.C.Surf, BorderSizePixel=0,
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    self:Corner(header, 10)

    local list = self:Make("ScrollingFrame", box, {
        Position=UDim2.fromOffset(8, self.RowH+4),
        Size=UDim2.new(1,-16,1,-self.RowH-4-self.RowH-12),
        BackgroundTransparency=1, BorderSizePixel=0,
        CanvasSize=UDim2.fromOffset(0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollingDirection=Enum.ScrollingDirection.Y, ScrollBarThickness=3,
        ScrollBarImageColor3=self.C.Stroke,
    })
    self:Make("UIListLayout", list, {Padding=UDim.new(0,3), SortOrder=Enum.SortOrder.LayoutOrder})

    for i, item in ipairs(items) do
        local b = self:Make("TextButton", list, {
            Size=UDim2.new(1,-4,0,self.RowH-2),
            BackgroundColor3=item == selected and self.C.AccD or self.C.Card,
            BorderSizePixel=0, Text="  "..item, Font=self.F, TextSize=13,
            TextColor3=self.C.Text, TextXAlignment=Enum.TextXAlignment.Left,
            AutoButtonColor=false, LayoutOrder=i,
        })
        self:Corner(b, 6)
        b.Activated:Connect(function() onPick(item); self:ClosePopup() end)
    end

    local done = self:Make("TextButton", box, {
        Position=UDim2.new(0,8,1,-self.RowH-8), Size=UDim2.new(1,-16,0,self.RowH),
        BackgroundColor3=self.C.Acc, BorderSizePixel=0, Text="Close",
        Font=self.F, TextSize=13, TextColor3=Color3.new(1,1,1), AutoButtonColor=false,
    })
    self:Corner(done, 8)
    done.Activated:Connect(function() self:ClosePopup() end)
end

-- ═══ TABS ═══
function A:BuildTabs()
    local bar = self:Make("Frame", self.Container, {Size=UDim2.new(1,0,0,self.TabH), BackgroundTransparency=1})
    local scroll = self:Make("ScrollingFrame", bar, {
        Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, BorderSizePixel=0,
        CanvasSize=UDim2.fromOffset(0,0), AutomaticCanvasSize=Enum.AutomaticSize.X,
        ScrollingDirection=Enum.ScrollingDirection.X, ScrollBarThickness=0,
    })
    self:Make("UIListLayout", scroll, {
        Padding=UDim.new(0,4),
        FillDirection=Enum.FillDirection.Horizontal,
        SortOrder=Enum.SortOrder.LayoutOrder,
        VerticalAlignment=Enum.VerticalAlignment.Center,
    })
    self.Tabs = {}
    for i, name in ipairs(self.PageNames) do
        local b = self:Make("TextButton", scroll, {
            Size=UDim2.new(0,0,1,0), AutomaticSize=Enum.AutomaticSize.X,
            BackgroundColor3=self.C.Surf, BorderSizePixel=0,
            Text=name, Font=self.F, TextSize=12, TextColor3=self.C.Dim,
            AutoButtonColor=false, LayoutOrder=i,
        })
        self:Corner(b, 8); self:Pad(b, 12, 12, 0, 0)
        b.Activated:Connect(function() if A.Alive then A:SwitchPage(name) end end)
        self.Tabs[name] = b
    end
end

function A:PaintTabs()
    for name, b in pairs(self.Tabs) do
        local on = name == self.Page
        A.Tween:Create(b, TweenInfo.new(0.15), {
            BackgroundColor3 = on and A.C.Acc or A.C.Surf,
            TextColor3 = on and Color3.new(1,1,1) or A.C.Dim,
        }):Play()
    end
end

function A:CreatePage(name)
    if self.Pages[name] then return self.Pages[name] end
    local p = self:Make("ScrollingFrame", self.Container, {
        Name=name, Position=UDim2.fromOffset(0, self.TabH+6),
        Size=UDim2.new(1,0,1,-self.TabH-6-40),
        BackgroundTransparency=1, BorderSizePixel=0,
        CanvasSize=UDim2.fromOffset(0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollingDirection=Enum.ScrollingDirection.Y, ScrollBarThickness=3,
        ScrollBarImageColor3=self.C.Stroke, Visible=name==self.Page,
    })
    self:Make("UIListLayout", p, {Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder})
    self:Pad(p, 0, 6, 4, 8)
    self.Pages[name] = p; return p
end

function A:SwitchPage(name)
    self:CancelKeybind()
    self:ClosePopup()
    self.Page = name
    for k, p in pairs(self.Pages) do p.Visible = k == name end
    self:PaintTabs()
    self:RefreshUI()
end

-- ═══ FILTER PANEL ═══
function A:FilterPanel(parent)
    local f = self.Filter
    local function changed() self:RefreshUI() end
    for _, entry in ipairs({{"Rarities",self.RarityNames},{"Types",self.EggNames},{"Mutations",self.MutationNames}}) do
        local group, names = entry[1], entry[2]
        local btn = self:Button(parent, "", function()
            self:OpenMulti(btn, group, names, f[group], changed)
        end)
        table.insert(self.FilterButtons, {Button=btn, Group=group, Names=names})
    end
    local mut = self:Button(parent, "", function()
        f.MutatedOnly = not f.MutatedOnly; changed()
    end)
    table.insert(self.FilterButtons, {Button=mut, Mutated=true})
    self:Text(parent, "Search egg names", 16, {size=11, color=self.C.Dim})
    local s = self:Make("TextBox", parent, {
        Size=UDim2.new(1,0,0,self.RowH), BackgroundColor3=self.C.Card, BorderSizePixel=0,
        Text="", PlaceholderText="  All egg names", ClearTextOnFocus=false,
        TextSize=13, Font=self.F, TextColor3=self.C.Text, PlaceholderColor3=self.C.Mute,
    })
    self:Corner(s, 8); self:Stroke(s, self.C.Soft, 1, 0.4)
    self:Connect(s:GetPropertyChangedSignal("Text"), function() f.Search = s.Text; changed() end)
    self:Number(parent, "MinLuck", "Minimum luck", 10, 0, 1e15, f)
    self:Number(parent, "MinWeight", "Minimum weight (kg)", 1, 0, 1e9, f)
    self:Number(parent, "MaxDistance", "Maximum distance (studs)", 100, 0, 100000, f)
end

-- ═══ MULTI-SELECT POPUP ═══
function A:OpenMulti(anchor, title, items, selected, onChange)
    self:ClosePopup()
    local layer = self:Make("Frame", self.Bounds, {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=50})
    self.Popup = layer
    local back = self:Make("TextButton", layer, {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, Text="", AutoButtonColor=false, ZIndex=1})
    back.Activated:Connect(function() self:ClosePopup() end)

    local area = self.Bounds.AbsoluteSize
    local w = math.min(math.max(anchor.AbsoluteSize.X, 280), area.X-16)
    local h = math.min(360, area.Y-32)
    local pos = anchor.AbsolutePosition - self.Bounds.AbsolutePosition
    local x = math.clamp(pos.X, 8, area.X-w-8)
    local y = pos.Y + anchor.AbsoluteSize.Y + 4
    if y + h > area.Y - 8 then y = math.max(8, pos.Y - h - 4) end

    local box = self:Make("Frame", layer, {Position=UDim2.fromOffset(x,y), Size=UDim2.fromOffset(w,h), BackgroundColor3=self.C.Surf, BorderSizePixel=0, ZIndex=2})
    self:Corner(box, 10); self:Stroke(box, self.C.Stroke, 1, 0.1)
    local header = self:Make("TextLabel", box, {
        Size=UDim2.new(1,0,0,self.RowH), Text="  "..title, TextSize=13, Font=self.FB,
        TextColor3=self.C.Text, BackgroundColor3=self.C.Surf, BorderSizePixel=0,
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    self:Corner(header, 10)

    local search
    local top = self.RowH + 4
    if #items > 15 then
        search = self:Make("TextBox", box, {
            Position=UDim2.fromOffset(8,top), Size=UDim2.new(1,-16,0,self.RowH),
            Text="", PlaceholderText="  Search...", ClearTextOnFocus=false,
            TextSize=13, Font=self.F, TextColor3=self.C.Text, PlaceholderColor3=self.C.Mute,
            BackgroundColor3=self.C.Card, BorderSizePixel=0,
        })
        self:Corner(search, 8); self:Stroke(search, self.C.Soft, 1, 0.4)
        top = top + self.RowH + 6
    end

    local list = self:Make("ScrollingFrame", box, {
        Position=UDim2.fromOffset(8, top), Size=UDim2.new(1,-16,1,-top-self.RowH-12),
        BackgroundTransparency=1, BorderSizePixel=0,
        CanvasSize=UDim2.fromOffset(0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
        ScrollingDirection=Enum.ScrollingDirection.Y, ScrollBarThickness=3,
        ScrollBarImageColor3=self.C.Stroke,
    })
    self:Make("UIListLayout", list, {Padding=UDim.new(0,3), SortOrder=Enum.SortOrder.LayoutOrder})

    local rows = {}
    for i, item in ipairs(items) do
        local b = self:Make("TextButton", list, {
            Size=UDim2.new(1,-4,0,self.RowH-2), BackgroundColor3=self.C.Card,
            BorderSizePixel=0, Text="  "..item, Font=self.F, TextSize=13,
            TextColor3=self.C.Text, TextXAlignment=Enum.TextXAlignment.Left,
            AutoButtonColor=false, LayoutOrder=i,
        })
        self:Corner(b, 6)
        local function paint()
            local on = selected[item]
            b.BackgroundColor3 = on and self.C.AccD or self.C.Card
            b.Text = (on and "  ✓ " or "     ")..item
        end
        paint()
        b.Activated:Connect(function()
            selected[item] = not selected[item]
            paint(); onChange()
        end)
        rows[#rows+1] = {Button=b, Name=string.lower(item), Paint=paint}
    end

    if search then
        search:GetPropertyChangedSignal("Text"):Connect(function()
            local q = string.lower(search.Text)
            for _, r in ipairs(rows) do
                r.Button.Visible = string.find(r.Name, q, 1, true) ~= nil
            end
        end)
    end

    local function footer(txt, i, n, cb, acc)
        local b = self:Make("TextButton", box, {
            Position=UDim2.new((i-1)/n, 8, 1, -self.RowH-8),
            Size=UDim2.new(1/n, -12, 0, self.RowH),
            Text=txt, Font=self.F, TextSize=13,
            TextColor3=acc and Color3.new(1,1,1) or self.C.Text,
            BackgroundColor3=acc and self.C.Acc or self.C.Card,
            BorderSizePixel=0, AutoButtonColor=false,
        })
        self:Corner(b, 8); b.Activated:Connect(cb)
    end

    footer("All", 1, 3, function()
        for _, item in ipairs(items) do selected[item] = true end
        for _, r in ipairs(rows) do r.Paint() end
        onChange()
    end)
    footer("None", 2, 3, function()
        for _, item in ipairs(items) do selected[item] = false end
        for _, r in ipairs(rows) do r.Paint() end
        onChange()
    end)
    footer("Done", 3, 3, function() self:ClosePopup() end, true)
end

-- ═══ KEYBIND / PANEL ═══
function A:RefreshKeybind()
    if not self.KeybindBtn then return end
    local n = self.Options.MenuKey.Name:gsub("(%l)(%u)", "%1 %2"):gsub("Control", "Ctrl")
    self.KeybindBtn.Text = self.BindingKey and "Press a key (Esc cancels)" or "Menu key: "..n
end

function A:CancelKeybind()
    self.BindingKey = false
    self:RefreshKeybind()
end

function A:SetMenuVisible(v)
    self:CancelKeybind()
    self.Panel.Visible = v
    self:ClosePopup()
    self:RefreshUI()
end

function A:RefreshMenuBtn()
    if self.Menu then self.Menu.Visible = not self.Panel.Visible end
end

function A:HandleMenuInput(input, processed)
    if not self.Alive or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if self.UIS:GetFocusedTextBox() then self:CancelKeybind(); return end
    if self.BindingKey then
        if input.KeyCode == Enum.KeyCode.Escape then
            self:CancelKeybind()
        elseif input.KeyCode ~= Enum.KeyCode.Unknown then
            self.Options.MenuKey = input.KeyCode
            self:CancelKeybind()
        end
        return
    end
    if not processed and input.KeyCode == self.Options.MenuKey then
        self:SetMenuVisible(not self.Panel.Visible)
    end
end

function A:ClampPanel(pos)
    local a, s = self.Bounds.AbsoluteSize, self.Panel.AbsoluteSize
    self.Panel.Position = UDim2.fromOffset(
        math.clamp(pos.X, 8, math.max(8, a.X-s.X-8)),
        math.clamp(pos.Y, 8, math.max(8, a.Y-s.Y-8))
    )
end

function A:Layout()
    local s = self.Bounds.AbsoluteSize
    if s.X <= 0 or s.Y <= 0 then return end
    self:ClosePopup()
    self.Panel.Size = UDim2.fromOffset(
        math.min(340, math.max(220, s.X-24)),
        math.min(520, math.max(200, s.Y-24))
    )
    self.Container.Visible = not self.Collapsed
    local pos = self.Positioned
        and Vector2.new(self.Panel.Position.X.Offset, self.Panel.Position.Y.Offset)
        or Vector2.new(16, math.floor(s.Y*0.18))
    self:ClampPanel(pos)
    self.Positioned = true
end

-- ═══ REFRESH UI ═══
function A:ControlRefresh()
    for k, c in pairs(self.Controls) do
        if c.Paint then c.Paint() end
    end
    for _, row in ipairs(self.FilterButtons) do
        if row.Mutated then
            row.Button.Text = (self.Filter.MutatedOnly and "✓ " or "   ").."Mutated eggs only"
        else
            local n = 0
            for _, name in ipairs(row.Names) do
                if self.Filter[row.Group][name] then n = n + 1 end
            end
            row.Button.Text = row.Group..": "..(n == #row.Names and "All" or n.." / "..#row.Names)
        end
    end
end

function A:OpenEggPicker()
    local eggs = self:EggList(false)
    local rows = {}
    for i, e in ipairs(eggs) do
        rows[i] = e.Name.."  ·  "..e.Rarity.."  ·  "..self:Format(e.KG).." kg"
    end
    self:OpenPopup(self.EggPicker, rows, nil, function(v)
        for i, label in ipairs(rows) do
            if label == v then
                self.Options.SelectedEgg = eggs[i].ID
                self:RefreshUI()
                return
            end
        end
    end)
end

function A:RefreshUI()
    if not self.StatusLabel then return end
    self:ControlRefresh()
    self.StatusLabel.Text = self.Status
    self.StatusLabel.TextColor3 = self.Job and self.C.Good or self.C.Mute
    self.FarmStats.Text = string.format("Basket %d/%s   ·   Stored %d   ·   Nests %d",
        self.Cache.Basket or 0, self:Format(self:Capacity()),
        self.Cache.Tools or 0, self.Cache.Nests or 0)
    local lines = {}
    for _, e in ipairs(self.Cache.Timers or {}) do
        table.insert(lines, e.Name..": "..(e.Remaining <= 0 and "Ready" or self:Time(e.Remaining)))
    end
    self.NestInfo.Text = #lines > 0 and table.concat(lines, "\n") or "No eggs in nests"
    self.NestInfo.Size = UDim2.new(1,0,0,math.max(22, #lines*18))

    local matchCount = 0
    for _, e in ipairs(self.Cache.Eggs or {}) do
        if self:Matches(e) then matchCount = matchCount + 1 end
    end
    self.EggPicker.Text = "  "..(matchCount == 0 and "No matching eggs" or "Select an egg ("..matchCount..")")
    self.ErrorInfo.Text = #self.Errors > 0 and self.Errors[#self.Errors] or "No errors"
    self:RefreshMenuBtn()
    self:PaintTabs()
end

-- ═══ ROOT UI ═══
A.Gui = A:Make("ScreenGui", A.Player:WaitForChild("PlayerGui"), {
    Name="RideAPet", ResetOnSpawn=false, DisplayOrder=250,
    ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    ScreenInsets=Enum.ScreenInsets.CoreUISafeInsets,
})
A.Bounds = A:Make("Frame", A.Gui, {
    Size=UDim2.fromScale(1,1), BackgroundTransparency=1, BorderSizePixel=0,
})
A.Panel = A:Make("Frame", A.Bounds, {
    Size=UDim2.fromOffset(340,500), BackgroundColor3=A.C.Surf,
    BorderSizePixel=0, Active=true,
})
A:Corner(A.Panel, 14)
A:Stroke(A.Panel, A.C.Stroke, 1, 0.15)

A.Title = A:Make("Frame", A.Panel, {
    Size=UDim2.new(1,0,0,A.TitleH), BackgroundColor3=A.C.Surf, BorderSizePixel=0,
})
A:Corner(A.Title, 14)

A.Collapse = A:Button(A.Title, "▾", function()
    A.Collapsed = not A.Collapsed
    A.Collapse.Text = A.Collapsed and "▸" or "▾"
    A:Layout()
end, A.C.Surf)
A.Collapse.Size = UDim2.fromOffset(A.TitleH, A.TitleH)

A.Header = A:Make("TextButton", A.Title, {
    Position=UDim2.fromOffset(A.TitleH+4,0),
    Size=UDim2.new(1,-A.TitleH*2-8,1,0),
    BackgroundTransparency=1, Text="Ride A Pet", Font=A.FB, TextSize=14,
    TextColor3=A.C.Text, TextXAlignment=Enum.TextXAlignment.Left,
    AutoButtonColor=false,
})

A.Close = A:Button(A.Title, "✕", function() A:SetMenuVisible(false) end, A.C.Surf)
A.Close.AnchorPoint = Vector2.new(1,0)
A.Close.Position = UDim2.fromScale(1,0)
A.Close.Size = UDim2.fromOffset(A.TitleH, A.TitleH)

A.Container = A:Make("Frame", A.Panel, {
    Position=UDim2.fromOffset(10, A.TitleH+8),
    Size=UDim2.new(1,-20,1,-A.TitleH-16),
    BackgroundTransparency=1,
})

A:BuildTabs()
for _, n in ipairs(A.PageNames) do A:CreatePage(n) end

A.StatusLabel = A:Text(A.Container, "Ready", 36, {size=11, color=A.C.Mute})
A.StatusLabel.Position = UDim2.new(0,0,1,-36)
A.StatusLabel.TextWrapped = true

-- Farm page
local farm = A.Pages.Farm
A:Section(farm, "Automation")
A:Toggle(farm, "AutoCollect", "Auto Collect Eggs")
A:Toggle(farm, "AutoPlace",   "Auto Place Eggs")
A:Toggle(farm, "AutoHatch",   "Auto Hatch Eggs")

A:Section(farm, "Tuning")
A:Choice(farm, "EggPriority", "Collection priority",
    {"Nearest","Rarest","Highest luck","Heaviest"})
A:Number(farm, "TweenSpeed",  "Flight speed (studs/s)", 10, 40, 350)
A:Number(farm, "MaxDistance", "Collection range (studs)", 100, 100, 15000)

A:Section(farm, "Status")
A.FarmStats = A:Text(farm, "", 32, {size=12, color=A.C.Dim})

A:Section(farm, "Actions")
A:Button(farm, "Place Eggs Now", function()
    A:StartJob("Placing eggs", function(t) A.Paused = false; A:PlaceEggs(t) end)
end)
A:Button(farm, "Hatch Ready Eggs", function()
    A:StartJob("Hatching eggs", function(t) A:HatchReady(t) end)
end)
A:Button(farm, "Fly to Ranch", function()
    A:StartJob("Returning to ranch", function(t) A.Paused = false; A:Home(t) end)
end)
A.NestInfo = A:Text(farm, "", 22, {size=11, color=A.C.Dim})

-- Eggs page
local eggs = A.Pages.Eggs
A.EggPicker = A:Button(eggs, "  Select an egg", function() A:OpenEggPicker() end)
A:Button(eggs, "Collect Selected Egg", function()
    A:StartJob("Collecting selected egg", function(t) A:CollectSelected(t) end)
end, A.C.Acc)
A:Button(eggs, "Stop Collecting", function() A:StopCollecting() end)

A:Section(eggs, "Filters")
A:FilterPanel(eggs)

-- ESP page
local esp = A.Pages.ESP
A:Section(esp, "Egg ESP")
A:Toggle(esp, "EggESP",    "Enable ESP")
A:Toggle(esp, "ESPName",   "Show name")
A:Toggle(esp, "ESPWeight", "Show weight (kg)")
A:Section(esp, "Tuning")
A:Number(esp, "ESPSize",     "Text size", 1, 12, 25)
A:Number(esp, "ESPCount",    "Maximum labels", 5, 1, 100)
A:Number(esp, "ESPDistance", "ESP range (studs)", 100, 100, 15000)

-- Settings page
local settings = A.Pages.Settings
A:Section(settings, "General")
A:Toggle(settings, "AntiAFK", "Anti-AFK")

A:Section(settings, "Keybind")
A.KeybindBtn = A:Button(settings, "Menu key: Right Ctrl", function()
    A:ClosePopup()
    A.BindingKey = not A.BindingKey
    A:RefreshKeybind()
end)
A:Text(settings, "Click, then press a key. Esc cancels.", 32,
    {size=11, color=A.C.Mute})

A:Section(settings, "Window")
A:Button(settings, "Center Window", function()
    local sz = A.Bounds.AbsoluteSize
    A:ClampPanel((sz - A.Panel.AbsoluteSize) / 2)
end)

A:Section(settings, "Diagnostics")
A.ErrorInfo = A:Text(settings, "No errors", 22, {size=11, color=A.C.Mute})

A:Section(settings, "Session")
A:Button(settings, "Unload", function() A:Unload() end, A.C.Acc)

-- Floating menu button
A.Menu = A:Button(A.Bounds, "Menu", function() A:SetMenuVisible(true) end, A.C.Acc)
A.Menu.Size = UDim2.fromOffset(74, 44)
A.Menu.Position = UDim2.new(1, -82, 1, -52)
A.Menu.ZIndex = 30
A.Menu.Visible = false

-- ═══ DRAG ═══
local dragInput, dragStart, panelStart
A:Connect(A.Header.InputBegan, function(input)
    if dragInput then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
       and input.UserInputType ~= Enum.UserInputType.Touch then return end
    A:ClosePopup()
    dragInput = input
    dragStart = Vector2.new(input.Position.X, input.Position.Y)
    panelStart = Vector2.new(A.Panel.Position.X.Offset, A.Panel.Position.Y.Offset)
end)
A:Connect(A.UIS.InputChanged, function(input)
    if dragInput and (input == dragInput or
       (dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseMovement)) then
        A:ClampPanel(panelStart + Vector2.new(input.Position.X, input.Position.Y) - dragStart)
    end
end)
A:Connect(A.UIS.InputEnded, function(input)
    if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragInput, dragStart, panelStart = nil, nil, nil
    end
end)

A:Connect(A.UIS.InputBegan, function(input, processed)
    A:HandleMenuInput(input, processed)
end)
A:Connect(A.Bounds:GetPropertyChangedSignal("AbsoluteSize"), function()
    A:Layout()
end)
A:Connect(A.Player.CharacterAdded, function()
    A:CancelJob()
    A.Status = "Respawned"
end)
A:Connect(A.ActiveEggs.ChildRemoved, function(e)
    A.FailedEggs[e.Name] = nil
end)
A:Connect(A.Run.RenderStepped, function()
    pcall(function() A:RenderESP() end)
end)

-- ═══ UNLOAD ═══
function A:Unload()
    if not self.Alive then return end
    self.Alive = false
    self:CancelJob()
    self:SetAntiAFK(false)
    self:ClearESP()
    for _, c in ipairs(self.Connections) do
        pcall(function() c:Disconnect() end)
    end
    for _, th in ipairs(self.Threads) do
        pcall(task.cancel, th)
    end
    if self.Gui then self.Gui:Destroy() end
    if Env.RideAPetCompact == self then Env.RideAPetCompact = nil end
end

-- ═══ BOOT ═══
A:Refresh()
A:RefreshUI()
A:Layout()
A:SetAntiAFK(true)

table.insert(A.Threads, task.spawn(function()
    while A.Alive do
        local ok, err = xpcall(function() A:Tick() end, debug.traceback)
        if not ok then A:Err("Automation", err) end
        task.wait(0.4)
    end
end))

table.insert(A.Threads, task.spawn(function()
    while A.Alive do
        local ok, err = xpcall(function()
            A:Refresh()
            pcall(function() A:UpdateESP() end)
            A:RefreshUI()
        end, debug.traceback)
        if not ok then A:Err("Refresh", err) end
        task.wait(0.7)
    end
end))

return A