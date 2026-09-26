dofile_once("mods/recocards_birthday/files/custom_credits/custom_credits.lua")
ModLuaFileAppend("data/scripts/gun/gun_actions.lua","mods/recocards_birthday/files/birthday_actions.lua")
ModLuaFileAppend("data/scripts/gun/gun_actions.lua","mods/recocards_birthday/files/glimmer_birthday/gun_actions.lua")
dofile_once("mods/recocards_birthday/files/glimmer_birthday/glimmer.lua")
dofile_once("mods/recocards_birthday/files/punchout_arcade/arcade.lua")
dofile_once("mods/recocards_birthday/files/mortal_kombat/arcade.lua")
dofile_once("mods/recocards_birthday/files/rhythm_arcade/arcade.lua")
dofile_once("mods/recocards_birthday/files/celebratium/celebratium.lua")
dofile_once("mods/recocards_birthday/files/trial_of_the_gods/trial.lua")

-- === Moist Mobbing wiring (ported from the sweatlingTest POC) ================
-- Reusable debug logger (consumer side lives here; init.lua has `io`). Producers
-- in any context call LOG(channel, msg) -> Globals queue; drained to a file each
-- frame. Moist Mobbing effect (main-context side) runs the actual entity spawns;
-- the streaming hook only enqueues requests across the context boundary.
dofile_once("mods/recocards_birthday/files/scripts/sweatling/debug_log.lua")
dofile_once("mods/recocards_birthday/files/scripts/sweatling/moist_mob_spawn.lua")

-- Streaming hook appended onto vanilla event_utilities.lua so our
-- _streaming_on_irc loads into the engine's callback context (which has no io,
-- so it logs via the Globals-queue LOG()).
ModLuaFileAppend(
    "data/scripts/streaming_integration/event_utilities.lua",
    "mods/recocards_birthday/files/scripts/sweatling/streaming_hook.lua"
)

-- Master Moist Mobbing toggle (settings.lua, ON by default). When OFF the whole
-- effect is inert: no queue draining, no spawns, no voting suppression.
local function moist_mobbing_enabled()
    return ModSettingGet("recocards_birthday.moist_mobbing_enabled") ~= false
end

-- Debug logging toggle (settings.lua). When OFF we skip the per-frame file
-- writes entirely.
local function moist_logging_enabled()
    return ModSettingGet("recocards_birthday.logging_enabled") == true
end

-- True when the native streaming client reports a live connection. The engine
-- returns int (1) or bool depending on build, so handle both.
local function moist_streaming_connected()
    local c = StreamingGetIsConnected()
    return c == 1 or c == true
end

-- Drain the Moist Mobbing queues (records enqueued by the streaming hook) and
-- run each in this main context. Records separated by \30: the sub/gift queue
-- holds celebrant names, the chatter queue holds numeric twitch ids.
local MOIST_SUBGIFT_QUEUE_KEY = "recocards_birthday_moist_mob_queue"
local MOIST_CHATTER_QUEUE_KEY = "recocards_birthday_moist_chatter_queue"
local function drain_moist_mob_queue()
    local queue = GlobalsGetValue(MOIST_SUBGIFT_QUEUE_KEY, "") or ""
    if queue ~= "" then
        GlobalsSetValue(MOIST_SUBGIFT_QUEUE_KEY, "")
        for celebrant in string.gmatch(queue, "([^\30]+)") do
            MoistMob_SpawnSubEffect(celebrant)
        end
    end

    local chatters = GlobalsGetValue(MOIST_CHATTER_QUEUE_KEY, "") or ""
    if chatters ~= "" then
        GlobalsSetValue(MOIST_CHATTER_QUEUE_KEY, "")
        for twitch_id in string.gmatch(chatters, "([^\30]+)") do
            MoistMob_QueuePulse(twitch_id)
        end
    end
end

-- Per-frame Moist Mobbing update: drain logs + queues, tick the test replay,
-- amortize spawns, and suppress vanilla Twitch voting while connected. Called
-- from OnWorldPreUpdate.
local function moist_mob_update()
    if not moist_mobbing_enabled() then return end
    if moist_logging_enabled() then LOG_DrainAll() end
    drain_moist_mob_queue()
    if MoistMob_TickReplay then MoistMob_TickReplay() end
    MoistMob_ProcessSpawnQueue()
    if moist_streaming_connected() then
        StreamingSetVotingEnabled(false)
    end
end
-- === end Moist Mobbing wiring ================================================

function OnModInit()
    dofile_once("mods/recocards_birthday/retextures/apply_retextures.lua")
    ModDevGenerateSpriteUVsForDirectory("mods/recocards_birthday/data/enemies_gfx/player.png")
    BirthdayCredits_OnModInit()
    RhythmArcade_OnModInit()
    BirthdayGlimmer_OnModInit()
    PunchOutArcade_OnModInit()
    MortalKombatArcade_OnModInit()
    ModMaterialsFileAdd(
        "mods/recocards_birthday/files/birthday_materials.xml"
    )

    local translations =
        ModTextFileGetContent(
            "data/translations/common.csv"
        )

    local key =
        "mat_recocards_guiding_powder"

    if
        string.find(
            translations,
            key,
            1,
            true
        ) ~= nil
    then
        translations =
            string.gsub(
                translations,
                "mat_recocards_guiding_powder,[^\r\n]*",
                "mat_recocards_guiding_powder,Birthday Guiding Powder,"
            )
    else
        translations =
            translations ..
            "\nmat_recocards_guiding_powder,Birthday Guiding Powder,\n"
    end

    ModTextFileSetContent(
        "data/translations/common.csv",
        translations
    )


    local function clone_sprite_metadata(source,target,png)
        local xml =
            ModTextFileGetContent(source)

        if xml == nil or xml == "" then
            return false
        end

        local replaced,count =
            string.gsub(
                xml,
                'filename="[^"]+%.png"',
                'filename="' .. png .. '"',
                1
            )

        if count == 0 then
            return false
        end

        ModTextFileSetContent(
            target,
            replaced
        )

        return true
    end

    clone_sprite_metadata(
        "data/enemies_gfx/player.xml",
        "mods/recocards_birthday/files/gfx/birthday_mina_player.xml",
        "mods/recocards_birthday/files/gfx/birthday_mina_player.png"
    )

    clone_sprite_metadata(
        "data/enemies_gfx/player_arm_no_item.xml",
        "mods/recocards_birthday/files/gfx/birthday_mina_arm.xml",
        "mods/recocards_birthday/files/gfx/birthday_mina_arm.png"
    )

    clone_sprite_metadata(
        "data/enemies_gfx/player_arm.xml",
        "mods/recocards_birthday/files/gfx/birthday_mina_arm_item.xml",
        "mods/recocards_birthday/files/gfx/birthday_mina_arm.png"
    )
