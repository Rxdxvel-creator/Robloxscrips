local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==========================================
-- GLOBALE EINSTELLUNGEN (Aimbot & ESP)
-- ==========================================
local AimbotEnabled = true
local AimbotFOV = 100

local ESP_ENABLED = true
local TEAM_CHECK = true
local MAX_STUCK_TIME = 1.5
local ESP_TOGGLE_KEY = Enum.KeyCode.RightAlt

local ESP = {}

-- Visualisierung des FOV (Kreis auf dem Bildschirm)
local FOVCircle = Drawing.new("Circle")
FOVCircle.Color = Color3.fromRGB(0, 120, 255)
FOVCircle.Thickness = 1
FOVCircle.NumSides = 64
FOVCircle.Filled = false
FOVCircle.Transparency = 0.5
FOVCircle.Visible = AimbotEnabled

-- Aktualisiert den FOV-Kreis jeden Frame
RunService.RenderStepped:Connect(function()
    if AimbotEnabled and FOVCircle then
        FOVCircle.Radius = AimbotFOV
        FOVCircle.Position = Camera.ViewportSize / 2
        FOVCircle.Visible = true
    else
        FOVCircle.Visible = false
    end
end)

-- Team-Check Funktion
local function areSameTeam(player1, player2)
    local success, areSameTeamFunc = pcall(function()
        return shared("AreSameTeam")
    end)
    if success and areSameTeamFunc then
        return areSameTeamFunc(player1, player2)
    end
    return player1.Team == player2.Team
end

-- ==========================================
-- AIMBOT LOGIK
-- ==========================================
local function getClosestHeadToCursor()
    if not AimbotEnabled then return nil end
    
    local cameraCFrame = Camera.CFrame
    local cameraPos = cameraCFrame.Position
    local bestHead = nil
    local bestScreenDistance = math.huge
    local maxScreenDistance = AimbotFOV

    for _, model in ipairs(Workspace:GetChildren()) do
        if not model:IsA("Model") then continue end
        local head = model:FindFirstChild("Head")
        if not (head and head:IsA("BasePart")) then continue end
        
        local character = model
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not (humanoid and humanoid.Health > 0) then continue end
        
        local player = Players:GetPlayerFromCharacter(character)
        if player and (player == LocalPlayer or areSameTeam(player, LocalPlayer)) then
            continue
        end
        
        local headPos = head.Position
        local screenPos, onScreen = Camera:WorldToScreenPoint(headPos)
        if not onScreen then continue end
        
        local screenCenter = Camera.ViewportSize / 2
        local screenDistance = (Vector2.new(screenPos.X, screenPos.Y) - screenCenter).Magnitude
        
        if screenDistance > maxScreenDistance then continue end
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Exclude
        raycastParams.FilterDescendantsInstances = { LocalPlayer.Character, Camera }
        
        local ray = Workspace:Raycast(cameraPos, headPos - cameraPos, raycastParams)
        if ray and ray.Instance:IsDescendantOf(character) then
            if screenDistance < bestScreenDistance then
                bestScreenDistance = screenDistance
                bestHead = head
            end
        end
    end
    return bestHead
end

-- Hitscan Hooking
local hitscanModule
local success, err = pcall(function()
    hitscanModule = require(LocalPlayer.PlayerScripts.Client.game.classes.Projectiles.HitscanProjectile)
end)

if not success then
    warn("HitscanProjectile module doesnt exist anymore:", err)
else
    local originalNew = hitscanModule.new
    hitscanModule.new = function(origin, velocity, magnetStrength, owner, uniqueId, weaponConfig, tracerConfig, tracerOffset)
        if AimbotEnabled and owner == LocalPlayer then
            local targetHead = getClosestHeadToCursor()
            if targetHead then
                local cameraPos = Camera.CFrame.Position
                local newDirection = (targetHead.Position - cameraPos).Unit
                local speed = velocity.Magnitude
                velocity = newDirection * speed
            end
        end
        return originalNew(origin, velocity, magnetStrength, owner, uniqueId, weaponConfig, tracerConfig, tracerOffset)
    end
end

-- ==========================================
-- ESP LOGIK
-- ==========================================
local function newDrawing(type, props)
	local obj = Drawing.new(type)
	for k,v in pairs(props) do
		obj[k] = v
	end
	return obj
