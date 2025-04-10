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

class LuDiAIAfterFix extends AIController {
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
	roadRouteManager = null;
	roadBuildManager = null;

	shipTownManager = null;
	shipRouteManager = null;
	shipBuildManager = null;

	airTownManager = null;
	airRouteManager = null;
	airBuildManager = null;

	railTownManager = null;
	railRouteManager = null;
	railBuildManager = null;

	sentToDepotAirGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sentToDepotWaterGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sentToDepotRailGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];

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

	constructor() {
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

		roadRouteManager = RoadRouteManager(this.sentToDepotRoadGroup, false);
		roadBuildManager = RoadBuildManager();

		shipRouteManager = ShipRouteManager(this.sentToDepotWaterGroup, false);
		shipBuildManager = ShipBuildManager();

		airRouteManager = AirRouteManager(this.sentToDepotAirGroup, false);
		airBuildManager = AirBuildManager();

		railRouteManager = RailRouteManager(this.sentToDepotRailGroup, false);
		railBuildManager = RailBuildManager();

		::scheduledRemovalsTable <- { Train = [], Road = {}, Ship = {}, Aircraft = {} };
		::caches <- Caches();

		loading = true;
	}

	function Start();

	function BuildRoadRoute(cityFrom, unfinished);
	function BuildWaterRoute(cityFrom, unfinished);
	function BuildAirRoute(cityFrom, unfinished);
	function BuildRailRoute(cityFrom, unfinished);

	function ResetRoadManagementVariables();
	function InterruptRoadManagement(cur_date);
	function ManageRoadvehRoutes();

	function ResetWaterManagementVariables();
	function InterruptWaterManagement(cur_date);
	function ManageShipRoutes();

	function ResetAirManagementVariables();
	function InterruptAirManagement(cur_date);
	function ManageAircraftRoutes();

	function ResetRailManagementVariables();
	function InterruptRailManagement(cur_date);
	function ManageTrainRoutes();

	function CheckForUnfinishedRoadRoute();
	function CheckForUnfinishedWaterRoute();
	function CheckForUnfinishedRailRoute();

	function RemoveLeftovers() {
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
				local railtype = i.m_railtype;

				AIRail.SetCurrentRailType(railtype);
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

	function PerformTownActions() {
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
//						AILog.Info(AITown.GetName(neartown) + " to existing station " + AIBaseStation.GetName(stationTowns.GetValue(neartown)) + " (" + AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(stationTowns.GetValue(neartown))) + " manhattan tiles)");
//						AILog.Info(AITown.GetName(neartown) + " to checking station " + AIBaseStation.GetName(st) + " (" + AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(st)) + " manhattan tiles)");
						if (AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(stationTowns.GetValue(neartown))) < AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(st))) {
							stationTowns.SetValue(neartown, st);
						}
					}
				}
			}
		}

		local towncount = townList.Count();
		if (AIController.GetSetting("build_statues") && statuecount < towncount) {
			for (local town = townList.Begin(); !townList.IsEnd(); town = townList.Next()) {
				local action = AITown.TOWN_ACTION_BUILD_STATUE;
				if (AITown.IsActionAvailable(town, action)) {
					local perform_action = true;
					local cost = TestPerformTownAction().TestCost(town, action);
					if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
						perform_action = false;
					}
					if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
						statuecount++;
						AILog.Warning("Built a statue in " + AITown.GetName(town) + " (" + statuecount + "/" + towncount + " " + AICargo.GetCargoLabel(cargo_type) + ")");
					}
				}
			}
		} else {
			for (local town = stationTowns.Begin(); !stationTowns.IsEnd(); town = stationTowns.Next()) {
				if (AIController.GetSetting("advertise")) {
					local station_location = AIBaseStation.GetLocation(stationTowns.GetValue(town));
					local distance = AITown.GetDistanceManhattanToTile(town, station_location);
					if (distance <= 10) {
						local action = AITown.TOWN_ACTION_ADVERTISE_SMALL;
						if (AITown.IsActionAvailable(town, action)) {
							local perform_action = true;
							local cost = TestPerformTownAction().TestCost(town, action);
							if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
								perform_action = false;
							}
							if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
								AILog.Warning("Initiated a small advertising campaign in " + AITown.GetName(town) + ".");
							}
						}
					} else if (distance <= 15) {
						local action = AITown.TOWN_ACTION_ADVERTISE_MEDIUM;
						if (AITown.IsActionAvailable(town, action)) {
							local perform_action = true;
							local cost = TestPerformTownAction().TestCost(town, action);
							if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
								perform_action = false;
							}
							if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
								AILog.Warning("Initiated a medium advertising campaign in " + AITown.GetName(town) + ".");
							}
						}
					} else if (distance <= 20) {
						local action = AITown.TOWN_ACTION_ADVERTISE_LARGE;
						if (AITown.IsActionAvailable(town, action)) {
							local perform_action = true;
							local cost = TestPerformTownAction().TestCost(town, action);
							if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
								perform_action = false;
							}
							if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
								AILog.Warning("Initiated a large advertising campaign in " + AITown.GetName(town) + ".");
							}
						}
					}
				}

				if (AIController.GetSetting("fund_buildings") && AITown.GetLastMonthProduction(town, cargo_type) <= (cC == AICargo.CC_PASSENGERS ? 70 : 35)) {
					local action = AITown.TOWN_ACTION_FUND_BUILDINGS;
					if (AITown.IsActionAvailable(town, action) && AITown.GetFundBuildingsDuration(town) == 0) {
						local perform_action = true;
						local cost = TestPerformTownAction().TestCost(town, action);
						if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
							perform_action = false;
						}
						if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
							AILog.Warning("Funded the construction of new buildings in " + AITown.GetName(town) + ".");
						}
					}
				}
			}
		}
	}

	function BuildHQ() {
		if (!AIController.GetSetting("build_hq")) return;

		if (!AIMap.IsValidTile(AICompany.GetCompanyHQ(::caches.m_my_company_id))) {
//			AILog.Info("We don't have a company HQ yet...");
			local tileN = AIBase.RandRange(AIMap.GetMapSize());
			if (AIMap.IsValidTile(tileN)) {
//				AILog.Info("North tile is valid");
				local tileE = AIMap.GetTileIndex(AIMap.GetTileX(tileN), AIMap.GetTileY(tileN) + 1);
				local tileW = AIMap.GetTileIndex(AIMap.GetTileX(tileN) + 1, AIMap.GetTileY(tileN));
				local tileS = AIMap.GetTileIndex(AIMap.GetTileX(tileN) + 1, AIMap.GetTileY(tileN) + 1);

				if (AIMap.IsValidTile(tileE) && AIMap.IsValidTile(tileW) && AIMap.IsValidTile(tileS) && AITile.IsBuildableRectangle(tileN, 2, 2) &&
						AITile.GetSlope(tileN) == AITile.SLOPE_FLAT && AITile.GetSlope(tileE) == AITile.SLOPE_FLAT &&
						AITile.GetSlope(tileW) == AITile.SLOPE_FLAT && AITile.GetSlope(tileS) == AITile.SLOPE_FLAT) {
//					AILog.Info("All tiles are valid, buildable and flat");
					local clear_costs = AIAccounting();
					AITestMode() && AITile.DemolishTile(tileN) && AITile.DemolishTile(tileE) && AITile.DemolishTile(tileW) && AITile.DemolishTile(tileS);
					AIExecMode();
					if (clear_costs.GetCosts() <= AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) {
						if (TestBuildHQ().TryBuild(tileN)) {
							AILog.Warning("Built company HQ near " + AITown.GetName(AITile.GetClosestTown(tileN)) + ".");
//						} else {
//							AILog.Info("Couldn't build HQ at tile " + tileN);
						}
//					} else {
//						AILog.Info("Clear costs are too expensive at tile " + tileN + ": " + clear_costs.GetCosts() + " > " + (AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) + ".");
					}
				}
			}
		}
	}

	function FoundTown() {
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
//					roadTownManager.m_nearCityPairArray[AICargo.CC_PASSENGERS].clear();
//					roadTownManager.m_nearCityPairArray[AICargo.CC_MAIL].clear();
					roadTownManager.m_usedCitiesList[AICargo.CC_PASSENGERS].Clear();
					roadTownManager.m_usedCitiesList[AICargo.CC_MAIL].Clear();
//					shipTownManager.m_nearCityPairArray[AICargo.CC_PASSENGERS].clear();
//					shipTownManager.m_nearCityPairArray[AICargo.CC_MAIL].clear();
					shipTownManager.m_usedCitiesList[AICargo.CC_PASSENGERS].Clear();
					shipTownManager.m_usedCitiesList[AICargo.CC_MAIL].Clear();
//					airTownManager.m_nearCityPairArray[AICargo.CC_PASSENGERS].clear();
//					airTownManager.m_nearCityPairArray[AICargo.CC_MAIL].clear();
					airTownManager.m_usedCitiesList[AICargo.CC_PASSENGERS].Clear();
					airTownManager.m_usedCitiesList[AICargo.CC_MAIL].Clear();
//					railTownManager.m_nearCityPairArray[AICargo.CC_PASSENGERS].clear();
//					railTownManager.m_nearCityPairArray[AICargo.CC_MAIL].clear();
					railTownManager.m_usedCitiesList[AICargo.CC_PASSENGERS].Clear();
					railTownManager.m_usedCitiesList[AICargo.CC_MAIL].Clear();
					AILog.Warning("Not all routes have been used at this time.");
				}
			}
		}
	}

	function Save() {
		local ops = AIController.GetOpsTillSuspend();
		if (loading) {
			if (loadData != null) return loadData;
			AILog.Error("WARNING! AI didn't finish loading previously saved data. It will be saving partial data!")
		}
//		AILog.Warning("Saving...");

		local table = {};
		table.rawset("road_town_manager", roadTownManager.SaveTownManager());
		table.rawset("road_route_manager", roadRouteManager.SaveRouteManager());
		table.rawset("road_build_manager", roadBuildManager.SaveBuildManager());

		table.rawset("ship_town_manager", shipTownManager.SaveTownManager());
		table.rawset("ship_route_manager", shipRouteManager.SaveRouteManager());
		table.rawset("ship_build_manager", shipBuildManager.SaveBuildManager());

		table.rawset("air_town_manager", airTownManager.SaveTownManager());
		table.rawset("air_route_manager", airRouteManager.SaveRouteManager());
		table.rawset("air_build_manager", airBuildManager.SaveBuildManager());

		table.rawset("rail_town_manager", railTownManager.SaveTownManager());
		table.rawset("rail_route_manager", railRouteManager.SaveRouteManager());
		table.rawset("rail_build_manager", railBuildManager.SaveBuildManager());

		table.rawset("scheduled_removals_table", ::scheduledRemovalsTable);

		table.rawset("best_routes_built", bestRoutesBuilt);
		table.rawset("all_routes_built", allRoutesBuilt);

		table.rawset("sent_to_depot_air_group", sentToDepotAirGroup);
		table.rawset("sent_to_depot_road_group", sentToDepotRoadGroup);
		table.rawset("sent_to_depot_water_group", sentToDepotWaterGroup);
		table.rawset("sent_to_depot_rail_group", sentToDepotRailGroup);

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

//		AILog.Warning("Saved!");

		AILog.Info("Used ops: " + (ops - AIController.GetOpsTillSuspend()));
		return table;
	}

	function Load(version, data) {
		loading = true;
		loadData = [version, data];
		AILog.Warning("Loading data from version " + version + "...");
	}
}

