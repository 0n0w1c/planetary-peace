local valid_types = { "unit" }

if script.active_mods["space-age"] then
    table.insert(valid_types, "spider-unit")
end

-- Note: Demolishers and other scripted planetary threats are not destroyed.
-- Only standard enemy units and modded biters are cleared when peaceful mode is enabled.
local function kill_all_hostile_units_on_surface(surface)
    local player_force = game.forces["player"]
    local neutral_force = game.forces["neutral"]

    for _, force in pairs(game.forces) do
        if force ~= player_force and force ~= neutral_force and force.is_enemy(player_force) then
            for _, entity_type in pairs(valid_types) do
                local entities = surface.find_entities_filtered({ force = force, type = entity_type })
                for _, entity in pairs(entities) do
                    entity.destroy()
                end
            end
        end
    end
end

local function update_shortcut(player)
    if not player or not player.valid then return end
    local surface = player.surface
    if surface then
        player.set_shortcut_toggled("planetary-peace-toggle", surface.peaceful_mode)
    end
end

local function toggle_planetary_peace(player)
    if not player or not player.valid then return end
    local surface = player.surface
    if not surface then return end

    surface.peaceful_mode = not surface.peaceful_mode

    for _, other_player in pairs(game.connected_players) do
        if other_player.surface == surface then
            update_shortcut(other_player)
        end
    end

    kill_all_hostile_units_on_surface(surface)
end

local function on_shortcut_key_pressed(event)
    local player = game.get_player(event.player_index)
    toggle_planetary_peace(player)
end

local function on_shortcut_button_pressed(event)
    if event.prototype_name == "planetary-peace-toggle" then
        local player = game.get_player(event.player_index)
        toggle_planetary_peace(player)
    end
end

local function on_player_surface_changed(event)
    local player = game.get_player(event.player_index)
    update_shortcut(player)
end

local function register_event_handlers()
    script.on_event("planetary-peace-toggle-key", on_shortcut_key_pressed)
    script.on_event(defines.events.on_lua_shortcut, on_shortcut_button_pressed)
    script.on_event(defines.events.on_player_changed_surface, on_player_surface_changed)
    script.on_event(defines.events.on_player_created, on_player_surface_changed)
end

script.on_init(function()
    for _, player in pairs(game.players) do
        update_shortcut(player)
    end
end)

script.on_configuration_changed(function()
    for _, player in pairs(game.players) do
        update_shortcut(player)
    end
end)

register_event_handlers()
