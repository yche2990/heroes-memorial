--- Stone Spikes (H7): all stacks on the target hex and the ring around it (H7's 5-hex cross) take base + perPower x Spell Power Earth damage
--- (h5Damage formula and damage adjustment, friend or foe); centerFactor[mastery]: multiplied again by this factor for the stack on the target hex (Expert = Earth Understanding III: double at the center).
--- The target hex is put first in the target list (an entry with only a hex and no stack), so the stack at the center can be identified when settling.
local Base = require("spells/h5Damage")
local Lib = require("spells/h5SpellLib")
local Script = setmetatable({}, {__index = Base})
Script.__index = Script

function Script:transformTarget(mechanics, aimPoint, spellTarget)
	local list = Base.transformTarget(self, mechanics, aimPoint, spellTarget)
	local aim = aimPoint[1]
	if aim and aim.hex and aim.hex:isValid() then
		table.insert(list, 1, { hex = aim.hex })
	end
	return list
end

function Script:filterTarget(mechanics, target)
	local result = {}
	for _, dest in ipairs(target) do
		if dest.unit == nil and dest.hex ~= nil then
			table.insert(result, dest)
		elseif dest.unit and self:isValidTarget(mechanics, dest.unit) and self:isReceptive(mechanics, dest.unit) then
			table.insert(result, dest)
		end
	end
	return result
end

function Script:apply(mechanics, server, target)
	local battle = mechanics:getBattle()
	local describe = server:describeChanges()
	local center = nil
	for _, dest in ipairs(target) do
		if dest.unit == nil and dest.hex ~= nil then center = dest.hex break end
	end
	local factor = 1
	if self.centerFactor then factor = self.centerFactor[Lib.level(mechanics) + 1] or 1 end
	local firstUnit, total, kills, multiple = nil, 0, 0, false
	for _, dest in ipairs(target) do
		local unit = dest.unit
		if unit and unit:isAlive() then
			local amount = Base.damageForTarget(self, 0, mechanics, unit)
			if center and factor ~= 1 and unit:coversPos(center) then amount = math.floor(amount * factor) end
			local dmg, killed = server:damageUnit(battle, unit, amount)
			if describe then
				if firstUnit then multiple = true else firstUnit = unit end
				total = total + dmg
				kills = kills + killed
			end
		end
	end
	if describe and firstUnit and total > 0 and self.describeEffect then
		self:describeEffect(server, battle, mechanics, firstUnit, kills, total, multiple)
	end
end

function Script:describeTargetStep(mechanics, partialTarget, hoveredHex)
	return nil
end

--- Hover estimate: same formula as apply (h5Damage damage, times centerFactor for the stack standing on the target hex); damage and kills of all targets are summed
function Script:getHealthChange(mechanics, spellTarget)
	local ok, result = pcall(function()
		local out = { hpDelta = 0, unitsDelta = 0 }
		local target = self:filterTarget(mechanics, spellTarget)
		local center = nil
		for _, dest in ipairs(target) do
			if dest.unit == nil and dest.hex ~= nil then center = dest.hex break end
		end
		local factor = 1
		if self.centerFactor then factor = self.centerFactor[Lib.level(mechanics) + 1] or 1 end
		for _, dest in ipairs(target) do
			local unit = dest.unit
			if unit and unit:isAlive() then
				local amount = Base.damageForTarget(self, 0, mechanics, unit)
				if center and factor ~= 1 and unit:coversPos(center) then amount = math.floor(amount * factor) end
				local copy = unit:copy()
				local hp, cnt = copy:getAvailableHealth(), copy:getCount()
				copy:damage(amount)
				out.hpDelta = out.hpDelta - (hp - copy:getAvailableHealth())
				out.unitsDelta = out.unitsDelta - (cnt - copy:getCount())
			end
		end
		return out
	end)
	if ok and result then return result end
	return { hpDelta = 0, unitsDelta = 0 }
end

return Script
