--- Implosion (H6): damage dealt by Implosion cannot be healed or resurrected. The stack's health cap is kept in a hidden mark (total health at battle start - total Implosion damage),
--- and any recovery (spells, regeneration, life drain...) above the cap is taken back at the next settlement. Parameter: key (mark name)
local Base = require("combat/combatScript")
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:clamp(server, battle, unit)
	if not unit:isAlive() then return end
	local cap = L.markValue(unit, self.key)
	if cap == nil then return end
	local over = unit:getAvailableHealth() - cap
	if over > 0 then server:damageUnit(battle, unit, over) end
end

function Script:onSpellHit(server, battle, unit) self:clamp(server, battle, unit) end
function Script:onRoundStart(server, battle, unit) self:clamp(server, battle, unit) end
function Script:onActionFinished(server, battle, unit) self:clamp(server, battle, unit) end
function Script:onAfterAttack(server, battle, unit) self:clamp(server, battle, unit) end

return Script
