-- ThesisModule.luau
--
-- The rules for theses, kept free of Roblox services so the Lune tests can
-- run them. ThesisService applies them. `rules` is Config/Social, passed in
-- because a server module can't reach ReplicatedStorage from Lune.
--
-- A thesis:
--   { id, userId, displayName, username, ticker, direction ("Bullish" or
--     "Bearish"), horizon (a THESIS_HORIZONS id), targetPrice?, priceAtPost,
--     text? (already filtered for broadcast), createdAt, endsAt }
-- priceAtPost is kept so a later phase can score how theses played out.

local ThesisModule = {}

local MAX_TARGET_PRICE = 1e9

-- Trimmed, with every run of whitespace (newlines included) as one space;
-- nil when nothing is left
function ThesisModule.normalizeText(text: string): string?
	local normalized = string.gsub(string.gsub(text, "%s+", " "), "^ ", "")

	normalized = string.gsub(normalized, " $", "")

	return if normalized == "" then nil else normalized
end

-- Checks a draft from the client: { direction, horizon, targetPrice?,
-- text? }. `price` is the ticker's price now. Returns true, or false and the
-- reason to show the player.
function ThesisModule.validate(draft, price: number, rules)
	if type(draft) ~= "table" then
		return false, "Invalid thesis."
	end

	if not table.find(rules.THESIS_DIRECTIONS, draft.direction) then
		return false, "Pick bullish or bearish."
	end

	if type(draft.horizon) ~= "string" or not rules.getHorizon(draft.horizon) then
		return false, "Pick a time horizon."
	end

	local target = draft.targetPrice

	if target ~= nil then
		-- target == target rules out NaN
		if type(target) ~= "number" or target ~= target or target <= 0 or target >= MAX_TARGET_PRICE then
			return false, "Enter a target price above $0."
		elseif draft.direction == "Bullish" and target <= price then
			return false, "A bullish target has to be above the current price."
		elseif draft.direction == "Bearish" and target >= price then
			return false, "A bearish target has to be below the current price."
		end
	end

	if draft.text ~= nil then
		if type(draft.text) ~= "string" then
			return false, "Invalid text."
		end

		local length = utf8.len(draft.text)

		if not length then
			return false, "Invalid text."
		elseif length > rules.THESIS_TEXT_MAX then
			return false, string.format("Keep it to %d characters.", rules.THESIS_TEXT_MAX)
		end
	end

	return true, nil
end

-- At most `perDay` theses per UTC day. `social` is playerData.Social.
function ThesisModule.checkDailyLimit(social, now: number, perDay: number)
	local today = os.date("!%Y-%m-%d", now)

	if social.ThesisDay == today and social.ThesesToday >= perDay then
		return false, string.format("You can publish %d theses a day.", perDay)
	end

	return true, nil
end

function ThesisModule.countPublish(social, now: number)
	local today = os.date("!%Y-%m-%d", now)

	if social.ThesisDay ~= today then
		social.ThesisDay = today
		social.ThesesToday = 0
	end

	social.ThesesToday += 1
end

-- The player's thesis on `ticker` that hasn't ended yet, if any: one open
-- thesis per ticker, so a player can't hold both sides
function ThesisModule.findOpen(theses, ticker: string, now: number)
	for _, thesis in ipairs(theses) do
		if thesis.ticker == ticker and thesis.endsAt > now then
			return thesis
		end
	end

	return nil
end

-- Appends to a list kept oldest first, dropping the oldest past `cap`
function ThesisModule.addToList(list, thesis, cap: number)
	table.insert(list, thesis)

	while #list > cap do
		table.remove(list, 1)
	end

	return list
end

-- Removes the thesis with `id`; returns whether one was there
function ThesisModule.removeFromList(list, id: string): boolean
	for index, thesis in ipairs(list) do
		if thesis.id == id then
			table.remove(list, index)

			return true
		end
	end

	return false
end

-- Up to `limit` copies, newest first. Without text when the viewer can't
-- see it (`textHidden` says there was some).
function ThesisModule.forViewer(list, limit: number, canSeeText: boolean)
	local copies = {}

	for index = #list, math.max(#list - limit + 1, 1), -1 do
		local copy = table.clone(list[index])

		if not canSeeText and copy.text then
			copy.text = nil
			copy.textHidden = true
		end

		table.insert(copies, copy)
	end

	return copies
end

-- Records a report on a thesis in its report `record` (nil for the first):
-- { thesis, reporters = { [userId string] = { at, counted } }, counted,
-- firstReportedAt, takenDown? }. A reporter counts once, and only when
-- `counts` (their account is old enough). Returns the record and whether
-- this report is the one that reached `threshold`.
function ThesisModule.addReport(record, thesis, reporterId: number, counts: boolean, now: number, threshold: number)
	record = record or { thesis = thesis, reporters = {}, counted = 0, firstReportedAt = now }

	local key = tostring(reporterId)

	if record.reporters[key] then
		return record, false
	end

	record.reporters[key] = { at = now, counted = counts }

	if counts then
		record.counted += 1
	end

	if record.counted >= threshold and not record.takenDown then
		record.takenDown = true

		return record, true
	end

	return record, false
end

-- Open theses on each side, for a ticker's "3 bullish · 1 bearish"
function ThesisModule.countOpen(list, now: number)
	local counts = { Bullish = 0, Bearish = 0 }

	for _, thesis in ipairs(list) do
		if thesis.endsAt > now and counts[thesis.direction] then
			counts[thesis.direction] += 1
		end
	end

	return counts
end

return ThesisModule
