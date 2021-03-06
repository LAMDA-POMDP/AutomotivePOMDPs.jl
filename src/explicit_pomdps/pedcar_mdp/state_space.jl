#=
Define a discrete state space for the PedCarMDP problem
=#

function n_states(mdp::PedCarMDP)
    n_ego = n_ego_states(mdp.env, mdp.pos_res, mdp.vel_res)
    n_ped = n_ped_states(mdp.env, mdp.pos_res, mdp.vel_ped_res)
    routes = get_car_routes(mdp.env)
    n_cars = 0
    for route in routes
        n_cars += n_car_states(mdp.env, route, mdp.pos_res, mdp.vel_res)
    end
    return n_ego*(n_cars + 1)*(n_ped + 1) # do not forget absent state
end

function POMDPs.states(mdp::PedCarMDP)
    state_space = PedCarMDPState[]
    ego_states = get_ego_states(mdp.env, mdp.pos_res, mdp.vel_res)
    ped_states = get_ped_states(mdp.env, mdp.pos_res, mdp.vel_ped_res)
    push!(ped_states, get_off_the_grid(mdp))
    routes = get_car_routes(mdp.env)
    for route in routes
        for ego in ego_states
            for ped in ped_states
                car_states = get_car_states(mdp.env, route, mdp.pos_res, mdp.vel_res)
                for car in car_states
                    collision =  is_colliding(Vehicle(ego, mdp.ego_type, EGO_ID), Vehicle(car, mdp.car_type, CAR_ID)) || is_colliding(Vehicle(ego, mdp.ego_type, EGO_ID), Vehicle(ped, mdp.ped_type, PED_ID)) 
                    # collision = crash(mdp, ego, car, ped)
                    # enumerate all possible routes
                    lane = get_lane(mdp.env.roadway, car)
                    push!(state_space, PedCarMDPState(collision, ego, ped, car, SVector{2, LaneTag}(route[1], route[end])))
                end
            end
        end
    end
    for ego in ego_states
        for ped in ped_states
            # add absent states
            collision = is_colliding(Vehicle(ego, mdp.ego_type, EGO_ID), Vehicle(ped, mdp.ped_type, PED_ID))
            # collision = collision_checker(ego, ped, mdp.ego_type, mdp.ped_type)
            push!(state_space, PedCarMDPState(collision, ego, ped, get_off_the_grid(mdp), SVector{2, LaneTag}(LaneTag(0,0), LaneTag(0, 0))))
        end
    end
    return state_space
end


function POMDPs.stateindex(mdp::PedCarMDP, s::PedCarMDPState)
    n_ego = n_ego_states(mdp.env, mdp.pos_res, mdp.vel_res)
    n_ped = n_ped_states(mdp.env, mdp.pos_res, mdp.vel_ped_res)
    routes = get_car_routes(mdp.env)
    # step 1: find ego_index
    ego_i = ego_stateindex(mdp.env, s.ego, mdp.pos_res, mdp.vel_res)
    # step 2: find ped index 
    if s.ped.posG == mdp.off_grid
        ped_i = n_ped + 1
    else
        ped_i = ped_stateindex(mdp.env, s.ped, mdp.pos_res, mdp.vel_ped_res)
    end

    # step 3 find route index 
    route_i = 0
    for (i, route) in enumerate(routes)
        if s.route[end] == route[end] && s.route[1] == route[1]
            route_i = i
        end
    end

    # handle off the grid case
    if s.car.posG == mdp.off_grid || s.route == [LaneTag(0, 0), LaneTag(0, 0)]
        si = 0
        for route in routes
            si += n_ego * (n_ped + 1) * n_car_states(mdp.env, route, mdp.pos_res, mdp.vel_res)
        end
        si += LinearIndices((n_ped + 1, n_ego))[ped_i, ego_i]
    else
        n_car = n_car_states(mdp.env, find_route(mdp.env, s.route), mdp.pos_res, mdp.vel_res)
        # step 2: find route_index
        route_i = 0
        for (i, route) in enumerate(routes)
            if  s.route[end] == route[end] && s.route[1] == route[1]
                route_i = i
            end
        end
        # step 3: find car_index in car states
        car_i = car_stateindex(mdp.env, s.car, find_route(mdp.env, s.route), mdp.pos_res, mdp.vel_res)
        # use linear/Cartesian magic
        si = LinearIndices((n_car, n_ped + 1, n_ego))[car_i, ped_i, ego_i]

        for i=2:route_i
            size_r = n_ego * (n_ped + 1) * n_car_states(mdp.env, routes[i-1], mdp.pos_res, mdp.vel_res)
            si += size_r
        end
    end
    return si
