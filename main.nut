require("RoadvehRouteManager.nut");
require("ShipRouteManager.nut");
require("AirRouteManager.nut");
require("TrainRouteManager.nut");

require("RoadvehRoute.nut");
require("ShipRoute.nut");
require("AirRoute.nut");
require("TrainRoute.nut");

require("RoadvehBuildManager.nut");
require("ShipBuildManager.nut");
require("AirBuildManager.nut");
require("TrainBuildManager.nut");

require("TownManager.nut");
require("Utils.nut");
require("WrightAI.nut");
require("Caches.nut");

class LuDiAIAfterFix extends AIController
{
	MAX_ROAD_VEHICLES = AIGameSettings.GetValue("max_roadveh");
	MAX_SHIP_VEHICLES = AIGameSettings.GetValue("max_ships");
	MAX_AIR_VEHICLES = AIGameSettings.GetValue("max_aircraft");
	MAX_TRAIN_VEHICLES = AIGameSettings.GetValue("max_trains");

	ROAD_DAYS_IN_TRANSIT = AIController.GetSetting("road_days_in_transit");
	WATER_DAYS_IN_TRANSIT = AIController.GetSetting("water_days_in_transit");
	RAIL_DAYS_IN_TRANSIT = AIController.GetSetting("rail_days_in_transit");

	MAX_DISTANCE_INCREASE = 25;

	bestRoutesBuilt = null;
	allRoutesBuilt = null;

	lastRoadManagedArray = -1;
	lastRoadManagedManagement = -1;

	lastWaterManagedArray = -1;
	lastWaterManagedManagement = -1;

	lastAirManagedArray = -1;
	lastAirManagedManagement = -1;

	lastRailManagedArray = -1;
	lastRailManagedManagement = -1;

	cargoClassRoad = null;
	cargoClassWater = null;
	cargoClassAir = null;
	cargoClassRail = null;

	roadTownManager = null;
	road_route_manager = null;
	road_build_manager = null;

	shipTownManager = null;
	ship_route_manager = null;
	ship_build_manager = null;

	airTownManager = null;
	air_route_manager = null;
	air_build_manager = null;

	railTownManager = null;
	rail_route_manager = null;
	rail_build_manager = null;

	sent_to_depot_water_group = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sent_to_depot_rail_group = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];

	loading = null;
	loadData = null;

	buildTimerRoad = 0;
	buildTimerWater = 0;
	buildTimerAir = 0;
	buildTimerRail = 0;

	reservedMoney = 0;

	reservedMoneyRoad = 0;
	reservedMoneyWater = 0;
	reservedMoneyAir = 0;
	reservedMoneyRail = 0;

	constructor()
	{
		roadTownManager = TownManager();
		shipTownManager = TownManager();
		airTownManager = TownManager();
		railTownManager = TownManager();

		cargoClassRoad = AIController.GetSetting("select_town_cargo") != 1 || !AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL)) ? AICargo.CC_PASSENGERS : AICargo.CC_MAIL;
		cargoClassWater = cargoClassRoad;
		cargoClassAir = cargoClassRoad;
		cargoClassRail = cargoClassRoad;

		/**
		 * 'allRoutesBuilt' and 'bestRoutesBuilt' are bits:
		 * bit 0 - Road/Passengers, bit 1 - Road/Mail
		 * bit 2 - Water/Passengers, bit 3 - Water/Mail
		 * bit 4 - Air/Passengers, bit 5 - Air/Mail
		 * bit 6 - Rail/Passengers, bit 7 - Rail/Mail
		 */
		allRoutesBuilt = 0;
		bestRoutesBuilt = 0

		road_route_manager = RoadRouteManager();
		road_build_manager = RoadBuildManager();

		ship_route_manager = ShipRouteManager(this.sent_to_depot_water_group, false);
		ship_build_manager = ShipBuildManager();

		air_route_manager = AirRouteManager();
		air_build_manager = AirBuildManager();

		rail_route_manager = RailRouteManager(this.sent_to_depot_rail_group, false);
		rail_build_manager = RailBuildManager();

		::scheduledRemovalsTable <- { Train = [], Road = {}, Ship = {}, Aircraft = {} };
		::caches <- Caches();

		loading = true;
	}
};

