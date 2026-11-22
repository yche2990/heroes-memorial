local Base = require("combat/combatScript")
local H5 = require("combat/h5Common")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- H5: cast a spell on the target by chance when attacking (Blinding Attack, Curse Attack, Lash Attack, Mark of Fire, Purge, Sleep Attack, Wound Strike)
---
--- After its own attack (not retaliation) hits an enemy, a chance is rolled on the first target; on success spell is cast (or one picked at random from spells).
--- Chance: chance% if given (times Deduction), otherwise by the H5 trigger factor pf (h5Common.procChance, by the ratio of both sides' total health).
--- Cast with server:castSpell; the effect value is encoded by the spells/h5SpellLib convention (1000000 + level x 100000 + spell power),
--- spell power = power (fixed) or, if not given, this stack's creature spell power (h5Common.creatureSP); duration is computed by the spell with the H5 formula.
--- Immunity: spell immunity, mind immunity (Blind, Berserk, Sleep) and non-living (Lash, Sleep, Wound, Blind) are checked by the script first; immune targets roll no chance.
---
--- Parameters:
---   spell / spells  spell id (this mod's h5Ab*); spells is an array, one picked at random
---   pf              H5 trigger factor; chance fixed chance (percent), give one of the two
---   power           fixed spell power
---   mastery         spell level 0-3
---   melee / ranged  whether melee / ranged attacks trigger

--- H5 duration of the spell (base, per point of spell power), animation, immunity tags
local INFO = {
	h5AbBlind         = { dur = { 0, 0.15 }, anim = "h5/fx/Spells_Blind", sound = "BLIND",    tags = { mind = true, living = true } },
	h5AbCurse         = { dur = { 0, 1 },    anim = "h5/fx/Spells_Curse",  sound = "CURSE",    tags = { negative = true } },
	h5AbSlow          = { dur = { 0, 1 },    anim = "h5/fx/Spells_Slow", sound = "MUCKMIRE", tags = { negative = true } },
	h5AbWeakness      = { dur = { 0, 1 },    anim = "h5/fx/Spells_Weakness", sound = "WEAKNESS", tags = { negative = true } },
	h5AbDisruptingRay = { dur = { 0, 1 },    anim = "h5/fx/Spells_DisruptingRay", sound = "DISRUPTR", tags = { negative = true } },
	h5AbBerserk       = { dur = { 1, 0 },    anim = "h5/fx/Spells_Berserk",  sound = "BERSERK",  tags = { mind = true, living = true } },
	h5AbMarkOfFire    = { dur = { 2, 0 },    anim = "h5/fx/Characters_FireHit", sound = "FIRESHLD", tags = { school = "fire" } },
	h5AbPurge         = { dur = { 1, 0 },    anim = nil,  sound = "DISPELL",  tags = {} },
	h5AbSleep         = { dur = { 2, 0 },    anim = "h5/fx/Spells_Blind", sound = "HYPNOTIZ", tags = { mind = true, living = true } },
	h5AbWound         = { dur = { 2, 0 },    anim = "h5/fx/Characters_hits_closecombat_hit03", sound = "WEAKNESS", tags = { living = true } }
}

local function pick(self, server)
	if self.spells and #self.spells > 0 then
		return self.spells[server:rngInt(1, #self.spells)]
	end
	return self.spell
end

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not unit:isAlive() then return end
	if payload.isCounter then return end
	if payload.ranged then
		if self.ranged == false then return end
	else
		if self.melee == false then return end
	end

	local entry = H5.firstTarget(payload)
	if entry == nil then return end
	local target = entry.unit
	if target == nil or not target:isAlive() or not battle:isHostile(unit, target) then return end
	if target:isInvincible() or target:hasBonuses({ type = "SIEGE_WEAPON" }) then return end

	local name = pick(self, server)
	if name == nil then return end
	local info = INFO[name] or { dur = { 0, 1 }, tags = {} }
	if H5.immuneToSpell(target, name, info.tags) then return end

	local chance
	if self.chance then
		chance = math.min(100, math.floor(self.chance * (100 + H5.boost(unit)) / 100))
	else
		chance = H5.procChance(unit, target, self.pf or 1)
	end
	if not H5.roll(server, battle, unit, chance) then return end

	local spell = H5.spell(name)
	if spell == nil then return end

	local power = self.power or H5.creatureSP(unit)
	local mastery = self.mastery or 0
	local turns = math.floor(info.dur[1] + info.dur[2] * power)
	if turns < 1 then turns = 1 end

	-- Level and spell power are encoded into the effect value by the convention of this mod's spell library (spells/h5SpellLib): 1000000 + level x 100000 + spell power.
	-- castSpell plays the spell animation and filters targets by the spell's own immunity rules; duration is computed by the spell itself with the H5 formula
	server:castSpell(battle, unit, spell, { target }, 1000000 + mastery * 100000 + power)

	-- Sleep Attack: records who put it to sleep; that stack's next hit on it deals maximum damage (damage rule see damage/h5DamagePatch)
	if name == "h5AbSleep" then
		server:addUnitBonus(battle, target, {
			type       = "H5_SLEEP_H5C",
			val        = unit:unitID() + 1,
			duration   = { "N_TURNS", "UNTIL_AFTER_ATTACK_SEQUENCE" },
			turns      = turns,
			sourceType = ENUM.BonusSource.other,
			sourceID   = unit:getCreature():getJsonKey(),
			stacking   = "h5Sleep",
			hidden     = true
		}, false)
	end
	server:refreshBattleUnits(battle)
end

return Script
