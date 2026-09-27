dofile_once("mods/recocards_birthday/files/scripts/util.lua")
local RQ_BOOK_NOTES = dofile_once("mods/recocards_birthday/files/book_notes.lua") or {}

function RQ_DiscoverBirthdayCard(id,author,acquisition,silent)
    if id == nil or id == "" then return false end

    acquisition = acquisition == "kill" and "kill" or "pickup"

    local flag = RQ_FoundFlag(id)

    if GameHasFlagRun(flag) then
        return false
    end

    GameAddFlagRun(flag)
    ModSettingSet(
        "recocards_birthday.found_" .. id,
        true
    )

    local found =
        tonumber(
            GlobalsGetValue(
                "recocards_found",
                "0"
            )
        ) or 0

    local total =
        tonumber(
            GlobalsGetValue(
                "recocards_total",
                "0"
            )
        ) or 0

    found = found + 1

    GlobalsSetValue(
        "recocards_found",
        tostring(found)
    )

    local sequence =
        tonumber(
            GlobalsGetValue(
                "recocards_discovery_sequence",
                "0"
            )
        ) or 0

    local persistent_sequence =
        tonumber(
            ModSettingGet(
                "recocards_birthday.discovery_sequence"
            )
        ) or 0

    if persistent_sequence > sequence then
        sequence = persistent_sequence
    end

    sequence = sequence + 1

    GlobalsSetValue(
        "recocards_discovery_sequence",
        tostring(sequence)
    )

    GlobalsSetValue(
        "recocards_discovery_order_" .. id,
        tostring(sequence)
    )

    ModSettingSet(
        "recocards_birthday.discovery_order_" .. id,
        sequence
    )

    ModSettingSet(
        "recocards_birthday.discovery_sequence",
        sequence
    )

    ModSettingSet(
        "recocards_birthday.discovery_method_" .. id,
        acquisition
    )

    GlobalsSetValue(
        "recocards_discovery_method_" .. id,
        acquisition
    )

    local pool = RQ_BOOK_NOTES[acquisition] or {}
    local note_counter_key = "recocards_birthday.note_sequence_" .. acquisition
    local note_global_key = "recocards_note_sequence_" .. acquisition
    local note_sequence = tonumber(GlobalsGetValue(note_global_key,"0")) or 0
    local persistent_note_sequence = tonumber(ModSettingGet(note_counter_key)) or 0

    if persistent_note_sequence > note_sequence then
        note_sequence = persistent_note_sequence
    end

    note_sequence = note_sequence + 1
    GlobalsSetValue(note_global_key,tostring(note_sequence))
    ModSettingSet(note_counter_key,note_sequence)

    local function gcd(a,b)
        while b ~= 0 do
            a,b = b,a % b
        end
        return a
    end

    local note_index = 1
    if #pool > 0 then
        local step = acquisition == "kill" and 53 or 37
        step = step % #pool
        if step == 0 then step = 1 end

        while gcd(step,#pool) ~= 1 do
            step = step + 1
            if step >= #pool then step = 1 end
        end

        local offset = acquisition == "kill" and 29 or 17
        note_index = (((note_sequence - 1) * step + offset) % #pool) + 1
    end

    ModSettingSet(
        "recocards_birthday.discovery_note_" .. id,
        note_index
    )

    GlobalsSetValue(
        "recocards_discovery_note_" .. id,
        tostring(note_index)
    )

    if not silent then
        GamePrintImportant(
            (author or "Birthday Spirit") .. "'s Birthday Page",
            tostring(found) ..
            " / " ..
            tostring(total) ..
            " cards added to the book"
        )
    end

    return true
end
