local Base = require("combat/combatScript")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Stealth (H4-H7 mechanics port, round 139; matches H6 Dungeon's Veil of Shadows)
---
--- At battle start the stack casts this mod's Stealth spell on itself (h47Stealth, see config/h47/spells.json):
---   - it cannot be targeted by attacks or spells (INVINCIBLE), attack damage +10%, and targets cannot retaliate;
---   - the stack fades to translucent (color fade in config/battleEffects.json), restored automatically when Stealth ends;
---   - after it attacks, or after 3 rounds, the spell effect ends naturally;
---   - if an enemy is adjacent at the start of a round, this script removes Stealth (revealed), plays the Dispel glow and writes a battle log line.
--- The damage bonus uses stacking group h47Stealth, so with other mods' stealth effects the larger one counts and they do not add up.
--- Only stacks on the field at battle start go into Stealth; those summoned or cloned later do not.
---
--- Parameters:
---   spell  JSON name of the Stealth spell, e.g. "heroes-memorial:h47Stealth"
---   mark   bonus name of this mod for texts; its value description 1 is the battle log line "revealed by approaching enemy"

local TAG = "h47Stealth"
local REVEAL_ANIMATION = "h47/fx/fx_stealthReveal" -- Round 150: dedicated reveal animation (it used to borrow the Dispel glow C05SPW)

--- Effects attached by this mod's Stealth spell (source is a spell whose name contains h47Stealth)
local function stealthBonuses(unit)
	return unit:getBonuses({ sourceType = ENUM.BonusSource.spellEffect }):filter(function(b)
		return string.find(b:getSourceID(), TAG, 1, true) ~= nil
	end)
end

local function adjacent(a, b)
	local around = a:getSurroundingHexes()
	local hexes = b:getHexes()
	for i = 1, hexes:size() do
		if around:contains(hexes:at(i)) then return true end
	end
	return false
end

function Script:onBattleStart(server, battle, unit, other, payload)
	if not unit:isAlive() or unit:isGhost() or unit:isClone() then return end

	local spell = LIBRARY:getSpellByName(self.spell)
	if spell == nil then
		error("h47Stealth: unknown spell " .. tostring(self.spell))
	end

	-- Casting plays the fade-out glow, and the engine writes the "cast Stealth" battle log line
	server:castSpell(battle, unit, spell, { unit }, 0)
end

function Script:onRoundStart(server, battle, unit, other, payload)
	if not unit:isAlive() then return end

	local bonuses = stealthBonuses(unit)
	if bonuses:size() == 0 then return end

	local side = unit:getSide()
	local enemies = battle:getUnitsIf(function(u)
		return battle:isHostile(unit, u) and u:isAlive() and not u:isGhost() and not u:isTurret() and adjacent(unit, u)
	end)
	if #enemies == 0 then return end

	server:removeUnitBonuses(battle, unit, bonuses)
	server:showBattleAnimation(battle, { { unit = unit } }, REVEAL_ANIMATION, "", 1.0, true) server:refreshBattleUnits(battle)
	server:appendLog(battle, {
		append         = { "core.bonus." .. self.mark .. ".description.1" },
		replaceStrings = { unit:getCreature():getNameTextID(unit:getCount()) }
	})
end

return Script
