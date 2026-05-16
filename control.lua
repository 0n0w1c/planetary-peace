local MAXIMUM_TO_DESTROY = 100
local EFFECT_UNIT_PREFIX = "planetary-peace-effect-"
local PLANET_UNIT_MARKER_PREFIX = "planetary-peace-planet-unit--"
local SURFACE_UNIT_MARKER_PREFIX = "planetary-peace-surface-unit--"
local EFFECT_UNIT_LIFETIME = 60 * 3
local HOSTILE_SPAWN_DISTANCE = 5
local HOSTILE_RANGED_SPAWN_DISTANCE = 12
local PEACEFUL_TARGET_DISTANCE = 24

local function animation_disabled()
    local setting = settings.startup["planetary-peace-disable-animation"]
    return setting and setting.value == true
end

local ENEMY_TYPES = { "unit" }
if script.active_mods["space-age"] then
    table.insert(ENEMY_TYPES, "spider-unit")
end

local function process_destroy_queue()
    local queue = storage.destroy_queue
    if not queue or table_size(queue) == 0 then
        storage.destroy_queue = nil
        script.on_nth_tick(1, nil)
        return
    end

    local count = 0
    while count < MAXIMUM_TO_DESTROY and table_size(queue) > 0 do
        local enemy_unit = table.remove(queue)
        if enemy_unit.valid then enemy_unit.destroy() end
        count = count + 1
    end
end

local function process_effect_units(event)
    local queue = storage.effect_units
    if not queue then return end

    for i = table_size(queue), 1, -1 do
        local entry = queue[i]
        if not entry.unit or not entry.unit.valid or event.tick >= entry.destroy_tick then
            if entry.unit and entry.unit.valid then entry.unit.destroy() end
            table.remove(queue, i)
        end
    end

    if table_size(queue) == 0 then
        storage.effect_units = nil
    end
end

local function queue_effect_unit_for_removal(unit)
    storage.effect_units = storage.effect_units or {}
    table.insert(storage.effect_units, {
        unit = unit,
        destroy_tick = game.tick + EFFECT_UNIT_LIFETIME
    })
end

local function mapped_effect_unit(prefix, key)
    if not key then return nil end

    local marker_prefix = prefix .. key .. "--"
    local marker_prefix_length = string.len(marker_prefix)

    for name, prototype in pairs(prototypes.entity) do
        if prototype.type == "simple-entity" and string.sub(name, 1, marker_prefix_length) == marker_prefix then
            local marker_data = string.sub(name, marker_prefix_length + 1)
            local ranged, unit_name = string.match(marker_data, "^(ranged)%-%-(.+)$")

            if not unit_name then
                unit_name = marker_data
                ranged = nil
            end

            if prototypes.entity[unit_name] then
                return {
                    name = unit_name,
                    ranged = ranged == "ranged"
                }
            end
        end
    end
end

local function surface_planet_name(surface)
    if not surface or not surface.valid or not surface.planet then return nil end
    return surface.planet.name
end

local function choose_effect_unit(surface)
    if not surface or not surface.valid then return nil end

    return mapped_effect_unit(PLANET_UNIT_MARKER_PREFIX, surface_planet_name(surface))
        or mapped_effect_unit(SURFACE_UNIT_MARKER_PREFIX, surface.name)
end

local function offset_position(position, distance, angle)
    return {
        x = position.x + math.cos(angle) * distance,
        y = position.y + math.sin(angle) * distance
    }
end

local function command_unit(unit, command)
    if unit and unit.valid and unit.commandable then
        unit.commandable.set_command(command)
    end
end

local function find_effect_anchor(surface, preferred_player)
    if preferred_player and preferred_player.valid and preferred_player.character and preferred_player.character.valid and preferred_player.surface == surface then
        return preferred_player.character.position, preferred_player.character, preferred_player.index
    end

    for _, player in pairs(game.connected_players) do
        if player.valid and player.character and player.character.valid and player.surface == surface then
            return player.character.position, player.character, player.index
        end
    end

    return game.forces.player.get_spawn_position(surface), nil, surface.index
end

