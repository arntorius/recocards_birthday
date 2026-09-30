-- settings.lua
-- Mod options for recocards_birthday, using Noita's stock mod_settings framework.
-- Setting ids are namespaced by the mod folder; read at runtime with
-- ModSettingGet("recocards_birthday.<id>"):
--   * rhythm_arcade_*       -> internal persistent Rhythm Arcade stats (hidden).
--   * moist_mobbing_enabled -> master toggle for the Moist Mobbing effect (ON by
--                              default). Requires a Twitch connection via the
--                              in-game Streaming tab to receive chat events.
--   * logging_enabled       -> Moist Mobbing debug/trigger file logging.
--   * debug_moist_mobbing   -> DEBUG detection profile (see moist_mob_config.lua):
--                              match ANY sender + self-typable sub/gift triggers
--                              + auto-play the recorded dnkM burst. OFF = LIVE
--                              (real bot detection, no auto-replay).
--   * dev_mode              -> show the in-world dev-tools overlay. OFF by default.

dofile("data/scripts/lib/mod_settings.lua")  -- Mk_* helpers + ModSettings* API

local mod_id = "recocards_birthday"

mod_settings_version = 1

mod_settings = {
    -- Rhythm Arcade persistent stats (hidden internal values).
    {
        id = "rhythm_arcade_highscore",
        ui_name = "Rhythm Arcade Highscore",
        ui_description = "Internal persistent Rhythm Arcade highscore.",
        value_default = 0,
        scope = MOD_SETTING_SCOPE_RUNTIME,
        hidden = true,
    },
    {
        id = "rhythm_arcade_best_combo",
        ui_name = "Rhythm Arcade Best Combo",
        ui_description = "Internal persistent Rhythm Arcade best combo.",
        value_default = 0,
        scope = MOD_SETTING_SCOPE_RUNTIME,
        hidden = true,
    },
    {
        id = "rhythm_arcade_highscore_accuracy",
        ui_name = "Rhythm Arcade Highscore Accuracy Legacy",
        ui_description = "Legacy internal persistent Rhythm Arcade accuracy.",
        value_default = 0,
        scope = MOD_SETTING_SCOPE_RUNTIME,
        hidden = true,
    },
    {
        id = "rhythm_arcade_highscore_accuracy_tenths",
        ui_name = "Rhythm Arcade Highscore Accuracy",
        ui_description = "Internal persistent Rhythm Arcade accuracy in tenths of a percent.",
        value_default = 0,
        scope = MOD_SETTING_SCOPE_RUNTIME,
        hidden = true,
    },

    -- Moist Mobbing toggles.
    {
        id = "moist_mobbing_enabled",
        ui_name = "Enable Moist Mobbing",
        ui_description =
            "Celebrate subs/gifts with a mob of sweatlings around the streamer.\n" ..
            "Requires connecting your Twitch channel in the game's Streaming tab.\n" ..
            "Relaunch to apply changes.",
        value_default = true,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
    {
        id = "logging_enabled",
        ui_name = "Enable debug logging",
        ui_description =
            "Write Moist Mobbing debug/trigger logs to files. Turn OFF for best performance.\n" ..
            "Relaunch to apply changes.",
        value_default = false,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
    {
        id = "debug_moist_mobbing",
        ui_name = "Enable Debug Moist Mobbing",
        ui_description =
            "Test mode: trigger simulated mobbing on ANY chatter\n" ..
            "in connected chat typing 'sub: name' or 'gift: name'.\n" ..
            "Relaunch to apply changes.",
        value_default = false,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
    {
        id = "trial_of_the_gods_require_sampo",
        ui_name = "Trial of the Gods: Require Sampo",
        ui_description = "Require the Sampo to activate the Trial of the Gods entrance portal.",
        value_default = true,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
    {
        id = "dev_mode",
        ui_name = "Enable Dev Tools",
        ui_description =
            "Show the in-world developer overlay (manifest count, teleport-to-card,\n" ..
            "and other debug buttons). Leave OFF for normal play.\n" ..
            "Relaunch to apply changes.",
        value_default = false,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
}

-- Standard boilerplate the framework calls. mod_settings_get_version /
-- mod_settings_gui / mod_settings_update are provided by mod_settings.lua and
-- operate on the `mod_settings` table + `mod_id` above.
function ModSettingsUpdate(init_scope)
    mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
