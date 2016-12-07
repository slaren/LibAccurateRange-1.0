local MAJOR_VERSION = "LibAccurateRange-1.0"
local MINOR_VERSION = 1

if not AceLibrary then error(MAJOR_VERSION .. " requires AceLibrary") end
if not AceLibrary:IsNewVersion(MAJOR_VERSION, MINOR_VERSION) then return end
if not AceLibrary:HasInstance("AceEvent-2.0") then error(MAJOR_VERSION .. " requires AceEvent-2.0") end

local AceEvent = AceLibrary("AceEvent-2.0")

local spells_40yd = {
	["Holy Light"] = true, ["Flash of Light"] = true,
	["Flash Heal"] = true, ["Heal"] = true, ["Lesser Heal"] = true, ["Greater Heal"] = true, ["Renew"] = true,
	["Healing Touch"] = true, ["Regrowth"] = true, ["Rejuvenation"] = true,
	["Healing Wave"] = true, ["Lesser Healing Wave"] = true, ["Chain Heal"] = true,
}

do
	local locale = GetLocale()

	if locale ~= "enUS" and locale ~= "enGB" then
		if AceLibrary:HasInstance("Babble-Spell-2.2") then
			local BS = AceLibrary("Babble-Spell-2.2")
			local loc_spells_40yd = {}
			for k, _ in pairs(spells_40yd) do
				loc_spells_40yd[BS[k]] = true
			end
			spells_40yd = loc_spells_40yd
		else
			error("AccurateRange requires Babble-Spell-2.2 for localization")
		end
	end
end

local _G = getfenv(0)
local next = next
local table_insert, table_getn, table_setn = table.insert, table.getn, table.setn
local GetTime = GetTime
local AttackTarget = AttackTarget
local IsCurrentAction, IsActionInRange = IsCurrentAction, IsActionInRange
local CheckInteractDistance = CheckInteractDistance
local TargetLastTarget, TargetUnit = TargetLastTarget, TargetUnit
local UnitExists, UnitIsCharmed, UnitIsConnected, UnitIsDeadOrGhost, UnitIsFriend, UnitIsUnit, UnitIsVisible = UnitExists, UnitIsCharmed, UnitIsConnected, UnitIsDeadOrGhost, UnitIsFriend, UnitIsUnit, UnitIsVisible

local frame = CreateFrame("Frame")
local Frame_GetScript = frame.GetScript
local Frame_SetScript = frame.SetScript
local Frame_GetChildren = frame.GetChildren
local Frame_GetParent = frame.GetParent


local action_slot_40yd
local action_slot_attack
local scan_units = {}
local current_scan_unit

local scan_tip = CreateFrame("GameTooltip", "AccurateRangeScanTip", nil, "GameTooltipTemplate")
scan_tip:SetOwner(scan_tip, "ANCHOR_NONE")
local scan_tip_l1 = AccurateRangeScanTipTextLeft1
local scan_tip_r1 = AccurateRangeScanTipTextRight1

local function print(...)
	for k = 1,table.getn(arg) do arg[k] = tostring(arg[k]) end
	DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00AccurateRange:|r " .. table.concat(arg, " "))
end

local function table_length(t)
	local count = 0
	local n = next(t)
	while n do
		count = count + 1
		n = next(t, n)
	end
	return count
end

local timedb = {}
local function timef(label, func, a1, a2, a3, a4)
	local start = debugprofilestop()
	func(a1, a2, a3, a4)
	local elapsed = debugprofilestop() - start

	if not timedb[label] then
		timedb[label] = { min = elapsed, max = elapsed, avg = elapsed }
	else
		--timedb[label].min =
	end

	print("<" .. (label or "unk") .. ">", elapsed / 1000000, "ms")
end

local function GetActionSpell(slot)
	if not HasAction(slot) or GetActionText(slot) then
		return nil
	end

	scan_tip:SetAction(slot)

	local lines = scan_tip:NumLines()
	if lines and lines > 0 then
		local spell_name = scan_tip_l1:IsShown() and scan_tip_l1:GetText()
		if spell_name ~= "" then
			return spell_name
		end
	end
end

