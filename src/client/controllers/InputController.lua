-- InputController v0.9.0: прицел больше не берёт сырой наклон камеры.
--
-- Камера в третьем лице смотрит вниз. Сырой LookVector отправлял мяч в пол в паре метров.
-- Теперь: горизонталь камеры + фиксированный лофт, влияние питча ослаблено.
-- Рывок идёт по джойстику, заряд отпускается глобально, геймпад поддержан.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local InputController = {}

local chargeStart: number? = nil

local function aimDirection(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, -1) end

	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	flat = flat.Unit

	local pitch = math.asin(math.clamp(look.Y, -1, 1)) * CFG.Throw.PitchInfluence
	local angle = math.clamp(
		pitch + math.rad(CFG.Throw.LoftDeg),
		math.rad(CFG.Throw.MinAngleDeg),
		math.rad(CFG.Throw.MaxAngleDeg)
	)

	return (flat * math.cos(angle) + Vector3.new(0, math.sin(angle), 0)).Unit
end

local function dodgeDirection(): Vector3
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		return humanoid.MoveDirection.Unit
	end
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, -1) end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

local function myRootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root and root.Position or nil
end

function InputController.BeginCharge(input: InputObject?)
	if chargeStart then return end
	chargeStart = os.clock()
end

function InputController.ReleaseCharge()
	if not chargeStart then return end
	local charge = math.clamp(os.clock() - chargeStart, CFG.Throw.ChargeMin, CFG.Throw.ChargeMax)
	chargeStart = nil
	local remote = Net.Get("ThrowRequest")
	if remote then remote:FireServer(charge, aimDirection(), myRootPosition()) end
end

function InputController.CancelCharge()
	chargeStart = nil
end

function InputController.GetCharge(): number
	if not chargeStart then return 0 end
	return math.clamp((os.clock() - chargeStart) / CFG.Throw.ChargeMax, 0, 1)
end

function InputController.IsCharging(): boolean
	return chargeStart ~= nil
end

function InputController.Catch()
	local remote = Net.Get("CatchRequest")
	if remote then remote:FireServer() end
end

function InputController.Dodge()
	local remote = Net.Get("DodgeRequest")
	if remote then remote:FireServer(dodgeDirection()) end
end

function InputController.Ult()
	local remote = Net.Get("UltRequest")
	if remote then remote:FireServer("Cannon") end
end

function InputController.Rematch()
	local remote = Net.Get("RematchRequest")
	if remote then remote:FireServer() end
end

function InputController.IsTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function InputController.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		local key = input.KeyCode

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.BeginCharge(input)
		elseif key == Enum.KeyCode.F then
			InputController.Catch()
		elseif key == Enum.KeyCode.LeftShift then
			InputController.Dodge()
		elseif key == Enum.KeyCode.Q then
			InputController.Ult()
		elseif CFG.Mobile.GamepadEnabled then
			if key == Enum.KeyCode.ButtonR2 then
				InputController.BeginCharge(input)
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
