-- CarryController: мяч в руке как локальный визуал, приклеенный к телу в RenderStepped.
-- Для своего персонажа позиция известна мгновенно -> отставание ноль.
-- Для чужих визуал наследует уже интерполированное тело -> относительного отставания тоже нет.
-- Визуал живёт только на клиенте: Anchored, не коллидирует, не реплицируется, не влияет на геймплей.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local CarryController = {}

local folder: Folder? = nil
local visuals: { [Model]: BasePart } = {}
local connections: { [Model]: RBXScriptConnection } = {}

local function destroyVisual(character: Model)
	local visual = visuals[character]
	if visual then
		visual:Destroy()
		visuals[character] = nil
	end
end

local function createVisual(character: Model)
	if visuals[character] then return end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not folder then return end

	local ball = Instance.new("Part")
	ball.Name = "CarriedBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * CFG.Ball.Size
	ball.Color = Color3.fromRGB(255, 197, 61)
	ball.Material = Enum.Material.SmoothPlastic
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanTouch = false
	ball.CanQuery = false
	ball.CastShadow = false
	ball.CFrame = root.CFrame * CFrame.new(CFG.Ball.CarryOffset)
	ball.Parent = folder

	if CFG.Carry.ShowGlow then
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 197, 61)
		glow.Brightness = CFG.Carry.GlowBrightness
		glow.Range = CFG.Carry.GlowRange
		glow.Parent = ball
	end

	visuals[character] = ball
end

local function sync(character: Model)
	if character:GetAttribute("Carrying") then
		createVisual(character)
	else
		destroyVisual(character)
	end
end

local function bind(character: Instance)
	if not character:IsA("Model") or connections[character] then return end

	connections[character] = character:GetAttributeChangedSignal("Carrying"):Connect(function()
		sync(character)
	end)
	sync(character)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			destroyVisual(character)
			local conn = connections[character]
			if conn then
				conn:Disconnect()
				connections[character] = nil
			end
		end
	end)
end

function CarryController.Init()
	local existing = workspace:FindFirstChild("RDCarryVisuals")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name = "RDCarryVisuals"
		created.Parent = workspace
		folder = created
	end
end

function CarryController.Start()
	for _, character in ipairs(CollectionService:GetTagged("DodgeballActor")) do
		bind(character)
	end
	CollectionService:GetInstanceAddedSignal("DodgeballActor"):Connect(bind)

	-- Приклейка после апдейта персонажа, до камеры. Без lerp: любое сглаживание вернёт отставание.
	RunService:BindToRenderStep("RDCarry", Enum.RenderPriority.Character.Value + 1, function()
		for character, visual in pairs(visuals) do
			if not character.Parent or not visual.Parent then
				destroyVisual(character)
			else
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					visual.CFrame = root.CFrame * CFrame.new(CFG.Ball.CarryOffset)
				else
					destroyVisual(character)
				end
			end
		end
	end)
end

return CarryController
