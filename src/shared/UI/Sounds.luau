-- Sounds.luau
--
-- The game's sound effects, played on the client: Sounds.play("Fill").
-- They're Roblox's own UI sounds, plus a Roblox-licensed APM sting for
-- level-ups, so they stay public (other creators' audio can be made private
-- and go silent). Each Sound is made the first time it plays.

local SoundService = game:GetService("SoundService")

local Sounds = {}

local SOUNDS = {
	Click = { id = 15675032796, volume = 0.4 }, -- Roblox_UI_Small_Click
	Fill = { id = 15675055424, volume = 0.6 }, -- Roblox_UI_Cute_Pop
	Profit = { id = 15675043410, volume = 0.6 }, -- Roblox_UI_Tonal_Stinger
	Challenge = { id = 15675085146, volume = 0.6 }, -- Roblox_UI_Indicator
	LevelUp = { id = 9038514384, volume = 0.5 }, -- APM, "Halfway to Rio (sting b)"
	Error = { id = 15675062723, volume = 0.4 }, -- Roblox_UI_Whistle_Low
}

local made = {} -- [name] = Sound

function Sounds.play(name: string)
	local sound = made[name]

	if not sound then
		local info = SOUNDS[name]

		if not info then
			warn("[Sounds] No sound named " .. tostring(name))

			return
		end

		sound = Instance.new("Sound")
		sound.Name = name
		sound.SoundId = "rbxassetid://" .. info.id
		sound.Volume = info.volume
		sound.Parent = SoundService
		made[name] = sound
	end

	sound:Play()
end

return Sounds
