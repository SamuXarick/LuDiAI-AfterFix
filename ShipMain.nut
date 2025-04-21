function LuDiAIAfterFix::BuildWaterRoute()
{
	if (!AIController.GetSetting("water_support")) return;

	local unfinished = ship_build_manager.HasUnfinishedRoute();
	if (unfinished || (ship_route_manager.GetShipCount() < max(AIGameSettings.GetValue("max_ships") - 10, 10)) && ((allRoutesBuilt >> 2) & 3) != 3) {
		local city_from = null;
		local city_to = null;
		local cheaper_route = false;
		local cargo_class = ship_route_manager.m_cargo_class;
		if (!unfinished) {
			ship_route_manager.SwapCargoClass();

			local cargo_type = Utils.GetCargoType(cargo_class);
			local tempList = AIEngineList(AIVehicle.VT_WATER);
			local engineList = AIList();
			for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
				if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo_type)) {
					engineList.AddItem(engine, AIEngine.GetPrice(engine));
				}
			}

			if (engineList.IsEmpty()) {
				return;
			}

			engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

			local bestengineinfo = WrightAI().GetBestEngineIncome(engineList, cargo_type, ShipRoute.COUNT_INTERVAL, false);
			local max_distance = (WATER_DAYS_IN_TRANSIT * 2 * 74 * AIEngine.GetMaxSpeed(bestengineinfo[0])) / (256 * 16);
			local min_distance = max(20, max_distance * 2 / 3);
