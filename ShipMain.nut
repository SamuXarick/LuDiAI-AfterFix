function LuDiAIAfterFix::BuildWaterRoute()
{
	if (!AIController.GetSetting("water_support")) return;

	local unfinished = shipBuildManager.HasUnfinishedRoute();
	if (unfinished || (shipRouteManager.GetShipCount() < max(MAX_SHIP_VEHICLES - 10, 10)) && ((allRoutesBuilt >> 2) & 3) != 3) {
		local cityFrom = null;
		local cityTo = null;
		local cheaper_route = false;
		local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassWater : (!unfinished ? cargoClassWater : (cargoClassWater == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
		if (!unfinished) {
			cargoClassWater = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassWater : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

			local cargo = Utils.GetCargoType(cC);
			local tempList = AIEngineList(AIVehicle.VT_WATER);
			local engineList = AIList();
			for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
				if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo)) {
					engineList.AddItem(engine, AIEngine.GetPrice(engine));
				}
			}

			if (engineList.IsEmpty()) {
//				cargoClassWater = cC;
				return;
			}

			engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

			local bestengineinfo = WrightAI().GetBestEngineIncome(engineList, cargo, ShipRoute.COUNT_INTERVAL, false);
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
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", canal_costs = " + canal_costs + ", clear_costs = " + clear_costs + ", dock_costs = " + dock_costs + ", depot_cost = " + depot_cost + ", buoy_costs = " + buoy_costs);
			if (!Utils.HasMoney(estimated_costs + reservedMoney - reservedMoneyWater)) {
				/* Try a cheaper route */
				if ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 1 || !Utils.HasMoney(estimated_costs - canal_costs - clear_costs + reservedMoney - reservedMoneyWater)) {
//					cargoClassWater = cC;
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

			if (cityFrom == null) {
				cityFrom = shipTownManager.GetUnusedCity(((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
				if (cityFrom == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						shipTownManager.m_usedCitiesList[cC].Clear();
					} else {
						if ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							bestRoutesBuilt = bestRoutesBuilt | (1 << (2 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							shipTownManager.m_usedCitiesList[cC].Clear();
//							shipTownManager.m_nearCityPairArray[cC].clear();
							AILog.Warning("Best " + AICargo.GetCargoLabel(cargo) + " water routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
						} else {
//							shipTownManager.m_nearCityPairArray[cC].clear();
							if ((((allRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								AILog.Warning("All " + AICargo.GetCargoLabel(cargo) + " water routes have been used!");
							}
							allRoutesBuilt = allRoutesBuilt | (1 << (2 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
						}
					}
				}
			}

			if (cityFrom != null) {
//				AILog.Info("s:New city found: " + AITown.GetName(cityFrom));

				shipTownManager.FindNearCities(cityFrom, min_dist, max_dist, ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);

				if (!shipTownManager.m_nearCityPairArray[cC].len()) {
					AILog.Info("No near city available");
					cityFrom = null;
				}
			}

			if (cityFrom != null) {
				for (local i = 0; i < shipTownManager.m_nearCityPairArray[cC].len(); ++i) {
					if (cityFrom == shipTownManager.m_nearCityPairArray[cC][i][0]) {
						if (!shipRouteManager.TownRouteExists(cityFrom, shipTownManager.m_nearCityPairArray[cC][i][1], cC)) {
							cityTo = shipTownManager.m_nearCityPairArray[cC][i][1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && shipRouteManager.HasMaxStationCount(cityFrom, cityTo, cC)) {
//								AILog.Info("shipRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + shipRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
								cityTo = null;
								continue;
							} else {
//								AILog.Info("shipRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + shipRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
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
				reservedMoney -=reservedMoneyWater;
				reservedMoneyWater = 0;
			}
		} else {
			if (!Utils.HasMoney(reservedMoneyWater)) {
				return;
			}
		}

		if (unfinished || cityFrom != null && cityTo != null) {
			if (!unfinished) {
				AILog.Info("s:New city found: " + AITown.GetName(cityFrom));
				AILog.Info("s:New near city found: " + AITown.GetName(cityTo));
			}

			if (!unfinished) buildTimerWater = 0;
			local from = unfinished ? shipBuildManager.m_city_from : cityFrom;
			local to = unfinished ? shipBuildManager.m_city_to : cityTo;
			local cargoC = unfinished ? shipBuildManager.m_cargo_class : cC;
			local cheaper = unfinished ? shipBuildManager.m_cheaperRoute : cheaper_route;
			local best_routes = unfinished ? shipBuildManager.m_best_routes_built : ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

			local start_date = AIDate.GetCurrentDate();
			local routeResult = shipRouteManager.BuildRoute(shipBuildManager, from, to, cargoC, cheaper, best_routes);
			buildTimerWater += AIDate.GetCurrentDate() - start_date;
			if (routeResult[0] != null) {
				if (routeResult[0] != 0) {
					reservedMoney -= reservedMoneyWater;
					reservedMoneyWater = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargoC)) + " water route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerWater + " day" + (buildTimerWater != 1 ? "s" : "") + ".");
				}
			} else {
				reservedMoney -= reservedMoneyWater;
				reservedMoneyWater = 0;
				shipTownManager.RemoveUsedCityPair(from, to, cC, false);
				AILog.Error("s:" + buildTimerWater + " day" + (buildTimerWater != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::ResetWaterManagementVariables()
{
	if (lastWaterManagedArray < 0) lastWaterManagedArray = shipRouteManager.m_townRouteArray.len() - 1;
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
	if (max_ships != MAX_SHIP_VEHICLES) {
		MAX_SHIP_VEHICLES = max_ships;
		AILog.Info("MAX_SHIP_VEHICLES = " + MAX_SHIP_VEHICLES);
	}

	local cur_date = AIDate.GetCurrentDate();
	ResetWaterManagementVariables();

//	for (local i = lastWaterManagedArray; i >= 0; --i) {
//		if (lastWaterManagedManagement != 7) break;
//		lastWaterManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(shipRouteManager.m_townRouteArray[i].m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(shipRouteManager.m_townRouteArray[i].m_dockTo)));
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
		shipRouteManager.m_townRouteArray[i].RenewVehicles();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 6) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 5) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		shipRouteManager.m_townRouteArray[i].SendNegativeProfitVehiclesToDepot();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 5) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = shipRouteManager.GetShipCount();
	local maxAllRoutesProfit = shipRouteManager.HighestProfitLastYear();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 4) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (MAX_SHIP_VEHICLES * 0.95 < num_vehs) {
			shipRouteManager.m_townRouteArray[i].SendLowProfitVehiclesToDepot(maxAllRoutesProfit);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 4) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 3) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeEngine");
		shipRouteManager.m_townRouteArray[i].UpgradeEngine();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 3) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 2) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		shipRouteManager.m_townRouteArray[i].SellVehiclesInDepot();
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 2) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = shipRouteManager.GetShipCount();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 1) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < MAX_SHIP_VEHICLES) {
			num_vehs += shipRouteManager.m_townRouteArray[i].AddRemoveVehicleToRoute(num_vehs < MAX_SHIP_VEHICLES);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 1) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastWaterManagedArray; i >= 0; --i) {
		if (lastWaterManagedManagement != 0) break;
		lastWaterManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local cityFrom = shipRouteManager.m_townRouteArray[i].m_city_from;
		local cityTo = shipRouteManager.m_townRouteArray[i].m_city_to;
		local cargoC = shipRouteManager.m_townRouteArray[i].m_cargo_class;
		if (shipRouteManager.m_townRouteArray[i].RemoveIfUnserviced()) {
			shipRouteManager.m_townRouteArray.remove(i);
			shipTownManager.RemoveUsedCityPair(cityFrom, cityTo, cargoC, true);
		}
		if (InterruptWaterManagement(cur_date)) return;
	}
	ResetWaterManagementVariables();
	if (lastWaterManagedManagement == 0) lastWaterManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}

function LuDiAIAfterFix::CheckForUnfinishedWaterRoute()
{
	if (shipBuildManager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered dock or ship depot tiles during save */
		local dockFrom = shipBuildManager.m_dockFrom;
		local dockTo = shipBuildManager.m_dockTo;
		local depotTile = shipBuildManager.m_depotTile;
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
				for (local i = shipRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
					if (shipRouteManager.m_townRouteArray[i].m_dockFrom == tile || shipRouteManager.m_townRouteArray[i].m_dockTo == tile) {
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

		if (depotTile == -1) {
			local allDepotsTiles = AIDepotList(AITile.TRANSPORT_WATER);
//			AILog.Info("allDepotsTiles has " + allDepotsTiles.Count() + " tiles");
			local allTilesFound = AITileList();
			for (local tile = allDepotsTiles.Begin(); !allDepotsTiles.IsEnd(); tile = allDepotsTiles.Next()) {
				if (::scheduledRemovalsTable.Ship.rawin(tile)) {
//					AILog.Info("scheduledRemovalsTable.Ship has tile " + tile);
					allTilesFound.AddTile(tile);
					break;
				}
				for (local i = shipRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
					if (shipRouteManager.m_townRouteArray[i].m_depotTile == tile) {
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
