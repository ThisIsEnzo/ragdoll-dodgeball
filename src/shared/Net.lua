-- Net v0.6.0: добавлены FtueState (сервер -> клиент) и UiEvent (клиент -> сервер, только UI).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

local RELIABLE = {
	"ThrowRequest", "CatchRequest", "DodgeRequest", "UltRequest",
	"QueueJoin", "PartyInvite", "ShopBuy", "QuestClaim",
	"MatchState", "PingRequest", "RematchRequest", "HypeState",
	"ProfileState", "QuestState", "LevelUp",
	"FtueState", "UiEvent",
}
local UNRELIABLE = { "FXEvent" }

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then return folder end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			local created = Instance.new("Folder")
			created.Name = "Remotes"
			created.Parent = ReplicatedStorage
			folder = created
		end
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder :: Folder
end

function Net.Init()
	assert(RunService:IsServer(), "Net.Init is server-only")
	local parent = getFolder()
	for _, name in ipairs(RELIABLE) do
		if not parent:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = parent
		end
	end
	for _, name in ipairs(UNRELIABLE) do
		if not parent:FindFirstChild(name) then
			local r = Instance.new("UnreliableRemoteEvent")
			r.Name = name
			r.Parent = parent
		end
	end
end

function Net.Get(name: string)
	local parent = getFolder()
	if RunService:IsServer() then return parent:FindFirstChild(name) end
	return parent:WaitForChild(name, 30)
end

function Net.On(name: string, handler: (...any) -> ())
	local remote = Net.Get(name)
	assert(remote, "Unknown remote: " .. name)
	return remote.OnServerEvent:Connect(handler)
end

function Net.FireClient(name: string, player: Player, ...: any)
	local r = Net.Get(name)
	if r then r:FireClient(player, ...) end
end

function Net.FireAll(name: string, ...: any)
	local r = Net.Get(name)
	if r then r:FireAllClients(...) end
end

return Net