end

function ind2state(mdp::PedCarMDP, si::Int64)
    n_ego = n_ego_states(mdp.env, mdp.pos_res, mdp.vel_res)
    n_ped = n_ped_states(mdp.env, mdp.pos_res, mdp.vel_ped_res)
    routes = get_car_routes(mdp.env)
    n_routes = length(routes)
    car, ped, ego = nothing, nothing, nothing
    # find route first
    ns = 0 
    route_ind = nothing
    route_shift = 0
    for (i, route) in enumerate(routes)
        n_cars = n_car_states(mdp.env, route, mdp.pos_res, mdp.vel_res)
        route_shift = ns
        ns += n_cars*n_ego*(n_ped + 1)
        if ns >= si 
            route_ind = i
            break
        end
    end
    # find car, ped, ego
    if route_ind == nothing # route was not found, car is off the grid
        si_ = si - ns # shift by all the states that were added before
        car = get_off_the_grid(mdp)
        # retrieve ped and ego
        ped_i, ego_i = Tuple(CartesianIndices((n_ped + 1, n_ego))[si_])
        ego = ind2ego(mdp.env, ego_i, mdp.pos_res, mdp.vel_res)
        if ped_i > n_ped
            ped = get_off_the_grid(mdp)
        else
            ped = ind2ped(mdp.env, ped_i, mdp.pos_res, mdp.vel_ped_res)
        end
        collision = crash(mdp, ego, car, ped)
        return PedCarMDPState(collision, ego, ped, car, SVector{2, LaneTag}(LaneTag(0,0), LaneTag(0, 0)))
    else
        si_ = si - route_shift
        route = routes[route_ind]
        sroute = SVector{2, LaneTag}(route[1], route[end])
        n_cars = n_car_states(mdp.env, route, mdp.pos_res, mdp.vel_res)
        # cartesian/linear magic
        car_i, ped_i, ego_i = Tuple(CartesianIndices((n_cars, n_ped + 1, n_ego))[si_])
        car = ind2car(mdp.env, car_i, route, mdp.pos_res, mdp.vel_res)
        ego = ind2ego(mdp.env, ego_i, mdp.pos_res, mdp.vel_res)
        if ped_i > n_ped
            ped = get_off_the_grid(mdp)
        else
            ped = ind2ped(mdp.env, ped_i, mdp.pos_res, mdp.vel_ped_res)
        end
        collision = crash(mdp, ego, car, ped)
        return PedCarMDPState(collision, ego, ped, car, sroute)
    end
end


#### INITIAL STATES 

function POMDPs.initialstate(mdp::PedCarMDP)
    ego = initial_ego_state(mdp)
    init_car_states, init_car_routes = initial_car_state_distribution(mdp)
    init_ped_dist = initial_ped_state_distribution(mdp) 
    init_states = Vector{PedCarMDPState}()
    for i=1:length(init_car_states)
        for j=1:length(init_ped_dist.vals)
            ped = init_ped_dist.vals[j]
            car = init_car_states[i]
            route = init_car_routes[i]
            crash = is_colliding(Vehicle(ego, mdp.ego_type, EGO_ID), Vehicle(car, mdp.car_type, CAR_ID)) || is_colliding(Vehicle(ego, mdp.ego_type, EGO_ID), Vehicle(ped, mdp.ped_type, PED_ID))
            push!(init_states, PedCarMDPState(crash, ego, ped, car, SVector{2, LaneTag}(route[1], route[end])))
        end
    end
    # uniform
    probs = ones(length(init_states))
    normalize!(probs, 1)
    return SparseCat(init_states, probs)
