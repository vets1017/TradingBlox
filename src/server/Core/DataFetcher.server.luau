local HttpService = game:GetService("HttpService")

local ServerURL = "" -- temp

_G.LiveData = {}

local function updateMarketData()
	local success, response = pcall(function()
		return HttpService:GetAsync(ServerURL)
	end)

	if success then
		local decodedData = HttpService:JSONDecode(response)
		_G.LiveMarketData = decodedData
		print("Market Data Updated Successfully!")
	else
		warn("Failed to fetch data: " .. tostring(response))
	end
end

task.spawn(function()
	while true do
		updateMarketData()
		task.wait(60)
	end
end)
