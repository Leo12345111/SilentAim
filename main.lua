local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "StatusIndicator"
screenGui.Parent = localPlayer:WaitForChild("PlayerGui")
screenGui.ResetOnSpawn = false

local indicator = Instance.new("Frame")
indicator.Name = "StatusFrame"
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
                local distance = (head.Position - myPos).Magnitude

                if distance < shortestDistance then
                    closestPlayer = player
                    shortestDistance = distance
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
        camera.CFrame = CFrame.new(cameraPosition, head.Position)
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
        if isLeftMouseDown or isHoldingAuto then
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

local inputConnection
inputConnection = UserInputService.InputBegan:Connect(function(input, isProcessed)
    if not isRunning then
        inputConnection:Disconnect()
        return
    end

    if input.KeyCode == Enum.KeyCode.K then
        isEnabled = not isEnabled
        indicator.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    elseif input.KeyCode == Enum.KeyCode.L then
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
        task.delay(1, function()
            indicator.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        end)
    elseif input.KeyCode == Enum.KeyCode.U then
        isRunning = false
        screenGui:Destroy()
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