//			AILog.Info("bestengineinfo: best_engine = " + AIEngine.GetName(bestengineinfo[0]) + "; best_distance = " + bestengineinfo[1] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

			local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
			local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
			local max_dist = min_dist + MAX_DISTANCE_INCREASE > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//			AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

			local estimated_costs = 0;
			local engine_costs = AIEngine.GetPrice(engineList.Begin());
			local canal_costs = AIMarine.GetBuildCost(AIMarine.BT_CANAL) * 2 * max_dist;
			local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
			local dock_costs = AIMarine.GetBuildCost(AIMarine.BT_DOCK) * 2;
			local depot_cost = AIMarine.GetBuildCost(AIMarine.BT_DEPOT);
			estimated_costs += engine_costs + canal_costs + clear_costs + dock_costs + depot_cost;
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", canal_costs = " + canal_costs + ", clear_costs = " + clear_costs + ", dock_costs = " + dock_costs + ", depot_cost = " + depot_cost);
			if (!Utils.HasMoney(estimated_costs + reservedMoney - reservedMoneyWater)) {
				/* Try a cheaper route */
				if ((((bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 1 || !Utils.HasMoney(estimated_costs - canal_costs - clear_costs + reservedMoney - reservedMoneyWater)) {
					return;
				} else {
					cheaper_route = true;
					reservedMoneyWater = estimated_costs - canal_costs - clear_costs;
					reservedMoney += reservedMoneyWater;
				}
			} else {
				reservedMoneyWater = estimated_costs;
				reservedMoney += reservedMoneyWater;
			}

			if (city_from == null) {
				city_from = shipTownManager.GetUnusedCity(((((bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						shipTownManager.m_used_cities_list[cargo_class].Clear();
					} else {
						if ((((bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							bestRoutesBuilt = bestRoutesBuilt | (1 << (2 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
							shipTownManager.m_used_cities_list[cargo_class].Clear();
//							shipTownManager.m_near_city_pair_array[cargo_class].clear();
							AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " water routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
						} else {
//							shipTownManager.m_near_city_pair_array[cargo_class].clear();
							if ((((allRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " water routes have been used!");
							}
							allRoutesBuilt = allRoutesBuilt | (1 << (2 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
						}
					}
				}
			}

			if (city_from != null) {
//				AILog.Info("s:New city found: " + AITown.GetName(city_from));

				shipTownManager.FindNearCities(city_from, min_dist, max_dist, ((((bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);

				if (!shipTownManager.m_near_city_pair_array[cargo_class].len()) {
					AILog.Info("No near city available");
					city_from = null;
				}
			}

			if (city_from != null) {
				for (local i = 0; i < shipTownManager.m_near_city_pair_array[cargo_class].len(); ++i) {
					if (city_from == shipTownManager.m_near_city_pair_array[cargo_class][i][0]) {
						if (!ship_route_manager.TownRouteExists(city_from, shipTownManager.m_near_city_pair_array[cargo_class][i][1], cargo_class)) {
							city_to = shipTownManager.m_near_city_pair_array[cargo_class][i][1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && ship_route_manager.HasMaxStationCount(city_from, city_to, cargo_class)) {
//								AILog.Info("ship_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + ship_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
								city_to = null;
								continue;
							} else {
//								AILog.Info("ship_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + ship_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
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
				reservedMoney -=reservedMoneyWater;
				reservedMoneyWater = 0;
			}
		} else {
			if (!Utils.HasMoney(reservedMoneyWater)) {
				return;
			}
		}

		if (unfinished || city_from != null && city_to != null) {
			if (!unfinished) {
				AILog.Info("s:New city found: " + AITown.GetName(city_from));
				AILog.Info("s:New near city found: " + AITown.GetName(city_to));
			}

			if (!unfinished) buildTimerWater = 0;
			city_from = unfinished ? ship_build_manager.m_city_from : city_from;
			city_to = unfinished ? ship_build_manager.m_city_to : city_to;
			cargo_class = unfinished ? ship_build_manager.m_cargo_class : cargo_class;
			local cheaper = unfinished ? ship_build_manager.m_cheaper_route : cheaper_route;
			local best_routes = unfinished ? ship_build_manager.m_best_routes_built : ((((bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

			local start_date = AIDate.GetCurrentDate();
			local routeResult = ship_route_manager.BuildRoute(ship_build_manager, city_from, city_to, cargo_class, cheaper, best_routes);
			buildTimerWater += AIDate.GetCurrentDate() - start_date;
			if (routeResult[0] != null) {
				if (routeResult[0] != 0) {
					reservedMoney -= reservedMoneyWater;
					reservedMoneyWater = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + " water route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerWater + " day" + (buildTimerWater != 1 ? "s" : "") + ".");
				}
			} else {
				reservedMoney -= reservedMoneyWater;
				reservedMoneyWater = 0;
				shipTownManager.ResetCityPair(city_from, city_to, cargo_class, false);
				AILog.Error("s:" + buildTimerWater + " day" + (buildTimerWater != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::ResetWaterManagementVariables()
{
	if (lastWaterManagedArray < 0) lastWaterManagedArray = ship_route_manager.m_town_route_array.len() - 1;
	if (lastWaterManagedManagement < 0) lastWaterManagedManagement = 6;
}

function LuDiAIAfterFix::InterruptWaterManagement(cur_date)
{
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (lastWaterManagedArray == -1) lastWaterManagedManagement--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageShipRoutes()
{
	local max_ships = AIGameSettings.GetValue("max_ships");

	local cur_date = AIDate.GetCurrentDate();
	ResetWaterManagementVariables();

//	for (local i = lastWaterManagedArray; i >= 0; --i) {
//		if (lastWaterManagedManagement != 7) break;
//		lastWaterManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(ship_route_manager.m_town_route_array[i].m_dock_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(ship_route_manager.m_town_route_array[i].m_dock_to)));
//		if (InterruptWaterManagement(cur_date)) return;
//	}
//	ResetWaterManagementVariables();
//	if (lastWaterManagedManagement == 7) lastWaterManagedManagement--;
//
//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 6) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		ship_route_manager.m_town_route_array[i].RenewVehicles();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 6) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 5) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		ship_route_manager.m_town_route_array[i].SendNegativeProfitVehiclesToDepot();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 5) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = ship_route_manager.GetShipCount();
	local max_all_routes_profit = ship_route_manager.HighestProfitLastYear();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 4) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (max_ships * 0.95 < num_vehs) {
			ship_route_manager.m_town_route_array[i].SendLowProfitVehiclesToDepot(max_all_routes_profit);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 4) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 3) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeEngine");
		ship_route_manager.m_town_route_array[i].UpgradeEngine();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 3) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 2) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		ship_route_manager.m_town_route_array[i].SellVehiclesInDepot();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 2) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = ship_route_manager.GetShipCount();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 1) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < max_ships) {
			num_vehs += ship_route_manager.m_town_route_array[i].AddRemoveVehicleToRoute(num_vehs < max_ships);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 1) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 0) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local city_from = ship_route_manager.m_town_route_array[i].m_city_from;
		local city_to = ship_route_manager.m_town_route_array[i].m_city_to;
		local cargo_class = ship_route_manager.m_town_route_array[i].m_cargo_class;
		if (ship_route_manager.m_town_route_array[i].RemoveIfUnserviced()) {
			ship_route_manager.m_town_route_array.remove(i);
			shipTownManager.ResetCityPair(city_from, city_to, cargo_class, true);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 0) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}

function LuDiAIAfterFix::CheckForUnfinishedWaterRoute()
{
	if (ship_build_manager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered dock or ship depot tiles during save */
		local dockFrom = ship_build_manager.m_dock_from;
		local dockTo = ship_build_manager.m_dock_to;
		local depot_tile = ship_build_manager.m_depot_tile;
		local station_type = AIStation.STATION_DOCK;

		if (dockFrom == -1 || dockTo == -1) {
			local station_list = AIStationList(station_type);
			local all_station_tiles = AITileList();
			for (local station_id = station_list.Begin(); !station_list.IsEnd(); station_id = station_list.Next()) {
				local station_tiles = AITileList_StationType(station_id, station_type);
				all_station_tiles.AddList(station_tiles);
			}
//			AILog.Info("all_station_tiles has " + all_station_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			if (dockFrom != -1) all_tiles_found.AddTile(dockFrom);
			for (local tile = all_station_tiles.Begin(); !all_station_tiles.IsEnd(); tile = all_station_tiles.Next()) {
				if (::scheduled_removals_table.Ship.rawin(tile)) {
//					AILog.Info("scheduled_removals_table.Ship has tile " + tile);
					all_tiles_found.AddTile(tile);
					break;
				}
				for (local i = ship_route_manager.m_town_route_array.len() - 1; i >= 0; --i) {
					if (ship_route_manager.m_town_route_array[i].m_dock_from == tile || ship_route_manager.m_town_route_array[i].m_dock_to == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), station_type);
						all_tiles_found.AddList(station_tiles);
						break;
					}
				}
			}

			if (all_tiles_found.Count() != all_station_tiles.Count()) {
//				AILog.Info(all_tiles_found.Count() + " != " + all_station_tiles.Count());
				local all_tiles_missing = AITileList();
				all_tiles_missing.AddList(all_station_tiles);
				all_tiles_missing.RemoveList(all_tiles_found);
				for (local tile = all_tiles_missing.Begin(); !all_tiles_missing.IsEnd(); tile = all_tiles_missing.Next()) {
					if (AIMarine.IsDockTile(tile) && AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
//						AILog.Info("Tile " + tile + " is missing");
						::scheduled_removals_table.Ship.rawset(tile, 0);
					}
				}
			}
		}

		if (depot_tile == -1) {
			local all_depots_tiles = AIDepotList(AITile.TRANSPORT_WATER);
//			AILog.Info("all_depots_tiles has " + all_depots_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			for (local tile = all_depots_tiles.Begin(); !all_depots_tiles.IsEnd(); tile = all_depots_tiles.Next()) {
				if (::scheduled_removals_table.Ship.rawin(tile)) {
//					AILog.Info("scheduled_removals_table.Ship has tile " + tile);
					all_tiles_found.AddTile(tile);
					break;
				}
				for (local i = ship_route_manager.m_town_route_array.len() - 1; i >= 0; --i) {
					if (ship_route_manager.m_town_route_array[i].m_depot_tile == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
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
				for (local tile = all_tiles_missing.Begin(); !all_tiles_missing.IsEnd(); tile = all_tiles_missing.Next()) {
//					AILog.Info("Tile " + tile + " is missing");
					::scheduled_removals_table.Ship.rawset(tile, 0);
				}
			}
		}
	}
}