end

local function hide(ui)
	ui.Box.Visible = false
	ui.Tracer.Visible = false
	ui.Health.Visible = false
	ui.Name.Visible = false
end

local function hideAll()
	for _,ui in pairs(ESP) do
		hide(ui)
	end
end

local function createESP(player)
	if player == LocalPlayer then return end
	if ESP[player] then return end
	
	ESP[player] = {
		Player = player,
		Box = newDrawing("Square", { Thickness = 1, Filled = false, Color = Color3.new(1,1,1), Visible = false }),
		Tracer = newDrawing("Line", { Thickness = 1, Color = Color3.new(1,1,1), Visible = false }),
		Health = newDrawing("Line", { Thickness = 3, Visible = false }),
		Name = newDrawing("Text", { Size = 13, Center = true, Outline = true, Font = 2, Visible = false }),
		LastPosition = nil,
		StuckTime = 0
	}
end

for _,player in ipairs(Players:GetPlayers()) do createESP(player) end
Players.PlayerAdded:Connect(createESP)

local function findCharacter(player)
	for _,model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") and model.Name == player.Name then
			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if hum and root then return model, hum, root end
		end
	end
	return nil
end

local function getBox(character)
	local cf, size = character:GetBoundingBox()
	local top = cf.Position + Vector3.new(0, size.Y/2, 0)
	local bottom = cf.Position - Vector3.new(0, size.Y/2, 0)

	local topPos, vis1 = Camera:WorldToViewportPoint(top)
	local bottomPos, vis2 = Camera:WorldToViewportPoint(bottom)

	if not vis1 or not vis2 then return nil end

	local height = math.abs(topPos.Y - bottomPos.Y)
	local width = height / 2
	return Vector2.new(topPos.X - width/2, topPos.Y), width, height
end

RunService.RenderStepped:Connect(function(dt)
	if not ESP_ENABLED then return end
	
	for player,ui in pairs(ESP) do
		if TEAM_CHECK and areSameTeam(player, LocalPlayer) then
			hide(ui)
			continue
		end
		
		local character, humanoid, root = findCharacter(player)
		if not character or not humanoid or humanoid.Health <= 0 then
			hide(ui)
			ui.LastPosition = nil
			ui.StuckTime = 0
			continue
		end
		
		local pos, width, height = getBox(character)
		if not pos then
			hide(ui)
			ui.LastPosition = nil
			ui.StuckTime = 0
			continue
		end
		
		if ui.LastPosition then
			if (ui.LastPosition - pos).Magnitude < 1 then
				ui.StuckTime += dt
			else
				ui.StuckTime = 0
			end
			if ui.StuckTime >= MAX_STUCK_TIME then
				hide(ui)
				ui.LastPosition = nil
				ui.StuckTime = 0
				continue
			end
		end
		
		ui.LastPosition = pos
		
		-- BOX
		ui.Box.Size = Vector2.new(width, height)
		ui.Box.Position = pos
		ui.Box.Visible = true
		
		-- HEALTH
		local hp = humanoid.Health / humanoid.MaxHealth
		local healthHeight = height * hp
		ui.Health.From = Vector2.new(pos.X - 5, pos.Y + height)
		ui.Health.To = Vector2.new(pos.X - 5, pos.Y + height - healthHeight)
		ui.Health.Color = Color3.fromRGB(255 - (255*hp), 255*hp, 0)
		ui.Health.Visible = true
		
		-- TRACER
		ui.Tracer.From = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y)
		ui.Tracer.To = Vector2.new(pos.X + width/2, pos.Y)
		ui.Tracer.Visible = true
		
		-- NAME + DISTANCE
		local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		if myRoot then
			local dist = (myRoot.Position - root.Position).Magnitude
			ui.Name.Text = player.Name .. " [" .. math.floor(dist) .. "m]"
		else
			ui.Name.Text = player.Name
		end
		ui.Name.Position = Vector2.new(pos.X + width/2, pos.Y - 15)
		ui.Name.Visible = true
	end
end)

