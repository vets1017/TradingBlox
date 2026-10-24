local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerDataStore = DataStoreService:GetDataStore("PlayerData_v1")

local CalculatorModule = require(ServerScriptService.Modules.CalculatorModule)

_G.PlayerData = _G.PlayerData or {}

_G.UpdatePlayerStat = function(player, statName, value)
	if _G.PlayerData[player.UserId] then
		_G.PlayerData[player.UserId][statName] = value
	end

	player:SetAttribute(statName, value)
end

_G.UpdatePortfolio = function(player, ticker, shares, price)
	local playerData = _G.PlayerData[player.UserId]

	if not playerData then
		return
	end

	playerData.Portfolio = playerData.Portfolio or {}
	playerData.Portfolio.AvgCost = playerData.Portfolio.AvgCost or {}

	local currentShares = playerData.Portfolio.Shares[ticker] or 0
	local newShares = currentShares + shares

	if newShares > 0 then
		playerData.Portfolio.Shares[ticker] = newShares

		if shares > 0 and price then
			-- Buying more: roll the new lot into a weighted-average cost.
			local currentAvgCost = playerData.Portfolio.AvgCost[ticker] or price

			playerData.Portfolio.AvgCost[ticker] = ((currentAvgCost * currentShares) + (price * shares)) / newShares
		end
	else
		playerData.Portfolio.Shares[ticker] = nil
		playerData.Portfolio.AvgCost[ticker] = nil
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
			AvgCost = {},
			Options = {},
		},
		Watchlist = {},
		Stats = {
			Trades = 0, -- filled share and option orders
			JoinedAt = os.time(),
		},
		NetWorthHistory = {}, -- see PortfolioHistoryModule
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
		_G.PlayerData[player.UserId].Watchlist = saveData.Watchlist or {}
		-- Saves from before these fields existed start fresh, so their
		-- JoinedAt is this session rather than the player's real first join
		_G.PlayerData[player.UserId].Stats = saveData.Stats or createDefaultData().Stats
		_G.PlayerData[player.UserId].NetWorthHistory = saveData.NetWorthHistory or {}

		for ticker, shares in pairs(_G.PlayerData[player.UserId].Portfolio.Shares) do
			local shareValue = Instance.new("IntValue")
			shareValue.Name = ticker
			shareValue.Value = shares
			shareValue.Parent = portfolioFolder
		end
	else
		_G.UpdatePlayerStat(player, "Balance", createDefaultData().Balance)

		_G.PlayerData[player.UserId].Portfolio = createDefaultData().Portfolio
		_G.PlayerData[player.UserId].Watchlist = createDefaultData().Watchlist
		_G.PlayerData[player.UserId].Stats = createDefaultData().Stats
		_G.PlayerData[player.UserId].NetWorthHistory = createDefaultData().NetWorthHistory
	end

	-- Seed NetWorth so the status bar has a value before the first trade;
	-- spawned because pricing held shares fetches candles over HTTP
	task.spawn(CalculatorModule.calculateNetWorth, player)
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
