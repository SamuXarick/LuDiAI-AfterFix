function LuDiAIAfterFix::BuildRoadRoute()
{
	if (!AIController.GetSetting("road_support")) return;

	local unfinished = this.roadBuildManager.HasUnfinishedRoute();
	if (unfinished || (this.roadRouteManager.GetRoadVehicleCount() < max(MAX_ROAD_VEHICLES - 10, 10)) && ((this.allRoutesBuilt >> 0) & 3) != 3) {
		local city_from = null;
		local city_to = null;
		local articulated = true;
		local cargo_class = AIController.GetSetting("select_town_cargo") != 2 ? this.cargoClassRoad : (!unfinished ? this.cargoClassRoad : (this.cargoClassRoad == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
		if (!unfinished) {
			this.cargoClassRoad = AIController.GetSetting("select_town_cargo") != 2 ? this.cargoClassRoad : (cargo_class == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

			local cargo_type = Utils.GetCargoType(cargo_class);
			local engine_list = AIEngineList(AIVehicle.VT_ROAD);
			foreach (engine_id, _ in engine_list) {
				if (!AIEngine.IsValidEngine(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.IsBuildable(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (AIEngine.GetRoadType(engine_id) != AIRoad.ROADTYPE_ROAD) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.CanRefitCargo(engine_id, cargo_type)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.IsArticulated(engine_id)) {
					articulated = false;
				}
				engine_list[engine_id] = AIEngine.GetPrice(engine_id);
			}

			if (engine_list.IsEmpty()) {
//				this.cargoClassRoad = cargo_class;
				return;
			}

//			engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

			local best_engine_info = WrightAI().GetBestEngineIncome(engine_list, cargo_type, RoadRoute.START_VEHICLE_COUNT, false);
			local max_distance = (ROAD_DAYS_IN_TRANSIT * 2 * 3 * 74 * AIEngine.GetMaxSpeed(best_engine_info[0]) / 4) / (192 * 16);
			local min_distance = max(20, max_distance * 2 / 3);
//			AILog.Info("best_engine_info: best_engine = " + AIEngine.GetName(best_engine_info[0]) + "; best_distance = " + best_engine_info[1] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

			local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
			local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
			local max_dist = min_dist + MAX_DISTANCE_INCREASE > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//			AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

			local estimated_costs = 0;
			local engine_costs = (AIEngine.GetPrice(engine_list.Begin()) + 500) * (cargo_class == AICargo.CC_PASSENGERS ? RoadRoute.START_VEHICLE_COUNT : RoadRoute.MIN_VEHICLE_START_COUNT);
			local road_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_ROAD) * 2 * max_dist;
			local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
			local station_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, cargo_class == AICargo.CC_PASSENGERS ? AIRoad.BT_BUS_STOP : AIRoad.BT_TRUCK_STOP) * 2;
			local depot_cost = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_DEPOT);
			estimated_costs += engine_costs + road_costs + clear_costs + station_costs + depot_cost;
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", road_costs = " + road_costs + ", clear_costs = " + clear_costs + ", station_costs = " + station_costs + ", depot_cost = " + depot_cost);
			if (!Utils.HasMoney(estimated_costs + this.reservedMoney - this.reservedMoneyRoad)) {
//				this.cargoClassRoad = cargo_class;
				return;
			} else {
				this.reservedMoneyRoad = estimated_costs;
				this.reservedMoney += this.reservedMoneyRoad;
			}

			if (city_from == null) {
				city_from = this.roadTownManager.GetUnusedCity(((((this.bestRoutesBuilt >> 0) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						this.roadTownManager.m_used_cities_list[cargo_class].Clear();
					} else if ((((this.bestRoutesBuilt >> 0) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
						this.bestRoutesBuilt = this.bestRoutesBuilt | (1 << (0 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
						this.roadTownManager.m_used_cities_list[cargo_class].Clear();
//						this.roadTownManager.m_near_city_pair_array[cargo_class].clear();
						AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " road routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
					} else {
//						this.roadTownManager.m_near_city_pair_array[cargo_class].clear();
						if ((((this.allRoutesBuilt >> 0) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " road routes have been used!");
						}
						this.allRoutesBuilt = this.allRoutesBuilt | (1 << (0 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
					}
				}
			}

			if (city_from != null) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));

				this.roadTownManager.FindNearCities(city_from, min_dist, max_dist, ((((this.bestRoutesBuilt >> 0) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);

				if (!this.roadTownManager.m_near_city_pair_array[cargo_class].len()) {
					AILog.Info("No near city available");
					city_from = null;
				}
			}

			if (city_from != null) {
				foreach (near_city_pair in this.roadTownManager.m_near_city_pair_array[cargo_class]) {
					if (city_from == near_city_pair[0]) {
						if (!this.roadRouteManager.TownRouteExists(city_from, near_city_pair[1], cargo_class)) {
							city_to = near_city_pair[1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((this.allRoutesBuilt >> 0) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && this.roadRouteManager.HasMaxStationCount(city_from, city_to, cargo_class)) {
//								AILog.Info("this.roadRouteManager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.roadRouteManager.HasMaxStationCount(city_from, city_to, cargo_class));
								city_to = null;
								continue;
							} else {
//								AILog.Info("this.roadRouteManager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.roadRouteManager.HasMaxStationCount(city_from, city_to, cargo_class));
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
				this.reservedMoney -= this.reservedMoneyRoad;
				this.reservedMoneyRoad = 0;
			}
		} else {
			if (!Utils.HasMoney(this.reservedMoneyRoad)) {
				return;
			}
		}

		if (unfinished || city_from != null && city_to != null) {
			if (!unfinished) {
				AILog.Info("r:New city found: " + AITown.GetName(city_from));
				AILog.Info("r:New near city found: " + AITown.GetName(city_to));
			}

			if (!unfinished) this.buildTimerRoad = 0;
			local arg_city_from = unfinished ? this.roadBuildManager.m_city_from : city_from;
			local arg_city_to = unfinished ? this.roadBuildManager.m_city_to : city_to;
			local arg_cargo_class = unfinished ? this.roadBuildManager.m_cargo_class : cargo_class;
			local arg_articulated = unfinished ? this.roadBuildManager.m_articulated : articulated;
			local arg_best_routes_built = unfinished ? this.roadBuildManager.m_best_routes_built : ((((this.bestRoutesBuilt >> 0) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

			local start_date = AIDate.GetCurrentDate();
			local route_result = this.roadRouteManager.BuildRoute(this.roadBuildManager, arg_city_from, arg_city_to, arg_cargo_class, arg_articulated, arg_best_routes_built);
			this.buildTimerRoad += AIDate.GetCurrentDate() - start_date;
			if (route_result[0] != null) {
				if (route_result[0] != 0) {
					this.reservedMoney -= this.reservedMoneyRoad;
					this.reservedMoneyRoad = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(arg_cargo_class)) + " road route between " + AIBaseStation.GetName(AIStation.GetStationID(route_result[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(route_result[2])) + " in " + this.buildTimerRoad + " day" + (this.buildTimerRoad != 1 ? "s" : "") + ".");
				}
			} else {
				this.reservedMoney -= this.reservedMoneyRoad;
				this.reservedMoneyRoad = 0;
				this.roadTownManager.ResetCityPair(arg_city_from, arg_city_to, cargo_class, false);
				AILog.Error("r:" + this.buildTimerRoad + " day" + (this.buildTimerRoad != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::ResetRoadManagementVariables()
{
	if (this.lastRoadManagedArray < 0) this.lastRoadManagedArray = this.roadRouteManager.m_townRouteArray.len() - 1;
	if (this.lastRoadManagedManagement < 0) this.lastRoadManagedManagement = 8;
}

function LuDiAIAfterFix::InterruptRoadManagement(cur_date)
{
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (this.lastRoadManagedArray == -1) this.lastRoadManagedManagement--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageRoadvehRoutes()
{
	local max_roadveh = AIGameSettings.GetValue("max_roadveh");
	if (max_roadveh != MAX_ROAD_VEHICLES) {
		MAX_ROAD_VEHICLES = max_roadveh;
		AILog.Info("MAX_ROAD_VEHICLES = " + MAX_ROAD_VEHICLES);
	}

	local cur_date = AIDate.GetCurrentDate();
	this.ResetRoadManagementVariables();

//	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
//		if (this.lastRoadManagedManagement != 9) break;
//		this.lastRoadManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(this.roadRouteManager.m_townRouteArray[i].m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.roadRouteManager.m_townRouteArray[i].m_stationTo)));
//		if (this.InterruptRoadManagement(cur_date)) return;
//	}
//	this.ResetRoadManagementVariables();
//	if (this.lastRoadManagedManagement == 9) this.lastRoadManagedManagement--;
//
//	local start_tick = AIController.GetTick();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 8) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		this.roadRouteManager.m_townRouteArray[i].RenewVehicles();
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 8) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 7) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		this.roadRouteManager.m_townRouteArray[i].SendNegativeProfitVehiclesToDepot();
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 7) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = this.roadRouteManager.GetRoadVehicleCount();
	local max_all_routes_profit = this.roadRouteManager.HighestProfitLastYear();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 6) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (MAX_ROAD_VEHICLES * 0.95 < num_vehs) {
			this.roadRouteManager.m_townRouteArray[i].SendLowProfitVehiclesToDepot(max_all_routes_profit);
		}
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 6) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 5) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeEngine");
		this.roadRouteManager.m_townRouteArray[i].UpgradeEngine();
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 5) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 4) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		this.roadRouteManager.m_townRouteArray[i].SellVehiclesInDepot();
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 4) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 3) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeBridges")
		this.roadRouteManager.m_townRouteArray[i].UpgradeBridges();
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 3) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = this.roadRouteManager.GetRoadVehicleCount();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 2) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < MAX_ROAD_VEHICLES) {
			num_vehs += this.roadRouteManager.m_townRouteArray[i].AddRemoveVehicleToRoute(num_vehs < MAX_ROAD_VEHICLES);
		}
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 2) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = this.roadRouteManager.GetRoadVehicleCount();
	if (AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations")) {
		for (local i = this.lastRoadManagedArray; i >= 0; --i) {
			if (this.lastRoadManagedManagement != 1) break;
			this.lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". ExpandRoadStation");
			if (MAX_ROAD_VEHICLES > num_vehs) {
				this.roadRouteManager.m_townRouteArray[i].ExpandRoadStation();
			}
			if (this.InterruptRoadManagement(cur_date)) return;
		}
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 1) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastRoadManagedArray; i >= 0; --i) {
		if (this.lastRoadManagedManagement != 0) break;
		this.lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local arg_city_from = this.roadRouteManager.m_townRouteArray[i].m_city_from;
		local arg_city_to = this.roadRouteManager.m_townRouteArray[i].m_city_to;
		local arg_cargo_class = this.roadRouteManager.m_townRouteArray[i].m_cargo_class;
		if (this.roadRouteManager.m_townRouteArray[i].RemoveIfUnserviced()) {
			this.roadRouteManager.m_townRouteArray.remove(i);
			this.roadTownManager.ResetCityPair(arg_city_from, arg_city_to, arg_cargo_class, true);
		}
		if (this.InterruptRoadManagement(cur_date)) return;
	}
	this.ResetRoadManagementVariables();
	if (this.lastRoadManagedManagement == 0) this.lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.roadRouteManager.m_townRouteArray.len() + " road route" + (this.roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}

function LuDiAIAfterFix::CheckForUnfinishedRoadRoute()
{
	if (this.roadBuildManager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered road station or depot tiles during save */
		local arg_station_from = this.roadBuildManager.m_stationFrom;
		local arg_station_to = this.roadBuildManager.m_stationTo;
		local arg_depot_tile = this.roadBuildManager.m_depotTile;
		local arg_station_type = this.roadBuildManager.m_cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;

		if (arg_station_from == -1 || arg_station_to == -1) {
			local station_list = AIStationList(arg_station_type);
			local all_stations_tiles = AITileList();
			foreach (station_id, _ in station_list) {
				local station_tiles = AITileList_StationType(station_id, arg_station_type);
				all_stations_tiles.AddList(station_tiles);
			}
//			AILog.Info("all_stations_tiles has " + all_stations_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			if (arg_station_from != -1) {
				all_tiles_found.AddTile(arg_station_from);
			}
			foreach (tile, _ in all_stations_tiles) {
				if (scheduledRemovalsTable.Road.rawin(tile)) {
//					AILog.Info("scheduledRemovalsTable.Road has tile " + tile);
					all_tiles_found[tile] = 0;
					break;
				}
				foreach (route in this.roadRouteManager.m_townRouteArray) {
					if (route.m_stationFrom == tile || route.m_stationTo == tile) {
						local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), arg_station_type);
						all_tiles_found.AddList(station_tiles);
						break;
					}
				}
			}

			if (all_tiles_found.Count() != all_stations_tiles.Count()) {
//				AILog.Info(all_tiles_found.Count() + " != " + all_stations_tiles.Count());
				local all_tiles_missing = AITileList();
				all_tiles_missing.AddList(all_stations_tiles);
				all_tiles_missing.RemoveList(all_tiles_found);
				foreach (tile, _ in all_tiles_missing) {
//					AILog.Info("Tile " + tile + " is missing");
					scheduledRemovalsTable.Road.rawset(tile, 0);
				}
			}
		}

		if (arg_depot_tile == -1) {
			local all_depots_tiles = AIDepotList(AITile.TRANSPORT_ROAD);
//			AILog.Info("all_depots_tiles has " + all_depots_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			foreach (tile, _ in all_depots_tiles) {
				if (scheduledRemovalsTable.Road.HasItem(tile)) {
//					AILog.Info("scheduledRemovalsTable.Road has tile " + tile);
					all_tiles_found[tile] = 0;
					break;
				}
				foreach (route in this.roadRouteManager.m_townRouteArray) {
					if (route.m_depotTile == tile) {
						all_tiles_found.AddTile(tile);
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
					scheduledRemovalsTable.Road.rawset(tile, 0);
				}
			}
		}
	}
}
