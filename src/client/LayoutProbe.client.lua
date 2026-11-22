-- LayoutProbe: runtime UI geometry diagnostic.
-- F8 toggles colored boxes; DUMP prints a report; RESCAN refreshes.
-- Geometry overlap is a warning, not proof of input interception.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local PROBE_NAME = "RDLayoutProbe"
local MIN_TEXT_PX = 9
local OVERLAP_TOLERANCE = 2

local SKIP_GUI = {
	[PROBE_NAME] = true, Chat = true, BubbleChat = true,
	PlayerList = true, Backpack = true, Health = true, Freecam = true,
}

local INK = Color3.fromRGB(8, 12, 26)
local SURFACE2 = Color3.fromRGB(26, 35, 66)
local TEXT = Color3.fromRGB(234, 240, 255)
local LIME = Color3.fromRGB(150, 255, 60)
local AMBER = Color3.fromRGB(255, 190, 0)
local RED = Color3.fromRGB(255, 58, 58)
local CYAN = Color3.fromRGB(0, 226, 255)

local overlayOn = false
local lastReport = {}
local lastCounts = { OFFSCREEN = 0, CLIPPED = 0, OVERLAP = 0, TINY = 0 }

local gui = Instance.new("ScreenGui")
gui.Name = PROBE_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.DisplayOrder = 100
gui.Parent = playerGui

local function make(class, props, parent)
	local item = Instance.new(class)
	for key, value in pairs(props) do item[key] = value end
	item.Parent = parent
	return item
end

local overlay = make("Frame", { Size = UDim2.fromScale(1,1), BackgroundTransparency = 1, Visible = false }, gui)
local bar = make("Frame", {
	Size = UDim2.fromOffset(268,96), Position = UDim2.fromOffset(12,12),
	BackgroundColor3 = INK, BackgroundTransparency = 0.06, BorderSizePixel = 0,
}, gui)
make("UICorner", { CornerRadius = UDim.new(0,11) }, bar)
make("UIStroke", { Color = CYAN, Thickness = 1.5, Transparency = 0.4 }, bar)
make("TextLabel", {
	Size = UDim2.new(1,-16,0,18), Position = UDim2.fromOffset(8,6),
	BackgroundTransparency = 1, Font = Enum.Font.FredokaOne, TextSize = 13,
	TextColor3 = CYAN, TextXAlignment = Enum.TextXAlignment.Left, Text = "LAYOUT PROBE  F8",
}, bar)
local summary = make("TextLabel", {
	Size = UDim2.new(1,-16,0,32), Position = UDim2.fromOffset(8,24),
	BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 11,
	TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = "measuring...",
}, bar)

local function smallButton(x, width, label, color, textColor)
	local button = make("TextButton", {
		Size = UDim2.fromOffset(width,26), Position = UDim2.fromOffset(x,62),
		BackgroundColor3 = color, TextColor3 = textColor,
		Font = Enum.Font.FredokaOne, TextSize = 11, Text = label,
	}, bar)
	make("UICorner", { CornerRadius = UDim.new(0,7) }, button)
	return button
end
local overlayButton = smallButton(8,82,"OVERLAY",SURFACE2,TEXT)
local dumpButton = smallButton(96,82,"DUMP",LIME,Color3.fromRGB(10,28,6))
local rescanButton = smallButton(184,76,"RESCAN",SURFACE2,TEXT)

local function viewport()
	local camera = workspace.CurrentCamera
	return camera and camera.ViewportSize or Vector2.new(1280,720)
end

local function isVisible(instance)
	local node = instance
	while node do
		if node:IsA("ScreenGui") then return node.Enabled end
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return false
end

local function ancestorScale(instance)
	local scale, node = 1, instance
	while node and not node:IsA("ScreenGui") do
		local uiScale = node:FindFirstChildOfClass("UIScale")
		if uiScale then scale *= uiScale.Scale end
		node = node.Parent
	end
	return scale
end

local function pathOf(instance)
	local parts, node = {}, instance
	while node and not node:IsA("ScreenGui") do
		if node.Name ~= "Frame" and node.Name ~= "ScrollingFrame" then table.insert(parts,1,node.Name) end
		node = node.Parent
	end
	return (node and node.Name or "?") .. "/" .. table.concat(parts,"/")
end

local function interactive(instance)
	return instance:IsA("TextButton") or instance:IsA("ImageButton") or instance:IsA("TextBox")
end

local function overlap(a,b)
	local ox = math.min(a.x+a.w,b.x+b.w)-math.max(a.x,b.x)
	local oy = math.min(a.y+a.h,b.y+b.h)-math.max(a.y,b.y)
	return ox > OVERLAP_TOLERANCE and oy > OVERLAP_TOLERANCE
end

local function related(a,b)
	local node=a.instance
	while node do if node==b.instance then return true end node=node.Parent end
	node=b.instance
	while node do if node==a.instance then return true end node=node.Parent end
	return false
end

