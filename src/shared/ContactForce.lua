-- ContactForce: pure normalization for contact-derived impact feedback.
-- This module deliberately does not apply physics or decide knockout outcomes.
local ContactForce = {}

local function finite(value)
	return typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function ContactForce.Calculate(closingSpeed, referenceSpeed, minimum, maximum)
	minimum = if finite(minimum) then minimum else 0
	maximum = if finite(maximum) then maximum else 1
	minimum = math.clamp(minimum, 0, 1)
	maximum = math.clamp(maximum, minimum, 1)

	if not finite(closingSpeed) or closingSpeed <= 0 then
		return { closingSpeed = 0, normalized = minimum == 0 and 0 or minimum }
	end
	if not finite(referenceSpeed) or referenceSpeed <= 0 then
		return { closingSpeed = 0, normalized = minimum == 0 and 0 or minimum }
	end

	local normalized = math.clamp(closingSpeed / referenceSpeed, minimum, maximum)
	return {
		closingSpeed = closingSpeed,
		normalized = normalized,
	}
end

return ContactForce
