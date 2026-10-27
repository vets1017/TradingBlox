-- Confetti.luau
--
-- A burst of confetti from a point, for wins: a profitable sale, a finished
-- challenge, a new level. The pieces are small frames thrown out and up,
-- then left to fall and fade, and removed after. Client-only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Theme = require(ReplicatedStorage.Modules.Multi.Theme)

local Confetti = {}

local COLORS = { Theme.Colors.Accent, Theme.Colors.AccentSoft, Theme.Colors.Up, Theme.Colors.Text }
local DEFAULT_PIECES = 36
local UPWARD_BIAS = 70 -- px; the burst throws up more than down

local random = Random.new()

-- `origin` is a position in `parent`; `pieces` defaults to a full burst
function Confetti.burst(parent: GuiObject, origin: UDim2, pieces: number?, zIndex: number?)
	for _ = 1, pieces or DEFAULT_PIECES do
		local piece = Instance.new("Frame")
		piece.Name = "Confetti"
		piece.BorderSizePixel = 0
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Size = UDim2.fromOffset(random:NextInteger(6, 10), random:NextInteger(3, 6))
		piece.Position = origin
		piece.Rotation = random:NextInteger(0, 359)
		piece.BackgroundColor3 = COLORS[random:NextInteger(1, #COLORS)]
		piece.ZIndex = zIndex or 1
		piece.Parent = parent

		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = random:NextNumber(80, 220)
		local outX = math.cos(angle) * distance
		local outY = math.sin(angle) * distance * 0.6 - UPWARD_BIAS

		local throw = TweenService:Create(
			piece,
			TweenInfo.new(random:NextNumber(0.35, 0.5), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = origin + UDim2.fromOffset(outX, outY),
				Rotation = piece.Rotation + random:NextInteger(-180, 180),
			}
		)

		throw.Completed:Connect(function()
			local fall = TweenService:Create(
				piece,
				TweenInfo.new(random:NextNumber(0.9, 1.4), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Position = origin + UDim2.fromOffset(outX * 1.2, outY + random:NextNumber(220, 360)),
					Rotation = piece.Rotation + random:NextInteger(-360, 360),
					BackgroundTransparency = 1,
				}
			)

			fall.Completed:Connect(function()
				piece:Destroy()
			end)

			fall:Play()
		end)

		throw:Play()
	end
end

return Confetti