local function ScanActionButtons()
	action_slot_40yd = nil
	action_slot_attack = nil

	for slot = 1, 120 do
		local spell_name = GetActionSpell(slot)
		if spells_40yd[spell_name] then
			print(slot, ": ", spell_name)
			action_slot_40yd = slot
			if action_slot_attack then return end
		end

		--elseif spells_attack[spell_name] then
		if IsAttackAction(slot) then
			print(slot, ": ", spell_name)
			action_slot_attack = slot
			if action_slot_40yd then return end
		end
	end

	error("AccurateRange: no suitable spell found in an action button")
end

local all_found_frames = {}
local event_found_frames
local disabled_frames

--[[
local function IsFrameInternal(f)
	local function has_func(func)
		return type(f[func]) == "function"
	end

	if type(rawget(f, 0)) == "userdata" and has_func("SetScript") and has_func("GetScript") and has_func("GetChildren") and has_func("GetParent") then
		-- very effective, but too slow to use as the first test
		Frame_GetScript(f, "OnEvent")
		return true
	end
end

local function IsFrame(f)
	local succ, res = pcall(IsFrameInternal, f)
	return succ and res
end

local function ScanFrame(frame)
	if not all_found_frames[frame] then
		all_found_frames[frame] = true
		for _, f in ipairs({ Frame_GetChildren(frame) }) do
			if not all_found_frames[f] and IsFrame(f) then ScanFrame(f) end
		end
		
		if Frame_GetParent(frame) then
			ScanFrame(Frame_GetParent(frame))
		end
	end
end

local scanned_tables = {}
local function ScanTableFrames(t)
	if scanned_tables[t] then return end
	scanned_tables[t] = true
	for name, f in pairs(t) do
		if type(f) == "table" then
			if IsFrame(f) then
				ScanFrame(f)
			end
			ScanTableFrames(f)
		end
	end
end
]]

local function ScanFrames()
	all_found_frames = {}
	event_found_frames = nil

	local frame = EnumerateFrames()
	while frame do
		all_found_frames[frame] = true
		frame = EnumerateFrames(frame)
	end

	-- scanned_tables = {}
	-- ScanTableFrames(_G)
	-- scanned_tables = nil
	print("Found", table_length(all_found_frames), "frames");
end

local function Frame_Tag_OnEvent()
	event_found_frames[this] = true
end

local function DisableFrames()
	disabled_frames = event_found_frames or all_found_frames

	-- print("disabling", table_length(disabled_frames))

	-- first run, tag the frames that are triggering OnEvent calls
	local new_func
	if not event_found_frames then
		event_found_frames = {}
		new_func = Frame_Tag_OnEvent
	end

	local frame = next(disabled_frames)
	while frame do
		frame.__ar_orig_onevent = Frame_GetScript(frame, "OnEvent")
		Frame_SetScript(frame, "OnEvent", new_func)
		frame = next(disabled_frames, frame)
	end
end

local function RestoreFrames()
	-- print("restoring", table_length(disabled_frames))
	local frame = next(disabled_frames)
	while frame do
		Frame_SetScript(frame, "OnEvent", frame.__ar_orig_onevent)
		frame = next(disabled_frames, frame)
	end
end

local function IsValidUnit(unit)
	return UnitExists(unit) and
			not UnitIsUnit("player", unit) and
			not UnitIsDeadOrGhost(unit) and
			UnitIsConnected(unit) and
			UnitIsVisible(unit) and
			UnitIsFriend("player", unit) and
			not UnitIsCharmed(unit)
end

local function AdvanceScanUnit()
	current_scan_unit = next(scan_units, current_scan_unit)
	if current_scan_unit == nil then
		current_scan_unit = next(scan_units)
	end
end

local function SetUnitRange(unit, inrange)
	if scan_units[unit] ~= inrange then
		scan_units[unit] = inrange
		AceEvent:TriggerEvent("AccurateRange_UnitUpdate", unit, inrange)
	end
end

local function GetNextScanUnit()
	local start_scan_unit = current_scan_unit

	while true do
		local scan_unit = current_scan_unit

		AdvanceScanUnit()
		
		if UnitIsUnit(scan_unit, "player") then
			SetUnitRange(scan_unit, true)
		elseif IsValidUnit(scan_unit) then
			if CheckInteractDistance(scan_unit, 4) then
				SetUnitRange(scan_unit, true)
			else
				return scan_unit
			end
		else
			SetUnitRange(scan_unit, false)
		end

		if current_scan_unit == start_scan_unit then
			-- print("no valid units")
			return nil
		end
	end
