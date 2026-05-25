local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")

_G.PlayerData = _G.PlayerData or {}

_G.UpdatePlayerStat = function(player, statName, value)
	if _G.PlayerData[player.UserId] then
		_G.PlayerData[player.UserId][statName] = value
	end

	player:SetAttribute(statName, value)
end

_G.UpdatePortfolio = function(player, ticker, shares)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return
	end

	playerData.Portfolio = playerData.Portfolio or {}

	local currentShares = playerData.Portfolio.Shares[ticker] or 0
	local newShares = currentShares + shares

	if newShares > 0 then
		playerData.Portfolio.Shares[ticker] = newShares
	else
		playerData.Portfolio.Shares[ticker] = nil
	end

	local PortfolioFolder = player:FindFirstChild("PortfolioFolder")
	if PortfolioFolder then
		local shareValue = PortfolioFolder:FindFirstChild(ticker)

		if newShares > 0 then
			if not shareValue then
				shareValue = Instance.new("IntValue")
				shareValue.Name = ticker
				shareValue.Parent = PortfolioFolder
			end

			shareValue.Value = newShares
		else
			if shareValue then
				shareValue:Destroy()
			end
		end
	end
end

local function createDefaultData()
	return {
		Balance = 10000,
		Portfolio = {
			Shares = {},
			Options = {},
		},
	}
end

local function onPlayerAdded(player)
	_G.PlayerData[player.UserId] = {}

	local portfolioFolder = Instance.new("Folder")
	portfolioFolder.Name = "PortfolioFolder"
	portfolioFolder.Parent = player

	local saveData = nil

	local success, error = pcall(function()
		saveData = PlayerDataStore:GetAsync(player.UserId)
	end)

	if success and saveData then
		_G.UpdatePlayerStat(player, "Balance", saveData.Balance)

		_G.PlayerData[player.UserId].Portfolio = saveData.Portfolio or {}

		for ticker, shares in pairs(_G.PlayerData[player.UserId].Portfolio.Shares) do
			local shareValue = Instance.new("IntValue")
			shareValue.Name = ticker
			shareValue.Value = shares
			shareValue.Parent = portfolioFolder
		end
	else
		_G.UpdatePlayerStat(player, "Balance", createDefaultData().Balance)

		_G.PlayerData[player.UserId].Portfolio = createDefaultData().Portfolio
	end
end

local function onPlayerRemoving(player)
	local sessionData = _G.PlayerData[player.UserId]

	if sessionData then
		local success, error = pcall(function()
			PlayerDataStore:SetAsync(player.UserId, sessionData)
		end)

		if not success then
			warn("Failed to save data for " .. player.Name .. ": " .. tostring(error))
		end

		_G.PlayerData[player.UserId] = nil
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

game:BindToClose(function()
	for _, player in pairs(Players:GetPlayers()) do
		onPlayerRemoving(player)
	end
	task.wait(2)
end)
