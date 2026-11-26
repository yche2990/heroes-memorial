--- Blessing of the Earth Mother (H6 class ability, approximation): the original raises the count of friendly Stronghold stacks by pct% for 1 round, with the extra creatures taking damage first.
--- VCMI cannot add creatures temporarily, so instead: damage +pct% (written in the h5Timed of the same spell, limited by faction to Stronghold and Horde),
--- plus an absorbing shield on those stacks = pct% of their current total health (settled by combat/h6SpShieldAbsorb), both lasting turns rounds.
--- Only stacks that already got this spell's damage bonus (that is, Stronghold and Horde stacks) get the shield. Parameters: pct, turns (4 numbers)
local Base = require("spells/unitEffect")
local L = require("combat/h6Lib")
local S = require("lib/h6SpLib")
local Proxy = require("lib/kadAiProxy")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit) return unit:isAlive() and unit:getSide() == mechanics:getCasterSide() end
function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local key = mechanics:getSpell():getJsonKey()
	local pct = S.pick(mechanics, self.pct)
	local turns = math.max(1, S.pick(mechanics, self.turns) or 1)
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() then
			local mine = u:getBonuses({ type = "PERCENTAGE_DAMAGE_BOOST" }):filter(function(b) return b:getSourceID() == key end)
			if mine:size() > 0 then
				local amount = math.floor(u:getAvailableHealth() * pct / 100)
				if Proxy.trial(server) then
					Proxy.buff(server, battle, u, { type = "PRIMARY_SKILL", subtype = "defence", val = 3, turns = turns })
				elseif amount > 0 then
					server:addUnitBonus(battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpShieldAbsorb", val = 0,
						duration = "N_TURNS", turns = turns, sourceType = "SPELL_EFFECT", sourceID = key, sourceSecondaryID = mechanics:getEffectLevel(),
						addInfo = { pct = 100, spell = key, key = key } }, false)
					L.setMark(server, battle, u, key, amount, turns)
				end
			end
		end
	end
end

if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
