-- Resolve: поиск модулей без зависимости от имён папок, регистра и разделителей.
-- Убирает класс ошибок "Infinite yield possible on WaitForChild('services')".

local Resolve = {}

local function normalize(name: string): string
	return (string.lower((string.gsub(name, "[%s_%-%.]", ""))))
end

-- Ищет потомка по имени в любом месте дерева root. Ждёт до timeout секунд.
function Resolve.Find(root: Instance, name: string, timeout: number?): Instance?
	local target = normalize(name)
	local deadline = os.clock() + (timeout or 8)
	repeat
		for _, descendant in ipairs(root:GetDescendants()) do
			if normalize(descendant.Name) == target then
				return descendant
			end
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return nil
end

-- Требует ModuleScript по имени. Вместо вечного ожидания — понятная ошибка.
function Resolve.Require(root: Instance, name: string, timeout: number?): any
	local module = Resolve.Find(root, name, timeout)
	if not module then
		error(string.format(
			"[Resolve] Модуль '%s' не найден внутри '%s'. Создай ModuleScript с этим именем "
			.. "(папка и регистр не важны) или проверь синхронизацию Rojo.",
			name, root:GetFullName()), 2)
	end
	if not module:IsA("ModuleScript") then
		error(string.format(
			"[Resolve] '%s' найден как %s, а нужен ModuleScript. Пересоздай инстанс правильного типа.",
			module:GetFullName(), module.ClassName), 2)
	end
	return require(module)
end

-- Диагностика: что реально лежит в дереве. Печатается один раз при старте.
function Resolve.Report(root: Instance, label: string)
	local names = {}
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ModuleScript") then
			table.insert(names, descendant.Name)
		end
	end
	table.sort(names)
	print(string.format("[%s] модули под %s: %s", label, root.Name,
		if #names > 0 then table.concat(names, ", ") else "НИ ОДНОГО"))
end

return Resolve