end

function initial_ego_state(mdp::PedCarMDP)
    lanes = get_ego_route(mdp.env)
    posF = Frenet(mdp.env.roadway[lanes[1]], mdp.ego_start)
    v0 = 0.
    return VehicleState(posF, mdp.env.roadway, v0)
end

function initial_car_state_distribution(mdp::PedCarMDP)
    routes = get_car_routes(mdp.env)
    init_car_routes = []
    init_car_states = VehicleState[]
    for route in routes 
        car_states = get_car_states(mdp.env, route, mdp.pos_res, mdp.vel_res)
        for cs in car_states 
            push!(init_car_states, cs)
            push!(init_car_routes, route)
        end
    end
    push!(init_car_states, get_off_the_grid(mdp))
    push!(init_car_routes, SVector{2, LaneTag}(LaneTag(0,0), LaneTag(0,0)))
    return init_car_states, init_car_routes
end

function initial_car_state(mdp::PedCarMDP, rng::AbstractRNG)
    init_car_states, init_car_routes = initial_car_state_distribution(mdp)
    return rand(rng, init_car_states), rand(rng, init_car_routes)
end

function car_starting_states(mdp::PedCarMDP, min_speed::Float64 = 6.0)
    # list of car starting states
    routes = get_car_routes(mdp.env)
    v_space = min_speed:mdp.vel_res:mdp.env.params.speed_limit 
    N_states = 0
    for route in routes 
        N_states += length(v_space)
    end
    car_states = Vector{VehicleState}(N_states)
    start_routes = Vector{SVector{2, LaneTag}}(N_states)
    i = 1
    for route in routes
        lane = route[1]
        for v in v_space
            car_states[i] = VehicleState(Frenet(mdp.env.roadway[lane], 0.), mdp.env.roadway, v)
            start_routes[i] = SVector{2, LaneTag}(route[1], route[end])
            i += 1
        end
    end
    return car_states, start_routes
end

function initial_ped_state_distribution(mdp::PedCarMDP)
    init_ped_states = get_ped_states(mdp.env, mdp.pos_res, mdp.vel_ped_res)
    push!(init_ped_states, get_off_the_grid(mdp))
    # uniform (maybe add more weights to the states when pedestrians are not there?)
    probs = ones(length(init_ped_states))
    normalize!(probs, 1)
    return SparseCat(init_ped_states, probs)
end

function initial_ped_state(mdp::PedCarMDP, rng::AbstractRNG)
    init_dist = initial_ped_state_distribution(mdp)
    return rand(rng, init_dist)
end

function pedestrian_starting_states(mdp::PedCarMDP)
    # list of pedestrian starting states
    n_headings = 2
    lanes = get_ped_lanes(mdp.env)
    v_space = get_ped_vspace(mdp.env, mdp.vel_ped_res)
    ped_states = Vector{VehicleState}(length(lanes)*length(v_space)*n_headings)
    i = 1
    for lane in lanes
        dlane = get_discretized_lane(lane, mdp.env.roadway, mdp.pos_res)
        for v in v_space
            ped_states[i] = VehicleState(Frenet(mdp.env.roadway[lane], 0., 0., 0.), mdp.env.roadway, v)
            i += 1
            ped_states[i] = VehicleState(Frenet(mdp.env.roadway[lane], dlane[end], 0., float(pi)), mdp.env.roadway, v)
            i += 1
        end
    end
    return ped_states
end
