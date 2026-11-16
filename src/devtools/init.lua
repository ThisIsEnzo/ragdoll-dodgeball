-- DevTools v0.7.2: загрузка через клон, чтобы обойти кэш ошибок Studio.
--
-- Проблема: если ModuleScript упал при первой загрузке, Roblox кэширует failure навсегда.
-- Дальше видно только "Requested module experienced an error while loading" без причины.
-- Клон — новый инстанс со свежей записью в кэше, поэтому ошибка печатается целиком.
--
-- Ограничение: инструменты обязаны использовать абсолютные пути (game:GetService...),
-- а не script-relative, потому что клон живёт отдельно от оригинала.
-- Все четыре инструмента этому условию удовлетворяют.

local DevTools = {}

local TOOLS = { "Doctor", "PerfSetup", "PerfReport", "FunnelReport" }

local function loadFresh(name: string)
	local child = script:FindFirstChild(name)
	if not child then
		warn("[DevTools] Missing module: " .. name .. " — Rojo sync incomplete?")
		return nil, nil
	end
	if not child:IsA("ModuleScript") then
		warn("[DevTools] " .. name .. " is " .. child.ClassName .. ", expected ModuleScript")
		return nil, nil
	end

	local clone = child:Clone()
	clone.Name = name .. "_Probe"
	clone.Parent = script

	local ok, module = pcall(require, clone)
	if not ok then
		clone:Destroy()
		warn("[DevTools] " .. name .. " LOAD ERROR: " .. tostring(module))
		return nil, nil
	end
	if type(module) ~= "table" or type(module.Run) ~= "function" then
		clone:Destroy()
		warn("[DevTools] " .. name .. " returned no Run() function")
		return nil, nil
	end

	return module, clone
end

local function call(name: string)
	return function(...)
		local module, clone = loadFresh(name)
		if not module then return nil end

		local ok, result = pcall(module.Run, ...)
		if clone then clone:Destroy() end

		if not ok then
			warn("[DevTools] " .. name .. " RUN ERROR: " .. tostring(result))
			return nil
		end
		return result
	end
end

for _, name in ipairs(TOOLS) do
	DevTools[name] = call(name)
end

-- Проверяет загрузку всех инструментов, ничего не запуская и ничего не меняя.
function DevTools.Diagnose()
	print("=====================================================")
	print("  DEVTOOLS DIAGNOSE")
	print("=====================================================")
	print("  container: " .. script:GetFullName() .. "  (" .. script.ClassName .. ")")

	local children = {}
	for _, child in ipairs(script:GetChildren()) do
		table.insert(children, child.Name .. " [" .. child.ClassName .. "]")
	end
	print("  children: " .. if #children > 0 then table.concat(children, ", ") else "NONE")

	local failures = 0
	for _, name in ipairs(TOOLS) do
		local module, clone = loadFresh(name)
		if module then
			print("  OK      " .. name)
			if clone then clone:Destroy() end
		else
			print("  FAILED  " .. name .. "  (see warning above for the real error)")
			failures += 1
		end
	end

	print("=====================================================")
	if failures == 0 then
		print("  All tools load. Run Doctor() next.")
	else
		warn("  " .. failures .. " tool(s) failed to load. The warnings above contain the real cause.")
	end
	print("=====================================================")
	return failures
end

function DevTools.Help()
	print("=====================================================")
	print("  DEVTOOLS")
	print("=====================================================")
	print("  Diagnose()    load-check every tool, change nothing")
	print("  Doctor()      validate project tree            [Edit]")
	print("  PerfSetup()   apply perf budget, then SAVE      [Edit]")
	print("  PerfReport()  budget compliance                 [Play, Server]")
	print("  FunnelReport() FTUE funnel                      [Play, Server]")
	print("")
	print("  Bypass a poisoned parent cache by calling a child directly:")
	print("    require(game.ServerStorage.DevTools.Doctor).Run()")
	print("")
	print("  Command Bar runs Luau code, not file paths.")
	print("=====================================================")
end

return DevTools
