function LuDiAIAfterFix::BuildRailRoute()
{
	if (!AIController.GetSetting("rail_support")) return;

	local unfinished = this.rail_build_manager.HasUnfinishedRoute();
	if (unfinished || (this.rail_route_manager.GetTrainCount() < max(AIGameSettings.GetValue("max_trains") - 10, 10)) && ((this.allRoutesBuilt >> 6) & 3) != 3) {
		local city_from = null;
		local city_to = null;
		local best_rail_type;
		local cargo_class = this.rail_route_manager.m_cargo_class_rail;
		if (!unfinished) {
			this.rail_route_manager.SwapCargoClass();
			local cargo_type = Utils.GetCargoType(cargo_class);

			local rail_types = AIRailTypeList();
			local train_list = AIEngineList(AIVehicle.VT_RAIL);
			local engine_list = AIList();
			local wagon_list = AIList();
			foreach (train_id, _ in train_list) {
				if (!AIEngine.IsValidEngine(train_id)) {
					continue;
				}
				if (!AIEngine.IsBuildable(train_id)) {
					continue;
				}
				if (!AIRail.IsRailTypeAvailable(AIEngine.GetRailType(train_id))) {
					continue;
				}
				if (!AIEngine.CanPullCargo(train_id, cargo_type)) {
					continue;
				}
				if (AIEngine.CanRefitCargo(train_id, cargo_type)) {
					if (AIEngine.IsWagon(train_id)) {
						wagon_list[train_id] = AIEngine.GetPrice(train_id);
					} else {
						engine_list[train_id] = AIEngine.GetPrice(train_id);
					}
				} else if (AIEngine.GetCapacity(train_id) == -1) {
					if (AIEngine.IsWagon(train_id)) {
//						wagon_list[train_id] = AIEngine.GetPrice(train_id);
					} else {
						engine_list[train_id] = AIEngine.GetPrice(train_id);
					}
				}
			}

			if (engine_list.IsEmpty() || wagon_list.IsEmpty()) {
				return;
			}

			local engine_wagon_pairs = AIList();
			foreach (engine_id, _ in engine_list) {
				foreach (wagon_id, _ in wagon_list) {
					local engine_wagon = (engine_id << 16) | wagon_id;
					foreach (rail_type, _ in rail_types) {
						if (!AIEngine.CanRunOnRail(engine_id, rail_type)) {
							continue;
						}
						if (!AIEngine.CanRunOnRail(wagon_id, rail_type)) {
							continue;
						}
						if (!AIEngine.HasPowerOnRail(engine_id, rail_type)) {
							continue;
						}
						if (!AIEngine.HasPowerOnRail(wagon_id, rail_type)) {
							continue;
						}
						if (!::caches.CanAttachToEngine(wagon_id, engine_id, cargo_type, rail_type)) {
							continue;
						}
						if (!engine_wagon_pairs.HasItem(engine_wagon)) {
							engine_wagon_pairs[engine_wagon] = 1 << rail_type;
						} else {
							local rail_types = engine_wagon_pairs[engine_wagon];
							rail_types = rail_types | (1 << rail_type);
							engine_wagon_pairs[engine_wagon] = rail_types;
						}
					}
				}
			}
//			AILog.Info("total engine_wagon_pairs: " + engine_wagon_pairs.Count());

			local max_station_spread = AIGameSettings.GetValue("station_spread");
			local max_train_length = AIGameSettings.GetValue("max_train_length");
			local platform_length = min(RailRoute.MAX_PLATFORM_LENGTH, min(max_station_spread, max_train_length));

			local best_pair_info = LuDiAIAfterFix.GetBestTrainIncome(engine_wagon_pairs, cargo_type, RAIL_DAYS_IN_TRANSIT, platform_length);
			if (best_pair_info[0][0] == -1) {
				return;
			}
			local engine_max_speed = AIEngine.GetMaxSpeed(best_pair_info[0][0]);
			local wagon_max_speed = AIEngine.GetMaxSpeed(best_pair_info[0][1]);
			local rail_type_max_speed = AIRail.GetMaxSpeed(best_pair_info[0][2][0]);
			local train_max_speed = min(rail_type_max_speed == 0 ? 65535 : rail_type_max_speed, min(engine_max_speed == 0 ? 65535 : engine_max_speed, wagon_max_speed == 0 ? 65535 : wagon_max_speed));
			local max_distance = best_pair_info[1];
//			local max_distance = (RAIL_DAYS_IN_TRANSIT * 2 * 74 * train_max_speed) / (256 * 16);
			local min_distance = max(40, max_distance * 2 / 3);

			local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
			local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
			local max_dist = (min_dist + MAX_DISTANCE_INCREASE) > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//			AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

			local best_rail_types = best_pair_info[0][2];
			local least_rail_type_cost = null;
			best_rail_type = AIRail.RAILTYPE_INVALID;
			foreach (rail_type in best_rail_types) {
				local cost = AIRail.GetMaintenanceCostFactor(rail_type);
				if (least_rail_type_cost == null || cost < least_rail_type_cost) {
					least_rail_type_cost = cost;
					best_rail_type = rail_type;
				}
			}
//			AILog.Info("best_pair_info: best_engine = " + AIEngine.GetName(best_pair_info[0][0]) + "; best_wagon = " + AIEngine.GetName(best_pair_info[0][1]) + " * " + best_pair_info[2] + "; best_rail_type = " + AIRail.GetName(best_rail_type) + "; best_capacity = " + best_pair_info[3] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

			local estimated_costs = 0;
			local engine_costs = ::caches.GetCostWithRefit(best_pair_info[0][0], cargo_type) * 1;
			local wagon_costs = ::caches.GetCostWithRefit(best_pair_info[0][1], cargo_type) * best_pair_info[2];
			local rail_costs = AIRail.GetBuildCost(best_rail_type, AIRail.BT_TRACK) * max_dist * 4;
			local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist * 4;
			local foundation_costs = AITile.GetBuildCost(AITile.BT_FOUNDATION) * max_dist * 2;
			local station_costs = AIRail.GetBuildCost(best_rail_type, AIRail.BT_STATION) * RailRoute.MAX_PLATFORM_LENGTH * 2;
			local depot_costs = AIRail.GetBuildCost(best_rail_type, AIRail.BT_DEPOT) * 2;
			estimated_costs += engine_costs + wagon_costs + rail_costs + clear_costs + foundation_costs + station_costs + depot_costs;
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + "; wagon_costs = " + wagon_costs + ", rail_costs = " + rail_costs + ", clear_costs = " + clear_costs + ", foundation_costs = " + foundation_costs + ", station_costs = " + station_costs + ", depot_costs = " + depot_costs);
			if (!Utils.HasMoney(estimated_costs + this.reservedMoney - this.reservedMoneyRail)) {
				return;
			} else {
//				AIController.Sleep(100);
//				AIController.Break(" ");
//				return;
				this.reservedMoneyRail = estimated_costs;
				this.reservedMoney += this.reservedMoneyRail;
			}

			if (city_from == null) {
				city_from = this.railTownManager.GetUnusedCity(((((this.bestRoutesBuilt >> 6) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						this.railTownManager.m_used_cities_list[cargo_class].Clear();
					} else if ((((this.bestRoutesBuilt >> 6) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
						this.bestRoutesBuilt = this.bestRoutesBuilt | (1 << (6 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
						this.railTownManager.m_used_cities_list[cargo_class].Clear();
//						this.railTownManager.m_near_city_pair_array[cargo_class].clear();
						AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " rail routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
					} else {
//						this.railTownManager.m_near_city_pair_array[cargo_class].clear();
						if ((((this.allRoutesBuilt >> 6) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " rail routes have been used!");
						}
						this.allRoutesBuilt = this.allRoutesBuilt | (1 << (6 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
					}
				}
			}

			if (city_from != null) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));

				this.railTownManager.FindNearCities(city_from, min_dist, max_dist, ((((this.bestRoutesBuilt >> 6) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);

				if (!this.railTownManager.m_near_city_pair_array[cargo_class].len()) {
					AILog.Info("No near city available");
					city_from = null;
				}
			}

			if (city_from != null) {
				foreach (near_city_pair in this.railTownManager.m_near_city_pair_array[cargo_class]) {
					if (city_from == near_city_pair[0]) {
						if (!this.rail_route_manager.TownRouteExists(city_from, near_city_pair[1], cargo_class)) {
							city_to = near_city_pair[1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((this.allRoutesBuilt >> 6) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && this.rail_route_manager.HasMaxStationCount(city_from, city_to, cargo_class)) {
//								AILog.Info("this.rail_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.rail_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
								city_to = null;
								continue;
							} else {
//								AILog.Info("this.rail_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.rail_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
								break;
							}
						}
					}
				}

				if (city_to == null) {
					city_from = null;
				}
			}

			if (city_from == null && city_to == null) {
				this.reservedMoney -= this.reservedMoneyRail;
				this.reservedMoneyRail = 0;
			}
		} else {
			if (!Utils.HasMoney(this.reservedMoneyRail / (this.rail_build_manager.m_builtWays + 1))) {
				return;
			}
		}

		if (unfinished || city_from != null && city_to != null) {
			if (!unfinished) {
				AILog.Info("t:New city found: " + AITown.GetName(city_from));
				AILog.Info("t:New near city found: " + AITown.GetName(city_to));
			}

			if (!unfinished) this.buildTimerRail = 0;
			city_from = unfinished ? this.rail_build_manager.m_city_from : city_from;
			city_to = unfinished ? this.rail_build_manager.m_city_to : city_to;
			cargo_class = unfinished ? this.rail_build_manager.m_cargo_class : cargo_class;
			local best_routes = unfinished ? this.rail_build_manager.m_best_routes_built : ((((this.bestRoutesBuilt >> 6) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);
			best_rail_type = unfinished ? this.rail_build_manager.m_rail_type : best_rail_type;

			local start_date = AIDate.GetCurrentDate();
			local route_result = this.rail_route_manager.BuildRoute(this.rail_build_manager, city_from, city_to, cargo_class, best_routes, best_rail_type);
			this.buildTimerRail += AIDate.GetCurrentDate() - start_date;
			if (route_result[0] != null) {
				if (route_result[0] != 0) {
					this.reservedMoney -= this.reservedMoneyRail;
					this.reservedMoneyRail = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + " rail route between " + AIBaseStation.GetName(AIStation.GetStationID(route_result[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(route_result[2])) + " in " + this.buildTimerRail + " day" + (this.buildTimerRail != 1 ? "s" : "") + ".");
				}
			} else {
				this.reservedMoney -= this.reservedMoneyRail;
				this.reservedMoneyRail = 0;
				this.railTownManager.ResetCityPair(city_from, city_to, cargo_class, false);
				AILog.Error("t:" + this.buildTimerRail + " day" + (this.buildTimerRail != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::GetBestTrainIncome(engine_wagon_pairs, cargo_type, days_in_transit, platform_length)
{
	local best_income = null;
	local best_distance = 0;
	local best_pair = [-1, -1, [AIRail.RAILTYPE_INVALID]];
	local best_num_wagons = 0;
	local best_capacity = 0;
	local best_rail_types = [];
	local best_platform_length = 0;
//	local queue = AIPriorityQueue();

	local length = platform_length;
	while (length <= platform_length) {
		foreach (engine_wagon, rail_types_mask in engine_wagon_pairs) {
			local engine_id = engine_wagon >> 16;
			local wagon_id = engine_wagon & 0xFFFF;
			local optimized = LuDiAIAfterFix.GetTrainOptimalDaysInTransit(engine_id, wagon_id, rail_types_mask, cargo_type, days_in_transit, length);
			local income = optimized[0];
			local distance = optimized[1];
			local num_wagons = optimized[2];
			local capacity = optimized[3];
			local rail_types = optimized[4];
//			queue.Insert([engine_id, wagon_id, income, distance, num_wagons, capacity, rail_types, length], income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_distance = distance;
				best_pair = [engine_id, wagon_id, rail_types];
				best_num_wagons = num_wagons;
				best_capacity = capacity;
				best_platform_length = length;
			}
		}
		length++;
	}

//	while (!queue.IsEmpty()) {
//		local item = queue.Pop();
//		AILog.Info("Length " + item[7] + ": " + AIEngine.GetName(item[0]) + " + " + item[4] + " * " + AIEngine.GetName(item[1]) + " (" + item[6].len() + " rail_types): " + item[5] + " " + AICargo.GetName(cargo_type) + ", " + item[3] + " dist, " + item[2] + " income");
//	}
	return [best_pair, best_distance, best_num_wagons, best_capacity];
}

function LuDiAIAfterFix::GetTrainOptimalDaysInTransit(engine_id, wagon_id, rail_types_mask, cargo_type, days_in_transit, platform_length)
{
	local engine_max_speed = AIEngine.GetMaxSpeed(engine_id) == 0 ? 65535 : AIEngine.GetMaxSpeed(engine_id);
	local wagon_max_speed = AIEngine.GetMaxSpeed(wagon_id) == 0 ? 65535 : AIEngine.GetMaxSpeed(wagon_id);
	local train_max_speed = min(engine_max_speed, wagon_max_speed);

	local rail_types_list = AIList();
	for (local rail_type = 0; rail_type < 64; rail_type++) {
		if (!(rail_types_mask & (1 << rail_type))) continue;
		local rail_type_max_speed = AIRail.GetMaxSpeed(rail_type) == 0 ? 65535 : AIRail.GetMaxSpeed(rail_type);
		rail_types_list.AddItem(rail_type, rail_type_max_speed);
	}

	local railtypes_below_train_speed = AIList();
	railtypes_below_train_speed.AddList(rail_types_list);
	railtypes_below_train_speed.KeepBelowValue(train_max_speed);
	rail_types_list.RemoveBelowValue(train_max_speed);

	local best_rail_types = [];
	if (rail_types_list.IsEmpty()) {
		/* Get the fastest ones */
		railtypes_below_train_speed.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		railtypes_below_train_speed.KeepValue(railtypes_below_train_speed.GetValue(railtypes_below_train_speed.Begin()));
		for (local rail_type = railtypes_below_train_speed.Begin(); !railtypes_below_train_speed.IsEnd(); rail_type = railtypes_below_train_speed.Next()) {
			best_rail_types.append(rail_type);
		}
	} else {
		/* Get the slowest ones */
		rail_types_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		rail_types_list.KeepValue(rail_types_list.GetValue(rail_types_list.Begin()));
		for (local rail_type = rail_types_list.Begin(); !rail_types_list.IsEnd(); rail_type = rail_types_list.Next()) {
			best_rail_types.append(rail_type);
		}
	}

	local rail_type = best_rail_types[0];
	local rail_type_max_speed = AIRail.GetMaxSpeed(rail_type) == 0 ? 65535 : AIRail.GetMaxSpeed(rail_type);
	train_max_speed = min(rail_type_max_speed, train_max_speed);

	local engine_length = ::caches.GetLength(engine_id, cargo_type);
	local wagon_length = ::caches.GetLength(wagon_id, cargo_type);
	local max_train_length = platform_length * 16;
	local num_wagons = (max_train_length - engine_length) / wagon_length;
	local engine_capacity = max(0, ::caches.GetCapacity(engine_id, cargo_type));
	local wagon_capacity = max(0, ::caches.GetCapacity(wagon_id, cargo_type));
	local train_capacity = engine_capacity + wagon_capacity * num_wagons;
	local engine_running_cost = AIEngine.GetRunningCost(engine_id);
	local wagon_running_cost = AIEngine.GetRunningCost(wagon_id);
	local train_running_cost = engine_running_cost + wagon_running_cost * num_wagons;

//	local engine_weight = AIEngine.GetWeight(engine_id);
//	local wagon_weight = AIEngine.GetWeight(wagon_id);
//	local freight_cargo = AICargo.IsFreight(cargo_type);
//	local freight_multiplier = AIGameSettings.GetValue("freight_trains");
//	local engine_cargo_weight = AICargo.GetWeight(cargo_type, engine_capacity) * (freight_cargo ? freight_multiplier : 1);
//	local wagon_cargo_weight = AICargo.GetWeight(cargo_type, wagon_capacity) * (freight_cargo ? freight_multiplier : 1);
//	local train_cargo_weight = engine_weight + engine_cargo_weight + (wagon_weight + wagon_cargo_weight) * num_wagons;
//	local engine_power = AIEngine.GetPower(engine_id);
//	local engine_max_tractive_effort = AIEngine.GetMaxTractiveEffort(engine_id);
//	local engine_cargo_max_tractive_effort_N = 1000 * engine_max_tractive_effort * (engine_weight + engine_cargo_weight) / engine_weight;

//	local air_drag = (train_max_speed <= 10) ? 192 : max(2048 / train_max_speed, 1);
//	local train_air_drag = air_drag + 3 * air_drag * (1 + num_wagons) / 20; // assumes 1 unit for multihead

//	AILog.Info("engine_id = " + AIEngine.GetName(engine_id));
//	AILog.Info("wagon_id = " + AIEngine.GetName(wagon_id));
//	AILog.Info("rail_type = " + AIRail.GetName(rail_type));
//	AILog.Info("engine_max_speed = " + engine_max_speed);
//	AILog.Info("wagon_max_speed = " + wagon_max_speed);
//	AILog.Info("rail_type_max_speed = " + rail_type_max_speed);
//	AILog.Info("train_max_speed = " + train_max_speed);

//	AILog.Info("engine_length = " + engine_length);
//	AILog.Info("wagon_length = " + wagon_length);
//	AILog.Info("max_train_length = " + max_train_length);
//	AILog.Info("num_wagons = " + num_wagons);
//	AILog.Info("engine_capacity = " + engine_capacity);
//	AILog.Info("wagon_capacity = " + wagon_capacity);
//	AILog.Info("train_capacity = " + train_capacity);
//	AILog.Info("engine_running_cost = " + engine_running_cost);
//	AILog.Info("wagon_running_cost = " + wagon_running_cost);
//	AILog.Info("train_running_cost = " + train_running_cost);

//	AILog.Info("engine_weight = " + engine_weight);
//	AILog.Info("wagon_weight = " + wagon_weight);
//	AILog.Info("freight_cargo = " + freight_cargo);
//	AILog.Info("freight_multiplier = " + freight_multiplier);
//	AILog.Info("engine_cargo_weight = " + engine_cargo_weight);
//	AILog.Info("wagon_cargo_weight = " + wagon_cargo_weight);
//	AILog.Info("train_cargo_weight = " + train_cargo_weight);
//	AILog.Info("engine_power = " + engine_power);
//	AILog.Info("engine_max_tractive_effort = " + engine_max_tractive_effort);
//	AILog.Info("engine_cargo_max_tractive_effort_N = " + engine_cargo_max_tractive_effort_N);

//	AILog.Info("air_drag = " + air_drag);
//	AILog.Info("train_air_drag = " + train_air_drag);

//	local engine_max_age = AIEngine.GetMaxAge(engine_id);
//	local engine_price = ::caches.GetCostWithRefit(engine_id, cargo_type);
//	local wagon_price = ::caches.GetCostWithRefit(wagon_id, cargo_type);
//	local train_price = engine_price + wagon_price * num_wagons;
//	local engine_reliability = AIEngine.GetReliability(engine_id);
//	local reliability = min(65535, (engine_reliability << 16) / 100);

//	AILog.Info("engine_max_age = " + engine_max_age);
//	AILog.Info("engine_price = " + engine_price);
//	AILog.Info("wagon_price = " + wagon_price);
//	AILog.Info("train_price = " + train_price);
//	AILog.Info("engine_reliability = " + engine_reliability);
//	AILog.Info("reliability = " + reliability);

//	AIController.Break(" ");

//	local distance_advanced = 0;
//	local breakdown_ctr = 0;
//	local breakdown_chance = 0;
//	local breakdown_delay = 0;
//	local tick_counter = 0;
//	local sub_speed = 0;
//	local cur_speed = 0;
//	local progress = 0;
//	local train_tick;
//	local days_in_ticks = days_in_transit * 74;
//	local timer = 0;
//	while (timer < days_in_ticks) {
//		timer++;
//		if (timer % 74 == 1) {
//			local check_vehicle_breakdown = CheckVehicleBreakdown(cur_speed, reliability, breakdown_ctr, breakdown_chance, breakdown_delay);
//			reliability = check_vehicle_breakdown[0];
//			breakdown_ctr = check_vehicle_breakdown[1];
//			breakdown_chance = check_vehicle_breakdown[2];
//			breakdown_delay = check_vehicle_breakdown[3];
//		}
//		train_tick = TrainTick(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress);
//		distance_advanced += train_tick[1];
//		tick_counter = train_tick[2];
//		breakdown_ctr = train_tick[3];
//		breakdown_delay = train_tick[4];
//		sub_speed = train_tick[5];
//		cur_speed = train_tick[6];
//		progress = train_tick[7];
//		if (timer % 74 == 0) {
//			AILog.Info("distance_advanced = " + distance_advanced + "; reliability = " + reliability + "; breakdown_ctr = " + breakdown_ctr +
//					"; breakdown_chance = " + breakdown_chance + "; breakdown_delay = " + breakdown_delay + "; tick_counter = " + tick_counter +
//					"; cur_speed = " + cur_speed + "; sub_speed = " + sub_speed + "; progress = " + progress + "; timer = " + timer);
//			AIController.Sleep(1);
//		}
//	}
//	local income = (train_capacity * AICargo.GetCargoIncome(cargo_type, distance_advanced / 16, days_in_transit) - train_running_cost * days_in_transit / 365 - days_in_transit * train_price / engine_max_age);
//	local income = (train_capacity * AICargo.GetCargoIncome(cargo_type, distance_advanced / 16, days_in_transit) * 365 * engine_max_age - train_running_cost * days_in_transit * engine_max_age - days_in_transit * train_price * 365) / (365 * engine_max_age);

//	AILog.Info("engine_id = " + AIEngine.GetName(engine_id) + "; wagon_id = " + AIEngine.GetName(wagon_id) + " * " + num_wagons + "; days_in_transit = " + days_in_transit + "; distance_advanced = " + distance_advanced / 16 + "; income = " + income);
//	AILog.Info("train_max_speed = " + train_max_speed + "; capacity = " + train_capacity + "; running cost = " + (train_running_cost * days_in_transit / 366) + "; train_price = " + (days_in_transit * train_price / engine_max_age) + "; engine_max_age = " + engine_max_age);

//	AIController.Break(" ");
//	return [income, distance_advanced / 16, num_wagons, train_capacity, best_rail_types];

	/* Simplified method for estimated income. */
	local multiplier = Utils.GetEngineReliabilityMultiplier(engine_id);
	local distance_advanced = (train_max_speed * 2 * 74 * days_in_transit) / (256 * 16);
	days_in_transit = days_in_transit + RailRoute.STATION_LOADING_INTERVAL;
	local income = ((train_capacity * AICargo.GetCargoIncome(cargo_type, distance_advanced, days_in_transit) - train_running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
	return [income, distance_advanced, num_wagons, train_capacity, best_rail_types];
}

// function LuDiAIAfterFix::CheckVehicleBreakdown(cur_speed, reliability, breakdown_ctr, breakdown_chance, breakdown_delay)
// {
// 	local rel;
// 	local no_servicing_if_no_breakdowns = AIGameSettings.GetValue("no_servicing_if_no_breakdowns");
// 	local vehicle_breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
// 	local reliability_spd_dec = 80; // assumes original default

// 	if (!no_servicing_if_no_breakdowns || vehicle_breakdowns != 0) {
// 		reliability = rel = max(reliability - reliability_spd_dec, 0);
// 	}

// 	if (breakdown_ctr != 0 || vehicle_breakdowns < 1 || cur_speed < 5) {
// 		return [reliability, breakdown_ctr, breakdown_chance, breakdown_delay];
// 	}

// 	local r = AIBase.Rand();

// 	local chance = breakdown_chance + 1;

// 	if ((((r & 0xFFFF) * 25 + 25 / 2) >> 16) < 1) chance += 25;
// 	breakdown_chance = min(255, chance);

// 	rel = reliability;
// 	if (vehicle_breakdowns == 1) rel += 0x6666;

// 	local _breakdown_chance = [
// 			  3,   3,   3,   3,   3,   3,   3,   3,
// 			  4,   4,   5,   5,   6,   6,   7,   7,
// 			  8,   8,   9,   9,  10,  10,  11,  11,
// 			 12,  13,  13,  13,  13,  14,  15,  16,
// 			 17,  19,  21,  25,  28,  31,  34,  37,
// 			 40,  44,  48,  52,  56,  60,  64,  68,
// 			 72,  80,  90, 100, 110, 120, 130, 140,
// 			150, 170, 190, 210, 230, 250, 250, 250
// 	];

// 	if (_breakdown_chance[min(rel, 0xFFFF) >> 10] <= breakdown_chance) {
// 		breakdown_ctr = ((r >> 16) & ((1 << 6) - 1)) + 0x3F;
// 		breakdown_delay = ((r >> 24) & ((1 << 7) - 1)) + 0x80;
// 		breakdown_chance = 0;
// 	}

// 	return [reliability, breakdown_ctr, breakdown_chance, breakdown_delay];
// }

// function LuDiAIAfterFix::HandleBreakdown(breakdown_ctr, cur_speed, tick_counter, breakdown_delay)
// {
// 	switch (breakdown_ctr) {
// 		case 0:
// 			return [false, breakdown_ctr, cur_speed, breakdown_delay];

// 		case 2:
// 			breakdown_ctr = 1;
// 			cur_speed = 0;

// 		case 1:
// 			if ((tick_counter & 3) == 0) {
// 				if (--breakdown_delay == 0) {
// 					breakdown_ctr = 0;
// 				}
// 			}
// 			return [true, breakdown_ctr, cur_speed, breakdown_delay];

// 		default:
// 			breakdown_ctr--;
// 			return [false, breakdown_ctr, cur_speed, breakdown_delay];
// 	}
// }

// function LuDiAIAfterFix::TrainTick(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress)
// {
// 	tick_counter = (tick_counter + 1) & 0xFF;

// 	local distance_advanced = 0;
// 	local train_loco_handler = TrainLocoHandler(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress);
// 	local res = train_loco_handler[0];
// 	distance_advanced += train_loco_handler[1];
// 	breakdown_ctr = train_loco_handler[2];
// 	breakdown_delay = train_loco_handler[3];
// 	sub_speed = train_loco_handler[4];
// 	cur_speed = train_loco_handler[5];
// 	progress = train_loco_handler[6];

// 	if (!res) return [false, distance_advanced, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress];

// 	train_loco_handler = TrainLocoHandler(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress);
// 	res = train_loco_handler[0];
// 	distance_advanced += train_loco_handler[1];
// 	breakdown_ctr = train_loco_handler[2];
// 	breakdown_delay = train_loco_handler[3];
// 	sub_speed = train_loco_handler[4];
// 	cur_speed = train_loco_handler[5];
// 	progress = train_loco_handler[6];
// 	return [res, distance_advanced, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress];
// }

// function LuDiAIAfterFix::TrainLocoHandler(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress)
// {
// 	local distance_advanced = 0;
// 	local handle_breakdown = HandleBreakdown(breakdown_ctr, cur_speed, tick_counter, breakdown_delay);
// 	local res = handle_breakdown[0];
// 	breakdown_ctr = handle_breakdown[1];
// 	cur_speed = handle_breakdown[2];
// 	breakdown_delay = handle_breakdown[3];

// 	if (res) return [true, distance_advanced, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress];

// 	local update_speed = UpdateSpeed(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, sub_speed, cur_speed, progress);
// 	local scaled_spd = update_speed[0];
// 	sub_speed = update_speed[1];
// 	cur_speed = update_speed[2];

// 	local adv_spd = 192; // assumes going straight, 128 for corners;

// 	if (scaled_spd >= adv_spd) {
// 		if (breakdown_ctr > 1) {
// 			local _breakdown_speeds = [225, 210, 195, 180, 165, 150, 135, 120, 105, 90, 75, 60, 45, 30, 15, 15];
// 			local break_speed = (~breakdown_ctr >> 4) & ((1 << 4) - 1);
// 			if (break_speed < cur_speed) cur_speed = break_speed;
// 		}
// 		for (;;) {
// 			scaled_spd -= adv_spd;
// 			distance_advanced++;
// 			if (scaled_spd < adv_spd) break;
// 		}
// 	}

// 	progress = scaled_spd;
// 	return [true, distance_advanced, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress];
// }

// function LuDiAIAfterFix::UpdateSpeed(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, sub_speed, cur_speed, progress)
// {
// 	local acceleration_model = AIGameSettings.GetValue("train_acceleration_model");

// 	if (acceleration_model == 0) {
// 		/* Original */
// 		local train_acceleration_base = Utils.Clamp(engine_power / train_cargo_weight * 4, 1, 255);
// 		return DoUpdateSpeed(train_acceleration_base * 2, 0, train_max_speed, sub_speed, cur_speed, progress);
// 	} else if (acceleration_model == 1) {
// 		/* Realistic */
// 		local train_power_watts = engine_power * 746;
// 		return DoUpdateSpeed(GetAcceleration(cur_speed, train_cargo_weight, train_power_watts, train_air_drag, engine_cargo_max_tractive_effort_N), 2, train_max_speed, sub_speed, cur_speed, progress);
// 	} else {
// 		throw "acceleration_model " + acceleration_model + " is unsupported in UpdateSpeed";
// 	}
// }

// function LuDiAIAfterFix::DoUpdateSpeed(accel, min_speed, max_speed, sub_speed, cur_speed, progress)
// {
// 	local spd = sub_speed + accel;
// 	sub_speed = spd & 0xFF;

// 	local tempmax = max_speed;
// 	if (cur_speed > max_speed) {
// 		tempmax = max(cur_speed - (cur_speed / 10 ) - 1, max_speed);
// 	}

// 	cur_speed = spd = max(min(cur_speed + (spd >> 8), tempmax), min_speed);

// 	local scaled_spd = spd * 3 / 4;

// 	scaled_spd += progress;

// 	return [scaled_spd, sub_speed, cur_speed];
// }

// function LuDiAIAfterFix::GetAcceleration(cur_speed, train_cargo_weight, train_power_watts, train_air_drag, engine_cargo_max_tractive_effort_N)
// {
// 	local train_axle_resistance = 10 * train_cargo_weight;
// 	local train_rolling_friction = 15 * (512 + cur_speed) / 512;
// 	local air_drag_area = 14; // 28 in tunnels.
// 	local slope_steepness = AIGameSettings.GetValue("train_slope_steepness");
// 	local train_slope_resistance = train_cargo_weight * slope_steepness * 100;

// 	local resistance = 0;
// 	resistance += train_axle_resistance;
// 	resistance += train_cargo_weight * train_rolling_friction;
// 	resistance += air_drag_area * train_air_drag * cur_speed * cur_speed / 1000;
///	resistance += train_slope_resistance; // this assumes worst case, entire train going uphill

// 	local force;
// 	if (cur_speed > 0) {
// 		force = train_power_watts * 18 / (cur_speed * 5);
// 		if (force > engine_cargo_max_tractive_effort_N) force = engine_cargo_max_tractive_effort_N;
// 	} else {
// 		force = min(engine_cargo_max_tractive_effort_N, train_power_watts);
// 		force = max(force, (train_cargo_weight * 8) + resistance);
// 	}

// 	if (force == resistance) return 0;

// 	local accel = Utils.Clamp((force - resistance) / (train_cargo_weight * 4), -2147483648, 2147483647);
// 	return force < resistance ? min(-1, accel) : max(1, accel);
// }

function LuDiAIAfterFix::ResetRailManagementVariables()
{
	if (this.lastRailManagedArray < 0) this.lastRailManagedArray = this.rail_route_manager.m_town_route_array.len() - 1;
	if (this.lastRailManagedManagement < 0) this.lastRailManagedManagement = 7;
}

function LuDiAIAfterFix::InterruptRailManagement(cur_date)
{
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (this.lastRailManagedArray == -1) this.lastRailManagedManagement--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageTrainRoutes()
{
	local max_trains = AIGameSettings.GetValue("max_trains");

	local cur_date = AIDate.GetCurrentDate();
	this.ResetRailManagementVariables();

//	for (local i = this.lastRailManagedArray; i >= 0; --i) {
//		if (this.lastRailManagedManagement != 8) break;
//		this.lastRailManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(this.rail_route_manager.m_town_route_array[i].m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.rail_route_manager.m_town_route_array[i].m_station_to)));
//		if (this.InterruptRailManagement(cur_date)) return;
//	}
//	this.ResetRailManagementVariables();
//	if (this.lastRailManagedManagement == 8) this.lastRailManagedManagement--;
//
//	local start_tick = AIController.GetTick();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 7) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		this.rail_route_manager.m_town_route_array[i].RenewVehicles();
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 7) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 6) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		this.rail_route_manager.m_town_route_array[i].SendNegativeProfitVehiclesToDepot();
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 6) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = this.rail_route_manager.GetTrainCount();
	local max_all_routes_profit = this.rail_route_manager.HighestProfitLastYear();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 5) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (max_trains * 0.95 < num_vehs) {
			this.rail_route_manager.m_town_route_array[i].SendLowProfitVehiclesToDepot(max_all_routes_profit);
		}
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 5) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 4) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". UpdateEngineWagonPair");
		this.rail_route_manager.m_town_route_array[i].UpdateEngineWagonPair();
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 4) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 3) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		this.rail_route_manager.m_town_route_array[i].SellVehiclesInDepot();
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 3) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 2) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeBridges")
		this.rail_route_manager.m_town_route_array[i].UpgradeBridges();
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 2) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = this.rail_route_manager.GetTrainCount();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 1) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < max_trains) {
			num_vehs += this.rail_route_manager.m_town_route_array[i].AddRemoveVehicleToRoute(num_vehs < max_trains);
		}
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 1) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRailManagedArray; i >= 0; --i) {
		if (this.lastRailManagedManagement != 0) break;
		this.lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local city_from = this.rail_route_manager.m_town_route_array[i].m_city_from;
		local city_to = this.rail_route_manager.m_town_route_array[i].m_city_to;
		local cargo_class = this.rail_route_manager.m_town_route_array[i].m_cargo_class;
		if (this.rail_route_manager.m_town_route_array[i].RemoveIfUnserviced()) {
			this.rail_route_manager.m_town_route_array.remove(i);
			this.railTownManager.ResetCityPair(city_from, city_to, cargo_class, true);
		}
		if (this.InterruptRailManagement(cur_date)) return;
	}
	this.ResetRailManagementVariables();
	if (this.lastRailManagedManagement == 0) this.lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.rail_route_manager.m_town_route_array.len() + " rail route" + (this.rail_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}

function LuDiAIAfterFix::CheckForUnfinishedRailRoute()
{
	if (this.rail_build_manager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered rail station or depot tiles during save */
		local station_from = this.rail_build_manager.m_station_from;
		local station_to = this.rail_build_manager.m_station_to;
		local depot_tile_from = this.rail_build_manager.m_depot_tile_from;
		local depot_tile_to = this.rail_build_manager.m_depot_tile_to;
		local station_type = AIStation.STATION_TRAIN;
		local station_from_dir = this.rail_build_manager.m_station_from_dir;
		local station_to_dir = this.rail_build_manager.m_station_to_dir;

		if (station_from == -1 || station_to == -1) {
			local station_list = AIStationList(station_type);
			local all_station_tiles = AITileList();
			foreach (station_id, _ in station_list) {
				local station_tiles = AITileList_StationType(station_id, station_type);
				station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
				local top_tile = station_tiles.Begin();
				all_station_tiles[top_tile] = 0;
			}
//			AILog.Info("all_station_tiles has " + all_station_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			if (station_from != -1) all_tiles_found.AddTile(station_from);
			foreach (tile, _ in all_station_tiles) {
				local found = false;
				foreach (id, i in ::scheduled_removals_table.Train) {
					local t = i.m_tile;
					local struct = i.m_struct;
					if (struct == RailStructType.STATION) {
						if (t == tile) {
							found = true;
							break;
						}
					}
				}
				if (found) {
//					AILog.Info("scheduled_removals_table.Train has tile " + tile);
					all_tiles_found[tile] = 0;
				}
				foreach (i, route in this.rail_route_manager.m_town_route_array) {
					if (route.m_station_from == tile || route.m_town_route_array[i].m_station_to == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), station_type);
						station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
						local top_tile = station_tiles.Begin();
						all_tiles_found[top_tile] = 0;
						break;
					}
				}
			}

			if (all_tiles_found.Count() != all_station_tiles.Count()) {
//				AILog.Info(all_tiles_found.Count() + " != " + all_station_tiles.Count());
				local all_tiles_missing = AITileList();
				all_tiles_missing.AddList(all_station_tiles);
				all_tiles_missing.RemoveList(all_tiles_found);
				foreach (tile, _ in all_tiles_missing) {
//					AILog.Info("Tile " + tile + " is missing");
					local station = RailStation.CreateFromTile(tile);
					RailRoute.ScheduleRemoveStation(station.m_tile, station.m_dir);
				}
			}
		}

		if (depot_tile_from == -1 || depot_tile_to == -1) {
			local all_depots_tiles = AIDepotList(AITile.TRANSPORT_RAIL);
//			AILog.Info("all_depots_tiles has " + all_depots_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			if (depot_tile_from != -1) all_tiles_found[depot_tile_from] = 0;
			foreach (tile, _ in all_depots_tiles) {
				local found = false;
				foreach (id, i in ::scheduled_removals_table.Train) {
					local t = i.m_tile;
					local struct = i.m_struct;
					if (struct == RailStructType.DEPOT) {
						if (t == tile) {
							found = true;
							break;
						}
					}
				}
				if (found) {
//					AILog.Info("scheduled_removals_table.Train has tile " + tile);
					all_tiles_found[tile] = 0;
				}
				foreach (i, route in this.rail_route_manager.m_town_route_array) {
					if (route.m_depot_tile_from == tile || route.m_depot_tile_to == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						all_tiles_found[tile] = 0;
						break;
					}
				}
			}

			if (all_tiles_found.Count() != all_depots_tiles.Count()) {
//				AILog.Info(all_tiles_found.Count() + " != " + all_depots_tiles.Count());
				local all_tiles_missing = AITileList();
				all_tiles_missing.AddList(all_depots_tiles);
				all_tiles_missing.RemoveList(all_tiles_found);
				foreach (tile, _ in all_tiles_missing) {
//					AILog.Info("Tile " + tile + " is missing");
					RailRoute.ScheduleRemoveDepot(tile);
				}
			}
		}
	}
}
