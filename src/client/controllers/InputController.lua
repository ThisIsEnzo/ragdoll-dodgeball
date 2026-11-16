-- InputController: PC и mobile. Клиент шлёт только намерения.

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CFG = require(Shared:WaitForChild("BalanceConfig"))
local Net = require(Shared:WaitForChild("Net"))

local InputController = {}
local chargeStart: number? = nil

local function cameraDirection(): Vector3
	local camera = workspace.CurrentCamera
	return camera and camera.CFrame.LookVector or Vector3.new(0, 0, -1)
end

local function moveDirection(): Vector3
	local camera = workspace.CurrentCamera
	if not camera then return Vector3.new(0, 0, -1) end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
end

function InputController.BeginCharge()
	chargeStart = os.clock()
end

function InputController.ReleaseCharge()
	if not chargeStart then return end
	local charge = math.clamp(os.clock() - chargeStart, CFG.Throw.ChargeMin, CFG.Throw.ChargeMax)
	chargeStart = nil
	local remote = Net.Get("ThrowRequest")
	if remote then remote:FireServer(charge, cameraDirection()) end
end

function InputController.GetCharge(): number
	if not chargeStart then return 0 end
	return math.clamp((os.clock() - chargeStart) / CFG.Throw.ChargeMax, 0, 1)
end

function InputController.Catch()
	local remote = Net.Get("CatchRequest")
	if remote then remote:FireServer() end
end

function InputController.Dodge()
	local remote = Net.Get("DodgeRequest")
	if remote then remote:FireServer(moveDirection()) end
end

function InputController.Ult()
	local remote = Net.Get("UltRequest")
	if remote then remote:FireServer("Cannon") end
end

function InputController.Rematch()
	local remote = Net.Get("RematchRequest")
	if remote then remote:FireServer() end
end

function InputController.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.BeginCharge()
		elseif input.KeyCode == Enum.KeyCode.F then
			InputController.Catch()
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			InputController.Dodge()
		elseif input.KeyCode == Enum.KeyCode.Q then
			InputController.Ult()
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			InputController.ReleaseCharge()
		end
	end)
end

function InputController.Start() end

return InputController
