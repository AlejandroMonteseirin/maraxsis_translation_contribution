local size = 16.5 -- of the octagon

local check_size = size - 0.01
local DOME_POLYGON = {
    7, check_size,
    -7, check_size,
    -check_size, 7,
    -check_size, -7,
    -7, -check_size,
    7, -check_size,
    check_size, -7,
    check_size, 7,
}

h2o.on_event('on_init', function()
    if remote.interfaces['PickerDollies'] and remote.interfaces['PickerDollies']['add_blacklist_name'] then
        remote.call('PickerDollies', 'add_blacklist_name', 'h2o-pressure-dome')
    end
    for mask in pairs(game.tile_prototypes['h2o-pressure-dome-tile'].collision_mask) do
        global.dome_collision_mask = mask
    end

    global.pressure_domes = global.pressure_domes or {}
end)

-- By Pedro Gimeno, donated to the public domain
function is_point_in_polygon(x, y)
    if x > size or x < -size or y > size or y < -size then
        return false
    end

    local x1, y1, x2, y2
    local len = #DOME_POLYGON
    x2, y2 = DOME_POLYGON[len - 1], DOME_POLYGON[len]
    local wn = 0
    for idx = 1, len, 2 do
        x1, y1 = x2, y2
        x2, y2 = DOME_POLYGON[idx], DOME_POLYGON[idx + 1]

        if y1 > y then
            if (y2 <= y) and (x1 - x) * (y2 - y) < (x2 - x) * (y1 - y) then
                wn = wn + 1
            end
        else
            if (y2 > y) and (x1 - x) * (y2 - y) > (x2 - x) * (y1 - y) then
                wn = wn - 1
            end
        end
    end
    return wn % 2 ~= 0 -- even/odd rule
end

local function find_entities_inside_octagon(pressure_dome_data)
    local dome_position = pressure_dome_data.position
    local x, y = dome_position.x, dome_position.y

    local entities_inside_square = entity.surface.find_entities_filtered {
        area = {
            {x - size, y - size},
            {x + size, y + size},
        },
        collision_mask = {'object-layer'},
    }

    local entities_inside_octagon = {}
    for _, e in pairs(entities_inside_square) do
        local e_x, e_y = e.position.x, e.position.y
        if is_point_in_polygon(e_x - x, e_y - y) then
            table.insert(entities_inside_octagon, e)
        end
    end

    return entities_inside_octagon
end

local function get_four_corners(entity)
    local position = entity.position
    local x, y = position.x, position.y
    local collision_box = entity.prototype.collision_box
    local orientation = entity.orientation

    if entity.type == 'straight-rail' then
        orientation = (orientation + 0.25) % 1
    elseif entity.type == 'cliff' then
        collision_box = {
            left_top = {x = -2, y = -2},
            right_bottom = {x = 2, y = 2},
        }
    else -- expand the collision box to the actual tile size
        collision_box = {
            left_top = {x = math.floor(collision_box.left_top.x * 2) / 2, y = math.floor(collision_box.left_top.y * 2) / 2},
            right_bottom = {x = math.ceil(collision_box.right_bottom.x * 2) / 2, y = math.ceil(collision_box.right_bottom.y * 2) / 2},
        }
    end

    local left_top = collision_box.left_top
    local right_bottom = collision_box.right_bottom

    if orientation == 0 then
        return {
            {x = x + left_top.x , y = y + left_top.y},
            {x = x + right_bottom.x, y = y + left_top.y},
            {x = x + right_bottom.x, y = y + right_bottom.y},
            {x = x + left_top.x, y = y + right_bottom.y},
        }
    end

    local cos = math.cos(orientation * 2 * math.pi)
    local sin = math.sin(orientation * 2 * math.pi)

    local corners = {}
    for _, corner in pairs({
        {x = left_top.x, y = left_top.y},
        {x = right_bottom.x, y = left_top.y},
        {x = right_bottom.x, y = right_bottom.y},
        {x = left_top.x, y = right_bottom.y},
    }) do
        local corner_x, corner_y = corner.x, corner.y
        corners[#corners + 1] = {
            x = x + corner_x * cos - corner_y * sin,
            y = y + corner_x * sin + corner_y * cos,
        }
    end
    return corners
