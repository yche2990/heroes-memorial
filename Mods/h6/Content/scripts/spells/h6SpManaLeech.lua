--- Mana Leech (H6, approximation): the original steals pct% of the enemy hero's current mana for your hero; VCMI combat scripts cannot change hero mana (Yu decided on 2026-11-07 to make an approximation),
--- so here the enemy hero loses pct% x own hero's maximum mana (Knowledge x 10) mana (not more than it has), once.
--- How it works: the engine's MANA_DRAIN drains once when a stack starts acting each round. The stack acting when the hero casts has already passed its "start acting" this round,
--- so first every own stack gets a probe (combat/h6SpManaLeechProbe); once the acting stack finishes, MANA_DRAIN is handed to another stack.
--- Parameter: pct (4 numbers)
local Base = require("spells/spellEffect")
local S = require("lib/h6SpLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target) return true end
function Script:transformTarget(mechanics, aimPoint, spellTarget) return spellTarget end
function Script:filterTarget(mechanics, target) return target end

function Script:apply(mechanics, server, target)
	if not server:describeChanges() then return end
	local battle = mechanics:getBattle()
	local hero = mechanics:getHeroCaster()
	local know = 0
	if hero then
		local ok, v = pcall(function() return hero:getPrimarySkill("knowledge") end)
		if ok and v then know = v end
	end
	local amount = math.floor(S.pick(mechanics, self.pct) * know * 10 / 100)
	if amount <= 0 then return end
	local key = mechanics:getSpell():getJsonKey()
	local side = mechanics:getCasterSide()
	for _, u in ipairs(battle:getUnitsIf(function(x) return x:getSide() == side and x:isAlive() and not x:isTurret() end)) do
		server:addUnitBonus(battle, u, { type = "COMBAT_EVENT_TRIGGER", subtype = "heroes-memorial.h6:h6SpManaLeechProbe", val = amount,
			duration = "N_TURNS", turns = 2, sourceType = "SPELL_EFFECT", sourceID = key, sourceSecondaryID = mechanics:getEffectLevel(),
			hidden = true, addInfo = { spell = key, amount = amount, level = mechanics:getEffectLevel() } }, false) -- level: review A1, the bonus handed over by the probe must also carry the casting level
	end
end

return Script
