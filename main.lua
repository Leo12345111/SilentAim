local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local function forceDestroyOldGuis()
    local names = {"ScriptSwitcherGui", "StatusIndicatorGui", "SilentAimIndicator", "CombatIndicator"}
    local pg = localPlayer:FindFirstChildOfClass("PlayerGui")
    if pg then
        for _, name in ipairs(names) do
            local g = pg:FindFirstChild(name)
            if g then g:Destroy() end
        end
    end
    pcall(function()
        if CoreGui then
            for _, name in ipairs(names) do
                local g = CoreGui:FindFirstChild(name)
                if g then g:Destroy() end
            end
        end
    end)
    pcall(function()
        if gethui then
            local h = gethui()
            if h then
                for _, name in ipairs(names) do
                    local g = h:FindFirstChild(name)
                    if g then g:Destroy() end
                end
            end
        end
    end)
end

if _G.TotalScriptCleanup then
    pcall(_G.TotalScriptCleanup)
    _G.TotalScriptCleanup = nil
end

forceDestroyOldGuis()

local switcherGui = Instance.new("ScreenGui")
switcherGui.Name = "ScriptSwitcherGui"
switcherGui.ResetOnSpawn = false
switcherGui.Parent = localPlayer:WaitForChild("PlayerGui")

local textLabel = Instance.new("TextLabel")
textLabel.Size = UDim2.new(0, 600, 0, 50)
textLabel.Position = UDim2.new(0.5, 0, 0, 30) -- Positioned in the middle, 30 px down from the top
textLabel.AnchorPoint = Vector2.new(0.5, 0)
textLabel.BackgroundTransparency = 1
textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
textLabel.TextSize = 26
textLabel.Font = Enum.Font.SourceSansBold
textLabel.TextStrokeTransparency = 0
textLabel.Text = "No Script Active"
textLabel.Parent = switcherGui

local currentScriptIndex = 0
local activeScriptCleanup = nil
local mainConnections = {}

local function castRobustRay(origin, targetPos, ignoreList)
    if not origin or not targetPos then return nil end
    local direction = targetPos - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    
    local currentIgnore = {table.unpack(ignoreList)}
    params.FilterDescendantsInstances = currentIgnore
    
    local maxPierces = 10
    local pierces = 0
    
    while pierces < maxPierces do
        local result = Workspace:Raycast(origin, direction, params)
        if not result then 
            return nil 
        end
        
        local hitPart = result.Instance
        if hitPart and hitPart.Parent and (hitPart.Size.X <= 2 or hitPart.Size.Y <= 2 or hitPart.Size.Z <= 2 or hitPart.Transparency >= 0.3 or not hitPart.CanCollide or hitPart:IsA("Accessory") or hitPart.Parent:IsA("Accessory")) then
            table.insert(currentIgnore, hitPart)
            params.FilterDescendantsInstances = currentIgnore
            pierces = pierces + 1
        else
            return result
        end
    end
    return nil
end