local function spawn_effect_unit_on_surface(surface, hostile, preferred_player)
    if not surface or not surface.valid then return end

    local effect_unit = choose_effect_unit(surface)
    if not effect_unit then return end

    local anchor_position, target_character, seed = find_effect_anchor(surface, preferred_player)
    if not anchor_position then return end

    local angle = (seed * 1.61803398875 + game.tick / 60) % (math.pi * 2)
    local spawn_distance = hostile and (effect_unit.ranged and HOSTILE_RANGED_SPAWN_DISTANCE or HOSTILE_SPAWN_DISTANCE) or 8
    local spawn_center = offset_position(anchor_position, spawn_distance, angle)
    local spawn_position = surface.find_non_colliding_position(effect_unit.name, spawn_center, 8, 0.5)
        or surface.find_non_colliding_position(effect_unit.name, anchor_position, 16, 0.5)

    if not spawn_position then return end

    local unit = surface.create_entity({
        name = effect_unit.name,
        position = spawn_position,
        force = "enemy",
        raise_built = false
    })

    if not unit or not unit.valid then return end

    unit.destructible = false
    unit.minable = false
    unit.operable = false

    if hostile and target_character and target_character.valid then
        command_unit(unit, {
            type = defines.command.attack,
            target = target_character,
            distraction = defines.distraction.none
        })
    else
        command_unit(unit, {
            type = defines.command.go_to_location,
            destination = offset_position(anchor_position, PEACEFUL_TARGET_DISTANCE, angle),
            distraction = defines.distraction.none
        })
    end

    queue_effect_unit_for_removal(unit)
end

local function create_toggle_effect(hostile, preferred_player)
    if animation_disabled() then return end
    if not preferred_player or not preferred_player.valid or not preferred_player.character or not preferred_player.character.valid then return end

    spawn_effect_unit_on_surface(preferred_player.character.surface, hostile, preferred_player)
end

local function destroy_all_enemy_units_on_surface(surface)
    local player_force = game.forces["player"]
    local neutral_force = game.forces["neutral"]
    local queue = {}

    for _, force in pairs(game.forces) do
        if force ~= player_force and force ~= neutral_force and force.is_enemy(player_force) then
            local enemies = surface.find_entities_filtered({ force = force, type = ENEMY_TYPES })

            for _, enemy in ipairs(enemies) do
                if not string.find(enemy.name, EFFECT_UNIT_PREFIX, 1, true) then
                    table.insert(queue, enemy)
                end
            end
        end
    end

    if table_size(queue) > 0 then
        storage.destroy_queue = queue
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

    if storage.destroy_queue and table_size(storage.destroy_queue) > 0 then
        for _, other_player in pairs(game.connected_players) do
            if other_player.surface == surface then
                update_shortcut(other_player)
            end
        end
        return
    end

    surface.peaceful_mode = not surface.peaceful_mode
    local hostile = not surface.peaceful_mode

    for _, other_player in pairs(game.connected_players) do
        if other_player.surface == surface then
            update_shortcut(other_player)
        end
    end

    destroy_all_enemy_units_on_surface(surface)
    create_toggle_effect(hostile, player)
end

local function on_shortcut_key_pressed(event)
    toggle_planetary_peace(game.get_player(event.player_index))
end

local function on_shortcut_button_pressed(event)
    if event.prototype_name == "planetary-peace-toggle" then
        toggle_planetary_peace(game.get_player(event.player_index))
    end
end

local function on_player_surface_changed(event)
    update_shortcut(game.get_player(event.player_index))
end

script.on_init(function()
    storage.effect_units = nil
    for _, player in pairs(game.players) do
        update_shortcut(player)
    end
end)

script.on_configuration_changed(function()
    if storage.effect_units and table_size(storage.effect_units) == 0 then
        storage.effect_units = nil
    end
    for _, player in pairs(game.players) do
        update_shortcut(player)
    end
end)

script.on_event("planetary-peace-toggle-key", on_shortcut_key_pressed)
script.on_event(defines.events.on_lua_shortcut, on_shortcut_button_pressed)
script.on_event(defines.events.on_player_changed_surface, on_player_surface_changed)
script.on_event(defines.events.on_player_created, on_player_surface_changed)
script.on_event(defines.events.on_tick, process_effect_units)
