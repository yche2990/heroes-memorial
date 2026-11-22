--- H6 memorial hero spells: put the original H6 battlefield statuses on stacks hit by the spell (h6Chilled Chilled, h6Frozen Frozen,
--- h6Soaked Soaked, h6Dazed Dazed; shared by the Dynasty Weapons and the memorial). Written after the damage effects, applied only to stacks still alive; statuses are cast as spells and immunity follows the engine's rules.
--- Parameters: status (status name), hostileOnly (only the casting side's enemies), livingOnly (only living stacks)
local Base = require("spells/unitEffect")   -- 2026-11-07 test: spellEffect cannot get the stacks in the spell's area, so the status was never applied
local L = require("combat/h6Lib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:isValidTarget(mechanics, unit) return unit:isAlive() end
function Script:applicableGeneral(mechanics, problem) return true end
function Script:applicableTarget(mechanics, problem, target) return true end

function Script:apply(mechanics, server, target)
	if not server:describeChanges() then return end      -- Not cast in the AI simulation
	local battle = mechanics:getBattle()
	local sp = LIBRARY:getSpellByName("kad-mechanics:" .. (self.status or ""))
	if not sp then return end
	local side = mechanics:getCasterSide()
	for _, dest in ipairs(target) do
		local u = dest.unit
		if u and u:isAlive() and L.real(u) and not (self.hostileOnly and u:getSide() == side) and not (self.livingOnly and not L.isLiving(u)) then
			local others = battle:getUnitsIf(function(x) return x:getSide() ~= u:getSide() and x:isAlive() and not x:isTurret() end)
			server:castSpell(battle, others[1] or u, sp, { u }, 0)
		end
	end
end

if not Base.describeTargetStep then function Script:describeTargetStep() return nil end end

return Script
