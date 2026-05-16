local setting = settings.startup["planetary-peace-disable-animation"]
if setting and setting.value then return end

local EFFECT_UNIT_PREFIX = "planetary-peace-effect-"
local PLANET_UNIT_MARKER_PREFIX = "planetary-peace-planet-unit--"
local SURFACE_UNIT_MARKER_PREFIX = "planetary-peace-surface-unit--"

local prototypes = {
    { type = "trigger-target-type", name = "planetary-peace-effect-unit" }
}

local function unit_prototype(name)
    return (data.raw.unit and data.raw.unit[name])
        or (data.raw["spider-unit"] and data.raw["spider-unit"][name])
end

local function effect_unit_name(source_unit_name)
    return EFFECT_UNIT_PREFIX .. source_unit_name
end

local function result_unit_name(result)
    if type(result) ~= "table" then return nil end
    return result.unit or result[1]
end

local function first_result_unit(spawner)
    for _, result in ipairs(spawner.result_units or {}) do
        local unit_name = result_unit_name(result)
        if unit_name and unit_prototype(unit_name) then
            return unit_name
        end
    end
end

local function first_spawner_for_control(control_name)
    local matches = {}

    for spawner_name, spawner in pairs(data.raw["unit-spawner"] or {}) do
        if spawner.autoplace and spawner.autoplace.control == control_name then
            local unit_name = first_result_unit(spawner)
            if unit_name then
                table.insert(matches, {
                    name = spawner_name,
                    order = spawner.order or "",
                    unit_name = unit_name
                })
            end
        end
    end

    table.sort(matches, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)

    return matches[1]
end

local function sorted_autoplace_controls(planet)
    local controls = {}
    local autoplace_controls = planet.map_gen_settings and planet.map_gen_settings.autoplace_controls

    for control_name in pairs(autoplace_controls or {}) do
        table.insert(controls, control_name)
    end

    table.sort(controls)
    return controls
end

local function selected_unit_for_planet(planet)
    for _, control_name in ipairs(sorted_autoplace_controls(planet)) do
        local spawner = first_spawner_for_control(control_name)
        if spawner then return spawner.unit_name end
    end
end

local function is_ranged_unit(source)
    local attack = source and source.attack_parameters
    if not attack then return false end

    if attack.ammo_category and attack.ammo_category ~= "melee" then return true end
    if attack.type and attack.type ~= "projectile" then return true end
    return attack.range and attack.range > 2
end

local function add_flag(prototype, flag)
    prototype.flags = prototype.flags or {}

    for _, existing in pairs(prototype.flags) do
        if existing == flag then return end
    end

    table.insert(prototype.flags, flag)
end

local function zero_damage_effects(value)
    if type(value) ~= "table" then return end

    if value.type == "damage" and value.damage then
        value.damage.amount = 0
    end

    for _, child in pairs(value) do
        zero_damage_effects(child)
    end
end

local function make_melee_attack_harmless(unit)
    if not unit.attack_parameters then return end

    unit.attack_parameters.type = "projectile"
    unit.attack_parameters.ammo_category = "melee"
    unit.attack_parameters.range = 0.5
    unit.attack_parameters.min_range = nil
    unit.attack_parameters.projectile_center = nil
    unit.attack_parameters.projectile_creation_distance = nil
    unit.attack_parameters.shell_particle = nil
    unit.attack_parameters.warmup = nil
    unit.attack_parameters.cooldown = unit.attack_parameters.cooldown or 60
    unit.attack_parameters.ammo_type = {
        target_type = "entity",
        action = {
            type = "direct",
            action_delivery = {
                type = "instant",
                target_effects = {
                    type = "damage",
                    damage = { amount = 0, type = "physical" }
                }
            }
        }
    }
end

local function make_ranged_attack_harmless(unit)
    if not unit.attack_parameters then return end

    unit.attack_parameters.damage_modifier = 0
    zero_damage_effects(unit.attack_parameters.ammo_type)
end

local function make_effect_unit(source_unit_name)
    local source = unit_prototype(source_unit_name)
    if not source then return false end

    local name = effect_unit_name(source_unit_name)
    if unit_prototype(name) then return true end

    local effect_unit = table.deepcopy(source)
    effect_unit.name = name
    effect_unit.localised_name = source.localised_name or { "entity-name." .. source_unit_name }
    effect_unit.localised_description = source.localised_description or { "entity-description." .. source_unit_name }
    effect_unit.max_health = 1
    effect_unit.healing_per_tick = 0
    effect_unit.selectable_in_game = false
    effect_unit.trigger_target_mask = { "planetary-peace-effect-unit" }
    effect_unit.collision_mask = { layers = {} }
    effect_unit.corpse = nil
    effect_unit.dying_explosion = nil
    effect_unit.working_sound = nil
    effect_unit.walking_sound = nil
    effect_unit.running_sound_animation_positions = nil
    effect_unit.loot = nil
    effect_unit.factoriopedia_simulation = nil

    add_flag(effect_unit, "not-on-map")
    add_flag(effect_unit, "placeable-off-grid")
    add_flag(effect_unit, "not-repairable")
    add_flag(effect_unit, "not-blueprintable")
    add_flag(effect_unit, "not-deconstructable")

    if is_ranged_unit(source) then
        make_ranged_attack_harmless(effect_unit)
    else
        make_melee_attack_harmless(effect_unit)
    end

    table.insert(prototypes, effect_unit)
    return true
end

local function add_marker(prefix, key, effect_name, ranged)
    local marker_unit_name = ranged and ("ranged--" .. effect_name) or effect_name

    table.insert(prototypes, {
        type = "simple-entity",
        name = prefix .. key .. "--" .. marker_unit_name,
        flags = { "not-on-map", "not-blueprintable", "not-deconstructable" },
        selectable_in_game = false,
        collision_mask = { layers = {} },
        pictures = { {
            filename = "__planetary-peace__/graphics/peaceful.png",
            width = 64,
            height = 64
        } }
    })
end

for planet_name, planet in pairs(data.raw.planet or {}) do
    local source_unit_name = selected_unit_for_planet(planet)

    if source_unit_name and make_effect_unit(source_unit_name) then
        local ranged = is_ranged_unit(unit_prototype(source_unit_name))

        local effect_name = effect_unit_name(source_unit_name)

        add_marker(PLANET_UNIT_MARKER_PREFIX, planet_name, effect_name, ranged)
        add_marker(SURFACE_UNIT_MARKER_PREFIX, planet_name, effect_name, ranged)
    end
end

data:extend(prototypes)
