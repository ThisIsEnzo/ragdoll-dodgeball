-- Collision: единая матрица столкновений. Регистрируется идемпотентно.
-- Ключевое решение: мяч НЕ сталкивается с игроками. Попадания считаются sweep-ом,
-- откат полностью скриптовый. Физика больше не может ни таранить, ни подбрасывать.

local PhysicsService = game:GetService("PhysicsService")

local Collision = {}

local GROUPS = { "Players", "Ragdolls", "Balls", "HeldBalls", "Arena" }

local RULES = {
	{ "Players", "Players", true },
	{ "Players", "Arena", true },
	{ "Players", "Default", true },

	{ "Ragdolls", "Ragdolls", false },
	{ "Ragdolls", "Players", false },
	{ "Ragdolls", "Arena", true },
	{ "Ragdolls", "Default", true },

	{ "Balls", "Balls", true },
	{ "Balls", "Arena", true },
	{ "Balls", "Default", true },
	{ "Balls", "Players", false },
	{ "Balls", "Ragdolls", false },

	{ "HeldBalls", "HeldBalls", false },
	{ "HeldBalls", "Balls", false },
	{ "HeldBalls", "Players", false },
	{ "HeldBalls", "Ragdolls", false },
	{ "HeldBalls", "Arena", false },
	{ "HeldBalls", "Default", false },
}

local done = false

function Collision.Setup()
	if done then return end
	for _, name in ipairs(GROUPS) do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	for _, rule in ipairs(RULES) do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(rule[1], rule[2], rule[3])
		end)
	end
	done = true
end

function Collision.SetParts(root: Instance, group: string)
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = group
		end
	end
end

return Collision
