local Players=game:GetService("Players")
local RS=game:GetService("ReplicatedStorage")
local SSS=game:GetService("ServerScriptService")
local Shared=RS:WaitForChild("Shared")
local CFG=require(Shared:WaitForChild("BalanceConfig"))
local Zones=require(Shared:WaitForChild("HitZones"))
local Resolve=require(Shared:WaitForChild("Resolve"))
local BallService=Resolve.Require(SSS,"BallService")
local folder=RS:FindFirstChild("ZoneRemotes")
if not folder then folder=Instance.new("Folder");folder.Name="ZoneRemotes";folder.Parent=RS end
local remote=folder:FindFirstChild("ZoneHit")
if not remote then remote=Instance.new("RemoteEvent");remote.Name="ZoneHit";remote.Parent=folder end
local reserved=setmetatable({},{__mode="k"})
local function waitRagdoll(c)
	local untilAt=os.clock()+.35
	repeat if not c.Parent then return false end;if c:GetAttribute("Ragdolled") then return true end;task.wait() until os.clock()>=untilAt
	return c:GetAttribute("Ragdolled")==true
end
local function mass(c)
	local n=0;for _,p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") and not p.Anchored then n+=p:GetMass() end end
	return math.max(n,12)
end
BallService.HitDetected.Event:Connect(function(ball,c,speed,impact)
	if not c or not c.Parent or c:GetAttribute("Benched") then return end
	local now=os.clock();if (reserved[c] or 0)>now then return end
	reserved[c]=now+.85 -- reserve before spawning to prevent concurrent duplicate impulses
	task.spawn(function()
		if not waitRagdoll(c) then return end
		local zone,limb=Zones.Classify(c,impact);local response=Zones.Response(zone);local root=Zones.Core(c)
		if not root or not root.Parent then return end;if not limb or not limb.Parent then limb=root end
		local velocity=ball and ball.Parent and ball.AssemblyLinearVelocity or Vector3.zero
		local flat=Vector3.new(velocity.X,0,velocity.Z);local dir=flat.Magnitude>.5 and flat.Unit or Vector3.new(0,0,-1)
		local strength=math.clamp(speed/math.max(CFG.Throw.SpeedMax,1),.35,1.25)
		local kick=(dir+Vector3.new(0,response.liftBias,0)).Unit
		-- Existing RagdollService already launches the root; keep this additive impulse bounded.
		local delta=math.clamp(speed*response.linearMul*strength*.025,5,22)
		limb:ApplyImpulse(kick*delta*limb:GetMass())
		local look,right=root.CFrame.LookVector,root.CFrame.RightVector
		local localDir=right*response.localKick.X+Vector3.yAxis*response.localKick.Y+look*response.localKick.Z
		if localDir.Magnitude>.01 then limb:ApplyImpulse(localDir.Unit*math.clamp(speed*response.localKickMul*strength*.018,3,14)*limb:GetMass()) end
		local angular=right*response.pitch+Vector3.yAxis*response.yaw+look*response.roll
		if angular.Magnitude>.01 then root:ApplyAngularImpulse(angular.Unit*math.min(angular.Magnitude,8)*mass(c)*strength*.12) end
		if zone=="legL" or zone=="legR" then
			limb:ApplyImpulse(Vector3.yAxis*math.min(speed*.12*strength,10)*limb:GetMass())
			root:ApplyImpulse(Vector3.yAxis*-math.min(speed*.035*strength,3)*root:GetMass())
		elseif zone=="head" then root:ApplyImpulse(Vector3.yAxis*math.min(speed*.06*strength,4)*root:GetMass()) end
		remote:FireAllClients(c,zone,impact,dir,strength)
		local plr=Players:GetPlayerFromCharacter(c)
		print(string.format("[Zone] %s %s spd=%d str=%.2f",plr and plr.Name or c.Name,response.label,math.floor(speed),strength))
	end)
end)
Players.PlayerRemoving:Connect(function(p) if p.Character then reserved[p.Character]=nil end end)
print("[Zone] directional ragdoll live: head, torso, arms, legs")
