local aliases={head="head",uppertorso="torso",lowertorso="torso",torso="torso",leftupperarm="armL",leftlowerarm="armL",lefthand="armL",leftarm="armL",rightupperarm="armR",rightlowerarm="armR",righthand="armR",rightarm="armR",leftupperleg="legL",leftlowerleg="legL",leftfoot="legL",leftleg="legL",rightupperleg="legR",rightlowerleg="legR",rightfoot="legR",rightleg="legR"}
local responses={
head={label="WHIPLASH",color=Color3.fromRGB(255,70,210),linearMul=9.5,liftBias=.62,pitch=-5.2,yaw=.6,roll=.4,localKick=Vector3.new(0,.85,-.55),localKickMul=7,streak=1.5},
torso={label="FOLDED",color=Color3.fromRGB(255,190,0),linearMul=12,liftBias=.2,pitch=-2.4,yaw=.3,roll=.2,localKick=Vector3.new(0,.15,-1),localKickMul=5,streak=1.2},
armL={label="SPUN OUT",color=Color3.fromRGB(0,226,255),linearMul=7,liftBias=.34,pitch=-.8,yaw=6.4,roll=2.2,localKick=Vector3.new(-1,.45,-.2),localKickMul=8.5,streak=1},
armR={label="SPUN OUT",color=Color3.fromRGB(0,226,255),linearMul=7,liftBias=.34,pitch=-.8,yaw=-6.4,roll=-2.2,localKick=Vector3.new(1,.45,-.2),localKickMul=8.5,streak=1},
legL={label="LEGS SWEPT",color=Color3.fromRGB(150,255,60),linearMul=8,liftBias=-.18,pitch=6.6,yaw=1.6,roll=1.4,localKick=Vector3.new(-.5,1,.75),localKickMul=10,streak=1.35},
legR={label="LEGS SWEPT",color=Color3.fromRGB(150,255,60),linearMul=8,liftBias=-.18,pitch=6.6,yaw=-1.6,roll=-1.4,localKick=Vector3.new(.5,1,.75),localKickMul=10,streak=1.35}}
local function core(c)
	for _,n in ipairs({"UpperTorso","LowerTorso","Torso"}) do local p=c:FindFirstChild(n,true);if p and p:IsA("BasePart") then return p end end
	return c:FindFirstChild("HumanoidRootPart")
end
local M={Responses=responses}
function M.Classify(c,pos)
	local best,score
	for _,p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then
		local z=aliases[string.lower((string.gsub(p.Name,"%s+","")))]
		if z then local s=(p.Position-pos).Magnitude-math.max(p.Size.X,p.Size.Y,p.Size.Z)*.425;if not score or s<score then best,score={zone=z,part=p},s end end
	end end
	if best then return best.zone,best.part end
	return "torso",core(c)
end
function M.Core(c) return core(c) end
function M.Response(z) return responses[z] or responses.torso end
return M