function LuDiAIAfterFix::Start() {
	if (AICompany.GetAutoRenewStatus(::caches.m_my_company_id)) AICompany.SetAutoRenewStatus(false);

	if (loading) {
		if (loadData == null) {
			for (local i = 0; i < sentToDepotAirGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotAirGroup[i])) {
					sentToDepotAirGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_AIR, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotAirGroup[i], "0: Aircraft to sell");
					if (i == 1) AIGroup.SetName(sentToDepotAirGroup[i], "1: Aircraft to renew");
					airRouteManager.m_sent_to_depot_air_group[i] = sentToDepotAirGroup[i];
				}
			}

			for (local i = 0; i < sentToDepotRoadGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotRoadGroup[i])) {
					sentToDepotRoadGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_ROAD, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotRoadGroup[i], "0: Road vehicles to sell");
					if (i == 1) AIGroup.SetName(sentToDepotRoadGroup[i], "1: Road vehicles to renew");
					roadRouteManager.m_sentToDepotRoadGroup[i] = sentToDepotRoadGroup[i];
				}
			}

			for (local i = 0; i < sentToDepotWaterGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotWaterGroup[i])) {
					sentToDepotWaterGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_WATER, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotWaterGroup[i], "0: Ships to sell");
					if (i == 1) AIGroup.SetName(sentToDepotWaterGroup[i], "1: Ships to renew");
					shipRouteManager.m_sentToDepotWaterGroup[i] = sentToDepotWaterGroup[i];
				}
			}

			for (local i = 0; i < sentToDepotRailGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotRailGroup[i])) {
					sentToDepotRailGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_RAIL AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotRailGroup[i], "0: Trains to sell");
					if (i == 1) AIGroup.SetName(sentToDepotRailGroup[i], "1: Trains to renew");
					railRouteManager.m_sentToDepotRailGroup[i] = sentToDepotRailGroup[i];
				}
			}
		}

		if (loadData != null) {
			if (loadData[1].rawin("road_town_manager")) {
				roadTownManager.LoadTownManager(loadData[1].rawget("road_town_manager"));
			}

			if (loadData[1].rawin("road_route_manager")) {
				roadRouteManager.LoadRouteManager(loadData[1].rawget("road_route_manager"));
			}

			if (loadData[1].rawin("road_build_manager")) {
				roadBuildManager.LoadBuildManager(loadData[1].rawget("road_build_manager"));
			}

			if (loadData[1].rawin("ship_town_manager")) {
				shipTownManager.LoadTownManager(loadData[1].rawget("ship_town_manager"));
			}

			if (loadData[1].rawin("ship_route_manager")) {
				shipRouteManager.LoadRouteManager(loadData[1].rawget("ship_route_manager"));
			}

			if (loadData[1].rawin("ship_build_manager")) {
				shipBuildManager.LoadBuildManager(loadData[1].rawget("ship_build_manager"));
			}

			if (loadData[1].rawin("air_town_manager")) {
				airTownManager.LoadTownManager(loadData[1].rawget("air_town_manager"));
			}

			if (loadData[1].rawin("air_route_manager")) {
				airRouteManager.LoadRouteManager(loadData[1].rawget("air_route_manager"));
			}

			if (loadData[1].rawin("air_build_manager")) {
				airBuildManager.LoadBuildManager(loadData[1].rawget("air_build_manager"));
			}

			if (loadData[1].rawin("rail_town_manager")) {
				railTownManager.LoadTownManager(loadData[1].rawget("rail_town_manager"));
			}

			if (loadData[1].rawin("rail_route_manager")) {
				railRouteManager.LoadRouteManager(loadData[1].rawget("rail_route_manager"));
			}

			if (loadData[1].rawin("rail_build_manager")) {
				railBuildManager.LoadBuildManager(loadData[1].rawget("rail_build_manager"));
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

			if (loadData[1].rawin("sent_to_depot_air_group")) {
				sentToDepotAirGroup = loadData[1].rawget("sent_to_depot_air_group");
			}

			if (loadData[1].rawin("sent_to_depot_road_group")) {
				sentToDepotRoadGroup = loadData[1].rawget("sent_to_depot_road_group");
			}

			if (loadData[1].rawin("sent_to_depot_water_group")) {
				sentToDepotRoadGroup = loadData[1].rawget("sent_to_depot_water_group");
			}

			if (loadData[1].rawin("sent_to_depot_rail_group")) {
				sentToDepotRailGroup = loadData[1].rawget("sent_to_depot_rail_group");
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
	local cityFrom = null;
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

		if (AIController.GetSetting("road_support")) {
//			local start_tick = AIController.GetTick();
//			AILog.Info("main loop . BuildRoadRoute");
			BuildRoadRoute(cityFrom, roadBuildManager.HasUnfinishedRoute());
//			local management_ticks = AIController.GetTick() - start_tick;
//			AILog.Info("BuildRoadRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
		}

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageAircraftRoutes");
		ManageAircraftRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageAircraftRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("air_support")) {
//			local start_tick = AIController.GetTick();
//			AILog.Info("main loop . BuildAirRoute");
			BuildAirRoute(cityFrom, airBuildManager.HasUnfinishedRoute());
//			local management_ticks = AIController.GetTick() - start_tick;
//			AILog.Info("BuildAirRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
		}

//		AILog.Info("available_ticks = " + (available_ticks - used_ticks));
//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageShipRoutes");
		ManageShipRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageShipRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("water_support")) {
//			local start_tick = AIController.GetTick();
//			AILog.Info("main loop . BuildWaterRoute");
			BuildWaterRoute(cityFrom, shipBuildManager.HasUnfinishedRoute());
//			local management_ticks = AIController.GetTick() - start_tick;
//			AILog.Info("BuildWaterRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
		}

//		AILog.Info("available_ticks = " + (available_ticks - used_ticks));
//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageTrainRoutes");
		ManageTrainRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageTrainRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("rail_support")) {
//			local start_tick = AIController.GetTick();
//			AILog.Info("main loop . BuildRailRoute");
			BuildRailRoute(cityFrom, railBuildManager.HasUnfinishedRoute());
//			local management_ticks = AIController.GetTick() - start_tick;
//			AILog.Info("BuildRailRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
		}

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
