
local MOD_TEXTURE_PATH = "mods/recocards_birthday/retextures/textures/"

local background_textures = {
    "background_excavationsite.png",
    "background_snowcave.png",
    "background_snowcastle.png",
    "background_rainforest.png",
    "background_vault.png",
    "background_robobase.png",
    "background_coalmine.png"
}

local biome_xml_files = {
    "data/biome/coalmine.xml",
    "data/biome/excavationsite.xml",
    "data/biome/snowcave.xml",
    "data/biome/snowcastle.xml",
    "data/biome/rainforest.xml",
    "data/biome/vault.xml",
    "data/biome/robobase.xml"
}

local function apply_backgrounds()
    for _, xml_path in ipairs(biome_xml_files) do
        local content = ModTextFileGetContent(xml_path)
        
        if content ~= nil then
            local changed = false
            
            for _, tex_name in ipairs(background_textures) do
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

apply_backgrounds()