end

local function count_points_in_dome(pressure_dome_data, entity)
    local dome_position = pressure_dome_data.position
    local x, y = dome_position.x, dome_position.y

    local count = 0
    for _, entity_corner in pairs(get_four_corners(entity)) do
        if is_point_in_polygon(entity_corner.x - x, entity_corner.y - y) then
            count = count + 1
        end
    end
    return count
end

h2o.on_event('on_built', function(event)
    local entity = event.entity or event.created_entity
    if not entity.valid or entity.name == 'h2o-pressure-dome' then return end
    local surface = entity.surface

    for _, pressure_dome_data in pairs(global.pressure_domes) do
        local dome = pressure_dome_data.entity
        if not dome.valid or dome.surface ~= surface then goto continue end

        local points_in_dome = count_points_in_dome(pressure_dome_data, entity)
        if points_in_dome == 0 then
            goto continue
        elseif points_in_dome == 4 then
            for _, collision_box in pairs(pressure_dome_data.collision_boxes) do
                if collision_box.valid then
                    collision_box.minable = false
                end
            end
            table.insert(pressure_dome_data.contained_entities, entity)
        else
            h2o.cancel_creation(entity, event.player_index, {'cant-build-reason.entity-in-the-way', dome.localised_name})
        end

        do return end
        ::continue::
    end
end)

