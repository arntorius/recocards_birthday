
local MOD_TEXTURE_PATH = "mods/recocards_birthday/retextures/textures/"

local my_textures = {
    "teleport_center.png",
    "handgun.png",
    "bomb_wand.png",
    "bouncy_orb.png",
    "bat.png",
    "slimeshooter.png",
    "fish_01.png",
    "firebug.png",
    "iceskull.png"
}

local target_xml_files = {
    "data/buildings_gfx/teleport_center.xml",
    "data/items_gfx/handgun.xml",
    "data/items_gfx/bomb_wand.xml",
    "data/enemies_gfx/bat.xml",
    "data/enemies_gfx/slimeshooter.xml",
    "data/enemies_gfx/shotgunner.xml",
    "data/enemies_gfx/fish_01.xml",
    "data/enemies_gfx/firebug.xml",
    "data/enemies_gfx/iceskull.xml",
}

local function apply_retextures()
    for _, xml_path in ipairs(target_xml_files) do
        local content = ModTextFileGetContent(xml_path)
        
        if content ~= nil then
            local changed = false
            
            for _, tex_name in ipairs(my_textures) do
                local safe_tex = tex_name:gsub("%.", "%%.")
                
                local search_pattern = '="[^"]*/(' .. safe_tex .. ')"'
                
                local replace_pattern = '="' .. MOD_TEXTURE_PATH .. '%1"'
                
                local new_content, replacements = string.gsub(content, search_pattern, replace_pattern)
                
                if replacements > 0 then
                    content = new_content
                    changed = true
                end
            end
            
            if changed then
                ModTextFileSetContent(xml_path, content)
            end
        end
    end
end

-- Run the script
apply_retextures()