function LuDiAIAfterFix::RemoveLeftovers()
{
	local clearedList = AIList();
	local toclearList = AIList();
	if (::scheduledRemovalsTable.Aircraft.len() > 0) {
		foreach (tile, value in ::scheduledRemovalsTable.Aircraft) {
			if (AIAirport.IsAirportTile(tile)) {
				if (TestRemoveAirport().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
				else {
					/* there was nothing to remove */
					clearedList.AddItem(tile, 0);
				}
			}
		}

		foreach (tile, _ in clearedList) {
			::scheduledRemovalsTable.Aircraft.rawdelete(tile);
		}
	}

	clearedList.Clear();
	toclearList.Clear();
	if (::scheduledRemovalsTable.Road.len() > 0) {
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		foreach (tile, value in ::scheduledRemovalsTable.Road) {
			if (value == 0) { // Remove without using demolish
				if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile)) {
					if (TestRemoveRoadStation().TryRemove(tile)) {
						clearedList.AddItem(tile, 0);
					}
				}
				else if (AIRoad.IsRoadDepotTile(tile)) {
					if (TestRemoveRoadDepot().TryRemove(tile)) {
						clearedList.AddItem(tile, 0);
					}
				}
				else {
					/* there was nothing to remove */
					clearedList.AddItem(tile, 0);
				}
			}
			/* Remove using demolish */
			else if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile) || AIRoad.IsRoadDepotTile(tile)) {
				if (TestDemolishTile().TryDemolish(tile)) {
					clearedList.AddItem(tile, 1);
				}
			}
			else {
				/* there was nothing to remove */
				clearedList.AddItem(tile, 1);
			}
		}

		foreach (tile, _ in clearedList) {
			::scheduledRemovalsTable.Road.rawdelete(tile);
		}
	}

	clearedList.Clear();
	toclearList.Clear();
	if (::scheduledRemovalsTable.Ship.len() > 0) {
		foreach (tile, value in ::scheduledRemovalsTable.Ship) {
			if (AIMarine.IsDockTile(tile)) {
				local slope = AITile.GetSlope(tile);
				if (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW) {
					if (TestRemoveDock().TryRemove(tile)) {
						/* Check for canal and remove it */
						local offset = 0;
						if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
						if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
						if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
						if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
						local tile2 = tile + offset;
						if (AIMarine.IsCanalTile(tile2)) {
							if (!TestRemoveCanal().TryRemove(tile2)) {
								toclearList.AddItem(tile2, 0);
							}
						}
						local tile3 = tile2 + offset;
						if (AIMarine.IsCanalTile(tile3) && !Utils.RemovingCanalBlocksConnection(tile3)) {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								toclearList.AddItem(tile3, 0);
							}
						}
						clearedList.AddItem(tile, 0);
					}
				} else {
					/* Not our dock, someone overbuilt it on top of a canal tile */
					clearedList.AddItem(tile, 0);
				}
			}
			else if (AIMarine.IsCanalTile(tile) && !Utils.RemovingCanalBlocksConnection(tile)) {
				if (TestRemoveCanal().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
			}
			else if (AIMarine.IsWaterDepotTile(tile)) {
				if (TestRemoveWaterDepot().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
			}
			else if (AIMarine.IsBuoyTile(tile)) {
				if (TestRemoveBuoy().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
			}
			else {
				/* there was nothing to remove */
				clearedList.AddItem(tile, 0);
			}
		}

		foreach (tile, _ in clearedList) {
			::scheduledRemovalsTable.Ship.rawdelete(tile);
		}
		foreach (tile, _ in toclearList) {
			::scheduledRemovalsTable.Ship.rawset(tile, 0);
		}
	}

	clearedList.Clear();
	toclearList.Clear();
	if (::scheduledRemovalsTable.Train.len() > 0) {
		foreach (id, i in ::scheduledRemovalsTable.Train) {
			local tile = i.m_tile;
			local struct = i.m_struct;
			local rail_type = i.m_rail_type;

			AIRail.SetCurrentRailType(rail_type);
			if (struct == RailStructType.STATION) {
				local tile2 = i.m_tile2;
				if (AIRail.IsRailStationTile(tile) && AIRail.IsRailStationTile(tile2) &&
						AITile.GetOwner(tile) == ::caches.m_my_company_id && AITile.GetOwner(tile2) == ::caches.m_my_company_id &&
						AIStation.GetStationID(tile) == AIStation.GetStationID(tile2)) {
					if (TestRemoveRailStationTileRectangle().TryRemove(tile, tile2, false)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.DEPOT) {
				if (AIRail.IsRailDepotTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestDemolishTile().TryDemolish(tile)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.BRIDGE) {
				local tile2 = i.m_tile2;
				if (AIBridge.IsBridgeTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) &&
						AIBridge.GetOtherBridgeEnd(tile) == tile2 && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveBridge().TryRemove(tile)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.TUNNEL) {
				local tile2 = i.m_tile2;
				if (AITunnel.IsTunnelTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) &&
						AITunnel.GetOtherTunnelEnd(tile) == tile2 && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveTunnel().TryRemove(tile)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.RAIL) {
				local tile_from = i.m_tile2;
				local tile_to = i.m_tile3;
				if (AIRail.IsRailTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveRail().TryRemove(tile_from, tile, tile_to)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
		}
		foreach (id, _ in clearedList) {
			::scheduledRemovalsTable.Train.remove(id);
		}
	}
}

function LuDiAIAfterFix::PerformTownActions()
{
	if (!AIController.GetSetting("fund_buildings") && !AIController.GetSetting("build_statues") && !AIController.GetSetting("advertise")) return;

	local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRoad : AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL)) ? AIBase.Chance(1, 2) ? AICargo.CC_PASSENGERS : AICargo.CC_MAIL : AICargo.CC_PASSENGERS;
	local cargo_type = Utils.GetCargoType(cC);

	local stationList = AIStationList(AIStation.STATION_ANY);
	local stationTowns = AIList();
	local townList = AIList();
	local statuecount = 0;
	for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
		if (AIStation.HasCargoRating(st, cargo_type)/* && !AIVehicleList_Station(st).IsEmpty()*/) { // too slow
			local neartown = AIStation.GetNearestTown(st);
			if (!townList.HasItem(neartown)) {
				townList.AddItem(neartown, 0);
				if (AITown.HasStatue(neartown)) {
					statuecount++;
				}
			}
			if (AIStation.GetCargoRating(st, cargo_type) < 50 && AIStation.GetCargoWaiting(st, cargo_type) <= 100) {
				if (!stationTowns.HasItem(neartown)) {
					stationTowns.AddItem(neartown, st);
				} else {
//					AILog.Info(AITown.GetName(neartown) + " to existing station " + AIBaseStation.GetName(stationTowns.GetValue(neartown)) + " (" + AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(stationTowns.GetValue(neartown))) + " manhattan tiles)");
//					AILog.Info(AITown.GetName(neartown) + " to checking station " + AIBaseStation.GetName(st) + " (" + AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(st)) + " manhattan tiles)");
					if (AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(stationTowns.GetValue(neartown))) < AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(st))) {
						stationTowns.SetValue(neartown, st);
					}
				}
			}
		}
	}

	local towncount = townList.Count();
	if (AIController.GetSetting("build_statues") && statuecount < towncount) {
		for (local town_id = townList.Begin(); !townList.IsEnd(); town_id = townList.Next()) {
			local action = AITown.TOWN_ACTION_BUILD_STATUE;
			if (AITown.IsActionAvailable(town_id, action)) {
				local perform_action = true;
				local cost = TestPerformTownAction().TestCost(town_id, action);
				if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
					perform_action = false;
				}
				if (perform_action && TestPerformTownAction().TryPerform(town_id, action)) {
					statuecount++;
					AILog.Warning("Built a statue in " + AITown.GetName(town_id) + " (" + statuecount + "/" + towncount + " " + AICargo.GetCargoLabel(cargo_type) + ")");
				}
			}
		}
	} else {
		for (local town_id = stationTowns.Begin(); !stationTowns.IsEnd(); town_id = stationTowns.Next()) {
			if (AIController.GetSetting("advertise")) {
				local station_location = AIBaseStation.GetLocation(stationTowns.GetValue(town_id));
				local distance = AITown.GetDistanceManhattanToTile(town_id, station_location);
				if (distance <= 10) {
					local action = AITown.TOWN_ACTION_ADVERTISE_SMALL;
					if (AITown.IsActionAvailable(town_id, action)) {
						local perform_action = true;
						local cost = TestPerformTownAction().TestCost(town_id, action);
						if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
							perform_action = false;
						}
						if (perform_action && TestPerformTownAction().TryPerform(town_id, action)) {
							AILog.Warning("Initiated a small advertising campaign in " + AITown.GetName(town_id) + ".");
						}
					}
				} else if (distance <= 15) {
					local action = AITown.TOWN_ACTION_ADVERTISE_MEDIUM;
					if (AITown.IsActionAvailable(town_id, action)) {
						local perform_action = true;
						local cost = TestPerformTownAction().TestCost(town_id, action);
						if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
							perform_action = false;
						}
						if (perform_action && TestPerformTownAction().TryPerform(town_id, action)) {
							AILog.Warning("Initiated a medium advertising campaign in " + AITown.GetName(town_id) + ".");
						}
					}
				} else if (distance <= 20) {
					local action = AITown.TOWN_ACTION_ADVERTISE_LARGE;
					if (AITown.IsActionAvailable(town_id, action)) {
						local perform_action = true;
						local cost = TestPerformTownAction().TestCost(town_id, action);
						if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
							perform_action = false;
						}
						if (perform_action && TestPerformTownAction().TryPerform(town_id, action)) {
							AILog.Warning("Initiated a large advertising campaign in " + AITown.GetName(town_id) + ".");
						}
					}
				}
			}

			if (AIController.GetSetting("fund_buildings") && TownManager.GetLastMonthProductionDiffRate(town_id, cargo_type) <= TownManager.CARGO_TYPE_LIMIT[cC]) {
				local action = AITown.TOWN_ACTION_FUND_BUILDINGS;
				if (AITown.IsActionAvailable(town_id, action) && AITown.GetFundBuildingsDuration(town_id) == 0) {
					local perform_action = true;
					local cost = TestPerformTownAction().TestCost(town_id, action);
					if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
						perform_action = false;
					}
					if (perform_action && TestPerformTownAction().TryPerform(town_id, action)) {
						AILog.Warning("Funded the construction of new buildings in " + AITown.GetName(town_id) + ".");
					}
				}
			}
		}
	}
}

