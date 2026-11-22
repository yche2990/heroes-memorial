local Base = require("combat/combatScript")
local A = require("heroes-memorial.h5:combat/h5Area")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

--- Death Cloud (H5 Lich, Arch Lich)
--- After a shot hits, non-undead stacks in the ring around the target (friend or foe) take val% (default 50%) of this stack's shot damage.
--- Parameter: val

function Script:onAfterAttack(server, battle, unit, other, payload)
	if not payload.ranged or payload.isCounter then return end
	if not unit:isAlive() then return end
	local target = A.primary(payload, other)
	if target == nil then return end
	local ring = target:getSurroundingHexes()
	local seen, victims = { [target:unitID()] = true, [unit:unitID()] = true }, {}
	for i = 1, ring:size() do
		local u = battle:getUnitByPos(ring:at(i), true)
		if u ~= nil and not seen[u:unitID()] and A.damageable(u) and not A.isUndead(u) then
			seen[u:unitID()] = true
			table.insert(victims, u)
		end
	end
	if #victims == 0 then return end
	server:showBattleAnimation(battle, { { unit = target } }, "h5/fx/Characters_Creatures_Necropolis_Lich_DeathCloud_Effect", "DEATHCLD", 0.6, true)
	for _, v in ipairs(victims) do
		if v:isAlive() then
			A.hit(server, battle, v, A.attackDamage(server, unit, v, self.val or 50, true), nil, nil)
		end
	end
end

return Script
