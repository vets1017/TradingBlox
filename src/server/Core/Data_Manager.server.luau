local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")

_G.PlayerData = {}

local function createDefaultData()
	return {
		Balance = 10000,
		Portfolio = {
			Shares = {},
			Options = {},
		},
	}
end

Players.PlayerAdded:Connect(function(player)
	local success, data = pcall(function()
		return PlayerDataStore:GetAsync(player.UserId)
	end)

	if success and data then
		_G.PlayerData[player.UserId] = data
	else
		_G.PlayerData[player.UserId] = createDefaultData()
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local dataToSave = _G.PlayerData[player.UserId]

	if dataToSave then
		local success, error = pcall(function()
			PlayerDataStore:SetAsync(player.UserId, dataToSave)
		end)

		if not success then
			warn("Failed to save data for player " .. player.Name .. ": " .. tostring(error))
		end

		_G.PlayerData[player.UserId] = nil
	end
end)