-- ==========================================
-- SCRIPT 1: Position Combat Script
-- ==========================================
local function startScript1()
    local isActive = false
    local isRunning = true
    local combatThread = nil
    local noclipConnection = nil
    local storedSafeParts = {}
    local safeToggleIndex = 1
    local currentTargetPlayer = nil
    local activationPos = Vector3.zero

    local headOffset = Vector3.new(0, 0.5, 0)
    local usePrediction = true
    local projectileSpeed = 999999999
    local pingCompensation = 0

    local damageKeywords = {
        "kill", "damage", "lava", "laser", "spike", "acid", "poison", "fire", "hurt", "toxic", "dead", "void", "trap",
        "satchel", "grenade", "molotov", "tripmine", "projectile", "spear", "vortex", "barrier", "barrel", "explosive"
    }

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "StatusIndicatorGui"
    screenGui.ResetOnSpawn = false
    screenGui.Parent = localPlayer:WaitForChild("PlayerGui")

    local statusCircle = Instance.new("Frame")
    statusCircle.Size = UDim2.new(0, 50, 0, 50)
    statusCircle.Position = UDim2.new(1, -50, 1, -50) 
    statusCircle.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    statusCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    statusCircle.Parent = screenGui

    local uiCorner = Instance.new("UICorner")
    uiCorner.CornerRadius = UDim.new(1, 0)
    uiCorner.Parent = statusCircle

    local function checkIsTeammate(player, hrp)
        if player.Team ~= nil and localPlayer.Team ~= nil and player.Team == localPlayer.Team then return true end
        if hrp and hrp:FindFirstChild("TeammateLabel") ~= nil then return true end
        return false
    end

    local function fireWeapon()
        if mouse1click then 
            mouse1click() 
        elseif mouse1press and mouse1release then
            mouse1press()
            task.wait()
            mouse1release()
        else
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
            task.wait()
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
        end
        local character = localPlayer.Character
        if character then
            local tool = character:FindFirstChildOfClass("Tool")
            if tool then tool:Activate() end
        end
    end

    local function lockCameraToHead()
        if currentTargetPlayer and currentTargetPlayer.Character and currentTargetPlayer.Character:FindFirstChild("Head") and currentTargetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local head = currentTargetPlayer.Character.Head
            local targetHRP = currentTargetPlayer.Character.HumanoidRootPart
            local cameraPosition = camera.CFrame.Position
            local aimPosition = head.Position + headOffset

            if usePrediction then
                local velocity = targetHRP.AssemblyLinearVelocity
                local distance = (aimPosition - cameraPosition).Magnitude
                local timeToHit = (distance / projectileSpeed) + pingCompensation
                aimPosition = aimPosition + (velocity * timeToHit)
            end

            camera.CFrame = CFrame.new(cameraPosition, aimPosition)
        end
    end

    local function isNearDamage(centerPos, radius, ignoreList)
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = ignoreList
        
        local partsInRadius = Workspace:GetPartBoundsInRadius(centerPos, radius, overlapParams)
        for _, part in ipairs(partsInRadius) do
            local lowerName = string.lower(part.Name)
            local lowerParentName = part.Parent and string.lower(part.Parent.Name) or ""
            local tagsString = ""
            for _, tag in ipairs(CollectionService:GetTags(part)) do
                tagsString = tagsString .. " " .. string.lower(tag)
            end
            for _, keyword in ipairs(damageKeywords) do
                if string.find(lowerName, keyword) or string.find(lowerParentName, keyword) or string.find(tagsString, keyword) then
                    return true
                end
            end
        end
        return false
    end

    local function characterWillFit(tpCFrame, baseIgnoreList, partToIgnore)
        local characterSize = Vector3.new(2, 4.5, 2) 
        local finalIgnoreList = {table.unpack(baseIgnoreList)}
        if partToIgnore then table.insert(finalIgnoreList, partToIgnore) end
        
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        overlapParams.FilterDescendantsInstances = finalIgnoreList

        local partsInSpace = Workspace:GetPartBoundsInBox(tpCFrame, characterSize, overlapParams)
        for _, part in ipairs(partsInSpace) do
            if part:IsA("BasePart") and part.CanCollide then return false end
        end
        return true
    end

    local function isPartStillValid(part, enemyHead, ignoreList)
        if not part or not part.Parent then return false end
        if not enemyHead or not enemyHead.Parent then return false end
        if not characterWillFit(part.CFrame, ignoreList, part) then return false end
        if isNearDamage(part.Position, 15, ignoreList) then return false end
        
        local fakeHeadPos = part.Position + Vector3.new(0, 1.5, 0)
        local raycastResult = castRobustRay(fakeHeadPos, enemyHead.Position, ignoreList)
        if not raycastResult or raycastResult.Instance:IsDescendantOf(enemyHead.Parent) then
            return true
        end
        return false
    end

    local function isReliableShape(part)
        if part:IsA("BasePart") then
            if part.Size.Y >= 2 and part.Size.Y <= 100 and part.Transparency < 0.95 then
                if part.Size.X <= 300 and part.Size.Z <= 300 then return true end
            end
        end
        return false
    end

    local function findAttackParts(centerPos, scanRadius, minWidth, minHeight, ignoreList, raycastTarget, maxResults)
        local validParts = {}
        local partsInRange = Workspace:GetPartBoundsInRadius(centerPos, scanRadius)
        
        for _, part in ipairs(partsInRange) do
            if isReliableShape(part) and part.Size.X >= minWidth and part.Size.Y >= minHeight and part.Size.Z >= minWidth then
                if not isNearDamage(part.Position, 15, ignoreList) then
                    if characterWillFit(part.CFrame, ignoreList, part) then
                        if raycastTarget then
                            local fakeHeadPos = part.Position + Vector3.new(0, 1.5, 0)
                            local raycastResult = castRobustRay(fakeHeadPos, raycastTarget.Position, ignoreList)
                            if not raycastResult or raycastResult.Instance:IsDescendantOf(raycastTarget.Parent) then
                                table.insert(validParts, part)
                            end
                        else
                            table.insert(validParts, part)
                        end
                    end
                end
            end
        end
        
        table.sort(validParts, function(a, b)
            return (a.Position - centerPos).Magnitude < (b.Position - centerPos).Magnitude
        end)
        
        local results = {}
        for i = 1, math.min(maxResults, #validParts) do
            table.insert(results, validParts[i])
        end
        return results
    end

    local function getValidOpponents(maxDistance)
        local opponents = {}
        local myCharacter = localPlayer.Character
        if not myCharacter or not myCharacter:FindFirstChild("HumanoidRootPart") then return opponents end
        local myPos = myCharacter.HumanoidRootPart.Position
        
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= localPlayer and player.Character then
                local hrp = player.Character:FindFirstChild("HumanoidRootPart")
                local hum = player.Character:FindFirstChild("Humanoid")
                if hrp and hum and hum.Health > 0 and not checkIsTeammate(player, hrp) then
                    if (hrp.Position - myPos).Magnitude <= maxDistance then table.insert(opponents, player) end
                end
            end
        end
        return opponents
    end

    local function gotoSafePart(myCharacter, hrp)
        local allValid = true
        for _, sp in ipairs(storedSafeParts) do
            if not sp or not sp.Parent or isNearDamage(sp.Position, 15, {myCharacter}) then
                allValid = false
                break
            end
        end

        if not allValid or #storedSafeParts == 0 then
            storedSafeParts = findAttackParts(activationPos, 150, 2, 2, {myCharacter}, nil, 2)
        end

        if #storedSafeParts > 0 then
            local targetCFrame
            if safeToggleIndex == 1 then
                if storedSafeParts[1] and storedSafeParts[1].Parent then targetCFrame = storedSafeParts[1].CFrame end
            else
                if storedSafeParts[2] and storedSafeParts[2].Parent then
                    targetCFrame = storedSafeParts[2].CFrame
                elseif storedSafeParts[1] then
                    targetCFrame = CFrame.new(activationPos)
                end
            end

            if targetCFrame then
                myCharacter:PivotTo(targetCFrame)
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
                safeToggleIndex = safeToggleIndex == 1 and 2 or 1
                return true
            end
        end
        return false
    end

    local function startCombatSequence()
        if combatThread then task.cancel(combatThread) end
        
        combatThread = task.spawn(function()
            storedSafeParts = {}
            while isActive and isRunning do
                local mainSuccess, _ = pcall(function()
                    local myCharacter = localPlayer.Character
                    if not myCharacter or not myCharacter:FindFirstChild("Humanoid") or myCharacter.Humanoid.Health <= 0 or not myCharacter:FindFirstChild("HumanoidRootPart") then
                        task.wait(0.2) 
                        return
                    end
                    
                    local hrp = myCharacter.HumanoidRootPart
                    local opponents = getValidOpponents(300)
                    local engagedSomeone = false
                    
                    for _, opponent in ipairs(opponents) do
                        if not isActive or not isRunning then break end
                        currentTargetPlayer = opponent
                        local enemyChar = currentTargetPlayer.Character
                        local enemyHead = enemyChar and enemyChar:FindFirstChild("Head")
                        local enemyHum = enemyChar and enemyChar:FindFirstChild("Humanoid")
                        local enemyHrp = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart")
                        
                        if enemyHead and enemyHum and enemyHum.Health > 0 and enemyHrp and not checkIsTeammate(currentTargetPlayer, enemyHrp) then
                            local ignoreList = {myCharacter, enemyChar}
                            local attackParts = findAttackParts(enemyHead.Position, 100, 2, 2, ignoreList, enemyHead, 2)
                            
                            if #attackParts > 0 then
                                engagedSomeone = true
                                local attackToggleIndex = 1
                                
                                while isActive and enemyHum.Health > 0 and enemyChar.Parent ~= nil do
                                    if not localPlayer.Character or localPlayer.Character ~= myCharacter or myCharacter.Humanoid.Health <= 0 then break end
                                    local currentEnemyHrp = enemyChar:FindFirstChild("HumanoidRootPart")
                                    if not currentEnemyHrp or checkIsTeammate(currentTargetPlayer, currentEnemyHrp) then break end

                                    local allValid = true
                                    for _, p in ipairs(attackParts) do
                                        if not isPartStillValid(p, enemyHead, ignoreList) then
                                            allValid = false
                                            break
                                        end
                                    end
                                    
                                    if not allValid then
                                        attackParts = findAttackParts(enemyHead.Position, 100, 2, 2, ignoreList, enemyHead, 2)
                                        if #attackParts == 0 then
                                            gotoSafePart(myCharacter, hrp)
                                            break 
                                        end
                                    end
                                    
                                    local targetCFrame
                                    if attackToggleIndex == 1 then
                                        if attackParts[1] and attackParts[1].Parent then targetCFrame = attackParts[1].CFrame end
                                    else
                                        if attackParts[2] and attackParts[2].Parent then
                                            targetCFrame = attackParts[2].CFrame
                                        elseif attackParts[1] then
                                            targetCFrame = CFrame.new(activationPos)
                                        end
                                    end
                                    
                                    if targetCFrame then
                                        myCharacter:PivotTo(targetCFrame)
                                        hrp.AssemblyLinearVelocity = Vector3.zero
                                        hrp.AssemblyAngularVelocity = Vector3.zero
                                        lockCameraToHead()
                                        attackToggleIndex = attackToggleIndex == 1 and 2 or 1
                                        fireWeapon()
                                    end
                                    RunService.Heartbeat:Wait() 
                                end
                            end
                        end
                        if not localPlayer.Character or localPlayer.Character ~= myCharacter or myCharacter.Humanoid.Health <= 0 then break end
                    end
                    
                    currentTargetPlayer = nil
                    if not engagedSomeone and isActive then
                        if myCharacter and myCharacter.Parent and myCharacter:FindFirstChild("Humanoid") and myCharacter.Humanoid.Health > 0 then
                            gotoSafePart(myCharacter, hrp)
                        end
                        task.wait(0.03) 
                    else
                        if isActive then RunService.Heartbeat:Wait() end
                    end
                end)
                if not mainSuccess then task.wait(0.03) end
            end
        end)
    end

    local function stopNoclip()
        if noclipConnection then noclipConnection:Disconnect(); noclipConnection = nil end
        if localPlayer.Character then
            for _, part in ipairs(localPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end

    local function handleInput(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.L and isRunning then
            isActive = not isActive
            if isActive then
                statusCircle.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
                local myCharacter = localPlayer.Character
                if myCharacter and myCharacter:FindFirstChild("HumanoidRootPart") then
                    activationPos = myCharacter.HumanoidRootPart.Position
                else
                    activationPos = Vector3.zero
                end
                stopNoclip()
                noclipConnection = RunService.Stepped:Connect(function()
                    if localPlayer.Character then
                        for _, part in ipairs(localPlayer.Character:GetDescendants()) do
                            if part:IsA("BasePart") then part.CanCollide = false end
                        end
                    end
                end)
                startCombatSequence()
            else
                statusCircle.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
                currentTargetPlayer = nil
                if combatThread then task.cancel(combatThread) end
                stopNoclip()
            end
        end
    end

    local renderConn = RunService.RenderStepped:Connect(function()
        if isActive and currentTargetPlayer then lockCameraToHead() end
    end)
    local inputConn = UserInputService.InputBegan:Connect(handleInput)

    return function()
        isRunning = false
        isActive = false
        currentTargetPlayer = nil
        if combatThread then task.cancel(combatThread) end
        stopNoclip()
        if renderConn then renderConn:Disconnect() end
        if inputConn then inputConn:Disconnect() end
        if screenGui then screenGui:Destroy() end
    end
end

-- ==========================================
-- SCRIPT 2: Silent Aim & Utility Script
-- ==========================================
local function startScript2()
    local isEnabled = false
    local autoClickEnabled = false
    local noclipEnabled = false
    local isRunning = true
    local isLeftMouseDown = false
    local leftClickStartTime = 0
    local lastAutoShot = 0
    local fireRate = 0
    local targetPlayer = nil
    local headOffset = Vector3.new(0, 0.5, 0)
    local flying = false
    local flySpeed = 200
    local bv, bg = nil, nil
    local ESPEnabled = false
    local Drawings = {}
    local usePrediction = true
    local projectileSpeed = 999999999
    local pingCompensation = 0

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "SilentAimIndicator"
    screenGui.IgnoreGuiInset = true 
    if gethui then screenGui.Parent = gethui() elseif syn and syn.protect_gui then syn.protect_gui(screenGui); screenGui.Parent = CoreGui else screenGui.Parent = CoreGui end

    local function createIndicator(name, xOffset)
        local ind = Instance.new("Frame")
        ind.Name = name
        ind.Size = UDim2.new(0, 30, 0, 30)
        ind.Position = UDim2.new(1, xOffset, 1, -25) 
        ind.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
        ind.BorderSizePixel = 0
        ind.AnchorPoint = Vector2.new(0.5, 0.5)
        ind.Parent = screenGui
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0) 
        corner.Parent = ind
        return ind
    end

    local indicator = createIndicator("Circle", -25)
    local autoClickIndicator = createIndicator("AutoClickCircle", -65)
    local noclipIndicator = createIndicator("NoClipCircle", -105)

    local screenTint = Instance.new("Frame")
    screenTint.Name = "ScreenTint"
    screenTint.Size = UDim2.new(1, 0, 1, 0)
    screenTint.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    screenTint.BackgroundTransparency = 0.8
    screenTint.BorderSizePixel = 0
    screenTint.Visible = false
    screenTint.Parent = screenGui

    local function isLobbyVisible()
        local mainGui = localPlayer.PlayerGui:FindFirstChild("MainGui")
        if mainGui and mainGui:FindFirstChild("MainFrame") and mainGui.MainFrame:FindFirstChild("Lobby") and mainGui.MainFrame.Lobby:FindFirstChild("Currency") then
            return mainGui.MainFrame.Lobby.Currency.Visible == true
        end
        return false
    end

    local function checkIsTeammate(player, hrp)
        if player.Team ~= nil and localPlayer.Team ~= nil and player.Team == localPlayer.Team then return true end
        if hrp and hrp:FindFirstChild("TeammateLabel") ~= nil then return true end
        return false
    end

    local function isVisible(target)
        local char = localPlayer.Character
        local targetChar = target.Character
        if not char or not char:FindFirstChild("Head") or not targetChar or not targetChar:FindFirstChild("Head") then return false end
        
        local origin = char.Head.Position
        local targetHead = targetChar.Head
        local direction = (targetHead.Position + headOffset) - origin
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local excludeList = {}
        for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(excludeList, p.Character) end end
        params.FilterDescendantsInstances = excludeList
        
        local pierces, maxPierces = 0, 3
        while pierces < maxPierces do
            local result = workspace:Raycast(origin, direction, params)
            if not result then return true end
            if result.Instance and (result.Instance.Size.X <= 2 or result.Instance.Size.Y <= 2 or result.Instance.Size.Z <= 2 or result.Instance.Transparency >= 0.3) then
                table.insert(excludeList, result.Instance)
                params.FilterDescendantsInstances = excludeList
                pierces = pierces + 1
            else
                return false
            end
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
            if player ~= localPlayer and player.Character and player.Character:FindFirstChild("Head") and player.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = player.Character.HumanoidRootPart
                local hum = player.Character:FindFirstChild("Humanoid")
                if hum and hum.Health > 0 and not checkIsTeammate(player, hrp) and isVisible(player) then
                    local distance = ((player.Character.Head.Position + headOffset) - myPos).Magnitude
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
        if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("Head") and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local head = targetPlayer.Character.Head
            local targetHRP = targetPlayer.Character.HumanoidRootPart
            local cameraPosition = camera.CFrame.Position
            local aimPosition = head.Position + headOffset

            if usePrediction then
                local velocity = targetHRP.AssemblyLinearVelocity
                local distance = (aimPosition - cameraPosition).Magnitude
                local timeToHit = (distance / projectileSpeed) + pingCompensation
                aimPosition = aimPosition + (velocity * timeToHit)
            end

            camera.CFrame = CFrame.new(cameraPosition, aimPosition)
        end
    end

    local function CreateESP(player)
        local box = Drawing.new("Square"); box.Visible = false; box.Color = Color3.new(1, 0, 0); box.Thickness = 1; box.Filled = true; box.Transparency = 0.4
        local outline = Drawing.new("Square"); outline.Visible = false; outline.Color = Color3.new(0, 0, 0); outline.Thickness = 2; outline.Filled = false; outline.Transparency = 1
        local healthBar = Drawing.new("Line"); healthBar.Visible = false; healthBar.Color = Color3.new(0, 1, 0); healthBar.Thickness = 2
        local healthText = Drawing.new("Text"); healthText.Visible = false; healthText.Color = Color3.new(1, 1, 1); healthText.Size = 14; healthText.Outline = true
        local nameText = Drawing.new("Text"); nameText.Visible = false; nameText.Color = Color3.new(1, 1, 1); nameText.Size = 16; nameText.Center = true; nameText.Outline = true
        Drawings[player] = {Box = box, Outline = outline, HealthBar = healthBar, HealthText = healthText, NameText = nameText}
    end

    local function RemoveESP(player)
        if Drawings[player] then for _, obj in pairs(Drawings[player]) do obj:Remove() end; Drawings[player] = nil end
    end

    local pAdded = Players.PlayerAdded:Connect(CreateESP)
    local pRemoving = Players.PlayerRemoving:Connect(RemoveESP)
    for _, player in pairs(Players:GetPlayers()) do if player ~= localPlayer then CreateESP(player) end end

    local function toggleFly()
        flying = not flying
        if not flying and bv then bv:Destroy(); bv = nil; if bg then bg:Destroy(); bg = nil end
            if localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local hrp = localPlayer.Character.HumanoidRootPart
                hrp.AssemblyLinearVelocity = Vector3.new(0,0,0); hrp.AssemblyAngularVelocity = Vector3.new(0,0,0)
                if localPlayer.Character:FindFirstChildOfClass("Humanoid") then localPlayer.Character:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Running) end
            end
        end
    end

    local autoClickLoop = task.spawn(function()
        while task.wait(0) do
            if not isRunning then break end
            if isEnabled and autoClickEnabled and not isLobbyVisible() then
                targetPlayer = getClosestPlayer()
                if targetPlayer then lockCameraToHead(); if typeof(mouse1click) == "function" then mouse1click() end end
            end
        end
    end)

    local noclipConn = RunService.Stepped:Connect(function()
        if not isRunning then return end
        if noclipEnabled and localPlayer.Character then
            for _, part in ipairs(localPlayer.Character:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = false end end
        end
    end)

    local heartbeatConn = RunService.Heartbeat:Connect(function()
        if not isRunning then return end
        local currentTime = tick()
        local isHoldingAuto = isLeftMouseDown and (currentTime - leftClickStartTime >= 0.6)
        if isEnabled and not isLobbyVisible() and isHoldingAuto and currentTime - lastAutoShot >= fireRate then
            targetPlayer = getClosestPlayer()
            if targetPlayer then
                lockCameraToHead(); if typeof(mouse1click) == "function" then mouse1click(); lastAutoShot = currentTime end
            end
        end
    end)

    local renderConn = RunService.RenderStepped:Connect(function()
        if not isRunning then return end
        if isEnabled and not isLobbyVisible() then screenTint.Visible = (getClosestPlayer() ~= nil) else screenTint.Visible = false end

        if ESPEnabled then
            for player, data in pairs(Drawings) do
                local char = player.Character
                if char and char:FindFirstChild("HumanoidRootPart") and char:FindFirstChild("Humanoid") then
                    local hrp, hum = char.HumanoidRootPart, char.Humanoid
                    local pos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                    if onScreen and hum.Health > 0 and not checkIsTeammate(player, hrp) then
                        local size = Vector2.new(2000 / pos.Z, 2500 / pos.Z)
                        local boxPos = Vector2.new(pos.X - size.X / 2, pos.Y - size.Y / 2)
                        data.Box.Size = size; data.Box.Position = boxPos; data.Box.Visible = true
                        data.Outline.Size = size; data.Outline.Position = boxPos; data.Outline.Visible = true
                        data.NameText.Position = Vector2.new(pos.X, boxPos.Y - 20); data.NameText.Text = player.Name; data.NameText.Visible = true
                        local barHeight = size.Y * (hum.Health / hum.MaxHealth)
                        data.HealthBar.From = Vector2.new(boxPos.X - 7, boxPos.Y + size.Y); data.HealthBar.To = Vector2.new(boxPos.X - 7, boxPos.Y + size.Y - barHeight); data.HealthBar.Visible = true
                        data.HealthText.Position = Vector2.new(boxPos.X - 45, boxPos.Y + size.Y - barHeight - 7); data.HealthText.Text = "hp: " .. math.floor(hum.Health); data.HealthText.Visible = true
                    else for _, obj in pairs(data) do obj.Visible = false end end
                else for _, obj in pairs(data) do obj.Visible = false end end
            end
        else for _, data in pairs(Drawings) do for _, obj in pairs(data) do obj.Visible = false end end end

        if flying and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local hrp = localPlayer.Character.HumanoidRootPart
            if not bv or bv.Parent ~= hrp then if bv then bv:Destroy() end; bv = Instance.new("BodyVelocity"); bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge); bv.Velocity = Vector3.zero; bv.Parent = hrp end
            if not bg or bg.Parent ~= hrp then if bg then bg:Destroy() end; bg = Instance.new("BodyGyro"); bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge); bg.CFrame = camera.CFrame; bg.Parent = hrp end
            local moveVector = Vector3.zero
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector = moveVector + camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector = moveVector - camera.CFrame.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector = moveVector - camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector = moveVector + camera.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveVector = moveVector + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveVector = moveVector - Vector3.new(0, 1, 0) end
            bg.CFrame = camera.CFrame
            if moveVector.Magnitude > 0 then bv.Velocity = moveVector.Unit * flySpeed else bv.Velocity = Vector3.zero end
        end
    end)

    local inputBeganConn = UserInputService.InputBegan:Connect(function(input, isProcessed)
        if not isRunning then return end
        if input.KeyCode == Enum.KeyCode.K and not isProcessed then isEnabled = not isEnabled; indicator.BackgroundColor3 = isEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        elseif input.KeyCode == Enum.KeyCode.J and not isProcessed then autoClickEnabled = not autoClickEnabled; autoClickIndicator.BackgroundColor3 = autoClickEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        elseif input.KeyCode == Enum.KeyCode.L and not isProcessed then noclipEnabled = not noclipEnabled; noclipIndicator.BackgroundColor3 = noclipEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
            if not noclipEnabled and localPlayer.Character then for _, part in ipairs(localPlayer.Character:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end end
        elseif input.KeyCode == Enum.KeyCode.P and not isProcessed then toggleFly()
        elseif input.KeyCode == Enum.KeyCode.O and not isProcessed then ESPEnabled = not ESPEnabled
        elseif not isProcessed and isEnabled and not isLobbyVisible() then
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                isLeftMouseDown = true; leftClickStartTime = tick(); targetPlayer = getClosestPlayer()
                if targetPlayer then lockCameraToHead() end
                if typeof(mouse1click) == "function" then mouse1click(); lastAutoShot = tick() end
            end
        end
    end)

    local inputEndedConn = UserInputService.InputEnded:Connect(function(input)
        if not isRunning then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then isLeftMouseDown = false end
    end)

    return function()
        isRunning = false; task.cancel(autoClickLoop); if pAdded then pAdded:Disconnect() end; if pRemoving then pRemoving:Disconnect() end; if noclipConn then noclipConn:Disconnect() end; if heartbeatConn then heartbeatConn:Disconnect() end; if renderConn then renderConn:Disconnect() end; if inputBeganConn then inputBeganConn:Disconnect() end; if inputEndedConn then inputEndedConn:Disconnect() end; if screenGui then screenGui:Destroy() end
        if flying then flying = false; if bv then bv:Destroy() end; if bg then bg:Destroy() end end
        if localPlayer.Character then
            for _, part in ipairs(localPlayer.Character:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end
            local hrp = localPlayer.Character:FindFirstChild("HumanoidRootPart"); local hum = localPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hrp then hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0); hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0) end
            if hum then hum:ChangeState(Enum.HumanoidStateType.Running) end
        end
        for player, _ in pairs(Drawings) do RemoveESP(player) end
        Drawings = {}
    end
