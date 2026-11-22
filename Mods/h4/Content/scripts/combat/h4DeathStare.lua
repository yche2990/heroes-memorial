--- Heroes IV Memorial: Medusa Stone Gaze. Chance and kills as the engine's combat/deathStare (called directly).
--- The engine casts the Death Stare spell with castSpell, and the client plays that spell's Heroes III animation, which the script cannot replace; so this step is taken over:
--- targets are checked with the Death Stare spell's immunity conditions, the Heroes IV stone_gaze plays, then creatures are killed by count (as the spell's killByCount) and the battle log is written as by the spell.
local Core = require("combat/deathStare")
local Fx = require("heroes-memorial.h4:combat/h4FxCore")
local BattleLog = require("battleLog")
local Script = setmetatable({}, {__index = Core})
Script.__index = Script

local IMMUNE = { "NON_LIVING", "MECHANICAL", "SIEGE_WEAPON", "UNDEAD", "GARGOYLE" }

local function immune(t, spell)
	if t:hasAbsoluteImmunity(spell) or t:isInvincible() then return true end
	for _, ty in ipairs(IMMUNE) do if t:hasBonuses({ type = ty }) then return true end end
	if t:hasBonuses({ type = "SPELL_IMMUNITY", subtype = "deathStare" }) then return true end
	-- Stacks immune to Stone Gaze (Troglodytes and others) are also protected from Medusas (round 587)
	if t:hasBonuses({ type = "SPELL_IMMUNITY", subtype = "stoneGaze" }) then return true end
	if t:hasBonuses({ type = "NEGATIVE_EFFECTS_IMMUNITY", subtype = "any" }) then return true end
	return false
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	local proxy = Fx.proxy(server, nil, function(b, caster, spell, targets, killed)
		for _, t in ipairs(targets) do
			if t and t:isAlive() and not immune(t, spell) and (killed or 0) > 0 then
				local n = math.min(killed, t:getCount())
				local dmg = (n - 1) * t:getMaxHealth() + t:getFirstHPleft()
				server:showBattleAnimation(b, { { unit = t } }, "h4/fx/stone_gaze", "DEATHSTR", 1.0, true)
				local dealt, k = server:damageUnit(b, t, dmg)
				BattleLog.spellDamage(server, b, spell, t, dealt, k)
			end
		end
	end)
	return Core.onAfterAttack(self, proxy, battle, unit, other, payload)
end

return Script
