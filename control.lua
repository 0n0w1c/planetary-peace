local MAXIMUM_TO_DESTROY = 100

local ENEMY_TYPES = { "unit" }
if script.active_mods["space-age"] then
    table.insert(ENEMY_TYPES, "spider-unit")
end

local function process_destroy_queue()
    local queue = storage.destroy_queue
    if not queue or #queue == 0 then
        storage.destroy_queue = nil
        storage.destroy_queue_processing = false
        script.on_nth_tick(1, nil)
        return
    end

    local count = 0
    while count < MAXIMUM_TO_DESTROY and #queue > 0 do
        local enemy_unit = table.remove(queue)
        if enemy_unit.valid then enemy_unit.destroy() end
        count = count + 1
    end
end

-- Destroys standard enemy units and modded biters when peaceful mode is toggled.
-- Demolishers and scripted planetary threats are not affected.
local function destroy_all_enemy_units_on_surface(surface, player)
    local player_force = game.forces["player"]
    local neutral_force = game.forces["neutral"]
    local queue = {}

    for _, force in pairs(game.forces) do
        if force ~= player_force and force ~= neutral_force and force.is_enemy(player_force) then
            local enemies = surface.find_entities_filtered({ force = force, type = ENEMY_TYPES })

            for _, enemy in ipairs(enemies) do
                table.insert(queue, enemy)
            end
        end
    end

    if #queue > 0 then
        storage.destroy_queue = queue
        storage.destroy_queue_processing = true
        script.on_nth_tick(1, process_destroy_queue)
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

    if storage.destroy_queue_processing then
        for _, other_player in pairs(game.connected_players) do
            if other_player.surface == surface then
                update_shortcut(other_player)
            end
        end
        return
    end

    surface.peaceful_mode = not surface.peaceful_mode

    for _, other_player in pairs(game.connected_players) do
        if other_player.surface == surface then
            update_shortcut(other_player)
        end
    end

    destroy_all_enemy_units_on_surface(surface, player)
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