function LuDiAIAfterFix::BuildHQ()
{
	if (!AIController.GetSetting("build_hq")) return;

	if (!AIMap.IsValidTile(AICompany.GetCompanyHQ(::caches.m_my_company_id))) {
//		AILog.Info("We don't have a company HQ yet...");
		local tileN = AIBase.RandRange(AIMap.GetMapSize());
		if (AIMap.IsValidTile(tileN)) {
//			AILog.Info("North tile is valid");
			local tileE = AIMap.GetTileIndex(AIMap.GetTileX(tileN), AIMap.GetTileY(tileN) + 1);
			local tileW = AIMap.GetTileIndex(AIMap.GetTileX(tileN) + 1, AIMap.GetTileY(tileN));
			local tileS = AIMap.GetTileIndex(AIMap.GetTileX(tileN) + 1, AIMap.GetTileY(tileN) + 1);

			if (AIMap.IsValidTile(tileE) && AIMap.IsValidTile(tileW) && AIMap.IsValidTile(tileS) && AITile.IsBuildableRectangle(tileN, 2, 2) &&
					AITile.GetSlope(tileN) == AITile.SLOPE_FLAT && AITile.GetSlope(tileE) == AITile.SLOPE_FLAT &&
					AITile.GetSlope(tileW) == AITile.SLOPE_FLAT && AITile.GetSlope(tileS) == AITile.SLOPE_FLAT) {
//				AILog.Info("All tiles are valid, buildable and flat");
				local clear_costs = AIAccounting();
				AITestMode() && AITile.DemolishTile(tileN) && AITile.DemolishTile(tileE) && AITile.DemolishTile(tileW) && AITile.DemolishTile(tileS);
				AIExecMode();
				if (clear_costs.GetCosts() <= AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) {
					if (TestBuildHQ().TryBuild(tileN)) {
						AILog.Warning("Built company HQ near " + AITown.GetName(AITile.GetClosestTown(tileN)) + ".");
//					} else {
//						AILog.Info("Couldn't build HQ at tile " + tileN);
					}
//				} else {
//					AILog.Info("Clear costs are too expensive at tile " + tileN + ": " + clear_costs.GetCosts() + " > " + (AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) + ".");
				}
			}
		}
	}
}