local function collect()
	local items={}
	for _,screenGui in ipairs(playerGui:GetChildren()) do
		if screenGui:IsA("ScreenGui") and not SKIP_GUI[screenGui.Name] then
			for _,instance in ipairs(screenGui:GetDescendants()) do
				if interactive(instance) and isVisible(instance) then
					local pos,size=instance.AbsolutePosition,instance.AbsoluteSize
					if size.X>0 and size.Y>0 then
						local scale=ancestorScale(instance)
					local textSize=nil
					if instance:IsA("TextButton") or instance:IsA("TextBox") then
						if not instance.TextScaled then textSize=instance.TextSize*scale end
					end
					table.insert(items,{
						instance=instance, path=pathOf(instance), text=instance.Text,
						x=pos.X,y=pos.Y,w=size.X,h=size.Y,scale=scale,textPx=textSize,
					})
					if instance.TextScaled then
						local constraint=instance:FindFirstChildOfClass("UITextSizeConstraint")
					if constraint then
						items[#items].textMin=constraint.MinTextSize*scale
					items[#items].textMax=constraint.MaxTextSize*scale
					end
					end
				end
				end
			end
		end
	end
	return items
end

local function audit()
	local view,items=viewport(),collect()
	local report={}
	local counts={OFFSCREEN=0,CLIPPED=0,OVERLAP=0,TINY=0}
	for _,item in ipairs(items) do
		local fullyOut=item.x+item.w<=0 or item.y+item.h<=0 or item.x>=view.X or item.y>=view.Y
		local partlyOut=item.x<0 or item.y<0 or item.x+item.w>view.X or item.y+item.h>view.Y
		if fullyOut then
			counts.OFFSCREEN+=1
			table.insert(report,{severity="OFFSCREEN",item=item,detail=string.format("rect %.0f,%.0f %.0fx%.0f outside %.0fx%.0f",item.x,item.y,item.w,item.h,view.X,view.Y)})
		elseif partlyOut then
			counts.CLIPPED+=1
			table.insert(report,{severity="CLIPPED",item=item,detail="element partly crosses viewport edge"})
		end
		if item.textPx and item.textPx>0 and item.textPx<MIN_TEXT_PX then
			counts.TINY+=1
			table.insert(report,{severity="TINY",item=item,detail=string.format("estimated text %.1fpx (minimum %dpx)",item.textPx,MIN_TEXT_PX)})
		elseif item.textMin and item.textMin<MIN_TEXT_PX then
			counts.TINY+=1
			table.insert(report,{severity="TINY",item=item,detail=string.format("TextScaled constraint minimum %.1fpx; actual rendered size not directly measured",item.textMin)})
		end
	end
	for i=1,#items do
		for j=i+1,#items do
			local a,b=items[i],items[j]
			if not related(a,b) and overlap(a,b) then
				counts.OVERLAP+=1
				table.insert(report,{severity="OVERLAP",item=a,other=b,detail=string.format("%s [%s] overlaps %s [%s]",a.path,a.text,b.path,b.text)})
			end
		end
	end
	lastReport,lastCounts=report,counts
	local issueTotal=counts.OFFSCREEN+counts.CLIPPED+counts.OVERLAP
	summary.TextColor3=if issueTotal==0 then LIME else RED
	summary.Text=string.format("%dx%d off=%d clip=%d overlap=%d tiny=%d",view.X,view.Y,counts.OFFSCREEN,counts.CLIPPED,counts.OVERLAP,counts.TINY)
	return report,counts,view
end

local function drawOverlay(report)
	overlay:ClearAllChildren()
	for _,entry in ipairs(report) do
		local color=AMBER
		if entry.severity=="OFFSCREEN" or entry.severity=="OVERLAP" then color=RED end
		if entry.severity=="TINY" then color=CYAN end
		local function draw(item)
			local box=make("Frame",{
				Size=UDim2.fromOffset(math.max(item.w,4),math.max(item.h,4)),
				Position=UDim2.fromOffset(item.x,item.y),BackgroundTransparency=0.86,
				BackgroundColor3=color,BorderSizePixel=0,
			},overlay)
			make("UIStroke",{Color=color,Thickness=2,Transparency=0.1},box)
			make("TextLabel",{Size=UDim2.fromOffset(120,14),Position=UDim2.fromOffset(0,-15),
				BackgroundTransparency=1,Font=Enum.Font.Code,TextSize=10,TextColor3=color,
				TextXAlignment=Enum.TextXAlignment.Left,Text=entry.severity},box)
		end
		draw(entry.item)
		if entry.other then draw(entry.other) end
	end
end

local function dump()
	local report,counts,view=audit()
	print("==== LAYOUT PROBE ====")
	print(string.format("viewport %.0fx%.0f",view.X,view.Y))
	print(string.format("offscreen=%d clipped=%d overlap=%d tiny=%d",counts.OFFSCREEN,counts.CLIPPED,counts.OVERLAP,counts.TINY))
	if #report==0 then print("no layout conflicts detected") else
		for _,entry in ipairs(report) do
			local item=entry.item
			local line=string.format("%s %s | %s | %s",entry.severity,item.path,item.text,entry.detail)
			if entry.severity=="OFFSCREEN" or entry.severity=="OVERLAP" then warn(line) else print(line) end
		end
	end
	print("==== END PROBE ====")
end

local function toggleOverlay()
	overlayOn=not overlayOn
	overlay.Visible=overlayOn
	local report=audit()
	if overlayOn then drawOverlay(report) end
	overlayButton.BackgroundColor3=if overlayOn then CYAN else SURFACE2
	overlayButton.TextColor3=if overlayOn then Color3.fromRGB(4,22,30) else TEXT
end

overlayButton.Activated:Connect(toggleOverlay)
dumpButton.Activated:Connect(dump)
rescanButton.Activated:Connect(function() local report=audit();if overlayOn then drawOverlay(report) end end)
UserInputService.InputBegan:Connect(function(input,processed)
	if not processed and input.KeyCode==Enum.KeyCode.F8 then toggleOverlay() end
end)

local elapsed=0
RunService.Heartbeat:Connect(function(dt)
	elapsed+=dt
	if elapsed<1 then return end
	elapsed=0
	local report=audit()
	if overlayOn then drawOverlay(report) end
end)

task.delay(6,dump)
print("[LayoutProbe] ready: F8 overlay; DUMP button for report")
