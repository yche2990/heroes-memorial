--- Mana Leech (H6) probe: after the spell is cast, the first stack on its side to finish acting is the one that was acting when it was cast; it will not "start acting" again this round,
--- so MANA_DRAIN is handed to another stack on its side (drained this round if it has not acted yet, next round if it has); if it is the only one left, it is handed to itself (drained next round).
--- If that never happens (the stack dies while acting etc.), it is handed to the first stack receiving an event at the start of the next round. After draining, h6SpManaLeechEnd removes it.
--- Parameters: spell (full spell name), amount (mana drained), level (casting level; the handed-over spell effect bonus stores it as sourceSecondaryID)
--- Review 2026-11-08: A1 the handed-over MANA_DRAIN / h6SpManaLeechEnd now carry the casting level (without it the engine records "any level" = 5 and the right-click description indexes out of range);
---               B6 handed() only searches its own side's stacks (when both sides cast Mana Leech it used to take the other side's entry for its own).
local Base = require("combat/combatScript")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function handed(battle, spell, side)
	local found = false
	battle:getUnitsIf(function(u)
		if not found and u:isAlive() and u:getSide() == side then
			local list = u:getBonuses({ type = "MANA_DRAIN" }):filter(function(b) return b:getSourceID() == spell end)
			if list:size() > 0 then found = true end
		end
		return false
	end)
	return found
end

local function handoff(self, server, battle, unit, preferOther)
	local side = unit:getSide()
	if handed(battle, self.spell, side) then return end
	local own = battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() and not x:isTurret() end)
	for _, u in ipairs(own) do S.removeSpell(server, battle, u, self.spell) end
	local carrier, minTurns = nil, 2
	if preferOther then
		for _, u in ipairs(own) do if u:unitID() ~= unit:unitID() then carrier = u; break end end
	end
	if carrier == nil then
		carrier = unit
		if preferOther then minTurns = 1 end    -- Handed to itself right after acting: that action does not count this round; drained next round, then removed
	end
	local d = { duration = "N_TURNS", turns = 2, sourceType = "SPELL_EFFECT", sourceID = self.spell,
		sourceSecondaryID = self.level or 0, hidden = true }
	local function add(t) for k, v in pairs(d) do t[k] = v end; server:addUnitBonus(battle, carrier, t, false) end
	add({ type = "MANA_DRAIN", val = self.amount or 0, stacking = "h6SpManaLeech" })
	add({ type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpManaLeechEnd", val = 0, addInfo = { spell = self.spell, minTurns = minTurns } })
end

function Script:onActionFinished(server, battle, unit, other, payload)
	if other == nil or other:unitID() ~= unit:unitID() then return end
	handoff(self, server, battle, unit, true)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if unit:isAlive() then handoff(self, server, battle, unit, false) end
end

return Script
