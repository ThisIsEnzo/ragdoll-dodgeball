-- AimAssist: серверная помощь прицеливанию. Клиент не может получить больше, чем разрешённый конус.
-- Направление от клиента остаётся основой; сервер лишь подтягивает его к ближайшей цели
-- внутри угла и дистанции, с проверкой линии видимости.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CFG = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

local AimAssist = {}

local function angleBetween(a: Vector3, b: Vector3): number
	return math.acos(math.clamp(a:Dot(b), -1, 1))
end

-- origin: точка вылета, dir: нормализованное направление от клиента
-- targets: список {root: BasePart, character: Model}
function AimAssist.Adjust(origin: Vector3, dir: Vector3, targets: { any }, isMobile: boolean, exclude: { Instance }): Vector3
	if not CFG.AimAssist.Enabled then return dir end
	if dir.Magnitude < 0.01 then return dir end

	local baseDir = dir.Unit
	local angleDeg = if isMobile then CFG.AimAssist.MobileAngleDeg else CFG.AimAssist.DesktopAngleDeg
	local maxAngle = math.rad(angleDeg)

	local best, bestAngle = nil, maxAngle
	for _, entry in ipairs(targets) do
		local root = entry.root
		if root and root.Parent then
			local offset = (root.Position + Vector3.new(0, 0.6, 0)) - origin
			local distance = offset.Magnitude
			if distance > 1 and distance <= CFG.AimAssist.MaxDistance then
				local angle = angleBetween(baseDir, offset.Unit)
				if angle < bestAngle then
					local visible = true
					if CFG.AimAssist.RequireLineOfSight then
						local params = RaycastParams.new()
						params.FilterType = Enum.RaycastFilterType.Exclude
						params.FilterDescendantsInstances = exclude
						params.IgnoreWater = true
						local hit = workspace:Raycast(origin, offset, params)
						if hit and not hit.Instance:IsDescendantOf(entry.character) then
							visible = false
						end
					end
					if visible then best, bestAngle = offset.Unit, angle end
				end
			end
		end
	end

	if not best then return baseDir end

	local blended = (baseDir:Lerp(best, CFG.AimAssist.Strength))
	if blended.Magnitude < 0.01 then return baseDir end
	blended = blended.Unit

	-- жёсткий кламп: суммарное отклонение не больше разрешённого угла
	if angleBetween(baseDir, blended) > maxAngle then
		local axis = baseDir:Cross(blended)
		if axis.Magnitude < 0.001 then return baseDir end
		blended = CFrame.fromAxisAngle(axis.Unit, maxAngle):VectorToWorldSpace(baseDir)
	end
	return blended.Unit
end

return AimAssist