end

dofile_once("mods/recocards_birthday/files/scripts/util.lua")
function RQ_WriteBirthdayLinkRequest(card_id,url)
    if io == nil or io.open == nil then
        GamePrintImportant(
            "Birthday Link",
            "Enable Unsafe mods in Noita to open web links."
        )
        return false
    end

    local file =
        io.open(
            "mods/recocards_birthday/files/generated/open_link_request.txt",
            "w"
        )

    if file == nil then
        GamePrintImportant(
            "Birthday Link",
            "Could not write the link request."
        )
        return false
    end

    file:write(
        tostring(card_id) ..
        "\n" ..
        tostring(url) ..
        "\n" ..
        tostring(GameGetFrameNum()) ..
        "\n"
    )
    file:flush()
    file:close()

    return true
end

dofile_once("mods/recocards_birthday/files/scripts/birthday_book_links.lua")
dofile_once("mods/recocards_birthday/files/scripts/birthday_spirit_radar.lua")

local MOD = "mods/recocards_birthday"
local OUT = MOD .. "/files/generated"
local MANIFEST = OUT .. "/manifest.txt"
local ZONES = MOD .. "/bridge/spawn_zones.csv"
local CFG = MOD .. "/bridge/quest_config.txt"

local spawned = false
local gui = nil
local book_page = 1
local book_prev_found_count = -1
local book_zoom_open = false
local book_mode = "cards"
local book_instruction_page = 1
local BOOK_INSTRUCTIONS = dofile_once("mods/recocards_birthday/files/book_instructions.lua") or {}
local BOOK_CARD_NOTES = dofile_once("mods/recocards_birthday/files/book_notes.lua") or {}
local recocards_by_id = {}
local pending_spawns = {}
local quest_zones_cache = {}
local loaded_manifest_text = ""
local cached_config = nil
local cached_config_frame = -1000000
local CONFIG_CACHE_FRAMES = 300

local function get_cached_config()
    local frame = GameGetFrameNum()
    if cached_config == nil or frame - cached_config_frame >= CONFIG_CACHE_FRAMES then
        cached_config = RQ_ReadConfig(CFG)
        cached_config_frame = frame
    end
    return cached_config
end

local function intersects(a,b,margin)
    return not (
        a.r + margin < b.l or
        a.l - margin > b.r or
        a.b + margin < b.t or
        a.t - margin > b.b
    )
end

local function zone_effective_weight(zone,usage)
    local weight = tonumber(zone.weight) or 1
    if weight <= 0 then
        return 0
    end

    local used = 0
    if usage ~= nil then
        used = usage[zone] or 0
    end

    return (1 / weight) / (1 + used * 0.75)
end