end

-- ==========================================
-- SCRIPT 3: Orbit & Combat Script
-- ==========================================
local function startScript3()
    local isRunning = true
    local orbitEnabled = false
    local targetList = {}
    local currentTarget = nil
    local safeZonePos = nil

    local minOrbitRadius = 10
    local maxOrbitRadius = 20
    local orbitSpeed = 99999
    local orbitTime = 0

    local headOffset = Vector3.new(0, 0.5, 0)
    local usePrediction = true
    local projectileSpeed = 999999999
    local pingCompensation = 0

    local ESPEnabled = false
    local Drawings = {}

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CombatIndicator"
    screenGui.IgnoreGuiInset = true
    if syn and syn.protect_gui then syn.protect_gui(screenGui) end
    if gethui then screenGui.Parent = gethui() else screenGui.Parent = CoreGui end

    local indicator = Instance.new("Frame")
    indicator.Name = "OrbitCircle"
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

    local function checkIsTeammate(player, hrp)
        if player.Team ~= nil and localPlayer.Team ~= nil and player.Team == localPlayer.Team then return true end
        if hrp and hrp:FindFirstChild("TeammateLabel") ~= nil then return true end
        return false
    end

    local function isValidTarget(player)
        if player == localPlayer then return false end
        local char = player.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local head = char:FindFirstChild("Head")
        local hum = char:FindFirstChild("Humanoid")
        if not hrp or not head or not hum or hum.Health <= 0 then return false end
        if checkIsTeammate(player, hrp) then return false end
        return true
    end

    local function refreshTargetList()
        targetList = {}
        for _, player in ipairs(Players:GetPlayers()) do
            if isValidTarget(player) then table.insert(targetList, player) end
        end
    end

    local function lockCameraToHead(target)
        if target and target.Character and target.Character:FindFirstChild("Head") and target.Character:FindFirstChild("HumanoidRootPart") then
            local head = target.Character.Head
            local targetHRP = target.Character.HumanoidRootPart
            local cameraPosition = camera.CFrame.Position
            local aimPosition = head.Position + headOffset

            if usePrediction then
                local velocity = targetHRP.AssemblyLinearVelocity
                local distance = (aimPosition - cameraPosition).Magnitude
                local timeToHit = (distance / projectileSpeed) + pingCompensation
                aimPosition = aimPosition + (velocity * timeToHit)
            end

            camera.CFrame = CFrame.new(cameraPosition, aimPosition)
        end
    end

    local function isPositionSafe(pos)
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        
        local excludeList = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then table.insert(excludeList, p.Character) end
        end
        overlapParams.FilterDescendantsInstances = excludeList
        
        local parts = workspace:GetPartBoundsInRadius(pos, 3, overlapParams)
        for _, part in ipairs(parts) do
            if CollectionService:HasTag(part, "EntityHitbox") or CollectionService:HasTag(part, "Vortex") or CollectionService:HasTag(part, "Barrier") then
                return false
            end
            if part:FindFirstAncestor("HazardArea") or part:FindFirstAncestor("Hazards") or part:FindFirstAncestor("GrindingInRivles") or part:FindFirstAncestor("SpearTightrope") or part:FindFirstAncestor("SubspaceTripMineHitbox") or part:FindFirstAncestor("SubspaceTripmineHitbox") then 
                return false 
            end
            local name = string.lower(part.Name)
            if string.find(name, "hazard") or string.find(name, "kill") or string.find(name, "lava") or string.find(name, "damage") or string.find(name, "molotovanchor") or string.find(name, "coreprojectile") or string.find(name, "throwable") then
                return false
            end
        end
        return true
    end

    local function findSafeZone(origin)
        local overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Exclude
        
        local excludeList = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then table.insert(excludeList, p.Character) end
        end
        overlapParams.FilterDescendantsInstances = excludeList

        local random = Random.new()
        for i = 1, 150 do
            local offsetX = (random:NextNumber() * 600) - 300
            local offsetZ = (random:NextNumber() * 600) - 300
            local offsetY = (random:NextNumber() * 100) + 10 
            
            local testPos = origin + Vector3.new(offsetX, offsetY, offsetZ)
            
            if testPos.Y > workspace.FallenPartsDestroyHeight + 50 then
                local parts = workspace:GetPartBoundsInBox(CFrame.new(testPos), Vector3.new(12, 12, 12), overlapParams)
                if #parts == 0 then return testPos end
            end
        end
        return origin + Vector3.new(0, 50, 0)
    end

    local function CreateESP(player)
        local box = Drawing.new("Square"); box.Visible = false; box.Color = Color3.new(1, 0, 0); box.Thickness = 1; box.Filled = true; box.Transparency = 0.4
        local outline = Drawing.new("Square"); outline.Visible = false; outline.Color = Color3.new(0, 0, 0); outline.Thickness = 2; outline.Filled = false; outline.Transparency = 1
        local healthBar = Drawing.new("Line"); healthBar.Visible = false; healthBar.Color = Color3.new(0, 1, 0); healthBar.Thickness = 2
        local healthText = Drawing.new("Text"); healthText.Visible = false; healthText.Color = Color3.new(1, 1, 1); healthText.Size = 14; healthText.Center = false; healthText.Outline = true
        local nameText = Drawing.new("Text"); nameText.Visible = false; nameText.Color = Color3.new(1, 1, 1); nameText.Size = 16; nameText.Center = true; nameText.Outline = true
        Drawings[player] = { Box = box, Outline = outline, HealthBar = healthBar, HealthText = healthText, NameText = nameText }
    end

    local function RemoveESP(player)
        if Drawings[player] then for _, obj in pairs(Drawings[player]) do obj:Remove() end; Drawings[player] = nil end
    end

    local pAdded = Players.PlayerAdded:Connect(CreateESP)
    local pRemoving = Players.PlayerRemoving:Connect(RemoveESP)
    for _, player in pairs(Players:GetPlayers()) do if player ~= localPlayer then CreateESP(player) end end

    local stepConn = RunService.Stepped:Connect(function()
        if not isRunning then return end
        if orbitEnabled and localPlayer.Character then
            for _, part in ipairs(localPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = false end
            end
        end
    end)

    local renderConn = RunService.RenderStepped:Connect(function(dt)
        if not isRunning then return end

        if ESPEnabled then
            for player, data in pairs(Drawings) do
                local character = player.Character
                if character and character:FindFirstChild("HumanoidRootPart") and character:FindFirstChild("Humanoid") then
                    local hrp = character.HumanoidRootPart
                    local humanoid = character.Humanoid
                    local pos, onScreen = camera:WorldToViewportPoint(hrp.Position)
                    local isTeammate = checkIsTeammate(player, hrp)
                    
                    if onScreen and humanoid.Health > 0 and not isTeammate then
                        local size = Vector2.new(2000 / pos.Z, 2500 / pos.Z)
                        local boxPos = Vector2.new(pos.X - size.X / 2, pos.Y - size.Y / 2)
                        
                        data.Box.Size = size; data.Box.Position = boxPos; data.Box.Visible = true
                        data.Outline.Size = size; data.Outline.Position = boxPos; data.Outline.Visible = true
                        data.NameText.Position = Vector2.new(pos.X, boxPos.Y - 20); data.NameText.Text = player.Name; data.NameText.Visible = true
                        
                        local barHeight = size.Y * (humanoid.Health / humanoid.MaxHealth)
                        data.HealthBar.From = Vector2.new(boxPos.X - 7, boxPos.Y + size.Y); data.HealthBar.To = Vector2.new(boxPos.X - 7, boxPos.Y + size.Y - barHeight); data.HealthBar.Visible = true
                        data.HealthText.Position = Vector2.new(boxPos.X - 45, boxPos.Y + size.Y - barHeight - 7); data.HealthText.Text = "hp: " .. math.floor(humanoid.Health); data.HealthText.Visible = true
                    else
                        for _, obj in pairs(data) do obj.Visible = false end
                    end
                else
                    for _, obj in pairs(data) do obj.Visible = false end
                end
            end
        else
            for _, data in pairs(Drawings) do for _, obj in pairs(data) do obj.Visible = false end end
        end

        if orbitEnabled and not isLobbyVisible() then
            if not currentTarget or not isValidTarget(currentTarget) then
                refreshTargetList()
                currentTarget = targetList[1]
            end

            if currentTarget and currentTarget.Character and currentTarget.Character:FindFirstChild("HumanoidRootPart") and localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
                orbitTime = orbitTime + (dt * orbitSpeed)
                local targetHrp = currentTarget.Character.HumanoidRootPart
                local myHrp = localPlayer.Character.HumanoidRootPart

                local currentRadius = minOrbitRadius + ((math.sin(orbitTime * 0.5) + 1) / 2) * (maxOrbitRadius - minOrbitRadius)
                local targetPos = targetHrp.Position
                local targetLook = targetHrp.CFrame.LookVector
                
                local newPos = targetPos
                local validPositionFound = false
                local testAngle = orbitTime
                local angleIncrement = math.pi / 4

                for i = 1, 8 do
                    local offsetX = math.cos(testAngle) * currentRadius
                    local offsetZ = math.sin(testAngle) * currentRadius
                    local offsetY = math.sin(testAngle * 0.5) * (currentRadius * 0.15)
                    local desiredPos = targetPos + Vector3.new(offsetX, offsetY, offsetZ)
                    local dirFromTarget = (desiredPos - targetPos)
                    local isInFront = targetLook:Dot(dirFromTarget.Unit) > 0.1
                    
                    if not isInFront and isPositionSafe(desiredPos) then
                        newPos = desiredPos; validPositionFound = true; break
                    end
                    testAngle = testAngle + angleIncrement
                end

                if not validPositionFound then
                    if safeZonePos then newPos = safeZonePos else newPos = targetPos + Vector3.new(0, 15, 0) end
                end

                local spinX = orbitTime * 99999; local spinY = orbitTime * 99999; local spinZ = orbitTime * 99999
                myHrp.AssemblyLinearVelocity = Vector3.zero
                myHrp.AssemblyAngularVelocity = Vector3.zero 
                myHrp.CFrame = CFrame.new(newPos) * CFrame.Angles(spinX, spinY, spinZ)
                
                lockCameraToHead(currentTarget)
                if typeof(mouse1click) == "function" then mouse1click() end
            end
        end
    end)

    local inputConn = UserInputService.InputBegan:Connect(function(input, isProcessed)
        if not isRunning or isProcessed then return end

        if input.KeyCode == Enum.KeyCode.L then
            orbitEnabled = not orbitEnabled
            indicator.BackgroundColor3 = orbitEnabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
            
            if orbitEnabled then
                if localPlayer.Character and localPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    safeZonePos = findSafeZone(localPlayer.Character.HumanoidRootPart.Position)
                end
            else
                currentTarget = nil
                targetList = {}
                safeZonePos = nil
                if localPlayer.Character then
                    for _, part in ipairs(localPlayer.Character:GetDescendants()) do
                        if part:IsA("BasePart") then part.CanCollide = true end
                    end
                end
            end
        elseif input.KeyCode == Enum.KeyCode.O then
            ESPEnabled = not ESPEnabled
        end
        -- Note: Enum.KeyCode.U omitted here so the master switch handles total script destruction cleanly without clashing.
    end)

    return function()
        isRunning = false
        orbitEnabled = false
        if pAdded then pAdded:Disconnect() end
        if pRemoving then pRemoving:Disconnect() end
        if stepConn then stepConn:Disconnect() end
        if renderConn then renderConn:Disconnect() end
        if inputConn then inputConn:Disconnect() end
        if screenGui then screenGui:Destroy() end
        for player, _ in pairs(Drawings) do RemoveESP(player) end
        Drawings = {}
        if localPlayer.Character then
            for _, part in ipairs(localPlayer.Character:GetDescendants()) do
                if part:IsA("BasePart") then part.CanCollide = true end
            end
        end
    end
end

-- ==========================================
-- SCRIPT SWITCHER LOGIC
-- ==========================================
local function switchScript()
    if activeScriptCleanup then
        pcall(activeScriptCleanup)
        activeScriptCleanup = nil
    end

    forceDestroyOldGuis()

    currentScriptIndex = currentScriptIndex + 1
    if currentScriptIndex > 3 then
        currentScriptIndex = 1
    end

    if currentScriptIndex == 1 then
        textLabel.Text = "Position Combat Script Active"
        activeScriptCleanup = startScript1()
    elseif currentScriptIndex == 2 then
        textLabel.Text = "Silent Aim & Utility Script Active"
        activeScriptCleanup = startScript2()
    elseif currentScriptIndex == 3 then
        textLabel.Text = "Orbit Combat Script Active"
        activeScriptCleanup = startScript3()
    end
end

local masterInput = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.Y then
        switchScript()
    elseif input.KeyCode == Enum.KeyCode.U then
        if activeScriptCleanup then
            pcall(activeScriptCleanup)
            activeScriptCleanup = nil
        end
        forceDestroyOldGuis()
        if switcherGui then
            switcherGui:Destroy()
        end
    end
end)
table.insert(mainConnections, masterInput)

_G.TotalScriptCleanup = function()
    if activeScriptCleanup then
        pcall(activeScriptCleanup)
        activeScriptCleanup = nil
    end
    for _, conn in ipairs(mainConnections) do
        if conn then conn:Disconnect() end
    end
    forceDestroyOldGuis()
    if switcherGui then switcherGui:Destroy() end
end

switchScript()