end

local function UpdateRoster()
	local function add_unit(unit)
		if UnitExists(unit) then
			scan_units[unit] = 0
		else
			scan_units[unit] = nil
		end
	end

	for i = 1, 40 do add_unit("raid" .. i) end
	for i = 1, 4 do add_unit("party" .. i) end
	scan_units["player"] = 0
	current_scan_unit = next(scan_units)
end

local next_update_time = 0
local scan_update_time
local update_interval = 0.005
local max_updates_per_frame = 3
local restore_attack = false
local current_frame = 0
local max_uptime_time_ns = 2000000
local function AccurateRange_OnUpdate()
	current_frame = current_frame + 1
	-- AttackTarget won't work on the same frame that the target changed, so try
	-- for the next few frames
	if restore_attack and (current_frame - restore_attack) > 30 then
		restore_attack = false
	elseif restore_attack and not IsCurrentAction(action_slot_attack) then
		AttackTarget()
		restore_attack = false
	end

	if scan_update_time and GetTime() >= scan_update_time then
		scan_update_time = nil
		timef("ScanFrames", ScanFrames)
		if not action_slot_attack or not action_slot_40yd then
			ScanActionButtons()
		end
	end

	if GetTime() < next_update_time then return end
	next_update_time = GetTime() + update_interval

	if not action_slot_40yd then return end

	local start_time = debugprofilestop()
	local num_updated_units = 0

	local restore_frames
	for upd = 1, max_updates_per_frame do
		local unit = GetNextScanUnit()
		if not unit then break end

		num_updated_units = num_updated_units + 1
		
		if action_slot_attack and IsCurrentAction(action_slot_attack) == 1 then
			restore_attack = current_frame
		end

		local change_target = not UnitIsUnit("target", unit)
		if change_target then
			if not restore_frames then
				-- timef("disable", DisableFrames)
				DisableFrames()
				restore_frames = true
			end
			-- timef("TargetUnit", TargetUnit, unit)
			TargetUnit(unit)
		end

		local inrange = IsActionInRange(action_slot_40yd) == 1
		SetUnitRange(unit, inrange)

		if change_target then
			TargetLastTarget()
		end

		local elapsed_time = debugprofilestop() - start_time
		if elapsed_time > max_uptime_time_ns then
			break
		end
	end

	if restore_frames then
		-- timef( "restore", RestoreFrames)
		RestoreFrames()
	end

	local elapsed_time = debugprofilestop() - start_time
	if random() > 0.99 and num_updated_units > 0 then
		print("update done in", elapsed_time / 1000000, "ms,", num_updated_units, "units updated")
	end
end

local function AccurateRange_OnEvent()
	if event == "PLAYER_ENTERING_WORLD" then
		scan_update_time = GetTime() + 3
	elseif event == "ACTIONBAR_SLOT_CHANGED" then
		if arg1 == 0 or action_slot_40yd == arg1 or action_slot_attack == arg1 or not action_slot_40yd or not action_slot_attack then
			ScanActionButtons()
		end
	elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
		UpdateRoster()
	end
end

local function AccurateRange_IsUnitInRange(unit)
	if scan_units[unit] == nil then
		print(unit, "not found")
		return
	end
	return scan_units[unit] == true
end

local function AccurateRange_Enable()
	frame:SetScript("OnUpdate", AccurateRange_OnUpdate)
	frame:SetScript("OnEvent", AccurateRange_OnEvent)
	frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	frame:RegisterEvent("PLAYER_ENTERING_WORLD")
	frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
	frame:RegisterEvent("RAID_ROSTER_UPDATE")
	UpdateRoster()
	scan_update_time = GetTime() + 3
end

local function AccurateRange_Disable()
	frame:UnregisterAllEvents()
	frame:SetScript("OnUpdate", nil)
end

do
	AccurateRange_Enable()
end

local AccurateRange = {
	["IsUnitInRange"] = AccurateRange_IsUnitInRange
}

AceLibrary:Register(AccurateRange, MAJOR_VERSION, MINOR_VERSION)