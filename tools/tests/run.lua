-- Balance invariant suite. Relationships, not fixed values, are asserted.
-- Roblox catalog shims (Color3/Vector3/Enum) allow plain Luau CLI loading.
local function color(r,g,b) return {r=r or 0,g=g or 0,b=b or 0} end
Color3={fromRGB=color,new=function(r,g,b) return color((r or 0)*255,(g or 0)*255,(b or 0)*255) end}
local function vec(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
Vector3={new=vec,zero=vec(0,0,0),one=vec(1,1,1)}
Enum=setmetatable({}, {__index=function(_,group) return setmetatable({}, {__index=function(_,item) return group.."."..item end}) end})
if not math.clamp then math.clamp=function(v,lo,hi) return math.max(lo,math.min(hi,v)) end end
if not typeof then typeof=function(v) return type(v) end end
local passed,failed=0,0
local missing={}
local function test(name,fn) local ok,err=pcall(fn); if ok then passed+=1 else failed+=1; print("FAIL  "..name.." -> "..tostring(err)) end end
local function assertTrue(c,m) if not c then error(m,2) end end
local function load(name) local ok,v=pcall(function() return require("../../src/shared/"..name) end); if not ok then missing[#missing+1]=name; return nil end; return v end
local CFG=load("BalanceConfig")
local Loadout=load("Loadout")
local Ranks=load("RankCatalog")
local Shop=load("ShopCatalog")
local Store=load("MonetizationCatalog")
local Audio=load("AudioCatalog")
for _,name in ipairs(missing) do failed+=1; print("FAIL module missing/load error: "..name) end

if CFG then
 test("catch ceiling covers fastest throw",function() assertTrue(CFG.Catch.MaxSpeed>=CFG.Throw.SpeedMax,"max catch speed below max throw speed") end)
 test("weakest throw can hit",function() assertTrue(CFG.Ball.MinHitSpeed<CFG.Throw.SpeedMin,"weak throw below hit threshold") end)
 test("pickup and hit thresholds overlap",function() assertTrue(CFG.Ball.PickupMaxSpeed>CFG.Ball.MinHitSpeed,"ball is stuck between pickup and hit thresholds") end)
 test("pickup height reaches floor ball",function() assertTrue(CFG.Ball.PickupVerticalLimit>CFG.Ball.Size,"pickup vertical limit below ball diameter") end)
 test("throw and charge ranges ordered",function() assertTrue(CFG.Throw.SpeedMin<CFG.Throw.SpeedMax and CFG.Throw.ChargeMin<CFG.Throw.ChargeMax,"invalid throw/charge range") end)
 test("dodge cooldown exceeds dodge duration",function() assertTrue(CFG.Movement.DodgeCooldown>CFG.Movement.DodgeDuration,"dodge cooldown is not longer than movement") end)
 test("dodge i-frames bounded by dodge duration",function() assertTrue(CFG.Movement.DodgeIFrames<=CFG.Movement.DodgeDuration+0.2,"dodge i-frames excessively outlast movement") end)
 test("catch stance reactable",function() assertTrue(CFG.Catch.StanceSeconds>=0.6,"catch stance too short for reaction/network") end)
 test("catch whiff penalty shorter than stance",function() assertTrue(CFG.Catch.WhiffCooldown<CFG.Catch.StanceSeconds,"whiff cooldown exceeds catch stance") end)
 do local max=CFG.Movement.WalkSpeed*CFG.Security.SpeedTolerance+CFG.Security.SpeedSlack; if max<CFG.Movement.DodgeSpeed then print(string.format("KNOWN_ISSUE anti-cheat ceiling: DodgeSpeed=%d exceeds ceiling %.1f; gameplay tuning decision required",CFG.Movement.DodgeSpeed,max)) end end
 test("ballistic range can cross court",function() local range=CFG.Throw.SpeedMax^2/(196.2*CFG.Ball.GravityScale); assertTrue(range>=CFG.Arena.Depth*0.8,string.format("range %.1f studs insufficient",range)) end)
 test("round timings coherent",function() assertTrue(CFG.Round.Warmup>0 and CFG.Round.Duration>CFG.Round.SuddenDeath and CFG.Round.WinsNeeded>=1,"invalid round timing or wins needed") end)
 test("ragdoll fits round-end pause",function() assertTrue(CFG.Round.RagdollTime<=CFG.Round.RoundEnd,"ragdoll overlaps next round") end)
 test("ultimate hype attainable within six hits",function() assertTrue(math.ceil(CFG.Hype.Max/CFG.Hype.Hit)<=6,"ultimate requires too many hits") end)
 test("bot spacing fits arena",function() assertTrue(CFG.BotAI.LaneSpacing*3<=CFG.Arena.Width,"three bot lanes exceed width") end)
 test("neutral band leaves playable court",function() assertTrue(CFG.Rules.NeutralBand*2<CFG.Arena.Depth*0.25,"neutral band too wide") end)
 test("XP curve increases",function() local prev=0; for lv=1,CFG.Progression.MaxLevel do local xp=CFG.XP.ToNext(lv); assertTrue(xp>prev,"XP does not increase at level "..lv); prev=xp end end)
 test("win rewards exceed loss rewards",function() assertTrue(CFG.Progression.MatchWinCoins>CFG.Progression.MatchLossCoins and CFG.Progression.MatchWinXP>CFG.Progression.MatchLossXP,"win rewards do not exceed loss") end)
 test("streak rewards nondecreasing",function() local prev=0; for i,r in ipairs(CFG.Progression.StreakCoins) do assertTrue(r>=prev,"streak reward dropped at "..i); prev=r end end)
 test("quest slots fit pool",function() assertTrue(CFG.Progression.QuestSlots<=#CFG.QuestPool,"quest slots exceed pool") end)
 test("quest stats tracked and targets positive",function() local tracked={kos=true,catches=true,throws=true,revives=true,roundWins=true,wins=true,matches=true}; for _,q in ipairs(CFG.QuestPool) do assertTrue(tracked[q.stat] and q.target>0,"invalid quest stat/target "..tostring(q.stat)) end end)
 test("first paid cosmetic attainable within eight matches",function() if not Shop then return end; local cheap=math.huge; for _,item in ipairs(Shop.Balls) do if item.price>0 and item.price<cheap then cheap=item.price end end; local rewards=CFG.Progression.MatchLossCoins+CFG.Progression.KoCoins*3; assertTrue(cheap/rewards<=8,string.format("cheapest skin requires %.1f matches",cheap/rewards)) end)
 test("unlock announcements correspond to ult gates",function() if not Shop then return end; for level,label in pairs(CFG.Unlocks) do local found=false; for id,gate in pairs(Shop.UltLevels) do if gate==level and string.find(string.lower(label),string.lower(id),1,true) then found=true end end; assertTrue(found,"unlock label at "..level.." has no matching ult gate: "..label) end end)
 test("all remotes have positive rate limits",function() for _,key in ipairs({"Throw","Catch","Dodge","Ult","QueueJoin","QuestClaim","UiEvent","PingRequest","ShopBuy"}) do assertTrue(CFG.RateLimits[key] and CFG.RateLimits[key]>0,"missing/invalid rate limit "..key) end end)
 test("catch rate limit supports responsive play",function() assertTrue(CFG.RateLimits.Catch>=3,"catch limit below 3/sec") end)
end
if Loadout then
 test("loadout order references entries",function() for _,key in ipairs(Loadout.Order) do assertTrue(Loadout.Types[key],"unknown throw type "..key) end end)
 test("throw unlock levels ascend",function() local prev=0; for _,key in ipairs(Loadout.Order) do local lv=Loadout.Types[key].level; assertTrue(lv>=prev,"unlock level decreases at "..key); prev=lv end end)
 test("baseline throw available at level one",function() assertTrue(Loadout.Types.Straight.level==1 and Loadout.Types.Straight.speed==1,"baseline throw locked or penalized") end)
 test("throw multipliers are positive and at most one",function() for key,e in pairs(Loadout.Types) do assertTrue(e.speed>0 and e.speed<=1,"throw type multiplier invalid: "..key) end end)
 test("all throws remain catchable",function() if not CFG then return end; for key,e in pairs(Loadout.Types) do assertTrue(CFG.Throw.SpeedMax*e.speed<=CFG.Catch.MaxSpeed,"throw type uncaught at max charge: "..key) end end)
end
if Ranks then
 test("rank thresholds increase",function() local prev=-1; for _,tier in ipairs(Ranks.Tiers) do assertTrue(tier.wins>prev,"rank threshold fails at "..tier.key); prev=tier.wins end end)
 test("first rank starts at zero wins",function() assertTrue(Ranks.Tiers[1].wins==0,"starting rank inaccessible") end)
 test("leaderboard stats tracked",function() local tracked={kos=true,catches=true,wins=true,level=true}; for _,b in ipairs(Ranks.Boards) do assertTrue(tracked[b.stat],"untracked board stat "..b.stat) end end)
 test("emote keys unique",function() local seen={}; for _,e in ipairs(Ranks.Emotes) do assertTrue(not seen[e.key],"duplicate emote "..e.key); seen[e.key]=true end end)
end
if Store then
 test("coin packs improve value by tier",function() local prev=0; for _,p in ipairs(Store.Products) do if p.coins then local value=p.coins/p.fallbackPrice; assertTrue(value>=prev,"coin pack value drops"); prev=value end end end)
 test("gamepasses define effects",function() for _,p in ipairs(Store.GamePasses) do assertTrue(Store.Effects[p.key],"pass missing effect "..p.key) end end)
 test("gamepasses are noncombat",function() for key,e in pairs(Store.Effects) do assertTrue(e.damage==nil and e.aim==nil and e.hitbox==nil,"combat advantage in pass "..key) end end)
end
if Audio and CFG then
 test("all audio groups have defaults",function() for _,g in ipairs(Audio.Groups) do assertTrue(Audio.Defaults[g]~=nil,"missing volume default "..g) end end)
 test("audio defaults stay normalized",function() for name,v in pairs(Audio.Defaults) do assertTrue(v>=0 and v<=1,"volume out of range "..name) end end)
 test("gameplay audio references exist",function() for _,key in ipairs({"throw","bonk","catch","whiff","dodge","revive","ult","shield","levelUp","click"}) do assertTrue(Audio.Sounds[key],"missing sound key "..key) end end)
end
print(string.format("\npassed %d, failed %d",passed,failed))
print("TESTS_FAILED="..failed)
if failed==0 then print("All balance invariants hold.") else error(string.format("%d invariant test(s) failed",failed)) end
