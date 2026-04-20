local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

local isEnabled = false
local isRunning = true
local isLeftMouseDown = false
local leftClickStartTime = 0
local lastAutoShot = 0
local fireRate = 0
local targetPlayer = nil
local ignoredPlayers = {}
local headOffset = Vector3.new(0, 0.5, 0)

local flying = false
local flySpeed = 200
local bv = nil
local bg = nil

local ESPEnabled = false
local Drawings = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SilentAimIndicator"
if syn and syn.protect_gui then syn.protect_gui(screenGui) end 
screenGui.Parent = CoreGui 

local indicator = Instance.new("Frame")
indicator.Name = "Circle"
indicator.Size = UDim2.new(0, 30, 0, 30)
indicator.Position = UDim2.new(1, -50, 1, -50) 
indicator.BackgroundColor3 = Color3.fromRGB(255, 0, 0) 
indicator.BorderSizePixel = 0
indicator.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0) 
corner.Parent = indicator

local function isLobbyVisible()
    local mainGui = localPlayer.PlayerGui:FindFirstChild("MainGui")
    if mainGui and mainGui:FindFirstChild("MainFrame") and mainGui.MainFrame:FindFirstChild("Lobby") and mainGui.MainFrame.Lobby:FindFirstChild("Currency") then
        return mainGui.MainFrame.Lobby.Currency.Visible == true
    end
    return false
end

local function checkLineOfSight(origin, targetPos, baseExcludeList)
    local direction = targetPos - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local excludeList = {table.unpack(baseExcludeList)}
    params.FilterDescendantsInstances = excludeList

    while true do
        local result = workspace:Raycast(origin, direction, params)
        if not result then
            return true
        end

        local hitPart = result.Instance
        if hitPart then
            if hitPart.Size.X <= 1 or hitPart.Size.Y <= 1 or hitPart.Size.Z <= 1 then
                table.insert(excludeList, hitPart)
                params.FilterDescendantsInstances = excludeList
            else
                return false
            end
        else
            break
        end
    end
    return true
end

local function isVisible(target)
    local char = localPlayer.Character
    local targetChar = target.Character
    if not char or not char:FindFirstChild("Head") then return false end
    if not targetChar or not targetChar:FindFirstChild("Head") then return false end

    local origin = char.Head.Position
    local targetHead = targetChar.Head

    local baseExcludeList = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            table.insert(baseExcludeList, p.Character)
        end
    end

    local successfulHits = 0
    local headSize = targetHead.Size

    local offsets = {
        Vector3.new(0, 0, 0),
        Vector3.new(0.5, 0, 0),
        Vector3.new(-0.5, 0, 0),
        Vector3.new(0, 0.5, 0),
        Vector3.new(0, -0.5, 0)
    }

    for _, offset in ipairs(offsets) do
        local localOffset = Vector3.new(offset.X * headSize.X, offset.Y * headSize.Y, offset.Z * headSize.Z)
        local targetPos = (targetHead.CFrame * localOffset) + headOffset
        
        if checkLineOfSight(origin, targetPos, baseExcludeList) then
            successfulHits = successfulHits + 1
        end
    end

    return successfulHits > 2
end

local function getClosestPlayer()
    local closestPlayer = nil
    local shortestDistance = math.huge
    local character = localPlayer.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end
    
    local myPos = character.HumanoidRootPart.Position

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character and player.Character:FindFirstChild("Head") and player.Character:FindFirstChild("Humanoid") then
            local head = player.Character.Head
            local humanoid = player.Character.Humanoid
            
            if humanoid.Health > 0 and not table.find(ignoredPlayers, player) then
                if isVisible(player) then
                    local distance = ((head.Position + headOffset) - myPos).Magnitude

                    if distance < shortestDistance then
                        closestPlayer = player
                        shortestDistance = distance
                    end
                end
            end
        end
    end
    return closestPlayer
end

local function lockCameraToHead()
    if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("Head") then
        local head = targetPlayer.Character.Head
        local cameraPosition = camera.CFrame.Position
        camera.CFrame = CFrame.new(cameraPosition, head.Position + headOffset)
    end
end

local function CreateESP(player)
    local box = Drawing.new("Square")
    box.Visible = false
    box.Color = Color3.new(1, 0, 0)
    box.Thickness = 1
    box.Filled = true
    box.Transparency = 0.4

    local outline = Drawing.new("Square")
    outline.Visible = false
    outline.Color = Color3.new(0, 0, 0)
    outline.Thickness = 2
    outline.Filled = false
    outline.Transparency = 1

    local healthBar = Drawing.new("Line")
    healthBar.Visible = false
    healthBar.Color = Color3.new(0, 1, 0)
    healthBar.Thickness = 2

    local healthText = Drawing.new("Text")
    healthText.Visible = false
    healthText.Color = Color3.new(1, 1, 1)
    healthText.Size = 14
    healthText.Center = false
    healthText.Outline = true

    local nameText = Drawing.new("Text")
    nameText.Visible = false
    nameText.Color = Color3.new(1, 1, 1)
    nameText.Size = 16
    nameText.Center = true
    nameText.Outline = true

    Drawings[player] = {
        Box = box,
        Outline = outline,
        HealthBar = healthBar,
        HealthText = healthText,
        NameText = nameText
    }
end

local function RemoveESP(player)
    if Drawings[player] then
        for _, obj in pairs(Drawings[player]) do
            obj:Remove()
        end
        Drawings[player] = nil
    end
end

