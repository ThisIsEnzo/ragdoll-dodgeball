-- PanelFit: scale fixed-size panels down to fit the current viewport.
--
-- Panels are authored at fixed sizes. On mobile landscape, their action buttons
-- can fall below the viewport. Each eligible panel is placed inside a transparent
-- full-screen wrapper carrying a UIScale; the controller's own panel UIScale
-- remains untouched, preserving its open tween.
--
-- This is a viewport-fit pass only. It does not redesign panel contents or
-- introduce scrolling. Panel identification is deliberately structural.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local WRAP_PREFIX = "PanelFit_"
local MIN_WIDTH = 300
local MIN_HEIGHT = 180
local MARGIN_X = 24
local MARGIN_Y = 24

local wrapped = {}
local entries = {}

local function viewportSize()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function isPanel(instance)
	if not instance:IsA("Frame") or wrapped[instance] then
		return false
	end

	local parent = instance.Parent
	if not parent or not parent:IsA("ScreenGui") then
		return false
	end
	if string.sub(parent.Name, 1, 2) ~= "RD" then
		return false
	end

	local anchor = instance.AnchorPoint
	if math.abs(anchor.X - 0.5) > 0.01 or math.abs(anchor.Y - 0.5) > 0.01 then
		return false
	end

	local size = instance.Size
	if size.X.Scale > 0.9 or size.Y.Scale > 0.9 then
		return false
	end
	if size.X.Offset < MIN_WIDTH or size.Y.Offset < MIN_HEIGHT then
		return false
	end

	return true
end

local function wrap(panel)
	local screenGui = panel.Parent
	if not screenGui then
		return
	end

	local wrapper = Instance.new("Frame")
	wrapper.Name = WRAP_PREFIX .. panel.Name
	wrapper.BackgroundTransparency = 1
	wrapper.BorderSizePixel = 0
	wrapper.Active = false
	wrapper.ClipsDescendants = false
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.Position = UDim2.fromScale(0.5, 0.5)
	wrapper.AnchorPoint = Vector2.new(0.5, 0.5)
	wrapper.ZIndex = panel.ZIndex
	wrapper.Parent = screenGui

	local fitScale = Instance.new("UIScale")
	fitScale.Name = "FitScale"
	fitScale.Scale = 1
	fitScale.Parent = wrapper

	panel.Parent = wrapper
	wrapped[panel] = true

	table.insert(entries, {
		panel = panel,
		wrapper = wrapper,
		scale = fitScale,
		width = panel.Size.X.Offset,
		height = panel.Size.Y.Offset,
	})
end

local function apply()
	local viewport = viewportSize()
	local availableWidth = math.max(120, viewport.X - MARGIN_X)
	local availableHeight = math.max(120, viewport.Y - MARGIN_Y)

	for index = #entries, 1, -1 do
		local entry = entries[index]
		if not entry.panel.Parent or not entry.wrapper.Parent then
			table.remove(entries, index)
		else
			local fitWidth = availableWidth / math.max(entry.width, 1)
			local fitHeight = availableHeight / math.max(entry.height, 1)
			local factor = math.min(1, fitWidth, fitHeight)
			entry.scale.Scale = factor
		end
	end
end

local function sweep()
	local found = false
	for _, screenGui in ipairs(playerGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and string.sub(screenGui.Name, 1, 2) == "RD" then
			for _, child in ipairs(screenGui:GetChildren()) do
				if isPanel(child) then
					wrap(child)
					found = true
				end
				-- Panels that were already wrapped are not direct ScreenGui
				-- children anymore, so this pass won't wrap them twice.
			end
		end
	end
	if found then
		apply()
	end
end

playerGui.DescendantAdded:Connect(function(instance)
	if instance:IsA("Frame") then
		task.defer(function()
			if instance.Parent and isPanel(instance) then
				wrap(instance)
				apply()
			end
		end)
	end
end)

local cameraConnection
local function bindCamera(camera)
	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
	if camera then
		cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(apply)
	end
	apply()
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	bindCamera(workspace.CurrentCamera)
end)
bindCamera(workspace.CurrentCamera)

UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(apply)

task.spawn(function()
	for _ = 1, 30 do
		sweep()
		task.wait(0.5)
	end
	while true do
		task.wait(5)
		sweep()
	end
end)

sweep()
apply()
print("[PanelFit] panels constrained to viewport")
