function LuDiAIAfterFix::BuildRailRoute(cityFrom, unfinished) {
	if (unfinished || (railRouteManager.GetTrainCount() < max(MAX_TRAIN_VEHICLES - 10, 10)) && ((allRoutesBuilt >> 6) & 3) != 3) {

		local cityTo = null;
		local best_railtype;
		local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRail : (!unfinished ? cargoClassRail : (cargoClassRail == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
		if (!unfinished) {
			cargoClassRail = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRail : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

			local cargo = Utils.GetCargoType(cC);

			local railtypes = AIRailTypeList();
//			for (local railtype = railtypes.Begin(); !railtypes.IsEnd(); railtype = railtypes.Next()) {
//				local railtype_name = AIRail.GetName(railtype);
//				local railtype_available = AIRail.IsRailTypeAvailable(railtype);
//				local railtype_max_speed = AIRail.GetMaxSpeed(railtype);
//				local railtype_maintenance_cost_factor = AIRail.GetMaintenanceCostFactor(railtype);
//				AILog.Info("railtype = " + railtype);
//				AILog.Info("railtype_name = " + railtype_name);
//				AILog.Info("railtype_available = " + railtype_available);
//				AILog.Info("railtype_max_speed = " + railtype_max_speed);
//				AILog.Info("railtype_maintenance_cost_factor = " + railtype_maintenance_cost_factor);
//			}
			local tempList = AIEngineList(AIVehicle.VT_RAIL);
			local engineList = AIList();
			local wagonList = AIList();
			for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
//				local engine_name = AIEngine.GetName(engine);
//				local engine_valid = AIEngine.IsValidEngine(engine);
//				local engine_buildable = AIEngine.IsBuildable(engine);
//				local engine_cargo_type = AIEngine.GetCargoType(engine);
//				local engine_refit_cargo = AIEngine.CanRefitCargo(engine, cargo);
//				local engine_pull_cargo = AIEngine.CanPullCargo(engine, cargo);
//				local engine_capacity = AIEngine.GetCapacity(engine);
//				local engine_reliability = AIEngine.GetReliability(engine);
//				local engine_max_speed = AIEngine.GetMaxSpeed(engine);
//				local engine_price = AIEngine.GetPrice(engine);
//				local engine_max_age = AIEngine.GetMaxAge(engine);
//				local engine_running_cost = AIEngine.GetRunningCost(engine);
//				local engine_power = AIEngine.GetPower(engine);
//				local engine_weight = AIEngine.GetWeight(engine);
//				local engine_tractive_effort = AIEngine.GetMaxTractiveEffort(engine);
//				local engine_design_date = AIEngine.GetDesignDate(engine);
//				local engine_vehicle_type = AIEngine.GetVehicleType(engine);
//				local engine_wagon = AIEngine.IsWagon(engine);
//				local engine_articulated = AIEngine.IsArticulated(engine);
//				local engine_order_distance = AIEngine.GetMaximumOrderDistance(engine);
//				local engine_railtype = AIEngine.GetRailType(engine);
//				AILog.Info("engine = " + engine);
//				AILog.Info("engine_name = " + engine_name);
//				AILog.Info("engine_valid = " + engine_name);
//				AILog.Info("engine_buildable = " + engine_buildable);
//				AILog.Info("engine_cargo_type = " + engine_cargo_type);
//				AILog.Info("engine_refit_cargo = " + engine_refit_cargo);
//				AILog.Info("engine_pull_cargo = " + engine_pull_cargo);
//				AILog.Info("engine_capacity = " + engine_capacity);
//				AILog.Info("engine_reliability = " + engine_reliability);
//				AILog.Info("engine_max_speed = " + engine_max_speed);
//				AILog.Info("engine_price = " + engine_price);
//				AILog.Info("engine_max_age = " + engine_max_age);
//				AILog.Info("engine_running_cost = " + engine_running_cost);
//				AILog.Info("engine_power = " + engine_power);
//				AILog.Info("engine_weight = " + engine_weight);
//				AILog.Info("engine_tractive_effort = " + engine_tractive_effort);
//				AILog.Info("engine_design_date = " + engine_design_date);
//				AILog.Info("engine_vehicle_type = " + engine_vehicle_type);
//				AILog.Info("engine_wagon = " + engine_wagon);
//				AILog.Info("engine_articulated = " + engine_articulated);
//				AILog.Info("engine_order_distance = " + engine_order_distance);
//				AILog.Info("engine_railtype = " + engine_railtype);
//				for (local railtype = railtypes.Begin(); !railtypes.IsEnd(); railtype = railtypes.Next()) {
//					local railtype_name = AIRail.GetName(railtype);
//					local engine_can_run_on_rail = AIEngine.CanRunOnRail(engine, railtype);
//					local engine_has_power_on_rail = AIEngine.HasPowerOnRail(engine, railtype);
//					local engine_railtype_can_run_on_rail = AIRail.TrainCanRunOnRail(engine_railtype, railtype);
//					local engine_railtype_has_power_on_rail = AIRail.TrainHasPowerOnRail(engine_railtype, railtype);
//					AILog.Info(" railtype = " + railtype);
//					AILog.Info(" railtype_name = " + railtype_name);
//					AILog.Info(" engine_can_run_on_rail = " + engine_can_run_on_rail);
//					AILog.Info(" engine_has_power_on_rail = " + engine_has_power_on_rail);
//					AILog.Info(" engine_railtype_can_run_on_rail = " + engine_railtype_can_run_on_rail);
//					AILog.Info(" engine_railtype_has_power_on_rail = " + engine_railtype_has_power_on_rail);
//				}
//				AIController.Break(" ");
				if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIRail.IsRailTypeAvailable(AIEngine.GetRailType(engine)) &&
						AIEngine.CanPullCargo(engine, cargo)) {
					if (AIEngine.CanRefitCargo(engine, cargo)) {
						if (AIEngine.IsWagon(engine)) {
							wagonList.AddItem(engine, AIEngine.GetPrice(engine));
						} else {
							engineList.AddItem(engine, AIEngine.GetPrice(engine));
						}
					} else if (AIEngine.GetCapacity(engine) == -1) {
						if (AIEngine.IsWagon(engine)) {
//							wagonList.AddItem(engine, AIEngine.GetPrice(engine));
						} else {
							engineList.AddItem(engine, AIEngine.GetPrice(engine));
						}
					}
				}
			}

			if (engineList.Count() == 0 || wagonList.Count() == 0) {
//				cargoClassRail = cC;
				return;
			}

			engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price
			wagonList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

			local engineWagonPairs = AIList();
			for (local engine = engineList.Begin(); !engineList.IsEnd(); engine = engineList.Next()) {
				for (local wagon = wagonList.Begin(); !wagonList.IsEnd(); wagon = wagonList.Next()) {
					local pair = (engine << 16) | wagon;
					for (local railtype = railtypes.Begin(); !railtypes.IsEnd(); railtype = railtypes.Next()) {
						if (AIEngine.CanRunOnRail(engine, railtype) && AIEngine.CanRunOnRail(wagon, railtype) &&
								AIEngine.HasPowerOnRail(engine, railtype) && AIEngine.HasPowerOnRail(wagon, railtype) &&
								::caches.CanAttachToEngine(wagon, engine, cargo, railtype)) {
							if (!engineWagonPairs.HasItem(pair)) {
								engineWagonPairs.AddItem(pair, 1 << railtype);
							} else {
								local railtypes = engineWagonPairs.GetValue(pair);
								railtypes = railtypes | (1 << railtype);
								engineWagonPairs.SetValue(pair, railtypes);
							}
						}
					}
				}
			}
//			AILog.Info("total engineWagonPairs: " + engineWagonPairs.Count());

			local max_station_spread = AIGameSettings.GetValue("station_spread");
			local max_train_length = AIGameSettings.GetValue("max_train_length");
			local platform_length = min(RailRoute.MAX_PLATFORM_LENGTH, min(max_station_spread, max_train_length));

			local bestpairinfo = LuDiAIAfterFix.GetBestTrainIncome(engineWagonPairs, cargo, RAIL_DAYS_IN_TRANSIT, platform_length);
			if (bestpairinfo[0][0] == -1) {
//				cargoClassRail = cC;
				return;
			}
			local engine_max_speed = AIEngine.GetMaxSpeed(bestpairinfo[0][0]);
			local wagon_max_speed = AIEngine.GetMaxSpeed(bestpairinfo[0][1]);
			local railtype_max_speed = AIRail.GetMaxSpeed(bestpairinfo[0][2][0]);
			local train_max_speed = min(railtype_max_speed == 0 ? 65535 : railtype_max_speed, min(engine_max_speed == 0 ? 65535 : engine_max_speed, wagon_max_speed == 0 ? 65535 : wagon_max_speed));
			local max_distance = bestpairinfo[1];
//			local max_distance = (RAIL_DAYS_IN_TRANSIT * 2 * 74 * train_max_speed) / (256 * 16);
			local min_distance = max(40, max_distance * 2 / 3);

			local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
			local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
			local max_dist = (min_dist + MAX_DISTANCE_INCREASE) > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//			AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

			local best_railtypes = bestpairinfo[0][2];
			local least_railtype_cost = null;
			best_railtype = AIRail.RAILTYPE_INVALID;
			foreach (railtype in best_railtypes) {
				local cost = AIRail.GetMaintenanceCostFactor(railtype);
				if (least_railtype_cost == null || cost < least_railtype_cost) {
					least_railtype_cost = cost;
					best_railtype = railtype;
				}
			}
//			AILog.Info("bestpairinfo: best_engine = " + AIEngine.GetName(bestpairinfo[0][0]) + "; best_wagon = " + AIEngine.GetName(bestpairinfo[0][1]) + " * " + bestpairinfo[2] + "; best_railtype = " + AIRail.GetName(best_railtype) + "; best_capacity = " + bestpairinfo[3] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

			local estimated_costs = 0;
			local engine_costs = ::caches.GetCostWithRefit(bestpairinfo[0][0], cargo) * 1;
			local wagon_costs = ::caches.GetCostWithRefit(bestpairinfo[0][1], cargo) * bestpairinfo[2];
			local rail_costs = AIRail.GetBuildCost(best_railtype, AIRail.BT_TRACK) * max_dist * 4;
			local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist * 4;
			local foundation_costs = AITile.GetBuildCost(AITile.BT_FOUNDATION) * max_dist * 2;
			local station_costs = AIRail.GetBuildCost(best_railtype, AIRail.BT_STATION) * RailRoute.MAX_PLATFORM_LENGTH * 2;
			local depot_costs = AIRail.GetBuildCost(best_railtype, AIRail.BT_DEPOT) * 2;
			estimated_costs += engine_costs + wagon_costs + rail_costs + clear_costs + foundation_costs + station_costs + depot_costs;
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + "; wagon_costs = " + wagon_costs + ", rail_costs = " + rail_costs + ", clear_costs = " + clear_costs + ", foundation_costs = " + foundation_costs + ", station_costs = " + station_costs + ", depot_costs = " + depot_costs);
			if (!Utils.HasMoney(estimated_costs + reservedMoney - reservedMoneyRail)) {
//				cargoClassRail = cC;
				return;
			} else {
//				AIController.Sleep(100);
//				AIController.Break(" ");
//				return;
				reservedMoneyRail = estimated_costs;
				reservedMoney += reservedMoneyRail;
			}

			if (cityFrom == null) {
				cityFrom = railTownManager.GetUnusedCity(((((bestRoutesBuilt >> 6) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
				if (cityFrom == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						if (cC == AICargo.CC_PASSENGERS) {
							railTownManager.m_usedCitiesPassList.Clear();
						} else {
							railTownManager.m_usedCitiesMailList.Clear();
						}
					} else {
						if ((((bestRoutesBuilt >> 6) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							bestRoutesBuilt = bestRoutesBuilt | (1 << (6 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							if (cC == AICargo.CC_PASSENGERS) {
								railTownManager.m_usedCitiesPassList.Clear();
							} else {
								railTownManager.m_usedCitiesMailList.Clear();
							}
//							railTownManager.ClearCargoClassArray(cC);
							AILog.Warning("Best " + AICargo.GetCargoLabel(cargo) + " rail routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
						} else {
//							railTownManager.ClearCargoClassArray(cC);
							if ((((allRoutesBuilt >> 6) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								AILog.Warning("All " + AICargo.GetCargoLabel(cargo) + " rail routes have been used!");
							}
							allRoutesBuilt = allRoutesBuilt | (1 << (6 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
						}
					}
				}
			}

			if (cityFrom != null) {
//				AILog.Info("New city found: " + AITown.GetName(cityFrom));

				railTownManager.FindNearCities(cityFrom, min_dist, max_dist, ((((bestRoutesBuilt >> 6) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);

				if (!railTownManager.HasArrayCargoClassPairs(cC)) {
					AILog.Info("No near city available");
					cityFrom = null;
				}
			}

			if (cityFrom != null) {
				for (local i = 0; i < railTownManager.m_nearCityPairArray.len(); ++i) {
					if (cityFrom == railTownManager.m_nearCityPairArray[i][0] && cC == railTownManager.m_nearCityPairArray[i][2]) {
						if (!railRouteManager.TownRouteExists(cityFrom, railTownManager.m_nearCityPairArray[i][1], cC)) {
							cityTo = railTownManager.m_nearCityPairArray[i][1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 6) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && railRouteManager.HasMaxStationCount(cityFrom, cityTo, cC)) {
//								AILog.Info("railRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + railRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
								cityTo = null;
								continue;
							} else {
//								AILog.Info("railRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + railRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
								break;
							}
						}
					}
				}

				if (cityTo == null) {
					cityFrom = null;
				}
			}

			if (cityFrom == null && cityTo == null) {
				reservedMoney -= reservedMoneyRail;
				reservedMoneyRail = 0;
			}
		} else {
			if (!Utils.HasMoney(reservedMoneyRail / (railBuildManager.m_builtWays + 1))) {
				return;
			}
		}

		if (unfinished || cityFrom != null && cityTo != null) {
			if (!unfinished) {
				AILog.Info("t:New city found: " + AITown.GetName(cityFrom));
				AILog.Info("t:New near city found: " + AITown.GetName(cityTo));
			}

			if (!unfinished) buildTimerRail = 0;
			local from = unfinished ? railBuildManager.m_cityFrom : cityFrom;
			local to = unfinished ? railBuildManager.m_cityTo : cityTo;
			local cargoC = unfinished ? railBuildManager.m_cargoClass : cC;
			local best_routes = unfinished ? railBuildManager.m_best_routes_built : ((((bestRoutesBuilt >> 6) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);
			local rt = unfinished ? railBuildManager.m_railtype : best_railtype;

			local start_date = AIDate.GetCurrentDate();
			local routeResult = railRouteManager.BuildRoute(railBuildManager, from, to, cargoC, best_routes, rt);
			buildTimerRail += AIDate.GetCurrentDate() - start_date;
			if (routeResult[0] != null) {
				if (routeResult[0] != 0) {
					reservedMoney -= reservedMoneyRail;
					reservedMoneyRail = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargoC)) + " rail route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerRail + " day" + (buildTimerRail != 1 ? "s" : "") + ".");
				}
			} else {
				reservedMoney -= reservedMoneyRail;
				reservedMoneyRail = 0;
				railTownManager.RemoveUsedCityPair(from, to, cC, false);
				AILog.Error("t:" + buildTimerRail + " day" + (buildTimerRail != 1 ? "s" : "") + " wasted!");
			}

//			cityFrom = cityTo; // use this line to look for a new town from the last town
			cityFrom = null;
		}
	}
}

function LuDiAIAfterFix::GetBestTrainIncome(pairList, cargo, days_in_transit, platform_length) {
	local best_income = null;
	local best_distance = 0;
	local best_pair = [-1, -1, [AIRail.RAILTYPE_INVALID]];
	local best_num_wagons = 0;
	local best_capacity = 0;
	local best_railtypes = [];
	local best_platform_length = 0;
//	local queue = AIPriorityQueue();

	local length = platform_length;
	while (length <= platform_length) {
		foreach (pair, railtypesmask in pairList) {
			local engine = pair >> 16;
			local wagon = pair & 0xFFFF;
			local optimized = LuDiAIAfterFix.GetTrainOptimalDaysInTransit(engine, wagon, railtypesmask, cargo, days_in_transit, length);
			local income = optimized[0];
			local distance = optimized[1];
			local num_wagons = optimized[2];
			local capacity = optimized[3];
			local railtypes = optimized[4];
//			queue.Insert([engine, wagon, income, distance, num_wagons, capacity, railtypes, length], income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_distance = distance;
				best_pair = [engine, wagon, railtypes];
				best_num_wagons = num_wagons;
				best_capacity = capacity;
				best_platform_length = length;
			}
		}
		length++;
	}

//	while (!queue.IsEmpty()) {
//		local item = queue.Pop();
//		AILog.Info("Length " + item[7] + ": " + AIEngine.GetName(item[0]) + " + " + item[4] + " * " + AIEngine.GetName(item[1]) + " (" + item[6].len() + " railtypes): " + item[5] + " " + AICargo.GetName(cargo) + ", " + item[3] + " dist, " + item[2] + " income");
//	}
	return [best_pair, best_distance, best_num_wagons, best_capacity];
}

function LuDiAIAfterFix::GetTrainOptimalDaysInTransit(engine, wagon, railtypesmask, cargo, days_in_transit, platform_length)
{
	local engine_max_speed = AIEngine.GetMaxSpeed(engine) == 0 ? 65535 : AIEngine.GetMaxSpeed(engine);
	local wagon_max_speed = AIEngine.GetMaxSpeed(wagon) == 0 ? 65535 : AIEngine.GetMaxSpeed(wagon);
	local train_max_speed = min(engine_max_speed, wagon_max_speed);

	local railtypes_list = AIList();
	for (local railtype = 0; railtype < 64; railtype++) {
		if (!(railtypesmask & (1 << railtype))) continue;
		local railtype_max_speed = AIRail.GetMaxSpeed(railtype) == 0 ? 65535 : AIRail.GetMaxSpeed(railtype);
		railtypes_list.AddItem(railtype, railtype_max_speed);
	}

	local railtypes_below_train_speed = AIList();
	railtypes_below_train_speed.AddList(railtypes_list);
	railtypes_below_train_speed.KeepBelowValue(train_max_speed);
	railtypes_list.RemoveBelowValue(train_max_speed);

	local best_railtypes = [];
	if (railtypes_list.IsEmpty()) {
		/* Get the fastest ones */
		railtypes_below_train_speed.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		railtypes_below_train_speed.KeepValue(railtypes_below_train_speed.GetValue(railtypes_below_train_speed.Begin()));
		for (local railtype = railtypes_below_train_speed.Begin(); !railtypes_below_train_speed.IsEnd(); railtype = railtypes_below_train_speed.Next()) {
			best_railtypes.append(railtype);
		}
	} else {
		/* Get the slowest ones */
		railtypes_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		railtypes_list.KeepValue(railtypes_list.GetValue(railtypes_list.Begin()));
		for (local railtype = railtypes_list.Begin(); !railtypes_list.IsEnd(); railtype = railtypes_list.Next()) {
			best_railtypes.append(railtype);
		}
	}

	local railtype = best_railtypes[0];
	local railtype_max_speed = AIRail.GetMaxSpeed(railtype) == 0 ? 65535 : AIRail.GetMaxSpeed(railtype);
	train_max_speed = min(railtype_max_speed, train_max_speed);

	local engine_length = ::caches.GetLength(engine, cargo);
	local wagon_length = ::caches.GetLength(wagon, cargo);
	local max_train_length = platform_length * 16;
	local num_wagons = (max_train_length - engine_length) / wagon_length;
	local engine_capacity = max(0, ::caches.GetCapacity(engine, cargo));
	local wagon_capacity = max(0, ::caches.GetCapacity(wagon, cargo));
	local train_capacity = engine_capacity + wagon_capacity * num_wagons;
	local engine_running_cost = AIEngine.GetRunningCost(engine);
	local wagon_running_cost = AIEngine.GetRunningCost(wagon);
	local train_running_cost = engine_running_cost + wagon_running_cost * num_wagons;

//	local engine_weight = AIEngine.GetWeight(engine);
//	local wagon_weight = AIEngine.GetWeight(wagon);
//	local freight_cargo = AICargo.IsFreight(cargo);
//	local freight_multiplier = AIGameSettings.GetValue("freight_trains");
//	local engine_cargo_weight = AICargo.GetWeight(cargo, engine_capacity) * (freight_cargo ? freight_multiplier : 1);
//	local wagon_cargo_weight = AICargo.GetWeight(cargo, wagon_capacity) * (freight_cargo ? freight_multiplier : 1);
//	local train_cargo_weight = engine_weight + engine_cargo_weight + (wagon_weight + wagon_cargo_weight) * num_wagons;
//	local engine_power = AIEngine.GetPower(engine);
//	local engine_max_tractive_effort = AIEngine.GetMaxTractiveEffort(engine);
//	local engine_cargo_max_tractive_effort_N = 1000 * engine_max_tractive_effort * (engine_weight + engine_cargo_weight) / engine_weight;

//	local air_drag = (train_max_speed <= 10) ? 192 : max(2048 / train_max_speed, 1);
//	local train_air_drag = air_drag + 3 * air_drag * (1 + num_wagons) / 20; // assumes 1 unit for multihead

//	AILog.Info("engine = " + AIEngine.GetName(engine));
//	AILog.Info("wagon = " + AIEngine.GetName(wagon));
//	AILog.Info("railtype = " + AIRail.GetName(railtype));
//	AILog.Info("engine_max_speed = " + engine_max_speed);
//	AILog.Info("wagon_max_speed = " + wagon_max_speed);
//	AILog.Info("railtype_max_speed = " + railtype_max_speed);
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

//	local engine_max_age = AIEngine.GetMaxAge(engine);
//	local engine_price = ::caches.GetCostWithRefit(engine, cargo);
//	local wagon_price = ::caches.GetCostWithRefit(wagon, cargo);
//	local train_price = engine_price + wagon_price * num_wagons;
	local engine_reliability = AIEngine.GetReliability(engine);
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
//	local income = (train_capacity * AICargo.GetCargoIncome(cargo, distance_advanced / 16, days_in_transit) - train_running_cost * days_in_transit / 365 - days_in_transit * train_price / engine_max_age);
//	local income = (train_capacity * AICargo.GetCargoIncome(cargo, distance_advanced / 16, days_in_transit) * 365 * engine_max_age - train_running_cost * days_in_transit * engine_max_age - days_in_transit * train_price * 365) / (365 * engine_max_age);

//	AILog.Info("engine = " + AIEngine.GetName(engine) + "; wagon = " + AIEngine.GetName(wagon) + " * " + num_wagons + "; days_in_transit = " + days_in_transit + "; distance_advanced = " + distance_advanced / 16 + "; income = " + income);
//	AILog.Info("train_max_speed = " + train_max_speed + "; capacity = " + train_capacity + "; running cost = " + (train_running_cost * days_in_transit / 366) + "; train_price = " + (days_in_transit * train_price / engine_max_age) + "; engine_max_age = " + engine_max_age);

//	AIController.Break(" ");
//	return [income, distance_advanced / 16, num_wagons, train_capacity, best_railtypes];

	/* Simplified method for estimated income. */
	local multiplier = engine_reliability;
	local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
	switch (breakdowns) {
		case 0:
			multiplier = 100;
			break;
		case 1:
			multiplier = engine_reliability + (100 - engine_reliability) / 2;
			break;
		case 2:
		default:
			multiplier = engine_reliability;
			break;
	}
	local distance_advanced = (train_max_speed * 2 * 74 * days_in_transit) / (256 * 16);
	days_in_transit = days_in_transit + RailRoute.STATION_LOADING_INTERVAL;
	local income = ((train_capacity * AICargo.GetCargoIncome(cargo, distance_advanced, days_in_transit) - train_running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
	return [income, distance_advanced, num_wagons, train_capacity, best_railtypes];
}

// function LuDiAIAfterFix::CheckVehicleBreakdown(cur_speed, reliability, breakdown_ctr, breakdown_chance, breakdown_delay) {
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

// function LuDiAIAfterFix::HandleBreakdown(breakdown_ctr, cur_speed, tick_counter, breakdown_delay) {
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

// function LuDiAIAfterFix::TrainTick(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress) {
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

// function LuDiAIAfterFix::TrainLocoHandler(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, tick_counter, breakdown_ctr, breakdown_delay, sub_speed, cur_speed, progress) {
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

// function LuDiAIAfterFix::UpdateSpeed(train_max_speed, train_cargo_weight, engine_power, train_air_drag, engine_cargo_max_tractive_effort_N, sub_speed, cur_speed, progress) {
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
// 		assert(false);
// 	}
// }

// function LuDiAIAfterFix::DoUpdateSpeed(accel, min_speed, max_speed, sub_speed, cur_speed, progress) {
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

// function LuDiAIAfterFix::GetAcceleration(cur_speed, train_cargo_weight, train_power_watts, train_air_drag, engine_cargo_max_tractive_effort_N) {
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

function LuDiAIAfterFix::ResetRailManagementVariables() {
	if (lastRailManagedArray < 0) lastRailManagedArray = railRouteManager.m_townRouteArray.len() - 1;
	if (lastRailManagedManagement < 0) lastRailManagedManagement = 7;
}

function LuDiAIAfterFix::InterruptRailManagement(cur_date) {
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (lastRailManagedArray == -1) lastRailManagedManagement--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageTrainRoutes() {
	local max_trains = AIGameSettings.GetValue("max_trains");
	if (max_trains != MAX_TRAIN_VEHICLES) {
		MAX_TRAIN_VEHICLES = max_trains;
		AILog.Info("MAX_TRAIN_VEHICLES = " + MAX_TRAIN_VEHICLES);
	}

	local cur_date = AIDate.GetCurrentDate();
	ResetRailManagementVariables();

//	for (local i = lastRailManagedArray; i >= 0; --i) {
//		if (lastRailManagedManagement != 8) break;
//		lastRailManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(railRouteManager.m_townRouteArray[i].m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(railRouteManager.m_townRouteArray[i].m_stationTo)));
//		if (InterruptRailManagement(cur_date)) return;
//	}
//	ResetRailManagementVariables();
//	if (lastRailManagedManagement == 8) lastRailManagedManagement--;
//
//	local start_tick = AIController.GetTick();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 7) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		railRouteManager.m_townRouteArray[i].RenewVehicles();
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 7) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 6) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		railRouteManager.m_townRouteArray[i].SendNegativeProfitVehiclesToDepot();
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 6) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = railRouteManager.GetTrainCount();
	local maxAllRoutesProfit = railRouteManager.HighestProfitLastYear();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 5) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (MAX_TRAIN_VEHICLES * 0.95 < num_vehs) {
			railRouteManager.m_townRouteArray[i].SendLowProfitVehiclesToDepot(maxAllRoutesProfit);
		}
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 5) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 4) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". UpdateEngineWagonPair");
		railRouteManager.m_townRouteArray[i].UpdateEngineWagonPair();
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 4) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 3) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		railRouteManager.m_townRouteArray[i].SellVehiclesInDepot();
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 3) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 2) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeBridges")
		railRouteManager.m_townRouteArray[i].UpgradeBridges();
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 2) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = railRouteManager.GetTrainCount();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 1) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < MAX_TRAIN_VEHICLES) {
			num_vehs += railRouteManager.m_townRouteArray[i].AddRemoveVehicleToRoute(num_vehs < MAX_TRAIN_VEHICLES);
		}
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 1) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRailManagedArray; i >= 0; --i) {
		if (lastRailManagedManagement != 0) break;
		lastRailManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local cityFrom = railRouteManager.m_townRouteArray[i].m_cityFrom;
		local cityTo = railRouteManager.m_townRouteArray[i].m_cityTo;
		local cargoC = railRouteManager.m_townRouteArray[i].m_cargoClass;
		if (railRouteManager.m_townRouteArray[i].RemoveIfUnserviced()) {
			railRouteManager.m_townRouteArray.remove(i);
			railTownManager.RemoveUsedCityPair(cityFrom, cityTo, cargoC, true);
		}
		if (InterruptRailManagement(cur_date)) return;
	}
	ResetRailManagementVariables();
	if (lastRailManagedManagement == 0) lastRailManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + railRouteManager.m_townRouteArray.len() + " rail route" + (railRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}