local function choose_zone(zones,rng,usage)
    local sum = 0
    for _,z in ipairs(zones) do
        sum = sum + zone_effective_weight(z,usage)
    end

    if sum <= 0 then
        return zones[#zones]
    end

    local r = rng() * sum
    local acc = 0

    for _,z in ipairs(zones) do
        acc = acc + zone_effective_weight(z,usage)
        if r <= acc then
            return z
        end
    end

    return zones[#zones]
end

local function get_card_id(entity)
    local vars = EntityGetComponent(entity,"VariableStorageComponent") or {}
    for _,c in ipairs(vars) do
        if ComponentGetValue2(c,"name") == "recocard_id" then
            return ComponentGetValue2(c,"value_string")
        end
    end
    return nil
end




local function get_or_create_run_spawn_seed()
    local existing =
        tonumber(
            GlobalsGetValue(
                "recocards_run_spawn_seed",
                ""
            )
        )

    if existing ~= nil and existing > 0 then
        return existing
    end


    -- Seed the run RNG before rolling. build_quest runs at world gen, before
    -- anything else seeds the global RNG, so Random() here would otherwise log
    -- "Random() called without calling SetRandomSeed()". Use a stable per-run
    -- position derived from the world seed so the spawn seed is reproducible.
    local ws = tonumber(StatsGetValue("world_seed")) or GameGetFrameNum()
    SetRandomSeed(ws % 100000, (ws * 7919) % 100000)

    local seed = Random(1,2147483000)

    if seed == nil or seed <= 0 then
        seed =
            math.max(
                1,
                GameGetFrameNum()*7919 + 156008746
            )
    end

    GlobalsSetValue(
        "recocards_run_spawn_seed",
        tostring(seed)
    )

    return seed
end

local function card_has_live_world_representation(id)
    local tags = {
        "recocards_birthday_spirit",
        "recocards_dropped_page"
    }

    for _,tag in ipairs(tags) do
        local entities = EntityGetWithTag(tag) or {}

        for _,e in ipairs(entities) do
            if EntityGetIsAlive(e) then
                local existing_id = get_card_id(e)

                if existing_id == id then
                    return true
                end
            end
        end
    end

    return false
end

local function spawn_note(card,x,y)
    local author = card.author or "Birthday Spirit"

    local spirit = EntityLoad(
        MOD .. "/files/entities/sweatling.xml",
        x,
        y
    )

    if spirit == nil or spirit == 0 then
        GamePrint(
            "Birthday Quest: failed to spawn spirit for " ..
            author
        )
        return
    end

    EntitySetName(spirit,author)
    EntityAddTag(spirit,"recocards_birthday_note")
    EntityAddTag(spirit,"recocards_birthday_spirit")


    EntityAddTag(spirit,"hittable")

    EntityAddComponent2(spirit,"VariableStorageComponent",{
        name="recocard_id",
        value_string=card.id
    })

    EntityAddComponent2(spirit,"VariableStorageComponent",{
        name="recocard_author",
        value_string=author
    })

    EntityAddComponent2(spirit,"VariableStorageComponent",{
        name="recocards_safe_position_done",
        value_int=0
    })

    dofile_once(
        "mods/recocards_birthday/files/scripts/sweatling/spawn_sweatling.lua"
    )
    RQ_DressSweatling(spirit,author)

    -- NOTE: the author name is now rendered by the sweatling's own text-sprite
    -- (attach_sweatling_name via sweatling_layers.lua). The old UIInfoComponent
    -- name label was removed here because it duplicated that name in-game.
    --
    -- The author-specific interact prompt (ui_text) is now set on the entity by
    -- RQ_DressSweatling (spawn_sweatling.lua), which already receives the author.
    -- The old per-spawn ui_text override lived here previously.
end

local function nearest_uncollected_note()
    local players = EntityGetWithTag("player_unit") or {}
    if #players == 0 then return nil end

    local player = players[1]
    local px,py = EntityGetTransform(player)

    local best = nil
    local best_d2 = nil

    local function consider(id,x,y,entity)
        if
            id ~= nil and
            not GameHasFlagRun(
                RQ_FoundFlag(id)
            )
        then
            local dx,dy = x-px,y-py
            local d2 = dx*dx + dy*dy

            if best == nil or d2 < best_d2 then
                best = {
                    entity=entity,
                    id=id,
                    x=x,
                    y=y,
                    d2=d2,
                    player=player
                }
                best_d2=d2
            end
        end
    end

    local spirits =
        EntityGetWithTag(
            "recocards_birthday_spirit"
        ) or {}

    for _,e in ipairs(spirits) do
        if EntityGetIsAlive(e) then
            local id = get_card_id(e)
            local x,y = EntityGetTransform(e)
            consider(id,x,y,e)
        end
    end

    local pages =
        EntityGetWithTag(
            "recocards_dropped_page"
        ) or {}

    for _,e in ipairs(pages) do
        if EntityGetIsAlive(e) then
            local id = get_card_id(e)
            local x,y = EntityGetTransform(e)
            consider(id,x,y,e)
        end
    end


    for _,pending in ipairs(pending_spawns) do
        if not pending.spawned then
            consider(
                pending.card.id,
                pending.x,
                pending.y,
                nil
            )
        end
    end

    return best
end


local function give_starting_guiding_powder(player)
    if GlobalsGetValue(
        "recocards_start_guiding_powder_given",
        "0"
    ) == "1" then
        return
    end

    local x,y = EntityGetTransform(player)

    local potion =
        EntityLoad(
            "data/entities/items/pickup/potion_empty.xml",
            x,
            y
        )

    if potion == nil or potion == 0 then
        GamePrint(
            "Birthday Quest: failed to create Birthday Guiding Powder potion"
        )
        return
    end

    AddMaterialInventoryMaterial(
        potion,
        "recocards_guiding_powder",
        1000
    )

    EntitySetName(
        potion,
        "Birthday Guiding Powder"
    )

    local item =
        EntityGetFirstComponentIncludingDisabled(
            potion,
            "ItemComponent"
        )

    if item ~= nil then
        ComponentSetValue2(
            item,
            "item_name",
            "Birthday Guiding Powder"
        )

        ComponentSetValue2(
            item,
            "ui_description",
            "Points toward the nearest missing Birthday Page."
        )

        ComponentSetValue2(
            item,
            "always_use_item_name_in_ui",
            true
        )
    end

    GamePickUpInventoryItem(
        player,
        potion,
        false
    )

    GlobalsSetValue(
        "recocards_start_guiding_powder_given",
        "1"
    )

    GamePrintImportant(
        "Birthday Guiding Powder",
        "Pour it out to reveal the direction of the nearest missing birthday page."
    )
end

local function update_birthday_guiding_target()

    if GameGetFrameNum()%15 ~= 0 then
        return
    end

    local target =
        nearest_uncollected_note()

    if target == nil then
        GlobalsSetValue(
            "recocards_guiding_target_x",
            ""
        )

        GlobalsSetValue(
            "recocards_guiding_target_y",
            ""
        )

        return
    end

    GlobalsSetValue(
        "recocards_guiding_target_x",
        tostring(target.x)
    )

    GlobalsSetValue(
        "recocards_guiding_target_y",
        tostring(target.y)
    )
end


local function get_variable_component(entity,name)
    local vars = EntityGetComponent(entity,"VariableStorageComponent") or {}
    for _,c in ipairs(vars) do
        if ComponentGetValue2(c,"name") == name then
            return c
        end
    end
    return nil
end

local function note_position_clear_of_other_notes(entity,x,y,min_distance)
    local notes = EntityGetWithTag("recocards_birthday_spirit") or {}
    local min_d2 = min_distance * min_distance

    for _,other in ipairs(notes) do
        if other ~= entity and EntityGetIsAlive(other) then
            local ox,oy = EntityGetTransform(other)
            local dx,dy = ox-x,oy-y
            if dx*dx + dy*dy < min_d2 then
                return false
            end
        end
    end

    return true
end

-- Forward declarations: these placement helpers are defined much later in this
-- file, but find_safe_note_position (below) calls them. Without forward-
-- declaring the locals here, the calls would resolve as nil globals at runtime
-- ("attempt to call global 'spirit_ground_position' (a nil value)").
local spirit_body_clear
local spirit_ground_position

local function find_safe_note_position(entity,x,y)
    local free_x,free_y =
        FindFreePositionForBody(
            x,
            y,
            0,
            0,
            10
        )

    if free_x == nil or free_y == nil then
        return nil,nil
    end

    local final_x,final_y =
        spirit_ground_position(
            free_x,
            free_y
        )

    if final_x == nil or final_y == nil then
        return nil,nil
    end

    if not note_position_clear_of_other_notes(
        entity,
        final_x,
        final_y,
        34
    ) then
        return nil,nil
    end

    return final_x,final_y
end

local function update_note_safe_positions()
    local notes = EntityGetWithTag("recocards_birthday_spirit") or {}

    for _,e in ipairs(notes) do
        if EntityGetIsAlive(e) then
            local safe_var =
                get_variable_component(
                    e,
                    "recocards_safe_position_done"
                )

            local done = false
            if safe_var ~= nil then
                done =
                    ComponentGetValue2(safe_var,"value_int") == 1
            end

            if not done then
                local x,y = EntityGetTransform(e)


                if DoesWorldExistAt(
                    math.floor(x-32),
                    math.floor(y-64),
                    math.floor(x+32),
                    math.floor(y+112)
                ) then
                    local safe_x,safe_y =
                        find_safe_note_position(e,x,y)

                    if safe_x ~= nil and safe_y ~= nil then
                        EntitySetTransform(e,safe_x,safe_y,0)

                        if safe_var ~= nil then
                            ComponentSetValue2(
                                safe_var,
                                "value_int",
                                1
                            )
                        end
                    end
                end
            end
        end
    end
end

local function restore_persistent_book_progress(cards)
    local sequence =
        tonumber(
            ModSettingGet(
                "recocards_birthday.discovery_sequence"
            )
        ) or 0

    for _,card in ipairs(cards) do
        local found_key =
            "recocards_birthday.found_" .. card.id

        local order_key =
            "recocards_birthday.discovery_order_" .. card.id

        local persistent_found =
            ModSettingGet(found_key) == true

        local run_found =
            GameHasFlagRun(
                RQ_FoundFlag(card.id)
            )

        local persistent_order =
            tonumber(
                ModSettingGet(order_key)
            )

        local run_order =
            tonumber(
                GlobalsGetValue(
                    "recocards_discovery_order_" .. card.id,
                    ""
                )
            )

        if run_found and not persistent_found then
            ModSettingSet(found_key,true)
            persistent_found = true
        end

        if run_found and persistent_order == nil then
            if run_order == nil then
                sequence = sequence + 1
                run_order = sequence
            end

            persistent_order = run_order
            ModSettingSet(
                order_key,
                persistent_order
            )
        end

        if persistent_found then
            GameAddFlagRun(
                RQ_FoundFlag(card.id)
            )

            if persistent_order == nil then
                sequence = sequence + 1
                persistent_order = sequence
                ModSettingSet(
                    order_key,
                    persistent_order
                )
            end

            GlobalsSetValue(
                "recocards_discovery_order_" .. card.id,
                tostring(persistent_order)
            )

            if persistent_order > sequence then
                sequence = persistent_order
            end
        end
    end

    GlobalsSetValue(
        "recocards_discovery_sequence",
        tostring(sequence)
    )

    ModSettingSet(
        "recocards_birthday.discovery_sequence",
        sequence
    )
end

local function build_quest()
    if spawned then return end

    local cards,manifest_text = RQ_ReadManifest(MANIFEST)

    restore_persistent_book_progress(cards)

    recocards_by_id = {}
    for _,card in ipairs(cards) do
        recocards_by_id[card.id] = card
    end

    local zones = RQ_ReadZones(ZONES)
    quest_zones_cache = zones

    local cfg = get_cached_config()
    if #cards == 0 or #zones == 0 then return end

    local note_w = 18
    local note_h = 20
    local margin = tonumber(cfg.spawn_margin) or 28
    local configured_salt =
        tonumber(cfg.spawn_seed) or 156008746

    local run_seed =
        get_or_create_run_spawn_seed()

    local seed =
        run_seed + configured_salt

    local rng =
        RQ_Rng(
            seed + (#cards * 1009)
        )

    pending_spawns = {}
    local planned = {}
    local zone_usage = {}

    for _,card in ipairs(cards) do

        if
            not GameHasFlagRun(RQ_FoundFlag(card.id)) and
            not card_has_live_world_representation(card.id)
        then
            local hw,hh = note_w*0.5,note_h*0.5
            local planned_ok = false

            for attempt=1,500 do
                local z = choose_zone(zones,rng,zone_usage)

                local minx =
                    math.min(z.x1,z.x2)+hw
                local maxx =
                    math.max(z.x1,z.x2)-hw
                local miny =
                    math.min(z.y1,z.y2)+hh
                local maxy =
                    math.max(z.y1,z.y2)-hh

                if minx <= maxx and miny <= maxy then
                    local x =
                        minx + (maxx-minx)*rng()
                    local y =
                        miny + (maxy-miny)*rng()

                    local box = {
                        l=x-hw,
                        r=x+hw,
                        t=y-hh,
                        b=y+hh
                    }

                    local ok = true
                    for _,other in ipairs(planned) do
                        if intersects(box,other,margin) then
                            ok=false
                            break
                        end
                    end

                    if ok then
                        table.insert(planned,box)

                        table.insert(pending_spawns,{
                            card=card,
                            zone=z,
                            x=x,
                            y=y,
                            seed=
                                math.floor(
                                    rng()*1000000000
                                ) + card.order*7919,
                            failed_passes=0,
                            spawned=false
                        })

                        zone_usage[z] =
                            (zone_usage[z] or 0) + 1

                        planned_ok = true
                        break
                    end
                end
            end

            if not planned_ok then
                GamePrint(
                    "Birthday Quest: no planned zone point for card " ..
                    card.id
                )
            end
        end
    end

    local found = 0
    for _,card in ipairs(cards) do
        if GameHasFlagRun(RQ_FoundFlag(card.id)) then
            found=found+1
        end
    end

    GlobalsSetValue(
        "recocards_total",
        tostring(#cards)
    )
    GlobalsSetValue(
        "recocards_found",
        tostring(found)
    )

    loaded_manifest_text = manifest_text or ""
    spawned = true
end

local function refresh_quest_if_manifest_changed()
    local cards,manifest_text =
        RQ_ReadManifest(MANIFEST)

    if
        manifest_text == nil or
        manifest_text == "" or
        #cards == 0
    then
        return
    end

    if loaded_manifest_text == "" then
        return
    end

    if manifest_text ~= loaded_manifest_text then
        spawned = false
        build_quest()

        GamePrint(
            "Birthday Quest: card manifest refreshed (" ..
            tostring(#cards) ..
            " cards)"
        )
    end
end

local function reset_persistent_birthday_progress()
    local cards =
        RQ_ReadManifest(MANIFEST)

    for _,card in ipairs(cards) do
        ModSettingSet(
            "recocards_birthday.found_" .. card.id,
            false
        )

        ModSettingSet(
            "recocards_birthday.discovery_order_" .. card.id,
            0
        )

        ModSettingSet(
            "recocards_birthday.discovery_method_" .. card.id,
            ""
        )

        ModSettingSet(
            "recocards_birthday.discovery_note_" .. card.id,
            0
        )

        GlobalsSetValue(
            "recocards_discovery_method_" .. card.id,
            ""
        )

        GlobalsSetValue(
            "recocards_discovery_note_" .. card.id,
            ""
        )

        GameRemoveFlagRun(
            RQ_FoundFlag(card.id)
        )

        GlobalsSetValue(
            "recocards_discovery_order_" .. card.id,
            ""
        )
    end

    ModSettingSet(
        "recocards_birthday.discovery_sequence",
        0
    )

    ModSettingSet(
        "recocards_birthday.note_sequence_pickup",
        0
    )

    ModSettingSet(
        "recocards_birthday.note_sequence_kill",
        0
    )

    GlobalsSetValue(
        "recocards_discovery_sequence",
        "0"
    )

    GlobalsSetValue(
        "recocards_note_sequence_pickup",
        "0"
    )

    GlobalsSetValue(
        "recocards_note_sequence_kill",
        "0"
    )

    GlobalsSetValue(
        "recocards_found",
        "0"
    )

    local tags = {
        "recocards_birthday_spirit",
        "recocards_dropped_page"
    }

    -- Defensive guard for the quest-reset death-grant risk: found-flags are
    -- cleared above BEFORE the EntityKill loop below. EntityKill is not
    -- expected to fire script_death (confirmed in the POC), but if it ever did
    -- the sweatling death handler would see no found-flag and FALSELY grant the
    -- card, re-setting the flag after reset cleared it. Setting this run flag
    -- around the kill loop lets sweatling_death.lua bail out, so a reset can
    -- never produce a spurious grant/FX regardless of EntityKill's behavior.
    GameAddFlagRun("recocards_birthday_resetting")

    for _,tag in ipairs(tags) do
        local entities =
            EntityGetWithTag(tag) or {}

        for _,entity in ipairs(entities) do
            if EntityGetIsAlive(entity) then
                EntityKill(entity)
            end
        end
    end

    GameRemoveFlagRun("recocards_birthday_resetting")

    pending_spawns = {}
    recocards_by_id = {}
    loaded_manifest_text = ""
    spawned = false
    book_page = 1
    book_prev_found_count = -1
    book_zoom_open = false

    build_quest()

    GamePrintImportant(
        "Birthday Progress Reset",
        "Persistent Birthday Book progress has been cleared."
    )
end


local function safe_material_point(x,y)
    if
        GetMaterialAtPosition ~= nil and
        CellFactory_GetType ~= nil
    then
        local material =
            GetMaterialAtPosition(
                math.floor(x),
                math.floor(y)
            )

        if material ~= nil and material ~= 0 then
            local cell_type =
                string.lower(
                    tostring(
                        CellFactory_GetType(material) or ""
                    )
                )

            if
                string.find(cell_type,"solid",1,true) ~= nil or
                string.find(cell_type,"liquid",1,true) ~= nil or
                string.find(cell_type,"sand",1,true) ~= nil or
                string.find(cell_type,"powder",1,true) ~= nil
            then
                return false
            end
        end
    end

    return true
end

function spirit_body_clear(x,y)
    local points = {
        {x-6,y-9},{x,y-9},{x+6,y-9},
        {x-6,y},{x,y},{x+6,y},
        {x-6,y+8},{x,y+8},{x+6,y+8}
    }

    for _,p in ipairs(points) do
        if not safe_material_point(p[1],p[2]) then
            return false
        end
    end

    if RaytraceSurfacesAndLiquiform ~= nil then
        local rays = {
            {x-7,y-8,x+7,y-8},
            {x-7,y,x+7,y},
            {x-7,y+8,x+7,y+8},
            {x,y-10,x,y+9}
        }

        for _,r in ipairs(rays) do
            local hit =
                RaytraceSurfacesAndLiquiform(
                    r[1],r[2],r[3],r[4]
                )

            if hit then
                return false
            end
        end
    elseif RaytraceSurfaces ~= nil then
        local hit =
            RaytraceSurfaces(
                x-7,
                y,
                x+7,
                y
            )
        if hit then return false end
    end

    return true
end

spirit_ground_position = function(x,y)
    local hit,hx,hy =
        RaytracePlatforms(
            x,
            y+8,
            x,
            y+90
        )

    if not hit then
        return nil,nil
    end

    local sx = hx
    local sy = hy-11

    if not spirit_body_clear(sx,sy) then
        return nil,nil
    end

    return sx,sy
end

local function candidate_inside_zone(zone,x,y)
    return
        x >= math.min(zone.x1,zone.x2) and
        x <= math.max(zone.x1,zone.x2) and
        y >= math.min(zone.y1,zone.y2) and
        y <= math.max(zone.y1,zone.y2)
end

local function find_safe_spawn_in_zone(pending)
    local zone = pending.zone
    local cfg = get_cached_config()

    local attempts =
        tonumber(cfg.safe_spawn_attempts) or 120
    local radius =
        tonumber(cfg.safe_spawn_search_radius) or 190

    local rng =
        RQ_Rng(
            pending.seed +
            pending.failed_passes*104729
        )

    for attempt=1,attempts do
        local cx,cy

        if attempt == 1 then
            cx,cy = pending.x,pending.y
        else
            local angle =
                rng()*math.pi*2
            local dist =
                radius*math.sqrt(rng())

            cx =
                pending.x +
                math.cos(angle)*dist
            cy =
                pending.y +
                math.sin(angle)*dist
        end

        if candidate_inside_zone(zone,cx,cy) then
            if DoesWorldExistAt(
                math.floor(cx-32),
                math.floor(cy-48),
                math.floor(cx+32),
                math.floor(cy+112)
            ) then
                local free_x,free_y =
                    FindFreePositionForBody(
                        cx,
                        cy,
                        0,
                        0,
                        10
                    )

                if free_x ~= nil and free_y ~= nil then
                    if
                        candidate_inside_zone(
                            zone,
                            free_x,
                            free_y
                        ) and
                        math.abs(free_x-cx) <= 55 and
                        math.abs(free_y-cy) <= 80
                    then
                        local sx,sy =
                            spirit_ground_position(
                                free_x,
                                free_y
                            )

                        if sx ~= nil and sy ~= nil then
                            if note_position_clear_of_other_notes(
                                0,
                                sx,
                                sy,
                                34
                            ) then
                                return sx,sy
                            end
                        end
                    end
                end
            end
        end
    end

    return nil,nil
end

local function choose_new_pending_zone(pending)
    if #quest_zones_cache == 0 then
        return
    end

    local rng =
        RQ_Rng(
            pending.seed +
            pending.failed_passes*65537 +
            31337
        )

    local usage = {}

    for _,other in ipairs(pending_spawns) do
        if other ~= pending and other.zone ~= nil then
            usage[other.zone] =
                (usage[other.zone] or 0) + 1
        end
    end

    local zone =
        choose_zone(
            quest_zones_cache,
            rng,
            usage
        )

    local hw,hh = 9,10

    local minx =
        math.min(zone.x1,zone.x2)+hw
    local maxx =
        math.max(zone.x1,zone.x2)-hw
    local miny =
        math.min(zone.y1,zone.y2)+hh
    local maxy =
        math.max(zone.y1,zone.y2)-hh

    if minx <= maxx and miny <= maxy then
        pending.zone = zone
        pending.x =
            minx + (maxx-minx)*rng()
        pending.y =
            miny + (maxy-miny)*rng()
        pending.seed =
            math.floor(
                rng()*1000000000
            ) + pending.card.order*1237
    end
end

local function update_pending_spawns()
    if #pending_spawns == 0 then return end

    for _,pending in ipairs(pending_spawns) do
        if
            not pending.spawned and
            not GameHasFlagRun(
                RQ_FoundFlag(
                    pending.card.id
                )
            )
        then
            if DoesWorldExistAt(
                math.floor(pending.x-48),
                math.floor(pending.y-64),
                math.floor(pending.x+48),
                math.floor(pending.y+128)
            ) then
                local sx,sy =
                    find_safe_spawn_in_zone(
                        pending
                    )

                if sx ~= nil and sy ~= nil then
                    spawn_note(
                        pending.card,
                        sx,
                        sy
                    )

                    pending.x = sx
                    pending.y = sy
                    pending.spawned = true
                else
                    pending.failed_passes =
                        pending.failed_passes + 1

                    if pending.failed_passes >= 5 then
                        choose_new_pending_zone(
                            pending
                        )
                        pending.failed_passes = 0
                    end
                end
            end
        end
    end
end

local function found_cards()
    local cards = RQ_ReadManifest(MANIFEST)
    local found = {}

    for _,card in ipairs(cards) do
        if GameHasFlagRun(RQ_FoundFlag(card.id)) then
            local discovery_order =
                tonumber(
                    GlobalsGetValue(
                        "recocards_discovery_order_" .. card.id,
                        "999999"
                    )
                ) or 999999

            card.discovery_order = discovery_order

            local acquisition =
                tostring(
                    ModSettingGet(
                        "recocards_birthday.discovery_method_" .. card.id
                    ) or ""
                )

            if acquisition ~= "kill" and acquisition ~= "pickup" then
                acquisition =
                    GlobalsGetValue(
                        "recocards_discovery_method_" .. card.id,
                        "pickup"
                    )
            end

            if acquisition ~= "kill" then
                acquisition = "pickup"
            end

            card.discovery_method = acquisition

            local note_index =
                tonumber(
                    ModSettingGet(
                        "recocards_birthday.discovery_note_" .. card.id
                    )
                )

            if note_index == nil or note_index < 1 then
                note_index =
                    tonumber(
                        GlobalsGetValue(
                            "recocards_discovery_note_" .. card.id,
                            "0"
                        )
                    ) or 0
            end

            card.discovery_note = note_index
            table.insert(found,card)
        end
    end

    table.sort(found,function(a,b)
        if a.discovery_order == b.discovery_order then
            return a.order < b.order
        end
        return a.discovery_order < b.discovery_order
    end)

    return found
end

local function nearest_undiscovered_card()
    return nearest_uncollected_note()
end

local function update_dev_tools()
    local cfg = get_cached_config()
    if tonumber(cfg.dev_mode) ~= 1 then return end

    local hx = tonumber(cfg.hud_x) or 16
    local hy = tonumber(cfg.hud_y) or 58

    local cards =
        RQ_ReadManifest(MANIFEST)

    GuiText(
        gui,
        hx,
        hy+52,
        "DEV manifest cards: " .. tostring(#cards)
    )

    if GuiButton(
        gui,
        7302,
        hx,
        hy+64,
        "RESET PERSISTENT BIRTHDAY PROGRESS"
    ) then
        reset_persistent_birthday_progress()
        return
    end

    local target = nearest_undiscovered_card()

    if target == nil then
        GuiText(gui,hx,hy+78,"DEV: no undiscovered cards")
        return
    end

    GuiText(
        gui,
        hx,
        hy+78,
        "DEV next card: " ..
        tostring(math.floor(target.x)) .. ", " ..
        tostring(math.floor(target.y)) ..
        "  distance " .. tostring(math.floor(math.sqrt(target.d2)))
    )

    if GuiButton(gui,7301,hx,hy+90,"DEV TELEPORT TO NEXT CARD") then
        EntitySetTransform(target.player,target.x,target.y-40)
        GameSetCameraPos(target.x,target.y-40)
        GamePrintImportant(
            "DEV teleport",
            "Card: " .. tostring(math.floor(target.x)) .. ", " .. tostring(math.floor(target.y))
        )
    end
end

local function draw_hud()
    if GlobalsGetValue("recocards_book_open","0") == "1" then return end
    local total =
        tonumber(
            GlobalsGetValue(
                "recocards_total",
                "0"
            )
        ) or 0

    local found =
        tonumber(
            GlobalsGetValue(
                "recocards_found",
                "0"
            )
        ) or 0

    local cfg = get_cached_config()
    local hud_x = tonumber(cfg.hud_x) or 16
    local hud_y = tonumber(cfg.hud_y) or 58
    local progress_x = hud_x

    if GameHasFlagRun("recocards_book_owned") then
        if GuiButton(
            gui,
            7401,
            hud_x,
            hud_y,
            "Birthday Book"
        ) then
            local open =
                GlobalsGetValue(
                    "recocards_book_open",
                    "0"
                ) == "1"

            GlobalsSetValue(
                "recocards_book_open",
                open and "0" or "1"
            )
        end

        progress_x = hud_x + 78
    end

    if total > 0 then
        local progress =
            "Birthday Cards: " ..
            tostring(found) ..
            " / " ..
            tostring(total)

        GuiText(
            gui,
            progress_x,
            hud_y,
            progress
        )
    end
end

local function draw_book()
    if not GameHasFlagRun("recocards_book_owned") then
        book_zoom_open = false
        return
    end

    if GlobalsGetValue("recocards_book_open","0") ~= "1" then
        book_zoom_open = false
        return
    end

    local cfg = get_cached_config()
    local maxw = tonumber(cfg.book_image_width) or 320
    local maxh = tonumber(cfg.book_image_max_height) or 205
    local card_page_width = tonumber(cfg.book_card_page_width) or 70
    local magnify_width = tonumber(cfg.book_magnify_width) or 315
    local magnify_view_height = tonumber(cfg.book_magnify_view_height) or 235

    local screen_w,screen_h = GuiGetScreenDimensions(gui)
    local panel_w = 360
    local panel_h = 320
    local bx = math.floor((screen_w-panel_w)*0.5)
    local by = math.floor((screen_h-panel_h)*0.5)
    local cards = found_cards()
    local count = #cards
    local instruction_count = #BOOK_INSTRUCTIONS

    if count ~= book_prev_found_count then
        if count > 0 then book_page = count end
        book_prev_found_count = count
    end

    if book_page < 1 then book_page = 1 end
    if count > 0 and book_page > count then book_page = count end
    if book_instruction_page < 1 then book_instruction_page = 1 end
    if book_instruction_page > instruction_count then book_instruction_page = instruction_count end

    local function ui_black()
        if GuiColorSetForNextWidget ~= nil then
            GuiColorSetForNextWidget(gui,0.08,0.08,0.08,1.0)
        end
    end

    local function ui_text(x,y,value)
        ui_black()
        GuiText(gui,x,y,value)
    end

    local function ui_button(id,x,y,label)
        ui_black()
        return GuiButton(gui,id,x,y,label)
    end

    local function ui_text_centered(cx,y,value)
        local w = #value * 4
        if GuiGetTextDimensions ~= nil then
            local ok,tw = pcall(GuiGetTextDimensions,gui,value)
            if ok and type(tw) == "number" then w = tw end
        end
        ui_text(math.floor(cx-w*0.5),y,value)
    end

    local function ui_button_centered(id,cx,y,label)
        local w = #label * 4
        if GuiGetTextDimensions ~= nil then
            local ok,tw = pcall(GuiGetTextDimensions,gui,label)
            if ok and type(tw) == "number" then w = tw end
        end
        return ui_button(id,math.floor(cx-w*0.5),y,label)
    end

    local function note_index_for_card(card,pool)
        if pool == nil or #pool == 0 then return 1 end
        local index = tonumber(card.discovery_note) or 0
        if index >= 1 and index <= #pool then return index end

        local seed = (tonumber(card.discovery_order) or 1) * 97
        local id = tostring(card.id or "")

        for i=1,#id do
            seed = seed + string.byte(id,i) * (i + 11)
        end

        return (seed % #pool) + 1
    end

    local function wrap_book_note(value,max_chars)
        local lines = {}
        local current = ""

        for word in string.gmatch(value or "","%S+") do
            local candidate = current == "" and word or (current .. " " .. word)

            if #candidate > max_chars and current ~= "" then
                table.insert(lines,current)
                current = word
            else
                current = candidate
            end
        end

        if current ~= "" then
            table.insert(lines,current)
        end

        return lines
    end

    local function card_note_lines(card)
        local method = card.discovery_method == "kill" and "kill" or "pickup"
        local pool = BOOK_CARD_NOTES[method] or BOOK_CARD_NOTES.pickup or {}
        if #pool == 0 then return {"A birthday card was added to the book."} end

        local index = note_index_for_card(card,pool)
        local note = tostring(pool[index] or pool[1] or "")
        local author = tostring(card.author or "Birthday Spirit")
        note = string.gsub(note,"{user}",author)

        return wrap_book_note(note,24)
    end

    local function instruction_panel_path(index)
        local numbered = MOD .. "/files/gfx/book_ui/book_panel_instructions_" .. string.format("%02d", index) .. ".png"
        if ModDoesFileExist ~= nil and ModDoesFileExist(numbered) then
            return numbered
        end
        return MOD .. "/files/gfx/book_ui/book_panel_instructions.png"
    end

    GuiOptionsClear(gui)
    if GUI_OPTION ~= nil and GUI_OPTION.DrawNoHoverAnimation ~= nil then
        GuiOptionsAdd(gui,GUI_OPTION.DrawNoHoverAnimation)
    end

    local z_panel = -100000
    local z_card = -100010
    local z_widgets = -100020

    if book_mode == "cards" and count > 0 and book_zoom_open then
        local card = cards[book_page]
        local panel_w_zoom = 410
        local panel_h_zoom = 268
        local panel_x = math.floor((screen_w-panel_w_zoom)*0.5)
        local panel_y = math.floor((screen_h-panel_h_zoom)*0.5) - 20
        local reader_w = magnify_width + 18
        local reader_x = math.floor(panel_x + (panel_w_zoom-reader_w)*0.5)
        local reader_y = panel_y + 44
                local reader_h = panel_h_zoom - 72
        local scale = magnify_width / card.w

        GuiZSetForNextWidget(gui,z_panel)
        GuiImage(gui,5300,panel_x,panel_y,MOD .. "/files/gfx/book_ui/book_zoom_panel.png",1.0,1.0,1.0)

        GuiZSet(gui,z_widgets)
        ui_text_centered(panel_x + panel_w_zoom*0.5,panel_y + 16,"Magnified Birthday Card")

        if ui_button(5302,panel_x + panel_w_zoom - 74,panel_y + 16,"Close Zoom") then
            book_zoom_open = false
            GuiOptionsClear(gui)
            return
        end

        GuiZSet(gui,z_card)
        GuiBeginScrollContainer(gui,5400,reader_x,reader_y,reader_w,reader_h,true,4,4)
        GuiLayoutBeginVertical(gui,0,0,true,0,0)
        if GuiColorSetForNextWidget ~= nil then
            GuiColorSetForNextWidget(gui,1.0,1.0,1.0,1.0)
        end
        GuiImage(gui,5401,math.floor((reader_w-magnify_width)*0.5),0,OUT .. "/" .. RQ_CardCurrentFile(card),1.0,scale,scale)
        GuiLayoutEnd(gui)
        GuiEndScrollContainer(gui)

        if card.links ~= nil and #card.links > 0 then
            local link_y = panel_y + panel_h_zoom + 4
            GuiZSet(gui,z_widgets)
            for i,url in ipairs(card.links) do
                local label = #card.links == 1 and "Open Link" or ("Open Link " .. tostring(i))
                if ui_button_centered(5500+i,panel_x + panel_w_zoom*0.5,link_y + (i-1)*12,label) then
                    RQ_RequestOpenCardLink(card.id,url)
                end
            end
        end

        GuiOptionsClear(gui)
        return
    end

    local panel_path = book_mode == "instructions" and instruction_panel_path(book_instruction_page) or (MOD .. "/files/gfx/book_ui/book_panel_cards.png")
    GuiZSetForNextWidget(gui,z_panel)
    GuiImage(gui,4999,bx,by,panel_path,1.0,1.0,1.0)

    GuiZSet(gui,z_widgets)
    ui_text(bx+20,by+20,"Dunk's Birthday Book")
    ui_text(bx+20,by+35,tostring(count) .. " discovered")

    if ui_button(5001,bx+185,by+18,book_mode == "cards" and "> Cards <" or "Cards") then
        book_mode = "cards"
        book_zoom_open = false
    end

    if ui_button(5002,bx+233,by+18,book_mode == "instructions" and "> Instructions <" or "Instructions") then
        book_mode = "instructions"
        book_zoom_open = false
    end

    if ui_button(5003,bx+320,by+18,"Close") then
        GlobalsSetValue("recocards_book_open","0")
        book_zoom_open = false
        GuiOptionsClear(gui)
        return
    end

    local content_x = bx + 22
    local content_y = by + 58
    local content_w = panel_w - 44
    local content_h = 182
    local footer_y = by + 264

    if book_mode == "instructions" then
        local page = BOOK_INSTRUCTIONS[book_instruction_page]
        ui_text(content_x+6,content_y+2,page.title)
        for i,line in ipairs(page.lines) do
            ui_text(content_x+6,content_y+18 + (i-1)*11,line)
        end

        local nav_left = bx + panel_w*0.25
        local nav_center = bx + panel_w*0.5
        local nav_right = bx + panel_w*0.75

        if book_instruction_page > 1 then
            if ui_button_centered(5200,nav_left,footer_y,"< Previous") then
                book_instruction_page = book_instruction_page-1
            end
        end

        ui_text_centered(nav_center,footer_y+2,tostring(book_instruction_page) .. " / " .. tostring(instruction_count))

        if book_instruction_page < instruction_count then
            if ui_button_centered(5201,nav_right,footer_y,"Next >") then
                book_instruction_page = book_instruction_page+1
            end
        end

        GuiOptionsClear(gui)
        return
    end

    if count == 0 then
        ui_text(content_x+36,content_y+66,"The book is still empty.")
        ui_text(content_x+14,content_y+82,"Find a Birthday Spirit to add")
        ui_text(content_x+34,content_y+94,"your first card here.")
        GuiOptionsClear(gui)
        return
    end

    local card = cards[book_page]
    local left_page_x = bx + 26
    local left_page_y = content_y + 8
    local right_page_x = bx + 198
    local right_page_y = content_y -9
    local right_page_w = 136
    local right_page_h = 200
    local scale_w = right_page_w / card.w
    local scale_h = right_page_h / card.h
    local scale = math.min(scale_w, scale_h)
    local draww = card.w*scale
    local drawh = card.h*scale
    local imgx = right_page_x + (right_page_w-draww)*0.5
    local imgy = right_page_y + (right_page_h-drawh)*0.5
    local note_lines = card_note_lines(card)

    ui_text(left_page_x,left_page_y,"A note about this card")

    for i,line in ipairs(note_lines) do
        ui_text(left_page_x,left_page_y+20+(i-1)*11,line)
    end

    GuiZSetForNextWidget(gui,z_card)
    if GuiColorSetForNextWidget ~= nil then
        GuiColorSetForNextWidget(gui,1.0,1.0,1.0,1.0)
    end
    GuiImage(gui,5100,imgx,imgy,OUT .. "/" .. RQ_CardCurrentFile(card),1.0,scale,scale)

    GuiZSet(gui,z_widgets)
    if book_page > 1 then
        if ui_button(5200,bx+18,footer_y,"< Previous") then book_page = book_page-1 end
    end

    ui_text(bx+166,footer_y+2,tostring(book_page) .. " / " .. tostring(count))

    if book_page < count then
        if ui_button(5201,bx+286,footer_y,"Next >") then book_page = book_page+1 end
    end

    local magnify_y = by + 285
    if ui_button_centered(5202,bx+panel_w*0.5,magnify_y,"Magnify Card") then book_zoom_open = true end

    if card.links ~= nil and #card.links > 0 then
        for i,url in ipairs(card.links) do
            local label = #card.links == 1 and "Open Link" or ("Open Link " .. tostring(i))
            if ui_button(5600+i,bx+244,magnify_y + (i-1)*12,label) then
                RQ_RequestOpenCardLink(card.id,url)
            end
        end
    end

    GuiOptionsClear(gui)
end


local function cleanup_recocards_origin_artifacts()
    local entities = EntityGetInRadius(0,0,160) or {}

    for _,e in ipairs(entities) do
        if EntityGetIsAlive(e) then
            local name = EntityGetName(e) or ""

            if
                EntityHasTag(e,"recocards_book_visual") or
                EntityHasTag(e,"recocards_birthday_note") or
                string.find(name,"birthday_spirit_book",1,true) ~= nil or
                string.find(name,"birthday_page_",1,true) ~= nil or
                name == "Dunk's Birthday Book"
            then
                local x,y = EntityGetTransform(e)
                if math.abs(x) < 160 and math.abs(y) < 160 then
                    EntityKill(e)
                end
            end
        end
    end
end


local function apply_birthday_player_sprites(player)
    local children =
        EntityGetAllChildren(player) or {}

    for _,child in ipairs(children) do
        local name =
            EntityGetName(child) or ""

        if name == "cape" then
            EntityKill(child)
        end
    end
end

local function spawn_birthday_spirit_radar_spell()
    if GameHasFlagRun(
        "recocards_birthday_radar_spawned_v3"
    ) then
        return
    end

    local x = 9115
    local y = -1800

    if not DoesWorldExistAt(
        x-64,
        y-64,
        x+64,
        y+64
    ) then
        return
    end

    local entity =
        CreateItemActionEntity(
            "BIRTHDAY_SPIRIT_RADAR",
            x,
            y
        )

    if entity ~= nil and entity ~= 0 then
        GameAddFlagRun(
            "recocards_birthday_radar_spawned_v3"
        )

        GamePrint(
            "Birthday Spirit Radar spawned."
        )
    end
end


function OnProjectileFired(shooter_id, projectile_id, initial_rng, position_x, position_y, target_x, target_y, send_message, unknown1, multicast_index, unknown3)
    TrialOfTheGods_OnProjectileFired(shooter_id, projectile_id, initial_rng, position_x, position_y, target_x, target_y, send_message, unknown1, multicast_index, unknown3)
end

function OnPlayerSpawned(player_entity)
    TrialOfTheGods_OnPlayerSpawned(player_entity)
    Celebratium_OnPlayerSpawned(player_entity)
    BirthdayGlimmer_OnPlayerSpawned(player_entity)
    apply_birthday_player_sprites(player_entity)
    give_starting_guiding_powder(player_entity)
    cleanup_recocards_origin_artifacts()
    spawn_birthday_spirit_radar_spell()
    GameAddFlagRun("recocards_book_owned")

    if GlobalsGetValue("recocards_book_initialized","0") ~= "1" then
        GlobalsSetValue("recocards_book_open","0")
        GlobalsSetValue("recocards_book_initialized","1")
    end

    get_or_create_run_spawn_seed()
    build_quest()
end

function OnWorldInitialized()
    build_quest()
    -- Fresh Moist Mobbing logs per session (if logging enabled).
    if moist_logging_enabled() then LOG_ResetAll() end
    LOG("debug", "world initialized; Moist Mobbing active")
end

function OnWorldPostUpdate()
    if not spawned and GameGetFrameNum()%60 == 0 then
        build_quest()
    end

    if GameGetFrameNum()%60 == 0 then
        spawn_birthday_spirit_radar_spell()
    end

    if spawned and GameGetFrameNum()%60 == 0 then
        refresh_quest_if_manifest_changed()
    end

    if GameGetFrameNum()%5 == 0 then
    end

    if GameGetFrameNum()%30 == 0 then
        update_note_safe_positions()
    end

    if GameGetFrameNum()%10 == 0 then
        update_pending_spawns()
    end


    update_birthday_guiding_target()

    if GameGetFrameNum()%15 == 0 then
        local players =
            EntityGetWithTag("player_unit") or {}

        if #players > 0 then
            apply_birthday_player_sprites(players[1])
        end
    end

end

function OnWorldPreUpdate()
    TrialOfTheGods_OnWorldPreUpdate()
    RhythmArcade_OnWorldPreUpdate()
    PunchOutArcade_OnWorldPreUpdate()
    MortalKombatArcade_OnWorldPreUpdate()

    if gui == nil then
        gui=GuiCreate()
    end

    GuiStartFrame(gui)

    RQ_UpdateBirthdaySpiritRadar()
    draw_hud()
    update_dev_tools()
    -- Author names are rendered by each sweatling's own in-world text sprite
    -- (attach_sweatling_name via sweatling_layers.lua); the old per-frame
    -- draw_spirit_names() GuiText overlay was removed to avoid a duplicate name.
    draw_book()

    -- Moist Mobbing per-frame update (drain queues, spawns, voting suppression).
    moist_mob_update()
end

function OnPlayerDied()
    RhythmArcade_OnPlayerDied()
    PunchOutArcade_OnPlayerDied()
    MortalKombatArcade_OnPlayerDied()
end
