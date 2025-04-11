function LuDiAIAfterFix::BuildRoadRoute()
{
	if (!AIController.GetSetting("road_support")) return;

	local unfinished = roadBuildManager.HasUnfinishedRoute();
	if (unfinished || (roadRouteManager.GetRoadVehicleCount() < max(MAX_ROAD_VEHICLES - 10, 10)) && ((allRoutesBuilt >> 0) & 3) != 3) {
		local cityFrom = null;
		local cityTo = null;
		local articulated;
		local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRoad : (!unfinished ? cargoClassRoad : (cargoClassRoad == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
		if (!unfinished) {
			cargoClassRoad = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRoad : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

			local cargo_type = Utils.GetCargoType(cC);
			local tempList = AIEngineList(AIVehicle.VT_ROAD);
			local engineList = AIList();
			for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
				if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.GetRoadType(engine) == AIRoad.ROADTYPE_ROAD && AIEngine.CanRefitCargo(engine, cargo_type)) {
					engineList.AddItem(engine, AIEngine.GetPrice(engine));
				}
			}

			if (engineList.IsEmpty()) {
//				cargoClassRoad = cC;
				return;
			}

			engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

			local bestengineinfo = WrightAI().GetBestEngineIncome(engineList, cargo_type, RoadRoute.START_VEHICLE_COUNT, false);
			local max_distance = (ROAD_DAYS_IN_TRANSIT * 2 * 3 * 74 * AIEngine.GetMaxSpeed(bestengineinfo[0]) / 4) / (192 * 16);
			local min_distance = max(20, max_distance * 2 / 3);
//			AILog.Info("bestengineinfo: best_engine = " + AIEngine.GetName(bestengineinfo[0]) + "; best_distance = " + bestengineinfo[1] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

			local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
			local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
			local max_dist = min_dist + MAX_DISTANCE_INCREASE > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//			AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

			local estimated_costs = 0;
			local engine_costs = (AIEngine.GetPrice(engineList.Begin()) + 500) * (cC == AICargo.CC_PASSENGERS ? RoadRoute.START_VEHICLE_COUNT : RoadRoute.MIN_VEHICLE_START_COUNT);
			local road_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_ROAD) * 2 * max_dist;
			local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
			local station_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, cC == AICargo.CC_PASSENGERS ? AIRoad.BT_BUS_STOP : AIRoad.BT_TRUCK_STOP) * 2;
			local depot_cost = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_DEPOT);
			estimated_costs += engine_costs + road_costs + clear_costs + station_costs + depot_cost;
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", road_costs = " + road_costs + ", clear_costs = " + clear_costs + ", station_costs = " + station_costs + ", depot_cost = " + depot_cost);
			if (!Utils.HasMoney(estimated_costs + reservedMoney - reservedMoneyRoad)) {
//				cargoClassRoad = cC;
				return;
			} else {
				reservedMoneyRoad = estimated_costs;
				reservedMoney += reservedMoneyRoad;
			}

			local articulatedList = AIList();
			articulatedList.AddList(engineList);
			for (local engine = engineList.Begin(); !engineList.IsEnd(); engine = engineList.Next()) {
				if (!AIEngine.IsArticulated(engine)) {
					articulatedList.RemoveItem(engine);
				}
			}
			articulated = engineList.Count() == articulatedList.Count();

			if (cityFrom == null) {
				cityFrom = roadTownManager.GetUnusedCity(((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
				if (cityFrom == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						roadTownManager.m_used_cities_list[cC].Clear();
					} else {
						if ((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							bestRoutesBuilt = bestRoutesBuilt | (1 << (0 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							roadTownManager.m_used_cities_list[cC].Clear();
//							roadTownManager.m_near_city_pair_array[cC].clear();
							AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " road routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
						} else {
//							roadTownManager.m_near_city_pair_array[cC].clear();
							if ((((allRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " road routes have been used!");
							}
							allRoutesBuilt = allRoutesBuilt | (1 << (0 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
						}
					}
				}
			}

			if (cityFrom != null) {
//				AILog.Info("New city found: " + AITown.GetName(cityFrom));

				roadTownManager.FindNearCities(cityFrom, min_dist, max_dist, ((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);

				if (!roadTownManager.m_near_city_pair_array[cC].len()) {
					AILog.Info("No near city available");
					cityFrom = null;
				}
			}

			if (cityFrom != null) {
				for (local i = 0; i < roadTownManager.m_near_city_pair_array[cC].len(); ++i) {
					if (cityFrom == roadTownManager.m_near_city_pair_array[cC][i][0]) {
						if (!roadRouteManager.TownRouteExists(cityFrom, roadTownManager.m_near_city_pair_array[cC][i][1], cC)) {
							cityTo = roadTownManager.m_near_city_pair_array[cC][i][1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && roadRouteManager.HasMaxStationCount(cityFrom, cityTo, cC)) {
//								AILog.Info("roadRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + roadRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
								cityTo = null;
								continue;
							} else {
//								AILog.Info("roadRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + roadRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
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
				reservedMoney -= reservedMoneyRoad;
				reservedMoneyRoad = 0;
			}
		} else {
			if (!Utils.HasMoney(reservedMoneyRoad)) {
				return;
			}
		}

		if (unfinished || cityFrom != null && cityTo != null) {
			if (!unfinished) {
				AILog.Info("r:New city found: " + AITown.GetName(cityFrom));
				AILog.Info("r:New near city found: " + AITown.GetName(cityTo));
			}

			if (!unfinished) buildTimerRoad = 0;
			local from = unfinished ? roadBuildManager.m_city_from : cityFrom;
			local to = unfinished ? roadBuildManager.m_city_to : cityTo;
			local cargoC = unfinished ? roadBuildManager.m_cargo_class : cC;
			local artic = unfinished ? roadBuildManager.m_articulated : articulated;
			local best_routes = unfinished ? roadBuildManager.m_best_routes_built : ((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

			local start_date = AIDate.GetCurrentDate();
			local routeResult = roadRouteManager.BuildRoute(roadBuildManager, from, to, cargoC, artic, best_routes);
			buildTimerRoad += AIDate.GetCurrentDate() - start_date;
			if (routeResult[0] != null) {
				if (routeResult[0] != 0) {
					reservedMoney -= reservedMoneyRoad;
					reservedMoneyRoad = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargoC)) + " road route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerRoad + " day" + (buildTimerRoad != 1 ? "s" : "") + ".");
				}
			} else {
				reservedMoney -= reservedMoneyRoad;
				reservedMoneyRoad = 0;
				roadTownManager.ResetCityPair(from, to, cC, false);
				AILog.Error("r:" + buildTimerRoad + " day" + (buildTimerRoad != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::ResetRoadManagementVariables()
{
	if (lastRoadManagedArray < 0) lastRoadManagedArray = roadRouteManager.m_townRouteArray.len() - 1;
	if (lastRoadManagedManagement < 0) lastRoadManagedManagement = 8;
}

function LuDiAIAfterFix::InterruptRoadManagement(cur_date)
{
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (lastRoadManagedArray == -1) lastRoadManagedManagement--;
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
	ResetRoadManagementVariables();

//	for (local i = lastRoadManagedArray; i >= 0; --i) {
//		if (lastRoadManagedManagement != 9) break;
//		lastRoadManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(roadRouteManager.m_townRouteArray[i].m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(roadRouteManager.m_townRouteArray[i].m_stationTo)));
//		if (InterruptRoadManagement(cur_date)) return;
//	}
//	ResetRoadManagementVariables();
//	if (lastRoadManagedManagement == 9) lastRoadManagedManagement--;
//
//	local start_tick = AIController.GetTick();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 8) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		roadRouteManager.m_townRouteArray[i].RenewVehicles();
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 8) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 7) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		roadRouteManager.m_townRouteArray[i].SendNegativeProfitVehiclesToDepot();
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 7) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = roadRouteManager.GetRoadVehicleCount();
	local maxAllRoutesProfit = roadRouteManager.HighestProfitLastYear();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 6) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (MAX_ROAD_VEHICLES * 0.95 < num_vehs) {
			roadRouteManager.m_townRouteArray[i].SendLowProfitVehiclesToDepot(maxAllRoutesProfit);
		}
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 6) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 5) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeEngine");
		roadRouteManager.m_townRouteArray[i].UpgradeEngine();
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 5) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 4) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		roadRouteManager.m_townRouteArray[i].SellVehiclesInDepot();
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 4) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 3) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeBridges")
		roadRouteManager.m_townRouteArray[i].UpgradeBridges();
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 3) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = roadRouteManager.GetRoadVehicleCount();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 2) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < MAX_ROAD_VEHICLES) {
			num_vehs += roadRouteManager.m_townRouteArray[i].AddRemoveVehicleToRoute(num_vehs < MAX_ROAD_VEHICLES);
		}
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 2) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = roadRouteManager.GetRoadVehicleCount();
	if (AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations")) {
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 1) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". ExpandRoadStation");
			if (MAX_ROAD_VEHICLES > num_vehs) {
				roadRouteManager.m_townRouteArray[i].ExpandRoadStation();
			}
			if (InterruptRoadManagement(cur_date)) return;
		}
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 1) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastRoadManagedArray; i >= 0; --i) {
		if (lastRoadManagedManagement != 0) break;
		lastRoadManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local cityFrom = roadRouteManager.m_townRouteArray[i].m_city_from;
		local cityTo = roadRouteManager.m_townRouteArray[i].m_city_to;
		local cargoC = roadRouteManager.m_townRouteArray[i].m_cargo_class;
		if (roadRouteManager.m_townRouteArray[i].RemoveIfUnserviced()) {
			roadRouteManager.m_townRouteArray.remove(i);
			roadTownManager.ResetCityPair(cityFrom, cityTo, cargoC, true);
		}
		if (InterruptRoadManagement(cur_date)) return;
	}
	ResetRoadManagementVariables();
	if (lastRoadManagedManagement == 0) lastRoadManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + roadRouteManager.m_townRouteArray.len() + " road route" + (roadRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}

function LuDiAIAfterFix::CheckForUnfinishedRoadRoute()
{
	if (roadBuildManager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered road station or depot tiles during save */
		local stationFrom = roadBuildManager.m_stationFrom;
		local stationTo = roadBuildManager.m_stationTo;
		local depotTile = roadBuildManager.m_depotTile;
		local stationType = roadBuildManager.m_cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;

		if (stationFrom == -1 || stationTo == -1) {
			local stationList = AIStationList(stationType);
			local allStationsTiles = AITileList();
			for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
				local stationTiles = AITileList_StationType(st, stationType);
				allStationsTiles.AddList(stationTiles);
			}
//			AILog.Info("allStationsTiles has " + allStationsTiles.Count() + " tiles");
			local allTilesFound = AITileList();
			if (stationFrom != -1) allTilesFound.AddTile(stationFrom);
			for (local tile = allStationsTiles.Begin(); !allStationsTiles.IsEnd(); tile = allStationsTiles.Next()) {
//				if (scheduledRemovals.HasItem(tile)) {
				if (scheduledRemovalsTable.Road.rawin(tile)) {
//					AILog.Info("scheduledRemovals has tile " + tile);
//					AILog.Info("scheduledRemovalsTable.Road has tile " + tile);
					allTilesFound.AddTile(tile);
					break;
				}
				for (local i = roadRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
					if (roadRouteManager.m_townRouteArray[i].m_stationFrom == tile || roadRouteManager.m_townRouteArray[i].m_stationTo == tile) {
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
//					AILog.Info("Tile " + tile + " is missing");
//					scheduledRemovals.AddItem(tile, 0);
					scheduledRemovalsTable.Road.rawset(tile, 0);
				}
			}
		}

		if (depotTile == -1) {
			local allDepotsTiles = AIDepotList(AITile.TRANSPORT_ROAD);
//			AILog.Info("allDepotsTiles has " + allDepotsTiles.Count() + " tiles");
			local allTilesFound = AITileList();
			for (local tile = allDepotsTiles.Begin(); !allDepotsTiles.IsEnd(); tile = allDepotsTiles.Next()) {
//				if (scheduledRemovals.HasItem(tile)) {
				if (scheduledRemovalsTable.Road.HasItem(tile)) {
//					AILog.Info("scheduledRemovals has tile " + tile);
//					AILog.Info("scheduledRemovalsTable.Road has tile " + tile);
					allTilesFound.AddTile(tile);
					break;
				}
				for (local i = roadRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
					if (roadRouteManager.m_townRouteArray[i].m_depotTile == tile) {
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
//					scheduledRemovals.AddItem(tile, 0);
					scheduledRemovalsTable.Road.rawset(tile, 0);
				}
			}
		}
	}
}