function LuDiAIAfterFix::CheckForUnfinishedRailRoute() {
	if (railBuildManager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered rail station or depot tiles during save */
		local stationFrom = railBuildManager.m_stationFrom;
		local stationTo = railBuildManager.m_stationTo;
		local depotFrom = railBuildManager.m_depotFrom;
		local depotTo = railBuildManager.m_depotTo;
		local stationType = AIStation.STATION_TRAIN;
		local stationFromDir = railBuildManager.m_stationFromDir;
		local stationToDir = railBuildManager.m_stationToDir;

		if (stationFrom == -1 || stationTo == -1) {
			local stationList = AIStationList(stationType);
			local allStationsTiles = AITileList();
			for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
				local stationTiles = AITileList_StationType(st, stationType);
				stationTiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
				local top_tile = stationTiles.Begin();
				allStationsTiles.AddTile(top_tile);
			}
//			AILog.Info("allStationsTiles has " + allStationsTiles.Count() + " tiles");
			local allTilesFound = AITileList();
			if (stationFrom != -1) allTilesFound.AddTile(stationFrom);
			for (local tile = allStationsTiles.Begin(); !allStationsTiles.IsEnd(); tile = allStationsTiles.Next()) {
				local found = false;
				foreach (id, i in scheduledRemovalsTable.Train) {
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
//					AILog.Info("scheduledRemovalsTable.Train has tile " + tile);
					allTilesFound.AddTile(tile);
				}
				for (local i = railRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
					if (railRouteManager.m_townRouteArray[i].m_stationFrom == tile || railRouteManager.m_townRouteArray[i].m_stationTo == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						local stationTiles = AITileList_StationType(AIStation.GetStationID(tile), stationType);
						stationTiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
						local top_tile = stationTiles.Begin();
						allTilesFound.AddTile(top_tile);
						break;
					}
				}
			}

			if (allTilesFound.Count() != allStationsTiles.Count()) {
//				AILog.Info(allTilesFound.Count() + " != " + allStationsTiles.Count());
				local allTilesMissing = AITileList();
				allTilesMissing.AddList(allStationsTiles);
				allTilesMissing.RemoveList(allTilesFound);
				for (local tile = allTilesMissing.Begin(); !allTilesMissing.IsEnd(); tile = allTilesMissing.Next()) {
//					AILog.Info("Tile " + tile + " is missing");
					local station = RailStation.CreateFromTile(tile);
					RailRoute.ScheduleRemoveStation(station.m_tile, station.m_dir);
				}
			}
		}

		if (depotFrom == -1 || depotTo == -1) {
			local allDepotsTiles = AIDepotList(AITile.TRANSPORT_RAIL);
//			AILog.Info("allDepotsTiles has " + allDepotsTiles.Count() + " tiles");
			local allTilesFound = AITileList();
			if (depotFrom != -1) allTilesFound.AddTile(depotFrom);
			for (local tile = allDepotsTiles.Begin(); !allDepotsTiles.IsEnd(); tile = allDepotsTiles.Next()) {
				local found = false;
				foreach (id, i in scheduledRemovalsTable.Train) {
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
//					AILog.Info("scheduledRemovalsTable.Train has tile " + tile);
					allTilesFound.AddTile(tile);
				}
				for (local i = railRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
					if (railRouteManager.m_townRouteArray[i].m_depotFrom == tile || railRouteManager.m_townRouteArray[i].m_depotTo == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						allTilesFound.AddTile(tile);
						break;
					}
				}
			}

			if (allTilesFound.Count() != allDepotsTiles.Count()) {
//				AILog.Info(allTilesFound.Count() + " != " + allDepotsTiles.Count());
				local allTilesMissing = AITileList();
				allTilesMissing.AddList(allDepotsTiles);
				allTilesMissing.RemoveList(allTilesFound);
				for (local tile = allTilesMissing.Begin(); !allTilesMissing.IsEnd(); tile = allTilesMissing.Next()) {
					if (tile == ::caches._depot_tile) continue; // skip this one
//					AILog.Info("Tile " + tile + " is missing");
					RailRoute.ScheduleRemoveDepot(tile);
				}
			}
		}
	}
}
