local NumberModule = {}

function NumberModule.format(amount)
	local formatted = tostring(amount)
	local k

	while true do
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")

		if k == 0 then
			break
		end
	end

	return "$" .. formatted
end

return NumberModule
