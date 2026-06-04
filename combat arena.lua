local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- ==========================================
-- GLOBALE EINSTELLUNGEN
-- ==========================================
local AimbotEnabled = true
local AimbotFOV = 100
local Smoothness = 0.1 -- Standardwert
local AimKey = Enum.UserInputType.MouseButton2 -- Rechtsklick zum Aimen

local ESP_ENABLED = true
local TEAM_CHECK = true
local MAX_STUCK_TIME = 1.5
local ESP_TOGGLE_KEY = Enum.KeyCode.RightAlt

local ESP = {}
local IsAiming = false

-- FOV Kreis
local FOVCircle = Drawing.new("Circle")
FOVCircle.Color = Color3.fromRGB(0, 120, 255)
FOVCircle.Thickness = 1
FOVCircle.NumSides = 64
FOVCircle.Transparency = 0.5
FOVCircle.Visible = AimbotEnabled

RunService.RenderStepped:Connect(function()
    if AimbotEnabled and FOVCircle then
        FOVCircle.Radius = AimbotFOV
        FOVCircle.Position = Camera.ViewportSize / 2
        FOVCircle.Visible = MainFrame.Visible or AimbotEnabled -- Sichtbar wenn Menü offen oder Aim an
    else
        FOVCircle.Visible = false
    end
end)

-- Team-Check
local function areSameTeam(player1, player2)
    local success, areSameTeamFunc = pcall(function() return shared("AreSameTeam") end)
    if success and areSameTeamFunc then return areSameTeamFunc(player1, player2) end
    return player1.Team == player2.Team
end

-- ==========================================
-- AIMBOT LOGIK
-- ==========================================
local function getClosestHeadToCursor()
    if not AimbotEnabled then return nil end
    local cameraPos = Camera.CFrame.Position
    local bestHead = nil
    local bestScreenDistance = math.huge

    for _, model in ipairs(Workspace:GetChildren()) do
        if not model:IsA("Model") then continue end
        local head = model:FindFirstChild("Head")
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if not (head and humanoid and humanoid.Health > 0) then continue end
        
        local player = Players:GetPlayerFromCharacter(model)
        if player and (player == LocalPlayer or areSameTeam(player, LocalPlayer)) then continue end
        
        local screenPos, onScreen = Camera:WorldToScreenPoint(head.Position)
        if not onScreen then continue end
        
        local screenDistance = (Vector2.new(screenPos.X, screenPos.Y) - (Camera.ViewportSize / 2)).Magnitude
        if screenDistance > AimbotFOV then continue end
        
        local ray = Workspace:Raycast(cameraPos, head.Position - cameraPos, RaycastParams.new())
        if screenDistance < bestScreenDistance then
            bestScreenDistance = screenDistance
            bestHead = head
        end
    end
    return bestHead
end

-- Fallback Aim-Logik
UserInputService.InputBegan:Connect(function(input) if input.UserInputType == AimKey then IsAiming = true end end)
UserInputService.InputEnded:Connect(function(input) if input.UserInputType == AimKey then IsAiming = false end end)

local hitscanModule
pcall(function() hitscanModule = require(LocalPlayer.PlayerScripts.Client.game.classes.Projectiles.HitscanProjectile) end)

if hitscanModule then
    local originalNew = hitscanModule.new
    hitscanModule.new = function(origin, velocity, ...)
        if AimbotEnabled and getClosestHeadToCursor() then
            local target = getClosestHeadToCursor()
            velocity = (target.Position - Camera.CFrame.Position).Unit * velocity.Magnitude
        end
        return originalNew(origin, velocity, ...)
    end
end

RunService.RenderStepped:Connect(function()
    if AimbotEnabled and IsAiming then
        local target = getClosestHeadToCursor()
        if target then
            Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position, target.Position), Smoothness)
        end
    end
end)

-- ==========================================
-- UI ERSTELLUNG
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CombatArena_Pro"
ScreenGui.Parent = pcall(function() return CoreGui end) and CoreGui or LocalPlayer.PlayerGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 310) -- Höhe vergrößert
MainFrame.Position = UDim2.new(0.5, -160, 0.4, -155)
MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Text = "Combat Arena SA | V2"
Title.TextColor3 = Color3.fromRGB(0, 150, 255)
Title.TextSize = 18
Title.Font = Enum.Font.SourceSansBold
Title.BackgroundTransparency = 1
Title.Parent = MainFrame

-- Helper Funktion für Slider
local function createSlider(name, pos, min, max, default)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 150, 0, 20)
    label.Position = pos
    label.Text = name .. ": " .. default
    label.TextColor3 = Color3.new(1,1,1)
    label.BackgroundTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = MainFrame

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(0, 280, 0, 6)
    bg.Position = pos + UDim2.new(0, 0, 0, 25)
    bg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    bg.Parent = MainFrame

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default-min)/(max-min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
    fill.BorderSizePixel = 0
    fill.Parent = bg

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 12, 0, 12)
    btn.Position = UDim2.new((default-min)/(max-min), -6, 0.5, -6)
    btn.Text = ""
    btn.Parent = bg

    local dragging = false
    local function update()
        local percent = math.clamp((UserInputService:GetMouseLocation().X - bg.AbsolutePosition.X) / bg.AbsoluteSize.X, 0, 1)
        local val = min + (max - min) * percent
        val = math.floor(val * 100) / 100 -- 2 Dezimalstellen
        fill.Size = UDim2.new(percent, 0, 1, 0)
        btn.Position = UDim2.new(percent, -6, 0.5, -6)
        label.Text = name .. ": " .. val
        return val
    end

    btn.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end end)
    UserInputService.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end end)
    RunService.Heartbeat:Connect(function() if dragging then 
        local v = update()
        if name == "FOV" then AimbotFOV = v elseif name == "Smoothness" then Smoothness = v end