-- ==========================================
-- UI ERSTELLUNG (Combat Arena SA)
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CombatArenaSA_UI"
ScreenGui.ResetOnSpawn = false
local uiParent = pcall(function() return CoreGui end) and CoreGui or LocalPlayer:WaitForChild("PlayerGui")
ScreenGui.Parent = uiParent

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 240) -- Höhe leicht vergrößert für das ESP Feature
MainFrame.Position = UDim2.new(0.5, -160, 0.4, -120)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, 0, 0, 40)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Combat Arena SA"
TitleLabel.TextColor3 = Color3.fromRGB(0, 150, 255)
TitleLabel.TextSize = 20
TitleLabel.Font = Enum.Font.SourceSansBold
TitleLabel.Parent = MainFrame

local Line = Instance.new("Frame")
Line.Size = UDim2.new(0, 280, 0, 1)
Line.Position = UDim2.new(0.5, -140, 0, 40)
Line.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
Line.BorderSizePixel = 0
Line.Parent = MainFrame

--- 1. AIMBOT TOGGLE ---
local ToggleLabel = Instance.new("TextLabel")
ToggleLabel.Size = UDim2.new(0, 150, 0, 30)
ToggleLabel.Position = UDim2.new(0, 20, 0, 50)
ToggleLabel.BackgroundTransparency = 1
ToggleLabel.Text = "Silent Aim:"
ToggleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleLabel.TextSize = 16
ToggleLabel.TextXAlignment = Enum.TextXAlignment.Left
ToggleLabel.Font = Enum.Font.SourceSans
ToggleLabel.Parent = MainFrame

local ToggleButton = Instance.new("TextButton")
ToggleButton.Size = UDim2.new(0, 50, 0, 24)
ToggleButton.Position = UDim2.new(1, -70, 0, 53)
ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
ToggleButton.Text = "ON"
ToggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleButton.TextSize = 12
ToggleButton.Font = Enum.Font.SourceSansBold
ToggleButton.Parent = MainFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 6)
ToggleCorner.Parent = ToggleButton

--- 2. ESP TOGGLE ---
local ESPLabel = Instance.new("TextLabel")
ESPLabel.Size = UDim2.new(0, 150, 0, 30)
ESPLabel.Position = UDim2.new(0, 20, 0, 90)
ESPLabel.BackgroundTransparency = 1
ESPLabel.Text = "Player ESP [RightAlt]:"
ESPLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
ESPLabel.TextSize = 16
ESPLabel.TextXAlignment = Enum.TextXAlignment.Left
ESPLabel.Font = Enum.Font.SourceSans
ESPLabel.Parent = MainFrame

local ESPButton = Instance.new("TextButton")
ESPButton.Size = UDim2.new(0, 50, 0, 24)
ESPButton.Position = UDim2.new(1, -70, 0, 93)
ESPButton.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
ESPButton.Text = "ON"
ESPButton.TextColor3 = Color3.fromRGB(255, 255, 255)
ESPButton.TextSize = 12
ESPButton.Font = Enum.Font.SourceSansBold
ESPButton.Parent = MainFrame

local ESPCorner = Instance.new("UICorner")
ESPCorner.CornerRadius = UDim.new(0, 6)
ESPCorner.Parent = ESPButton

--- 3. SLIDER (FOV RADIUS) ---
local SliderLabel = Instance.new("TextLabel")
SliderLabel.Size = UDim2.new(0, 150, 0, 25)
SliderLabel.Position = UDim2.new(0, 20, 0, 135)
SliderLabel.BackgroundTransparency = 1
SliderLabel.Text = "FOV Radius:"
SliderLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
SliderLabel.TextSize = 16
SliderLabel.TextXAlignment = Enum.TextXAlignment.Left
SliderLabel.Font = Enum.Font.SourceSans
SliderLabel.Parent = MainFrame

local ValueLabel = Instance.new("TextLabel")
ValueLabel.Size = UDim2.new(0, 50, 0, 25)
ValueLabel.Position = UDim2.new(1, -70, 0, 135)
ValueLabel.BackgroundTransparency = 1
ValueLabel.Text = tostring(AimbotFOV)
ValueLabel.TextColor3 = Color3.fromRGB(0, 150, 255)
ValueLabel.TextSize = 16
ValueLabel.TextXAlignment = Enum.TextXAlignment.Right
ValueLabel.Font = Enum.Font.SourceSansBold
ValueLabel.Parent = MainFrame