function LuDiAIAfterFix::FoundTown()
{
	if (!AIController.GetSetting("found_towns")) return;

	local town_tile = AIBase.RandRange(AIMap.GetMapSize());
	if (AIMap.IsValidTile(town_tile) && AITile.IsBuildable(town_tile) && AITile.GetSlope(town_tile) == AITile.SLOPE_FLAT) {
		local perform_action = true;
		local cost = TestFoundTown().TestCost(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null);
		if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
			perform_action = false;
		}
		if (perform_action && TestFoundTown().TryFound(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null)) {
			AILog.Warning("Founded town " + AITown.GetName(AITile.GetTownAuthority(town_tile)) + ".");
			if (allRoutesBuilt != 0) {
				allRoutesBuilt = 0;
//				roadTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//				roadTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
				roadTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
				roadTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//				shipTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//				shipTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
				shipTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
				shipTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//				airTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//				airTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
				airTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
				airTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//				railTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//				railTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
				railTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
				railTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
				AILog.Warning("Not all routes have been used at this time.");
			}
		}
	}
}

function LuDiAIAfterFix::Save()
{
	local ops = AIController.GetOpsTillSuspend();
	if (loading) {
		if (loadData != null) return loadData;
		AILog.Error("WARNING! AI didn't finish loading previously saved data. It will be saving partial data!")
	}

	local table = {};
	table.rawset("road_town_manager", roadTownManager.SaveTownManager());
	table.rawset("road_route_manager", road_route_manager.SaveRouteManager());
	table.rawset("road_build_manager", road_build_manager.SaveBuildManager());

	table.rawset("ship_town_manager", shipTownManager.SaveTownManager());
	table.rawset("ship_route_manager", ship_route_manager.SaveRouteManager());
	table.rawset("ship_build_manager", ship_build_manager.SaveBuildManager());

	table.rawset("air_town_manager", airTownManager.SaveTownManager());
	table.rawset("air_route_manager", air_route_manager.SaveRouteManager());
	table.rawset("air_build_manager", air_build_manager.SaveBuildManager());

	table.rawset("rail_town_manager", railTownManager.SaveTownManager());
	table.rawset("rail_route_manager", rail_route_manager.SaveRouteManager());
	table.rawset("rail_build_manager", rail_build_manager.SaveBuildManager());

	table.rawset("scheduled_removals_table", ::scheduledRemovalsTable);

	table.rawset("best_routes_built", bestRoutesBuilt);
	table.rawset("all_routes_built", allRoutesBuilt);

	table.rawset("sent_to_depot_water_group", sent_to_depot_water_group);
	table.rawset("sent_to_depot_rail_group", sent_to_depot_rail_group);

	table.rawset("last_road_managed_array", lastRoadManagedArray);
	table.rawset("last_road_managed_management", lastRoadManagedManagement);

	table.rawset("last_water_managed_array", lastWaterManagedArray);
	table.rawset("last_water_managed_management", lastWaterManagedManagement);

	table.rawset("last_air_managed_array", lastAirManagedArray);
	table.rawset("last_air_managed_management", lastAirManagedManagement);

	table.rawset("last_rail_managed_array", lastRailManagedArray);
	table.rawset("last_rail_managed_management", lastRailManagedManagement);

	table.rawset("reserved_money", reservedMoney);
	table.rawset("reserved_money_road", reservedMoneyRoad);
	table.rawset("reserved_money_water", reservedMoneyWater);
	table.rawset("reserved_money_air", reservedMoneyAir);
	table.rawset("reserved_money_rail", reservedMoneyRail);

	table.rawset("cargo_class_road", cargoClassRoad);
	table.rawset("cargo_class_water", cargoClassWater);
	table.rawset("cargo_class_air", cargoClassAir);
	table.rawset("cargo_class_rail", cargoClassRail);

	table.rawset("caches", ::caches.SaveCaches());

	AILog.Info("Saved! Used ops: " + (ops - AIController.GetOpsTillSuspend()));
	return table;
}

