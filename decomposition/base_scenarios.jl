# Define several base scenarios derived from the large urban environment

# ego + 2 cars
const TwoCars = UrbanPOMDP(max_cars=2, max_peds=0, obstacles=false)

# ego + 1 ped + 1 car
const PedCar = UrbanPOMDP(max_cars=1, max_peds=1, obstacles=false)

# ego + 1 ped + 1 obstacle
const ObsPed = UrbanPOMDP(max_cars=0, max_peds=1, obstacles=true)

# ego + 1 car + 1 obstacle
const ObsCar = UrbanPOMDP(max_cars=1, max_peds=0, obstacles=true)

# Wrappers
@with_kw struct TwoCarsScenario
    problem::UrbanPOMDP = TwoCars
end

@with_kw struct PedCarScenario
    problem::UrbanPOMDP = PedCar
end

@with_kw struct ObsPedScenario
    problem::UrbanPOMDP = ObsPed
end

@with_kw struct ObsCarScenario
    problem::UrbanPOMDP = ObsCar
end


### Extract input


# given a big observation vector, split to an entity-wise representation
function split_o(obs::UrbanObs, pomdp::UrbanPOMDP, n_features=4, n_obstacles=3)
    car_map, ped_map, obs_map = Dict(), Dict(), Dict()
    ego = obs[1:n_features]
#     println("ego idx ", 1, ":", n_features)
    for (j,i) in enumerate(1:pomdp.max_cars)
        car_map["car$j"] = obs[i*n_features+1:(i+1)*n_features]
#         println("car$j idx ", i*n_features+1:(i+1)*n_features)
    end
    for (j,i) in enumerate(pomdp.max_cars + 1:pomdp.max_cars + pomdp.max_peds)
        ped_map["ped$j"] = obs[i*n_features+1:(i+1)*n_features]
#         println("ped$j idx ", i*n_features+1:(i+1)*n_features)
    end
    for (j,i)  in enumerate(pomdp.max_cars + pomdp.max_peds + 1:pomdp.max_cars + pomdp.max_peds + n_obstacles)
        obs_map["obs$j"] = obs[i*n_features+1:(i+1)*n_features]
#         println("obs$j idx ", i*n_features+1:(i+1)*n_features)
    end
    return ego, car_map, ped_map, obs_map
end

# return a list of tuple (pb_id, pb_input)
function get_problem_input(ego, car_map, ped_map, obs_map)
    inputs = []
    # build obs ped
    for (ped, ped_state) in ped_map
        obs_states = []
        for (obs, obs_state) in obs_map
            push!(obs_states, obs_state)

        end
        feature_vec = vcat(ego, ped_state, obs_states...)
        push!(inputs, (:obsped, feature_vec))
    end

    # build obs car
    for (car, car_state) in car_map
        obs_states = []
        for (obs, obs_state) in obs_map
            push!(obs_states, obs_state)
        end
        feature_vec = vcat(ego, car_state, obs_states...)
        push!(inputs, (:obscar, feature_vec))
    end

    # build ped car
    for (ped, ped_state) in ped_map
        for (car, car_state) in car_map
            feature_vec = vcat(ego, car_state, ped_state)
            push!(inputs, (:obscar, feature_vec))
        end
    end

    # build twocars
     for (car, car_state) in car_map
        for (car, car_state) in car_map
            feature_vec = vcat(ego, car_state, car_state)
            push!(inputs, (:twocars, feature_vec))
        end
    end
    return inputs
end

function decompose_input{O}(pomdp::UrbanPOMDP, o::O)
    ego, car_map, ped_map, obs_map = split_o(o, pomdp)
    inputs = get_problem_input(ego, car_map, ped_map, obs_map)
    return inputs
end