local SliderBackground = Instance.new("Frame")
SliderBackground.Size = UDim2.new(0, 280, 0, 6)
SliderBackground.Position = UDim2.new(0.5, -140, 0, 175)
SliderBackground.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
SliderBackground.BorderSizePixel = 0
SliderBackground.Parent = MainFrame

local SliderCorner = Instance.new("UICorner")
SliderCorner.CornerRadius = UDim.new(1, 0)
SliderCorner.Parent = SliderBackground

local SliderFill = Instance.new("Frame")
SliderFill.Size = UDim2.new(0, 51, 1, 0)
SliderFill.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
SliderFill.BorderSizePixel = 0
SliderFill.Parent = SliderBackground

local FillCorner = Instance.new("UICorner")
FillCorner.CornerRadius = UDim.new(1, 0)
FillCorner.Parent = SliderFill

local SliderButton = Instance.new("TextButton")
SliderButton.Size = UDim2.new(0, 14, 0, 14)
SliderButton.Position = UDim2.new(0, 45, 0.5, -7)
SliderButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
SliderButton.Text = ""
SliderButton.BorderSizePixel = 0
SliderButton.Parent = SliderBackground

local ButtonCorner = Instance.new("UICorner")
ButtonCorner.CornerRadius = UDim.new(1, 0)
ButtonCorner.Parent = SliderButton

-- Infotext ganz unten
local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size = UDim2.new(1, 0, 0, 20)
InfoLabel.Position = UDim2.new(0, 0, 1, -22)
InfoLabel.BackgroundTransparency = 1
InfoLabel.Text = "Menü schließen/öffnen mit [P]"
InfoLabel.TextColor3 = Color3.fromRGB(120, 120, 120)
InfoLabel.TextSize = 12
InfoLabel.Font = Enum.Font.SourceSansItalic
InfoLabel.Parent = MainFrame

-- ==========================================
-- INTERAKTIONEN & BUTTON LOGIK
-- ==========================================

-- Aimbot Toggle Funktion
local function toggleAimbot()
    AimbotEnabled = not AimbotEnabled
    if AimbotEnabled then
        ToggleButton.Text = "ON"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    else
        ToggleButton.Text = "OFF"
        ToggleButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    end
end
ToggleButton.MouseButton1Click:Connect(toggleAimbot)

-- ESP Toggle Funktion
local function updateESPButton()
    if ESP_ENABLED then
        ESPButton.Text = "ON"
        ESPButton.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    else
        ESPButton.Text = "OFF"
        ESPButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
        hideAll()
    end
end

ESPButton.MouseButton1Click:Connect(function()
    ESP_ENABLED = not ESP_ENABLED
    updateESPButton()
end)

-- Slider Logik
local minFOV = 10
local maxFOV = 500
local isDragging = false

local function updateSlider(input)
    local sliderWidth = SliderBackground.AbsoluteSize.X
    local mouseX = input.Position.X - SliderBackground.AbsolutePosition.X
    local percentage = math.clamp(mouseX / sliderWidth, 0, 1)
    
    AimbotFOV = math.floor(minFOV + (percentage * (maxFOV - minFOV)))
    
    SliderButton.Position = UDim2.new(percentage, -7, 0.5, -7)
    SliderFill.Size = UDim2.new(percentage, 0, 1, 0)
    ValueLabel.Text = tostring(AimbotFOV)
end

SliderButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = true
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        isDragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        updateSlider(input)
    end
end)

-- ==========================================
-- HOTKEYS (P & RightAlt)
-- ==========================================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- Taste P toggelt das Menüfenster
    if input.KeyCode == Enum.KeyCode.P then
        MainFrame.Visible = not MainFrame.Visible
        if not MainFrame.Visible then
            FOVCircle.Visible = false
        else
            FOVCircle.Visible = AimbotEnabled
        end
        
    -- Taste RightAlt toggelt das ESP direkt
    elseif input.KeyCode == ESP_TOGGLE_KEY then
        ESP_ENABLED = not ESP_ENABLED
        updateESPButton()
    end
end)
