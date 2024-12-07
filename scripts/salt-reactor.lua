maraxsis.on_event(maraxsis.events.on_init(), function()
    storage.salt_reactors = storage.salt_reactors or {}
end)

maraxsis.on_event(maraxsis.events.on_built(), function(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= "maraxsis-salt-reactor" then return end

    local energy_interface = entity.surface.create_entity {
        name = "maraxsis-salt-reactor-energy-interface",
        position = entity.position,
        force = entity.force_index,
        quality = entity.quality,
        create_build_effect_smoke = false,
    }

    energy_interface.destructible = false
    energy_interface.operable = false
    energy_interface.minable = false
    energy_interface.electric_buffer_size = (50000000 * 50) * (1 + entity.quality.level * 0.3)

    storage.salt_reactors[entity.unit_number] = {
        entity = entity,
        energy_interface = energy_interface,
    }
end)

local effect_id = "maraxsis-salt-reactor-energy-created"
maraxsis.on_event(defines.events.on_script_trigger_effect, function(event)
    if event.effect_id ~= effect_id then return end

    local entity = event.source_entity
    if not entity or not entity.valid then return end

    local reactor_data = storage.salt_reactors[entity.unit_number]
    if not reactor_data then return end

    local energy_interface = reactor_data.energy_interface
    if not energy_interface or not energy_interface.valid then return end

    local _, quality = entity.get_recipe()
    if not quality then return end

    local quality_level = quality.level
    if quality_level >= 5 then quality_level = quality_level - 1 end
    energy_interface.energy = energy_interface.energy + 10000000 * (2 ^ quality_level)
end)

maraxsis.on_event(maraxsis.events.on_destroyed(), function(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.name ~= "maraxsis-salt-reactor" then return end

    local reactor_data = storage.salt_reactors[entity.unit_number]
    if not reactor_data then return end
    reactor_data.energy_interface.destroy()
    storage.salt_reactors[entity.unit_number] = nil
end)
