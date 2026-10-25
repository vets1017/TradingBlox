-- MuteService.luau
--
-- Whose content a player has chosen not to see. Mutes are the game's own,
-- saved in the player's profile. Blocks are the player's Roblox blocks,
-- which the client reports each session (Roblox doesn't give servers a
-- player's block list), so they're kept only for the session. A thesis the
-- player reported is hidden from them too. The feed, ticker theses and
-- public profiles all read getFilter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Social = require(ReplicatedStorage.Config.Social)
local PlayerDataService = require(ServerScriptService.Services.PlayerDataService)
local SocialModule = require(ServerScriptService.Modules.SocialModule)

local MAX_ROBLOX_BLOCKS = 1000

-- Weak keys, so a player who has left drops out on their own
local robloxBlocks = setmetatable({}, { __mode = "k" }) -- [player] = { [userId] = true }

local MuteService = {}

-- What `viewer` doesn't want to see, read once for a whole list:
-- { hidesUser(userId), hidesThesis(thesisId), isMuted(userId), isBlocked(userId) }
function MuteService.getFilter(viewer)
	local data = PlayerDataService.get(viewer)
	local social = data and data.Social
	local blocks = robloxBlocks[viewer] or {}

	local filter = {}

	function filter.isBlocked(userId: number): boolean
		return blocks[userId] == true
	end

	function filter.isMuted(userId: number): boolean
		return social ~= nil and SocialModule.isMuted(social, userId)
	end

	function filter.hidesUser(userId: number): boolean
		return filter.isBlocked(userId) or filter.isMuted(userId)
	end

	function filter.hidesThesis(thesisId: string): boolean
		return social ~= nil and social.HiddenTheses[thesisId] ~= nil
	end

	return filter
end

-- Mutes or unmutes a player. Returns { success, message?, isMuted }.
function MuteService.setMuted(player, userId: number, shouldMute: boolean)
	local data = PlayerDataService.get(player)

	if not data then
		return { success = false, message = "Your data is still loading." }
	end

	if shouldMute and not SocialModule.isMuted(data.Social, userId) then
		local canMute, message = SocialModule.checkMute(data.Social, player.UserId, userId, Social.MAX_MUTED)

		if not canMute then
			return { success = false, message = message }
		end
	end

	SocialModule.setMuted(data.Social, userId, shouldMute, os.time())

	return { success = true, isMuted = shouldMute }
end

-- Replaces the session's Roblox blocks with `userIds`, as the client read
-- them. A client can only hide things from itself with this, so it isn't
-- checked beyond its shape.
function MuteService.setRobloxBlocks(player, userIds)
	local blocks = {}

	for index, userId in ipairs(userIds) do
		if index > MAX_ROBLOX_BLOCKS then
			break
		end

		if type(userId) == "number" and userId == math.floor(userId) and userId > 0 then
			blocks[userId] = true
		end
	end

	robloxBlocks[player] = blocks
end

-- Hides a thesis from the player, for when they report it
function MuteService.hideThesis(player, thesisId: string)
	local data = PlayerDataService.get(player)

	if data then
		SocialModule.addCapped(data.Social.HiddenTheses, thesisId, os.time(), Social.MAX_HIDDEN_THESES)
	end
end

return MuteService
