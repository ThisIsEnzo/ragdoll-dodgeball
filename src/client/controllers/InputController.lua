-- InputController: PC, mobile, gamepad. ÐšÐ»Ð¸ÐµÐ½Ñ‚ ÑˆÐ»Ñ‘Ñ‚ Ñ‚Ð¾Ð»ÑŒÐºÐ¾ Ð½Ð°Ð¼ÐµÑ€ÐµÐ½Ð¸Ñ.
-- Q Ð¾Ñ‚Ð¿Ñ€Ð°Ð²Ð»ÑÐµÑ‚ Ð²Ñ‹Ð±Ñ€Ð°Ð½Ð½Ñ‹Ð¹ Ð² Ð¼Ð°Ð³Ð°Ð·Ð¸Ð½Ðµ ÑƒÐ»ÑŒÑ‚.
-- Ð’ÐÐ–ÐÐž: if-Ð²Ñ‹Ñ€Ð°Ð¶ÐµÐ½Ð¸Ðµ Luau Ð½ÐµÐ»ÑŒÐ·Ñ Ð¿ÐµÑ€ÐµÐ´Ð°Ð²Ð°Ñ‚ÑŒ Ð°Ñ€Ð³ÑƒÐ¼ÐµÐ½Ñ‚Ð¾Ð¼ Ð²Ñ‹Ð·Ð¾Ð²Ð° Ð±ÐµÐ· ÑÐºÐ¾Ð±Ð¾Ðº,
-- Ð¿Ð¾ÑÑ‚Ð¾Ð¼Ñƒ ÑÐ½Ð°Ñ‡Ð°Ð»Ð° Ð¿Ñ€Ð¸ÑÐ²Ð°Ð¸Ð²Ð°ÐµÐ¼ Ð² Ð»Ð¾ÐºÐ°Ð»ÑŒÐ½ÑƒÑŽ Ð¿ÐµÑ€ÐµÐ¼ÐµÐ½Ð½ÑƒÑŽ.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local InputController = {}

local chargeStart = nil

local GAME_KEYS = {
	[Enum.KeyCode.F] = true,
	[Enum.KeyCode.LeftShift] = true,
	[Enum.KeyCode.Q] = true,
	[Enum.KeyCode.ButtonX] = true,
	[Enum.KeyCode.ButtonB] = true,
	[Enum.KeyCode.ButtonY] = true,
	[Enum.KeyCode.ButtonR2] = true,
}

local function cameraLook()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.LookVector
	end
	return Vector3.new(0, 0, -1)
end

local function aimDirection()
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, -1) end

	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	local pitch = math.asin(math.clamp(look.Y, -1, 1)) * CFG.Throw.PitchInfluence
	local angle = math.clamp(
		pitch + math.rad(CFG.Throw.LoftDeg),
		math.rad(CFG.Throw.MinAngleDeg),
		math.rad(CFG.Throw.MaxAngleDeg)
	)
	return (flat * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)).Unit
end

local function dodgeDirection()
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection.Unit
	end
	local look = cameraLook()
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.01 then
		return flat.Unit
	end
	return Vector3.new(0, 0, -1)
end

local function myRootPosition()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		return root.Position
	end
	return nil
end

function InputController.BeginCharge()
	if chargeStart then return end
	chargeStart = os.clock()
end

function InputController.ReleaseCharge()
	if not chargeStart then return end
	local charge = math.clamp(os.clock() - chargeStart, CFG.Throw.ChargeMin, CFG.Throw.ChargeMax)
	chargeStart = nil
	local remote = Net.Get("ThrowRequest")
	if remote then
		remote:FireServer(charge, aimDirection(), myRootPosition())
	end
end

function InputController.CancelCharge()
	chargeStart = nil
end

function InputController.GetCharge()
	if not chargeStart then return 0 end
	return math.clamp((os.clock() - chargeStart) / CFG.Throw.ChargeMax, 0, 1)
end

function InputController.IsCharging()
	return chargeStart ~= nil
end

function InputController.Catch()
	local remote = Net.Get("CatchRequest")
	if remote then
		remote:FireServer(cameraLook())
	end
end

function InputController.Dodge()
	local remote = Net.Get("DodgeRequest")
	if remote then
		remote:FireServer(dodgeDirection())
	end
end

function InputController.Ult()
	local remote = Net.Get("UltRequest")
	if not remote then return end
	local selected = Players.LocalPlayer:GetAttribute("SelectedUlt")
	local ultId = "Cannon"
	if typeof(selected) == "string" then
		ultId = selected
	end
	remote:FireServer(ultId)
end

function InputController.Rematch()
	local remote = Net.Get("RematchRequest")
	if remote then
		remote:FireServer()
	end
end

function InputController.IsTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function InputController.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		local key = input.KeyCode
		if processed and not GAME_KEYS[key] then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.BeginCharge()
		elseif key == Enum.KeyCode.F then
			InputController.Catch()
		elseif key == Enum.KeyCode.LeftShift then
			InputController.Dodge()
		elseif key == Enum.KeyCode.Q then
			InputController.Ult()
		elseif CFG.Mobile.GamepadEnabled then
			if key == Enum.KeyCode.ButtonR2 then
				InputController.BeginCharge()
			elseif key == Enum.KeyCode.ButtonX then
				InputController.Catch()
			elseif key == Enum.KeyCode.ButtonB then
				InputController.Dodge()
			elseif key == Enum.KeyCode.ButtonY then
				InputController.Ult()
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if not chargeStart then return end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1
			or kind == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonR2 then
			InputController.ReleaseCharge()
		end
	end)

	UserInputService.WindowFocusReleased:Connect(function()
		InputController.CancelCharge()
	end)

	RunService.Heartbeat:Connect(function()
		if chargeStart and os.clock() - chargeStart > CFG.Mobile.ChargeSafetySeconds then
			InputController.ReleaseCharge()
		end
	end)
end

function InputController.Start() end

return InputController