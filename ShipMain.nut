function LuDiAIAfterFix::BuildWaterRoute()
{
	if (!AIController.GetSetting("water_support")) return;

	local unfinished = ship_build_manager.HasUnfinishedRoute();
	if (unfinished || (ship_route_manager.GetShipCount() < max(AIGameSettings.GetValue("max_ships") - 10, 10)) && ((all_routes_built >> 2) & 3) != 3) {
		local city_from = null;
		local city_to = null;
		local cheaper_route = false;
		local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargo_class_water : (!unfinished ? cargo_class_water : (cargo_class_water == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
		if (!unfinished) {
			cargo_class_water = AIController.GetSetting("select_town_cargo") != 2 ? cargo_class_water : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

			local cargo_type = Utils.GetCargoType(cC);
			local tempList = AIEngineList(AIVehicle.VT_WATER);
			local engineList = AIList();
			for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
				if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo_type)) {
					engineList.AddItem(engine, AIEngine.GetPrice(engine));
				}
			}

			if (engineList.IsEmpty()) {
//				cargo_class_water = cC;
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
			if (!Utils.HasMoney(estimated_costs + reserved_money - reserved_money_water)) {
				/* Try a cheaper route */
				if ((((best_routes_built >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 1 || !Utils.HasMoney(estimated_costs - canal_costs - clear_costs + reserved_money - reserved_money_water)) {
//					cargo_class_water = cC;
					return;
				} else {
					cheaper_route = true;
					reserved_money_water = estimated_costs - canal_costs - clear_costs;
					reserved_money += reserved_money_water;
				}
			} else {
				reserved_money_water = estimated_costs;
				reserved_money += reserved_money_water;
			}

			if (city_from == null) {
				city_from = ship_town_manager.GetUnusedCity(((((best_routes_built >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						ship_town_manager.m_used_cities_list[cC].Clear();
					} else {
						if ((((best_routes_built >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							best_routes_built = best_routes_built | (1 << (2 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							ship_town_manager.m_used_cities_list[cC].Clear();
//							ship_town_manager.m_near_city_pair_array[cC].clear();
							AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " water routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
						} else {
//							ship_town_manager.m_near_city_pair_array[cC].clear();
							if ((((all_routes_built >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " water routes have been used!");
							}
							all_routes_built = all_routes_built | (1 << (2 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
						}
					}
				}
			}

			if (city_from != null) {
//				AILog.Info("s:New city found: " + AITown.GetName(city_from));

				ship_town_manager.FindNearCities(city_from, min_dist, max_dist, ((((best_routes_built >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);

				if (!ship_town_manager.m_near_city_pair_array[cC].len()) {
					AILog.Info("No near city available");
					city_from = null;
				}
			}

			if (city_from != null) {
				for (local i = 0; i < ship_town_manager.m_near_city_pair_array[cC].len(); ++i) {
					if (city_from == ship_town_manager.m_near_city_pair_array[cC][i][0]) {
						if (!ship_route_manager.TownRouteExists(city_from, ship_town_manager.m_near_city_pair_array[cC][i][1], cC)) {
							city_to = ship_town_manager.m_near_city_pair_array[cC][i][1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((all_routes_built >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && ship_route_manager.HasMaxStationCount(city_from, city_to, cC)) {
//								AILog.Info("ship_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cC + ") == " + ship_route_manager.HasMaxStationCount(city_from, city_to, cC));
								city_to = null;
								continue;
							} else {
//								AILog.Info("ship_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cC + ") == " + ship_route_manager.HasMaxStationCount(city_from, city_to, cC));
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
				reserved_money -=reserved_money_water;
				reserved_money_water = 0;
			}
		} else {
			if (!Utils.HasMoney(reserved_money_water)) {
				return;
			}
		}

		if (unfinished || city_from != null && city_to != null) {
			if (!unfinished) {
				AILog.Info("s:New city found: " + AITown.GetName(city_from));
				AILog.Info("s:New near city found: " + AITown.GetName(city_to));
			}

			if (!unfinished) build_timer_water = 0;
			local from = unfinished ? ship_build_manager.m_city_from : city_from;
			local to = unfinished ? ship_build_manager.m_city_to : city_to;
			local cargoC = unfinished ? ship_build_manager.m_cargo_class : cC;
			local cheaper = unfinished ? ship_build_manager.m_cheaperRoute : cheaper_route;
			local best_routes = unfinished ? ship_build_manager.m_best_routes_built : ((((best_routes_built >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

			local start_date = AIDate.GetCurrentDate();
			local routeResult = ship_route_manager.BuildRoute(ship_build_manager, from, to, cargoC, cheaper, best_routes);
			build_timer_water += AIDate.GetCurrentDate() - start_date;
			if (routeResult[0] != null) {
				if (routeResult[0] != 0) {
					reserved_money -= reserved_money_water;
					reserved_money_water = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargoC)) + " water route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + build_timer_water + " day" + (build_timer_water != 1 ? "s" : "") + ".");
				}
			} else {
				reserved_money -= reserved_money_water;
				reserved_money_water = 0;
				ship_town_manager.ResetCityPair(from, to, cC, false);
				AILog.Error("s:" + build_timer_water + " day" + (build_timer_water != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::ResetWaterManagementVariables()
{
	if (last_water_managed_array < 0) last_water_managed_array = ship_route_manager.m_town_route_array.len() - 1;
	if (last_water_managed_management < 0) last_water_managed_management = 6;
}

function LuDiAIAfterFix::InterruptWaterManagement(cur_date)
{
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (last_water_managed_array == -1) last_water_managed_management--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageShipRoutes()
{
	local max_ships = AIGameSettings.GetValue("max_ships");

	local cur_date = AIDate.GetCurrentDate();
	ResetWaterManagementVariables();

//	for (local i = last_water_managed_array; i >= 0; --i) {
//		if (last_water_managed_management != 7) break;
//		last_water_managed_array--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(ship_route_manager.m_town_route_array[i].m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(ship_route_manager.m_town_route_array[i].m_dockTo)));
//		if (InterruptWaterManagement(cur_date)) return;
//	}
//	ResetWaterManagementVariables();
//	if (last_water_managed_management == 7) last_water_managed_management--;
//
//	local start_tick = AIController.GetTick();
	for (local i = last_water_managed_array; i >= 0; --i) {
		if (last_water_managed_management != 6) break;
		last_water_managed_array--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		ship_route_manager.m_town_route_array[i].RenewVehicles();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (last_water_managed_management == 6) last_water_managed_management--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = last_water_managed_array; i >= 0; --i) {
		if (last_water_managed_management != 5) break;
		last_water_managed_array--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		ship_route_manager.m_town_route_array[i].SendNegativeProfitVehiclesToDepot();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (last_water_managed_management == 5) last_water_managed_management--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = ship_route_manager.GetShipCount();
	local maxAllRoutesProfit = ship_route_manager.HighestProfitLastYear();
	for (local i = last_water_managed_array; i >= 0; --i) {
		if (last_water_managed_management != 4) break;
		last_water_managed_array--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (max_ships * 0.95 < num_vehs) {
			ship_route_manager.m_town_route_array[i].SendLowProfitVehiclesToDepot(maxAllRoutesProfit);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (last_water_managed_management == 4) last_water_managed_management--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = last_water_managed_array; i >= 0; --i) {
		if (last_water_managed_management != 3) break;
		last_water_managed_array--;
//		AILog.Info("managing route " + i + ". UpgradeEngine");
		ship_route_manager.m_town_route_array[i].UpgradeEngine();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (last_water_managed_management == 3) last_water_managed_management--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = last_water_managed_array; i >= 0; --i) {
		if (last_water_managed_management != 2) break;
		last_water_managed_array--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		ship_route_manager.m_town_route_array[i].SellVehiclesInDepot();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (last_water_managed_management == 2) last_water_managed_management--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = ship_route_manager.GetShipCount();
	for (local i = last_water_managed_array; i >= 0; --i) {
		if (last_water_managed_management != 1) break;
		last_water_managed_array--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < max_ships) {
			num_vehs += ship_route_manager.m_town_route_array[i].AddRemoveVehicleToRoute(num_vehs < max_ships);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (last_water_managed_management == 1) last_water_managed_management--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = last_water_managed_array; i >= 0; --i) {
		if (last_water_managed_management != 0) break;
		last_water_managed_array--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local city_from = ship_route_manager.m_town_route_array[i].m_city_from;
		local city_to = ship_route_manager.m_town_route_array[i].m_city_to;
		local cargoC = ship_route_manager.m_town_route_array[i].m_cargo_class;
		if (ship_route_manager.m_town_route_array[i].RemoveIfUnserviced()) {
			ship_route_manager.m_town_route_array.remove(i);
			ship_town_manager.ResetCityPair(city_from, city_to, cargoC, true);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (last_water_managed_management == 0) last_water_managed_management--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + ship_route_manager.m_town_route_array.len() + " water route" + (ship_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}

function LuDiAIAfterFix::CheckForUnfinishedWaterRoute()
{
	if (ship_build_manager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered dock or ship depot tiles during save */
		local dockFrom = ship_build_manager.m_dockFrom;
		local dockTo = ship_build_manager.m_dockTo;
		local depot_tile = ship_build_manager.m_depot_tile;
		local stationType = AIStation.STATION_DOCK;

		if (dockFrom == -1 || dockTo == -1) {
			local stationList = AIStationList(stationType);
			local allStationsTiles = AITileList();
			for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
				local stationTiles = AITileList_StationType(st, stationType);
				allStationsTiles.AddList(stationTiles);
			}
//			AILog.Info("allStationsTiles has " + allStationsTiles.Count() + " tiles");
			local allTilesFound = AITileList();
			if (dockFrom != -1) allTilesFound.AddTile(dockFrom);
			for (local tile = allStationsTiles.Begin(); !allStationsTiles.IsEnd(); tile = allStationsTiles.Next()) {
				if (::scheduledRemovalsTable.Ship.rawin(tile)) {
//					AILog.Info("scheduledRemovalsTable.Ship has tile " + tile);
					allTilesFound.AddTile(tile);
					break;
				}
				for (local i = ship_route_manager.m_town_route_array.len() - 1; i >= 0; --i) {
					if (ship_route_manager.m_town_route_array[i].m_dockFrom == tile || ship_route_manager.m_town_route_array[i].m_dockTo == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						local stationTiles = AITileList_StationType(AIStation.GetStationID(tile), stationType);
						allTilesFound.AddList(stationTiles);
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
					if (AIMarine.IsDockTile(tile) && AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
//						AILog.Info("Tile " + tile + " is missing");
						::scheduledRemovalsTable.Ship.rawset(tile, 0);
					}
				}
			}
		}

		if (depot_tile == -1) {
			local allDepotsTiles = AIDepotList(AITile.TRANSPORT_WATER);
//			AILog.Info("allDepotsTiles has " + allDepotsTiles.Count() + " tiles");
			local allTilesFound = AITileList();
			for (local tile = allDepotsTiles.Begin(); !allDepotsTiles.IsEnd(); tile = allDepotsTiles.Next()) {
				if (::scheduledRemovalsTable.Ship.rawin(tile)) {
//					AILog.Info("scheduledRemovalsTable.Ship has tile " + tile);
					allTilesFound.AddTile(tile);
					break;
				}
				for (local i = ship_route_manager.m_town_route_array.len() - 1; i >= 0; --i) {
					if (ship_route_manager.m_town_route_array[i].m_depot_tile == tile) {
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
//					AILog.Info("Tile " + tile + " is missing");
					::scheduledRemovalsTable.Ship.rawset(tile, 0);
				}
			}
		}
	}
}
