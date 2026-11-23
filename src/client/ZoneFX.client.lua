local RunService=game:GetService("RunService")
local TweenService=game:GetService("TweenService")
local RS=game:GetService("ReplicatedStorage")
local Zones=require(RS:WaitForChild("Shared"):WaitForChild("HitZones"))
local remote=RS:WaitForChild("ZoneRemotes"):WaitForChild("ZoneHit")
local folder=Instance.new("Folder");folder.Name="RDZoneFX";folder.Parent=workspace
local active={}
local function part(size,color)
	local p=Instance.new("Part");p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.CastShadow=false;p.Material=Enum.Material.SmoothPlastic;p.Color=color;p.Size=size;p.Parent=folder;return p
end
local function track(p,t,s,f) table.insert(active,{instance=p,dies=os.clock()+t,scale=s,frame=f}) end
local function label(pos,r,strength)
	local a=part(Vector3.new(.1,.1,.1),r.color);a.Transparency=1;a.CFrame=CFrame.new(pos+Vector3.new(0,2.4,0))
	local gui=Instance.new("BillboardGui");gui.Size=UDim2.fromOffset(190,46);gui.AlwaysOnTop=true;gui.LightInfluence=0;gui.MaxDistance=190;gui.Parent=a
	local f=Instance.new("Frame");f.Size=UDim2.fromScale(1,1);f.BackgroundColor3=Color3.fromRGB(8,12,26);f.BackgroundTransparency=.18;f.BorderSizePixel=0;f.Parent=gui
	Instance.new("UICorner",f).CornerRadius=UDim.new(0,11)
	local stroke=Instance.new("UIStroke");stroke.Color=r.color;stroke.Thickness=2;stroke.Parent=f
	local scale=Instance.new("UIScale");scale.Scale=.6;scale.Parent=f
	local word=Instance.new("TextLabel");word.Size=UDim2.new(1,-12,0,26);word.Position=UDim2.fromOffset(6,4);word.BackgroundTransparency=1;word.Font=Enum.Font.FredokaOne;word.TextScaled=true;word.TextColor3=r.color;word.Text=r.label.."!";word.Parent=f
	local sub=Instance.new("TextLabel");sub.Size=UDim2.new(1,-12,0,14);sub.Position=UDim2.fromOffset(6,29);sub.BackgroundTransparency=1;sub.Font=Enum.Font.GothamBold;sub.TextSize=10;sub.TextColor3=Color3.fromRGB(206,218,244);sub.Text=string.format("%d%% force",math.floor(strength*100));sub.Parent=f
	TweenService:Create(scale,TweenInfo.new(.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play();track(a,1.5,scale,f)
end
local function fx(pos,dir,r,strength)
	local len=math.clamp(6+strength*12,6,26)*r.streak
	local streak=part(Vector3.new(.34,.34,len),r.color);streak.Transparency=.25;streak.CFrame=CFrame.lookAt(pos+dir*(len*.5),pos+dir*len)
	TweenService:Create(streak,TweenInfo.new(.34,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Transparency=1,Size=Vector3.new(.06,.06,len*1.5)}):Play();track(streak,.42)
	local burst=part(Vector3.new(.1,.1,.1),r.color);burst.Transparency=1;burst.CFrame=CFrame.new(pos)
	local att=Instance.new("Attachment",burst);local em=Instance.new("ParticleEmitter");em.Texture="rbxasset://textures/particles/sparkles_main.dds";em.Color=ColorSequence.new(r.color,r.color:Lerp(Color3.new(1,1,1),.5));em.Lifetime=NumberRange.new(.28,.6);em.Rate=0;em.Speed=NumberRange.new(10,22);em.SpreadAngle=Vector2.new(46,46);em.Rotation=NumberRange.new(0,360);em.RotSpeed=NumberRange.new(-200,200);em.Size=NumberSequence.new({NumberSequenceKeypoint.new(0,.55+strength*.4),NumberSequenceKeypoint.new(1,0)});em.Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,.05),NumberSequenceKeypoint.new(1,1)});em.LightEmission=.7;em.Orientation=Enum.ParticleOrientation.VelocityParallel;em.Parent=att;em:Emit(math.floor(16+strength*20));track(burst,.9)
	local ring=part(Vector3.new(.14,2,2),r.color);ring.Shape=Enum.PartType.Cylinder;ring.Transparency=.4;ring.CFrame=CFrame.new(pos)*CFrame.Angles(0,0,math.rad(90))
	TweenService:Create(ring,TweenInfo.new(.36,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{Size=Vector3.new(.14,13+strength*7,13+strength*7),Transparency=1}):Play();track(ring,.44)
end
remote.OnClientEvent:Connect(function(character,zone,pos,direction,strength)
	if typeof(pos)~="Vector3" or typeof(zone)~="string" then return end
	local camera=workspace.CurrentCamera;if camera and (camera.CFrame.Position-pos).Magnitude>190 then return end
	local r=Zones.Response(zone);local dir=typeof(direction)=="Vector3" and direction.Magnitude>.01 and direction.Unit or Vector3.new(0,0,-1)
	fx(pos,dir,r,typeof(strength)=="number" and math.clamp(strength,.3,1.6) or 1);label(pos,r,typeof(strength)=="number" and math.clamp(strength,.3,1.6) or 1)
end)
local acc=0
RunService.Heartbeat:Connect(function(dt)
	acc+=dt;if acc<.1 then return end;acc=0;local now=os.clock()
	for i=#active,1,-1 do local e=active[i]
		if now>=e.dies or not e.instance.Parent then if e.instance.Parent then e.instance:Destroy() end;table.remove(active,i)
		elseif e.scale and now>e.dies-.25 then e.scale.Scale=math.max(.5,e.scale.Scale-.08);e.frame.BackgroundTransparency=math.min(.9,e.frame.BackgroundTransparency+.06) end
	end
end)
print("[ZoneFX] zone labels, force streaks and impact rings live")