Players.PlayerAdded:Connect(CreateESP)
Players.PlayerRemoving:Connect(RemoveESP)

for _, player in pairs(Players:GetPlayers()) do
    if player ~= localPlayer then CreateESP(player) end
end

local function toggleFly()
    flying = not flying
    local char = localPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return end
    
    local hrp = char.HumanoidRootPart
    
    if flying then
        bv = Instance.new("BodyVelocity")
        bg = Instance.new("BodyGyro")
        
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Velocity = Vector3.zero
        bv.Parent = hrp
        
        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bg.CFrame = camera.CFrame
        bg.Parent = hrp
    else
        if bv then bv:Destroy() end
        if bg then bg:Destroy() end
    end
end

local heartbeatConnection
heartbeatConnection = RunService.Heartbeat:Connect(function()
    if not isRunning then
        heartbeatConnection:Disconnect()
        return
    end

    local currentTime = tick()
    local isHoldingAuto = isLeftMouseDown and (currentTime - leftClickStartTime >= 0.6)

    if isEnabled and not isLobbyVisible() then
        if isHoldingAuto then
            if currentTime - lastAutoShot >= fireRate then
                targetPlayer = getClosestPlayer()
                if targetPlayer then
                    lockCameraToHead()
                    if typeof(mouse1click) == "function" then
                        mouse1click()
                        lastAutoShot = currentTime
                    end
                end
            end
        end
    end
end)

RunService.RenderStepped:Connect(function()
    if not isRunning then return end

    if ESPEnabled then
        for player, data in pairs(Drawings) do
            local character = player.Character
            if character and character:FindFirstChild("HumanoidRootPart") and character:FindFirstChild("Humanoid") then
                local hrp = character.HumanoidRootPart
                local humanoid = character.Humanoid
                local pos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                
                if onScreen and humanoid.Health > 0 then
                    local size = Vector2.new(2000 / pos.Z, 2500 / pos.Z)
                    local boxPos = Vector2.new(pos.X - size.X / 2, pos.Y - size.Y / 2)
                    
                    data.Box.Size = size
                    data.Box.Position = boxPos
                    data.Box.Visible = true
                    
                    data.Outline.Size = size
                    data.Outline.Position = boxPos
                    data.Outline.Visible = true
                    
                    data.NameText.Position = Vector2.new(pos.X, boxPos.Y - 20)
                    data.NameText.Text = player.Name
                    data.NameText.Visible = true
                    
                    local barHeight = size.Y * (humanoid.Health / humanoid.MaxHealth)
                    data.HealthBar.From = Vector2.new(boxPos.X - 7, boxPos.Y + size.Y)
                    data.HealthBar.To = Vector2.new(boxPos.X - 7, boxPos.Y + size.Y - barHeight)
                    data.HealthBar.Visible = true
                    
                    data.HealthText.Position = Vector2.new(boxPos.X - 45, boxPos.Y + size.Y - barHeight - 7)
                    data.HealthText.Text = "hp: " .. math.floor(humanoid.Health)
                    data.HealthText.Visible = true
                else
                    for _, obj in pairs(data) do obj.Visible = false end
                end
            else
                for _, obj in pairs(data) do obj.Visible = false end
            end
        end
    else
        for _, data in pairs(Drawings) do
            for _, obj in pairs(data) do
                obj.Visible = false
            end
        end
    end

    if flying and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") and bv and bg then
        local moveVector = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector - camera.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector - camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + camera.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector = moveVector + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector = moveVector - Vector3.new(0, 1, 0) end

        bg.CFrame = camera.CFrame
        if moveVector.Magnitude > 0 then
            bv.Velocity = moveVector.Unit * flySpeed
        else
            bv.Velocity = Vector3.zero
        end
    end
end)

local inputConnection
inputConnection = UserInputService.InputBegan:Connect(function(input, isProcessed)
    if not isRunning then
        inputConnection:Disconnect()
        return
    end

    if input.KeyCode == Enum.KeyCode.K and not isProcessed then
        isEnabled = not isEnabled
        indicator.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        
    elseif input.KeyCode == Enum.KeyCode.L and not isProcessed then
        ignoredPlayers = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                local distance = (player.Character.HumanoidRootPart.Position - localPlayer.Character.HumanoidRootPart.Position).Magnitude
                if distance <= 20 then
                    table.insert(ignoredPlayers, player)
                end
            end
        end
        indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 0)
        task.delay(0.5, function()
            if isRunning then
                indicator.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
            end
        end)
        
    elseif input.KeyCode == Enum.KeyCode.U and not isProcessed then
        isRunning = false
        screenGui:Destroy()
        if flying then toggleFly() end
        for player, _ in pairs(Drawings) do
            RemoveESP(player)
        end
        
    elseif input.KeyCode == Enum.KeyCode.P and not isProcessed then
        toggleFly()
        
    elseif input.KeyCode == Enum.KeyCode.O and not isProcessed then
        ESPEnabled = not ESPEnabled
        
    elseif not isProcessed and isEnabled and not isLobbyVisible() then
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            isLeftMouseDown = true
            leftClickStartTime = tick()
            targetPlayer = getClosestPlayer()
            if targetPlayer then
                lockCameraToHead()
            end
            if typeof(mouse1click) == "function" then
                mouse1click()
                lastAutoShot = tick()
            end
        end
    end
end)

local inputEndedConnection
inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
    if not isRunning then
        inputEndedConnection:Disconnect()
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        isLeftMouseDown = false
    end
end)
