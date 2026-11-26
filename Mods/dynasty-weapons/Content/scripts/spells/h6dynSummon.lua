--- H6 Dynasty Weapons: summons of fixed count (Summon Juggernaut, Spectral Dragon).
--- The core summon count is hero Spell Power x spell level power; dynasty weapon summons have a fixed count, only affected by
--- SPECIFIC_SPELL_DAMAGE bonuses such as "summoning ability". Apart from the amount parameter, as the core summon (id, permanent, exclusive...).
local Base = require("spells/summon")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:summonedEffectValue(mechanics)
	return mechanics:applySpecificSpellBonus(self.amount or 1)
end

--- Cursor and status bar text while choosing a target: return nil to use the engine default ("Cast X on Y" / "Cast X", with damage and healing estimates added automatically).
--- Every spell effect script must define this function.
function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

return Script
