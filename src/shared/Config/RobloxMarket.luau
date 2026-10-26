-- RobloxMarket.luau
--
-- The Roblox market (GDD §6): Roblox experiences traded as simulated
-- securities. RobloxMarketService simulates each one's price from its public
-- stats; this is the list of who's listed. Shared so the client can name
-- them and explain the labels.
--
-- Picked from Roblox's Top Playing Now, Top Revisited and Top Trending sorts
-- (2026-10-25): rated Minimal or Mild, at least six months old, across
-- genres (TECHNICAL-PLAN "Phase 3 decisions"). Names are ours: live names
-- carry emoji and event tags. Removing one delists it: trading stops and
-- holdings pay out at the last price.

local RobloxMarket = {}

RobloxMarket.EXPERIENCES = {
	{ ticker = "RBX-BRKH", universeId = 1686885941, name = "Brookhaven RP" }, -- Roleplay & Avatar Sim, since 2020, Minimal
	{ ticker = "RBX-STBR", universeId = 7709344486, name = "Steal a Brainrot" }, -- Simulation, since 2025, Minimal
	{ ticker = "RBX-ADPT", universeId = 383310974, name = "Adopt Me!" }, -- Roleplay & Avatar Sim, since 2017, Minimal
	{ ticker = "RBX-JJSH", universeId = 3508322461, name = "Jujutsu Shenanigans" }, -- Action, since 2022, Mild
	{ ticker = "RBX-99NF", universeId = 7326934954, name = "99 Nights in the Forest" }, -- Survival, since 2025, Minimal
	{ ticker = "RBX-RVLS", universeId = 6035872082, name = "RIVALS" }, -- Shooter, since 2024, Mild
	{ ticker = "RBX-BLXF", universeId = 994732206, name = "Blox Fruits" }, -- RPG, since 2019, Mild
	{ ticker = "RBX-FSHT", universeId = 6701277882, name = "Fish It!" }, -- Simulation, since 2024, Minimal
	{ ticker = "RBX-DNDY", universeId = 5569032992, name = "Dandy's World" }, -- Survival, since 2024, Mild
	{ ticker = "RBX-CTLG", universeId = 2711375305, name = "Catalog Avatar Creator" }, -- Shopping, since 2021, Minimal
	{ ticker = "RBX-DTI", universeId = 5203828273, name = "Dress to Impress" }, -- Roleplay & Avatar Sim, since 2023, Minimal
	{ ticker = "RBX-PS99", universeId = 3317771874, name = "Pet Simulator 99" }, -- Simulation, since 2022, Minimal
	{ ticker = "RBX-FSCH", universeId = 5750914919, name = "Fisch" }, -- Simulation, since 2024, Minimal
	{ ticker = "RBX-TSB", universeId = 3808081382, name = "The Strongest Battlegrounds" }, -- Action, since 2022, Mild
	{ ticker = "RBX-VBLL", universeId = 6931042565, name = "Volleyball Legends" }, -- Sports & Racing, since 2024, Minimal
	{ ticker = "RBX-EVDE", universeId = 3647333358, name = "Evade" }, -- Survival, since 2022, Mild
	{ ticker = "RBX-ANAD", universeId = 3183403065, name = "Anime Adventures" }, -- Strategy, since 2021, Mild
	{ ticker = "RBX-FRSK", universeId = 6331902150, name = "Forsaken" }, -- Survival, since 2024, Mild
	{ ticker = "RBX-DOOR", universeId = 2440500124, name = "DOORS" }, -- Survival, since 2021, Mild
	{ ticker = "RBX-SOLS", universeId = 5361032378, name = "Sol's RNG" }, -- Simulation, since 2023, Minimal
	{ ticker = "RBX-FLEE", universeId = 372226183, name = "Flee the Facility" }, -- Survival, since 2017, Mild
	{ ticker = "RBX-BEES", universeId = 601130232, name = "Bee Swarm Simulator" }, -- Simulation, since 2018, Minimal
	{ ticker = "RBX-BERY", universeId = 3240075297, name = "Berry Avenue RP" }, -- Roleplay & Avatar Sim, since 2022, Minimal
	{ ticker = "RBX-FLNG", universeId = 2668101271, name = "Fling Things and People" }, -- Simulation, since 2021, Mild
	{ ticker = "RBX-LIFE", universeId = 4839802560, name = "LifeTogether RP" }, -- Roleplay & Avatar Sim, since 2023, Minimal
	{ ticker = "RBX-NFLU", universeId = 184199275, name = "NFL Universe Football" }, -- Sports & Racing, since 2018, Minimal
	{ ticker = "RBX-VNGD", universeId = 5578556129, name = "Anime Vanguards" }, -- Strategy, since 2024, Minimal
	{ ticker = "RBX-BLXB", universeId = 88070565, name = "Welcome to Bloxburg" }, -- Roleplay & Avatar Sim, since 2014, Minimal
	{ ticker = "RBX-HYPR", universeId = 5995470825, name = "Hypershot" }, -- Shooter, since 2024, Mild
	{ ticker = "RBX-BDWR", universeId = 2619619496, name = "BedWars" }, -- Action, since 2021, Minimal
	{ ticker = "RBX-DRVE", universeId = 1202096104, name = "Driving Empire" }, -- Simulation, since 2019, Minimal
	{ ticker = "RBX-CSON", universeId = 1831550657, name = "Creatures of Sonaria" }, -- Roleplay & Avatar Sim, since 2020, Minimal
	{ ticker = "RBX-RSSC", universeId = 4949420752, name = "Realistic Street Soccer" }, -- Sports & Racing, since 2023, Minimal
	{ ticker = "RBX-GRWG", universeId = 7436755782, name = "Grow a Garden" }, -- Simulation, since 2025, Minimal
	{ ticker = "RBX-AOTR", universeId = 4658598196, name = "Attack on Titan Revolution" }, -- RPG, since 2023, Mild
	{ ticker = "RBX-PIGY", universeId = 1516533665, name = "Piggy" }, -- Survival, since 2020, Mild
	{ ticker = "RBX-DRMV", universeId = 6521100398, name = "Dreamville RP" }, -- Roleplay & Avatar Sim, since 2024, Minimal
	{ ticker = "RBX-TDS", universeId = 1176784616, name = "Tower Defense Simulator" }, -- Strategy, since 2019, Minimal
	{ ticker = "RBX-BLRV", universeId = 6325068386, name = "Blue Lock: Rivals" }, -- Sports & Racing, since 2024, Minimal
	{ ticker = "RBX-BLDB", universeId = 4777817887, name = "Blade Ball" }, -- Action, since 2023, Mild
	{ ticker = "RBX-GRNV", universeId = 371263894, name = "Greenville RP" }, -- Roleplay & Avatar Sim, since 2017, Minimal
	{ ticker = "RBX-SLAP", universeId = 2380077519, name = "Slap Battles" }, -- Action, since 2021, Mild
	{ ticker = "RBX-ASTD", universeId = 1720936166, name = "All Star Tower Defense" }, -- Strategy, since 2020, Minimal
	{ ticker = "RBX-UBG", universeId = 4730278139, name = "Untitled Boxing Game" }, -- Action, since 2023, Mild
	{ ticker = "RBX-ABA", universeId = 578392296, name = "Anime Battle Arena" }, -- Action, since 2018, Mild
	{ ticker = "RBX-RBCH", universeId = 7178032757, name = "Rebirth Champions: Ultimate" }, -- Simulation, since 2025, Minimal
	{ ticker = "RBX-GRTD", universeId = 7703614594, name = "Garden Tower Defense" }, -- Strategy, since 2025, Minimal
	{ ticker = "RBX-HWFS", universeId = 8342498724, name = "Heavyweight Fishing" }, -- Simulation, since 2025, Minimal
	{ ticker = "RBX-100D", universeId = 9167377564, name = "100 Days at Sea" }, -- Survival, since 2025, Minimal
	{ ticker = "RBX-FORG", universeId = 7671049560, name = "The Forge" }, -- RPG, since 2025, Mild
}

-- How the research view words the two kinds of number (GDD §6 asks they
-- never be confused)
RobloxMarket.OBSERVED_NOTE = "Observed: public stats from Roblox, refreshed every minute."
RobloxMarket.SIMULATED_NOTE = "Simulated price: modeled from players online (averaged over 7 days), the "
	.. "like ratio, a week's growth and how recently it was updated. Not a real valuation of the experience "
	.. "or its developer."
RobloxMarket.WARMUP_NOTE = "New listing: trading opens once a full day of player counts is in, so the "
	.. "time of day it was listed can't skew its price. Until then the price is still forming."

local byTicker = {}

for _, experience in ipairs(RobloxMarket.EXPERIENCES) do
	byTicker[experience.ticker] = experience
end

-- The listed experience for a ticker, or nil
function RobloxMarket.getExperience(ticker: string)
	return byTicker[ticker]
end

return RobloxMarket
