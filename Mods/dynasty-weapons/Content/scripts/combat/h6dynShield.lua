--- H6 Dynasty Weapons: shield at battle start (Angel Alliance level 3 "Heavenly Armor", Tide Staff level 5 "Frost Bastion").
--- Original: Heavenly Armor (mass) absorbs 100% of damage until ShieldValue (171/223/290, scaling with hero stats) is absorbed;
---       Frost Armor absorbs 100% of damage up to 225 for 4 rounds, and melee attackers are "chilled".
--- Here: at battle start every own stack gets a shield absorbing at most val damage: after attack and spell damage land, health is restored by the absorbed amount (even those killed by that hit are saved),
---       damage from this mod's scripts (damage over time, reflected damage...) is taken from the shield before it lands;
---       with turns > 0 it lasts only turns rounds; with chill true, stacks attacking it in melee are chilled (original Chilled: movement -1, physical damage taken +20%, 1 round; since round 316t heroes-memorial:h6Chilled is cast).
--- Status: H6DYN_SHIELD_LEFT (remaining absorption, hidden), H6DYN_SHIELD_ON (for display, with description; vanishes by rounds when turns is set)
--- "Already restored this hit" convention (review A5, 2026-11-08; see the healedValue section of spells/h6dynLib, the same convention as combat/h6Lib of the H6 memorial):
---   attack damage only absorbs the part not yet restored by other scripts (H6 Heavenly Armor, Earth Mother's Blessing, Sacrifice, Ignore Pain, Feign Death...), and the amount absorbed is recorded on the target's
---   MEMORIAL_MARK mark (stacking "h6Healed|<attacker id>"); onBeforeAttacked clears these marks. Spell damage is worked out from the difference between unitBefore and current health.
---   Several restoring effects together restore at most one share of the same hit.
local Base = require("combat/combatScript")
local Lib = require("spells/h6dynLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

local function on(unit)
	return unit:getBonusesValue({ type = "H6DYN_SHIELD_ON" }) > 0
end

function Script:onBattleStart(server, battle, unit)
	if not unit:isAlive() or unit:isTurret() then return end
	if on(unit) then return end
	Lib.setCounter(server, battle, unit, "H6DYN_SHIELD_LEFT", self.val or 0)
	local d = { type = "H6DYN_SHIELD_ON", val = 1, duration = "ONE_BATTLE", sourceType = "OTHER" }
	if (self.turns or 0) > 0 then d.duration = "N_TURNS"; d.turns = self.turns end
	if self.text then d.description = "@" .. self.text end
	if self.icon then d.icon = self.icon end
	server:addUnitBonus(battle, unit, d, false)
	if Lib.anim(server, battle, unit, self.anim) then server:refreshBattleUnits(battle) end
end

--- Damage already dealt is restored up to the shield's remaining amount (even those killed by that hit are saved; with the Ring of Oblivion in play only healing, no resurrection, as hota ringOfOblivionPatch)
--- Returns the amount restored
local function healBack(server, battle, unit, dealt)
	if dealt <= 0 then return 0 end
	local _, absorbed = Lib.absorb(server, battle, unit, dealt)
	if absorbed > 0 then
		local level = Lib.ringOfOblivion(unit) and ENUM.HealLevel.heal or ENUM.HealLevel.resurrect
		server:healUnit(battle, unit, absorbed, level, ENUM.HealPower.permanent)
	end
	return absorbed
end

function Script:onBeforeAttacked(server, battle, unit, other, payload)
	Lib.clearHealed(server, battle, unit)
end

function Script:onAfterAttacked(server, battle, unit, other, payload)
	local wasOn = on(unit)
	if wasOn then
		local entry = self:ownEntry(unit, payload)
		if entry then
			Lib.addHealed(server, battle, unit, other, healBack(server, battle, unit, Lib.unhealed(unit, other, entry.damage)))
		end
	end
	if self.chill and other and other:isAlive() and not payload.ranged and not payload.isCounter and wasOn then
		-- Round 316t: casts the original H6 Chilled (heroes-memorial:h6Chilled, Speed -1, attack damage taken +20%, 1 round, original icon and tint)
		Lib.status(server, battle, other, "h6Chilled", unit)
	end
end

--- Spell damage (hero and stack spells) is absorbed too; this mod's own script damage already went through the shield in Lib.damage
function Script:onSpellHit(server, battle, unit, other, payload)
	if not on(unit) then return end
	local entry = self:ownEntry(unit, payload)
	if not entry or not entry.unitBefore then return end
	healBack(server, battle, unit, entry.unitBefore:getAvailableHealth() - unit:getAvailableHealth())
end

return Script
