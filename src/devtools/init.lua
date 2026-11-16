-- DevTools: инструменты разработчика как модули проекта.
-- Лежат в ServerStorage, клиентам не реплицируются, эксплойтер их не вызовет.
--
-- Запуск из Command Bar одной строкой:
--   require(game.ServerStorage.DevTools).PerfSetup()     -- Edit
--   require(game.ServerStorage.DevTools).PerfReport()    -- Play, Server
--   require(game.ServerStorage.DevTools).FunnelReport()  -- Play, Server
--   require(game.ServerStorage.DevTools).Doctor()        -- Edit
--   require(game.ServerStorage.DevTools).Help()

local DevTools = {}

local function lazy(name: string)
	return function(...)
		local child = script:FindFirstChild(name)
		if not child then
			warn("[DevTools] Module not found: " .. name .. ". Is the Rojo sync complete?")
			return nil
		end
		local ok, result = pcall(function()
			return require(child).Run(...)
		end)
		if not ok then
			warn("[DevTools] " .. name .. " failed: " .. tostring(result))
			return nil
		end
		return result
	end
end

DevTools.PerfSetup = lazy("PerfSetup")
DevTools.PerfReport = lazy("PerfReport")
DevTools.FunnelReport = lazy("FunnelReport")
DevTools.Doctor = lazy("Doctor")

function DevTools.Help()
	print("=====================================================")
	print("  DEVTOOLS COMMANDS")
	print("=====================================================")
	print("  EDIT mode:")
	print("    require(game.ServerStorage.DevTools).PerfSetup()")
	print("    require(game.ServerStorage.DevTools).Doctor()")
	print("  PLAY mode, Server context:")
	print("    require(game.ServerStorage.DevTools).PerfReport()")
	print("    require(game.ServerStorage.DevTools).FunnelReport()")
	print("  PLAY mode, Client context (FPS probe):")
	print('    local n,t=0,0 local c c=game:GetService("RunService").RenderStepped:Connect(function(dt) n+=1 t+=dt end) task.delay(1.5,function() c:Disconnect() print(("FPS %.1f"):format(n/t)) end)')
	print("=====================================================")
	print("  Command Bar runs Luau code, not file paths.")
	print("=====================================================")
end

return DevTools