local function place_tiles(pressure_dome_data)
    local surface = pressure_dome_data.surface
    if not surface.valid then return end
    local position = pressure_dome_data.position
    local x, y = position.x, position.y

    local tiles = {}

    for xx = -math.floor(size), math.floor(size) do
        for yy = -math.floor(size), math.floor(size) do
            if is_point_in_polygon(xx + 0.5, yy + 0.5) then
                local x, y = x + xx, y + yy
                tiles[#tiles + 1] = {name = 'h2o-pressure-dome-tile', position = {x, y}}
            end
        end
    end

    surface.set_tiles(tiles, true, false, true, false)
end

local DEFAULT_MARAXSIS_TILE = 'dirt-5-underwater'
local function unplace_tiles(pressure_dome_data)
    local surface = pressure_dome_data.surface
    if not surface.valid then return end
    local position = pressure_dome_data.position
    local x, y = position.x, position.y

    local tiles_in_square = surface.find_tiles_filtered {
        area = {
            {x - size, y - size},
            {x + size, y + size},
        },
        name = 'h2o-pressure-dome-tile',
    }

    local tiles = {}

    for _, tile in pairs(tiles_in_square) do
        local tile_position = tile.position
        local xx, yy = tile_position.x, tile_position.y
        if is_point_in_polygon(xx - x + 0.5, yy - y + 0.5) then
            tiles[#tiles + 1] = {name = tile.hidden_tile or DEFAULT_MARAXSIS_TILE, position = {xx, yy}}
        end
    end

    surface.set_tiles(tiles, true, false, true, false)
end

local function place_collision_boxes(pressure_dome_data)
    local surface = pressure_dome_data.surface
    if not surface.valid then return end
    local position = pressure_dome_data.position
    local x, y = position.x, position.y
    local force = pressure_dome_data.entity.force_index

    local diagonal_offset = 4.75
    local positions_and_orientations = {
        {x, y - size, 0},
        {x, y + size, 0},
        {x - size, y, 0.25},
        {x + size, y, 0.25},
        {x + (size - diagonal_offset), y - (size - diagonal_offset), 0.125},
        {x - (size - diagonal_offset), y - (size - diagonal_offset), 0.375},
        {x + (size - diagonal_offset), y + (size - diagonal_offset), 0.375},
        {x - (size - diagonal_offset), y + (size - diagonal_offset), 0.125},
    }

    for _, pos_and_orient in pairs(positions_and_orientations) do
        local pos_x, pos_y, orientation = pos_and_orient[1], pos_and_orient[2], pos_and_orient[3]
        local collision_box = surface.create_entity{
            name = 'h2o-pressure-dome-collision',
            position = {pos_x, pos_y},
            force = force,
            create_build_effect_smoke = false,
        }
        collision_box.health = pressure_dome_data.entity.health
        collision_box.orientation = orientation
        collision_box.active = false
        collision_box.operable = false -- vanilla bug: operable does nothing on cars
        table.insert(pressure_dome_data.collision_boxes, collision_box)
    end
end

local function check_can_build_dome(entity)
    local surface = entity.surface
    local position = entity.position
    local x, y = position.x, position.y

    local entities_inside_square = surface.find_entities_filtered {
        area = {
            {x - size, y - size},
            {x + size, y + size},
        },
        collision_mask = {'object-layer'},
    }
    
    local contained_entities = {}

    for _, e in pairs(entities_inside_square) do
        local count = count_points_in_dome({position = position}, e)
        if count == 0 then
            -- pass
        elseif count == 4 then
            if e.prototype.collision_mask[global.dome_collision_mask] then
                return false, {}, {'cant-build-reason.entity-in-the-way', e.localised_name}
            end
            contained_entities[#contained_entities + 1] = e
        else
            return false, {}, {'cant-build-reason.entity-in-the-way', e.localised_name}
        end
    end

    for xx = -math.floor(size) + x, math.floor(size) + x do
        for yy = -math.floor(size) + y, math.floor(size) + y do
            local tile = surface.get_tile(xx, yy)
            if tile.collides_with('water-tile') or tile.collides_with('ground-tile') then
                return false, {}, {'cant-build-reason.entity-in-the-way', tile.prototype.localised_name}
            end
        end
    end

    return true, contained_entities
end

h2o.on_event('on_built', function(event)
    local entity = event.entity or event.created_entity
    if not entity.valid or entity.name ~= 'h2o-pressure-dome' then return end

    local can_build, contained_entities, error_msg = check_can_build_dome(entity)
    if not can_build then
        h2o.cancel_creation(entity, event.player_index, error_msg)
        return
    end

    entity.minable = false
    entity.destructible = false

    local pressure_dome_data = {
        entity = entity,
        unit_number = entity.unit_number,
        position = entity.position,
        surface = entity.surface,
        contained_entities = contained_entities,
        collision_boxes = {},
    }

    place_collision_boxes(pressure_dome_data)
    place_tiles(pressure_dome_data)
    entity.health = entity.prototype.max_health

    if table_size(contained_entities) ~= 0 then
        for _, e in pairs(pressure_dome_data.collision_boxes) do
            e.minable = false
        end
    end

    global.pressure_domes[entity.unit_number] = pressure_dome_data
end)

local function delete_invalid_entities_from_contained_entities_list(pressure_dome_data, additional_entity_to_delete)
    local dome = pressure_dome_data.entity
    if not dome.valid then return end

    local contained_entities = pressure_dome_data.contained_entities
    for _, e in pairs(contained_entities) do
        if not e.valid or e == additional_entity_to_delete then
            local new_contained = {}
            for _, e in pairs(contained_entities) do
                if e.valid and e ~= additional_entity_to_delete then
                    new_contained[#new_contained + 1] = e
                end
            end
            pressure_dome_data.contained_entities = new_contained
            break
        end
    end

    if table_size(pressure_dome_data.contained_entities) == 0 then
        for _, collision_box in pairs(pressure_dome_data.collision_boxes) do
            if collision_box.valid then
                collision_box.minable = true
            end
        end
    end
end

local function destroy_collision_boxes(pressure_dome_data)
    for _, collision_box in pairs(pressure_dome_data.collision_boxes) do
        if collision_box.valid then
            collision_box.destroy()
        end
    end
    pressure_dome_data.collision_boxes = {}
end

local function bigass_explosion(surface, x, y) -- this looks really stupid. too bad!
    if not surface.valid then return end
    x = x + math.random(-5, 5)
    y = y + math.random(-5, 5)
    surface.create_entity {
        name = 'kr-big-random-pipes-remnant',
        position = {x, y},
    }
    if math.random() > 0.33 then
        surface.create_entity {
            name = 'nuclear-reactor-explosion',
            position = {x, y},
        }
        rendering.draw_light {
            sprite = 'utility/light_medium',
            scale = 3,
            intensity = 0.5,
            target = {x, y},
            time_to_live = 60,
            surface = surface,
        }
    end
end
h2o.register_delayed_function('bigass_explosion', bigass_explosion)

local function random_point_in_circle(radius)
    local angle = math.random() * 2 * math.pi
    radius = math.random() * radius
    return radius * math.cos(angle), radius * math.sin(angle)
end

local function on_dome_died(event, pressure_dome_data)
    local dome = pressure_dome_data.entity
    local surface = dome.surface
    local position = dome.position

    local contained_entities = pressure_dome_data.contained_entities
    for _, e in pairs(contained_entities) do
        if e.valid then
            if event.cause then
                e.die(event.force, event.cause)
            elseif event.force then
                e.die(event.force)
            else
                e.die()
            end
        end
    end

    for i = 1, #DOME_POLYGON, 2 do
        local x, y = position.x + DOME_POLYGON[i], position.y + DOME_POLYGON[i + 1]
        h2o.execute_later('bigass_explosion', math.random(1, 90), surface, x, y)
    end
    for i = 1, #DOME_POLYGON, 2 do
        local x, y = position.x + DOME_POLYGON[i], position.y + DOME_POLYGON[i + 1]
        h2o.execute_later('bigass_explosion', math.random(1, 90), surface, x, y)
    end
    for i = 1, 16 do
        local rx, ry = random_point_in_circle(size)
        h2o.execute_later('bigass_explosion', math.random(1, 90), surface, position.x + rx, position.y + ry)
    end
end

h2o.on_event('on_destroyed', function(event)
    local entity = event.entity
    if not entity.valid then return end
    local unit_number = entity.unit_number

    if entity.name == 'h2o-pressure-dome-collision' then
        for _, pressure_dome_data in pairs(global.pressure_domes) do
            local dome = pressure_dome_data.entity
            if dome.valid then
                for _, collision_box in pairs(pressure_dome_data.collision_boxes) do
                    if collision_box.valid and collision_box == entity then
                        entity = dome
                        unit_number = dome.unit_number
                        goto parent_dome_found
                    end
                end
            end
        end
    end
    ::parent_dome_found::

    local pressure_dome_data = global.pressure_domes[unit_number]
    if pressure_dome_data then
        global.pressure_domes[unit_number] = nil
        unplace_tiles(pressure_dome_data)
        destroy_collision_boxes(pressure_dome_data)
        if event.name == defines.events.on_entity_died then
            on_dome_died(event, pressure_dome_data)
        end
        entity.destroy()
        return
    end

    local surface = entity.surface
    local surface_name = surface.name
    if surface_name ~= h2o.MARAXSIS_SURFACE_NAME and surface_name ~= h2o.TRENCH_SURFACE_NAME then
        return
    end

    local new_pressdomes = nil

    for _, pressure_dome_data in pairs(global.pressure_domes) do
        local dome = pressure_dome_data.entity
        
        if dome.valid then
            delete_invalid_entities_from_contained_entities_list(pressure_dome_data, entity)
        elseif not new_pressure_domes then
            new_pressure_domes = {}
            for _, pressure_dome_data in pairs(global.pressure_domes) do
                local dome = pressure_dome_data.entity
                if dome.valid then
                    pressure_dome_data.unit_number = dome.unit_number
                    new_pressure_domes[dome.unit_number] = pressure_dome_data
                end
            end
        end
    end

    if new_pressure_domes then
        global.pressure_domes = new_pressure_domes
    end
end)

local function find_pressure_dome_data_by_collision_entity(collision_box)
    for _, pressure_dome_data in pairs(global.pressure_domes) do
        for _, cb in pairs(pressure_dome_data.collision_boxes) do
            if cb.valid and cb == collision_box then
                return pressure_dome_data
            end
        end
    end
end

h2o.on_event(defines.events.on_entity_damaged, function(event)
    local entity = event.entity
    if not entity.valid then return end

    if entity.name ~= 'h2o-pressure-dome-collision' then return end

    local pressure_dome_data = find_pressure_dome_data_by_collision_entity(entity)
    if not pressure_dome_data then return end
    
    for _, collision_box in pairs(pressure_dome_data.collision_boxes) do
        if collision_box.valid then
            collision_box.health = entity.health
        end
    end
end)