function LuDiAIAfterFix::Load(version, data)
{
	loading = true;
	loadData = [version, data];
	AILog.Warning("Loading data from version " + version + "...");
}

function LuDiAIAfterFix::Start()
{
	if (AICompany.GetAutoRenewStatus(::caches.m_my_company_id)) AICompany.SetAutoRenewStatus(false);

	if (loading) {
		if (loadData == null) {
			for (local i = 0; i < sent_to_depot_water_group.len(); ++i) {
				if (!AIGroup.IsValidGroup(sent_to_depot_water_group[i])) {
					sent_to_depot_water_group[i] = AIGroup.CreateGroup(AIVehicle.VT_WATER, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sent_to_depot_water_group[i], "0: Ships to sell");
					if (i == 1) AIGroup.SetName(sent_to_depot_water_group[i], "1: Ships to renew");
					ship_route_manager.m_sentToDepotWaterGroup[i] = sent_to_depot_water_group[i];
				}
			}

			for (local i = 0; i < sent_to_depot_rail_group.len(); ++i) {
				if (!AIGroup.IsValidGroup(sent_to_depot_rail_group[i])) {
					sent_to_depot_rail_group[i] = AIGroup.CreateGroup(AIVehicle.VT_RAIL AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sent_to_depot_rail_group[i], "0: Trains to sell");
					if (i == 1) AIGroup.SetName(sent_to_depot_rail_group[i], "1: Trains to renew");
					rail_route_manager.m_sentToDepotRailGroup[i] = sent_to_depot_rail_group[i];
				}
			}
		}

		if (loadData != null) {
			if (loadData[1].rawin("road_town_manager")) {
				roadTownManager.LoadTownManager(loadData[1].rawget("road_town_manager"));
			}

			if (loadData[1].rawin("road_route_manager")) {
				road_route_manager.LoadRouteManager(loadData[1].rawget("road_route_manager"));
			}

			if (loadData[1].rawin("road_build_manager")) {
				road_build_manager.LoadBuildManager(loadData[1].rawget("road_build_manager"));
			}

			if (loadData[1].rawin("ship_town_manager")) {
				shipTownManager.LoadTownManager(loadData[1].rawget("ship_town_manager"));
			}

			if (loadData[1].rawin("ship_route_manager")) {
				ship_route_manager.LoadRouteManager(loadData[1].rawget("ship_route_manager"));
			}

			if (loadData[1].rawin("ship_build_manager")) {
				ship_build_manager.LoadBuildManager(loadData[1].rawget("ship_build_manager"));
			}

			if (loadData[1].rawin("air_town_manager")) {
				airTownManager.LoadTownManager(loadData[1].rawget("air_town_manager"));
			}

			if (loadData[1].rawin("air_route_manager")) {
				air_route_manager.LoadRouteManager(loadData[1].rawget("air_route_manager"));
			}

			if (loadData[1].rawin("air_build_manager")) {
				air_build_manager.LoadBuildManager(loadData[1].rawget("air_build_manager"));
			}

			if (loadData[1].rawin("rail_town_manager")) {
				railTownManager.LoadTownManager(loadData[1].rawget("rail_town_manager"));
			}

			if (loadData[1].rawin("rail_route_manager")) {
				rail_route_manager.LoadRouteManager(loadData[1].rawget("rail_route_manager"));
			}

			if (loadData[1].rawin("rail_build_manager")) {
				rail_build_manager.LoadBuildManager(loadData[1].rawget("rail_build_manager"));
			}

			if (loadData[1].rawin("scheduled_removals_table")) {
				::scheduledRemovalsTable = loadData[1].rawget("scheduled_removals_table");
			}

			if (loadData[1].rawin("best_routes_built")) {
				bestRoutesBuilt = loadData[1].rawget("best_routes_built");
			}

			if (loadData[1].rawin("all_routes_built")) {
				allRoutesBuilt = loadData[1].rawget("all_routes_built");
			}

			if (loadData[1].rawin("sent_to_depot_water_group")) {
				sent_to_depot_water_group = loadData[1].rawget("sent_to_depot_water_group");
			}

			if (loadData[1].rawin("sent_to_depot_rail_group")) {
				sent_to_depot_rail_group = loadData[1].rawget("sent_to_depot_rail_group");
			}

			if (loadData[1].rawin("last_road_managed_array")) {
				lastRoadManagedArray = loadData[1].rawget("last_road_managed_array");
			}

			if (loadData[1].rawin("last_road_managed_management")) {
				lastRoadManagedManagement = loadData[1].rawget("last_road_managed_management");
			}

			if (loadData[1].rawin("last_water_managed_array")) {
				lastWaterManagedArray = loadData[1].rawget("last_water_managed_array");
			}

			if (loadData[1].rawin("last_water_managed_management")) {
				lastWaterManagedManagement = loadData[1].rawget("last_water_managed_management");
			}

			if (loadData[1].rawin("last_air_managed_array")) {
				lastAirManagedArray = loadData[1].rawget("last_air_managed_array");
			}

			if (loadData[1].rawin("last_air_managed_management")) {
				lastAirManagedManagement = loadData[1].rawget("last_air_managed_management");
			}

			if (loadData[1].rawin("last_rail_managed_array")) {
				lastRailManagedArray = loadData[1].rawget("last_rail_managed_array");
			}

			if (loadData[1].rawin("last_rail_managed_management")) {
				lastRailManagedManagement = loadData[1].rawget("last_rail_managed_management");
			}

			if (loadData[1].rawin("reserved_money")) {
				reservedMoney = loadData[1].rawget("reserved_money");
			}

			if (loadData[1].rawin("reserved_money_road")) {
				reservedMoneyRoad = loadData[1].rawget("reserved_money_road");
			}

			if (loadData[1].rawin("reserved_money_water")) {
				reservedMoneyWater = loadData[1].rawget("reserved_money_water");
			}

			if (loadData[1].rawin("reserved_money_air")) {
				reservedMoneyAir = loadData[1].rawget("reserved_money_air");
			}

			if (loadData[1].rawin("reserved_money_rail")) {
				reservedMoneyRail = loadData[1].rawget("reserved_money_rail");
			}

			if (loadData[1].rawin("cargo_class_road")) {
				cargoClassRoad = loadData[1].rawget("cargo_class_road");
			}

			if (loadData[1].rawin("cargo_class_water")) {
				cargoClassWater = loadData[1].rawget("cargo_class_water");
			}

			if (loadData[1].rawin("cargo_class_air")) {
				cargoClassAir = loadData[1].rawget("cargo_class_air");
			}

			if (loadData[1].rawin("cargo_class_rail")) {
				cargoClassRail = loadData[1].rawget("cargo_class_rail");
			}

			if (loadData[1].rawin("caches")) {
				::caches.LoadCaches(loadData[1].rawget("caches"));
			}

			CheckForUnfinishedRoadRoute();
			CheckForUnfinishedWaterRoute();
			CheckForUnfinishedRailRoute();

			AILog.Warning("Game loaded.");
			loadData = null;

		} else {
			/* Name company */
			local cargostr = "";
			if (AIController.GetSetting("select_town_cargo") != 2) {
				cargostr += " " + AICargo.GetCargoLabel(Utils.GetCargoType(cargoClassRoad));
			}
			if (!AICompany.SetName("LuDiAI AfterFix" + cargostr)) {
				local i = 2;
				while (!AICompany.SetName("LuDiAI AfterFix" + cargostr + " #" + i)) {
					++i;
				}
			}
		}
		loading = false;
	}

	while (AIController.Sleep(1)) {
//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RepayLoan");
		Utils.RepayLoan();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RepayLoan " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RemoveLeftovers");
		RemoveLeftovers();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RemoveLeftovers " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageRoadvehRoutes");
		ManageRoadvehRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageRoadvehRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildRoadRoute");
		BuildRoadRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildRoadRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageAircraftRoutes");
		ManageAircraftRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageAircraftRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildAirRoute");
		BuildAirRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildAirRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageShipRoutes");
		ManageShipRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageShipRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildWaterRoute");
		BuildWaterRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildWaterRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageTrainRoutes");
		ManageTrainRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageTrainRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildRailRoute");
		BuildRailRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildRailRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . PerformTownActions");
		PerformTownActions();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("PerformTownActions " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . FoundTown");
		FoundTown();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("FoundTown " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildHQ");
		BuildHQ();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildHQ " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}
}

require("RoadvehMain.nut");
require("ShipMain.nut");
require("AirMain.nut");
require("TrainMain.nut");
