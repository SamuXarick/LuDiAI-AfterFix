import("Library.SCPLib", "SCPLib", 45);
import("Library.SCPClient_CompanyValueGS", "SCPClient_CompanyValueGS", 1);
import("Library.SCPClient_NoCarGoal", "SCPClient_NoCarGoal", 1);

require("RouteManager.nut");
require("Route.nut");

require("TownManager.nut");
require("BuildManager.nut");
require("Utils.nut");

require("WrightAI.nut");

class LuDiAIAfterFix extends AIController {
	MAX_TOWN_VEHICLES = AIGameSettings.GetValue("max_roadveh");
	MIN_DISTANCE = AIController.GetSetting("road_min_dist");
	MAX_DISTANCE = 115;
	MAX_DISTANCE_INCREASE = 25;

	townManager = null;
	routeManager = null;
	buildManager = null;
	scheduledRemovals = AIList();

	lastManaged = 0;

	cargoClass = null;

	bestRoutesBuilt = null;
	allRoutesBuilt = null;

	wrightAI = null;

	sentToDepotAirGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];

	loading = null;
	loadData = null;
	buildTimer = 0;

	scp = null;
	cvgs = null;
	ncg = null;

	constructor() {
		townManager = TownManager();
		routeManager = RouteManager(this.sentToDepotRoadGroup);
		buildManager = BuildManager();

		if (!AIController.GetSetting("select_town_cargo")) {
			cargoClass = AICargo.CC_PASSENGERS;
		} else {
			cargoClass = AICargo.CC_MAIL;
		}

		bestRoutesBuilt = false;
		allRoutesBuilt = false;

		wrightAI = WrightAI(cargoClass, this.sentToDepotAirGroup);

		loading = true;
	}

	function Start();

	function BuildRoadRoute(cityFrom, unfinished) {
		if (unfinished || (routeManager.getRoadVehicleCount() < MAX_TOWN_VEHICLES - 10) && !allRoutesBuilt) {

			local cargo = Utils.getCargoId(cargoClass);
			local engineList = AIEngineList(AIVehicle.VT_ROAD);
			engineList.Valuate(AIEngine.IsValidEngine);
			engineList.KeepValue(1);
			engineList.Valuate(AIEngine.IsBuildable);
			engineList.KeepValue(1);
			engineList.Valuate(AIEngine.GetRoadType);
			engineList.KeepValue(AIRoad.ROADTYPE_ROAD);
			engineList.Valuate(AIEngine.CanRefitCargo, cargo);
			engineList.KeepValue(1);

			if (engineList.Count() != 0) {
				engineList.Valuate(AIEngine.GetPrice);
				engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

//				local bestengineinfo = WrightAI.GetBestEngineIncome(engineList, cargo, Route.START_VEHICLE_COUNT, false);
//				AILog.Info("bestengineinfo: best_engine = " + AIEngine.GetName(bestengineinfo[0]) + "; best_distance = " + bestengineinfo[1]);

				local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
				local min_dist = MIN_DISTANCE > map_size / 3 ? map_size / 3 : MIN_DISTANCE;
				local max_dist = min_dist + MAX_DISTANCE_INCREASE > MAX_DISTANCE ? min_dist + MAX_DISTANCE_INCREASE : MAX_DISTANCE;
//				AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

				local estimated_costs = 0;
				local engine_costs = (AIEngine.GetPrice(engineList.Begin()) + 500) * (cargoClass == AICargo.CC_PASSENGERS ? Route.START_VEHICLE_COUNT : Route.MIN_VEHICLE_START_COUNT);
				local road_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_ROAD) * 2 * max_dist;
				local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
				local station_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, cargoClass == AICargo.CC_PASSENGERS ? AIRoad.BT_BUS_STOP : AIRoad.BT_TRUCK_STOP) * 2;
				local depot_cost = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_DEPOT);
				estimated_costs += engine_costs + road_costs + clear_costs + station_costs + depot_cost;
//				AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", road_costs = " + road_costs + ", clear_costs = " + clear_costs + ", station_costs = " + station_costs + ", depot_cost = " + depot_cost);
				if (!Utils.HasMoney(estimated_costs)) {
					return;
				}

				local cityTo;
				local articulated;
				if (!unfinished) {
					local articulatedList = AIList();
					articulatedList.AddList(engineList);
					articulatedList.Valuate(AIEngine.IsArticulated);
					articulatedList.KeepValue(1);
					articulated = engineList.Count() == articulatedList.Count();

					if (cityFrom == null) {
						cityFrom = townManager.getUnusedCity(bestRoutesBuilt, cargoClass);
						if (cityFrom == null) {
							if (AIController.GetSetting("pick_mode") == 1) {
								townManager.m_usedCities.Clear();
							} else {
								if (!bestRoutesBuilt) {
									bestRoutesBuilt = true;
									townManager.m_usedCities.Clear();
//									townManager.m_nearCityPairArray = [];
									AILog.Warning("Best road routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
								} else {
									allRoutesBuilt = true;
									townManager.m_nearCityPairArray = [];
									AILog.Warning("All road routes have been used!");
								}
							}
						}
					}

					if (cityFrom != null) {
						AILog.Info("New city found: " + AITown.GetName(cityFrom));

						townManager.findNearCities(cityFrom, min_dist, max_dist, bestRoutesBuilt, cargoClass);
						if (!townManager.m_nearCityPairArray.len()) {
							AILog.Info("No near city available");
							cityFrom = null;
						}
					}

					cityTo = null;
					if (cityFrom != null) {
						for (local i = 0; i < townManager.m_nearCityPairArray.len(); ++i) {
							if (cityFrom == townManager.m_nearCityPairArray[i].m_cityFrom) {
								if (!routeManager.townRouteExists(cityFrom, townManager.m_nearCityPairArray[i].m_cityTo)) {
									cityTo = townManager.m_nearCityPairArray[i].m_cityTo;

									if (routeManager.hasMaxStationCount(cityFrom, cityTo)) {
										cityTo = null;
										continue;
									} else {
										break;
									}
								}
							}
						}

						if (cityTo == null) {
							cityFrom = null;
						}
					}
				}

				if (unfinished || cityFrom != null && cityTo != null) {
					if (!unfinished) AILog.Info("New near city found: " + AITown.GetName(cityTo));

					if (!unfinished) buildTimer = 0;
					local from = unfinished ? buildManager.m_cityFrom : cityFrom;
					local to = unfinished ? buildManager.m_cityTo : cityTo;
					local cargo = unfinished ? buildManager.m_cargoClass : cargoClass;
					local artic = unfinished ? buildManager.m_articulated : articulated;

					local start_date = AIDate.GetCurrentDate();
					local routeResult = routeManager.buildRoute(buildManager, from, to, cargo, artic);
					buildTimer += AIDate.GetCurrentDate() - start_date;
					if (routeResult[0] != null) {
						if (routeResult[0] != 0) {
							AILog.Warning("Built road route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimer + " day" + (buildTimer != 1 ? "s" : "") + ".");
						}
					} else {
						townManager.removeUsedCityPair(from, to, false);
						AILog.Error(buildTimer + " day" + (buildTimer != 1 ? "s" : "") + " wasted!");
					}

					//cityFrom = cityTo; // use this line to look for a new town from the last town
					cityFrom = null;
				}
			}
		}
	}

	function RemoveLeftovers() {
		if (scheduledRemovals.Count() == 0) {
			return;
		}

		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

		local clearedList = AIList();
		for (local tile = scheduledRemovals.Begin(); !scheduledRemovals.IsEnd(); tile = scheduledRemovals.Next()) {
			if (scheduledRemovals.GetValue(tile) == 0) { // Remove without using demolish
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
					// there was nothing to remove
					clearedList.AddItem(tile, 0);
				}
			}
			// Remove using demolish
			else if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile) || AIRoad.IsRoadDepotTile(tile)) {
				if (TestDemolishTile().TryDemolish(tile)) {
					clearedList.AddItem(tile, 1);
				}
			}
			else {
				// there was nothing to remove
				clearedList.AddItem(tile, 1);
			}
		}
		scheduledRemovals.RemoveList(clearedList);
	}

	function updateVehicles() {
		local max_roadveh = AIGameSettings.GetValue("max_roadveh");
		if (max_roadveh != MAX_TOWN_VEHICLES) {
			MAX_TOWN_VEHICLES = max_roadveh;
			AILog.Info("MAX_TOWN_VEHICLES = " + MAX_TOWN_VEHICLES);
		}

//		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(routeManager.m_townRouteArray[i].m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(routeManager.m_townRouteArray[i].m_stationTo)));
//		}
//
//		local start_tick = AIController.GetTick();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("managing route " + i + ". renewVehicles");
			routeManager.m_townRouteArray[i].renewVehicles();
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("managing route " + i + ". sendNegativeProfitVehiclesToDepot");
			routeManager.m_townRouteArray[i].sendNegativeProfitVehiclesToDepot();
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		local num_vehs = routeManager.getRoadVehicleCount();
		local maxAllRoutesProfit = routeManager.highestProfitLastYear();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("managing route " + i + ". sendLowProfitVehiclesToDepot");
			if (MAX_TOWN_VEHICLES < num_vehs) {
				routeManager.m_townRouteArray[i].sendLowProfitVehiclesToDepot(maxAllRoutesProfit);
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("managing route " + i + ". updateEngine");
			routeManager.m_townRouteArray[i].updateEngine();
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("managing route " + i + ". sellVehiclesInDepot");
			routeManager.m_townRouteArray[i].sellVehiclesInDepot();
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("managing route " + i + ". updateBridges")
			routeManager.m_townRouteArray[i].updateBridges();
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = routeManager.getRoadVehicleCount();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//			AILog.Info("managing route " + i + ". addremoveVehicleToRoute");
			if (num_vehs < MAX_TOWN_VEHICLES) {
				num_vehs += routeManager.m_townRouteArray[i].addremoveVehicleToRoute(num_vehs < MAX_TOWN_VEHICLES);
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = routeManager.getRoadVehicleCount();
		if (AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations")) {
			for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
//				AILog.Info("managing route " + i + ". expandStations");
				local cityFrom = routeManager.m_townRouteArray[i].m_cityFrom;
				local cityTo = routeManager.m_townRouteArray[i].m_cityTo;
				if (MAX_TOWN_VEHICLES > num_vehs) {
					routeManager.m_townRouteArray[i].expandStations();
				}
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
			local cityFrom = routeManager.m_townRouteArray[i].m_cityFrom;
			local cityTo = routeManager.m_townRouteArray[i].m_cityTo;
//			AILog.Info("managing route " + i + ". removeIfUnserviced");
			if (routeManager.m_townRouteArray[i].removeIfUnserviced()) {
				 routeManager.m_townRouteArray.remove(i);
				 townManager.removeUsedCityPair(cityFrom, cityTo, true);
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}

	function PerformTownActions() {
		local myCID = Utils.MyCID();
		if (!cvgs.IsCompanyValueGSGame() || cvgs.GetCompanyIDRank(myCID) == 1) {
			local cargoId = Utils.getCargoId(cargoClass);

			local stationList = AIStationList(AIStation.STATION_ANY);
			stationList.Valuate(AIStation.HasCargoRating, cargoId);
			stationList.KeepValue(1);
			stationList.Valuate(AIStation.GetCargoRating, cargoId);
			stationList.KeepBelowValue(50);
			local stationTowns = AIList();
			for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
				if (AIVehicleList_Station(st).Count()) {
					local neartown = AIStation.GetNearestTown(st);
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
			for (local town = stationTowns.Begin(); !stationTowns.IsEnd(); town = stationTowns.Next()) {
				if (!AITown.HasStatue(town)) {
					local action = AITown.TOWN_ACTION_BUILD_STATUE;
					if (AITown.IsActionAvailable(town, action)) {
						local perform_action = true;
						if (cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//							AILog.Info("Cost of perfoming action: " + TestPerformTownAction().TestCost(town, action) + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
							if (TestPerformTownAction().TestCost(town, action) > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
								perform_action = false;
							}
						}
						if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
							AILog.Warning("Built a statue in " + AITown.GetName(town) + ".");
						}
					}
				} else if (!AIController.GetSetting("is_friendly")) {
					local station_location = AIBaseStation.GetLocation(stationTowns.GetValue(town));
					local distance = AITown.GetDistanceManhattanToTile(town, station_location);
					if (distance <= 10) {
						local action = AITown.TOWN_ACTION_ADVERTISE_SMALL;
						if (AITown.IsActionAvailable(town, action)) {
							local perform_action = true;
							if (cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//								AILog.Info("Cost of perfoming action: " + TestPerformTownAction().TestCost(town, action) + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
								if (TestPerformTownAction().TestCost(town, action) > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
									perform_action = false;
								}
							}
							if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
								AILog.Warning("Initiated a small advertising campaign in " + AITown.GetName(town) + ".");
							}
						}
					} else if (distance <= 15) {
						local action = AITown.TOWN_ACTION_ADVERTISE_MEDIUM;
						if (AITown.IsActionAvailable(town, action)) {
							local perform_action = true;
							if (cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//								AILog.Info("Cost of perfoming action: " + TestPerformTownAction().TestCost(town, action) + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
								if (TestPerformTownAction().TestCost(town, action) > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
									perform_action = false;
								}
							}
							if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
								AILog.Warning("Initiated a medium advertising campaign in " + AITown.GetName(town) + ".");
							}
						}
					} else if (distance <= 20) {
						local action = AITown.TOWN_ACTION_ADVERTISE_LARGE;
						if (AITown.IsActionAvailable(town, action)) {
							local perform_action = true;
							if (cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//								AILog.Info("Cost of perfoming action: " + TestPerformTownAction().TestCost(town, action) + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
								if (TestPerformTownAction().TestCost(town, action) > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
									perform_action = false;
								}
							}
							if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
								AILog.Warning("Initiated a large advertising campaign in " + AITown.GetName(town) + ".");
							}
						}
					}
				}

				if (AITown.GetLastMonthProduction(town, cargoId) <= (cargoClass == AICargo.CC_PASSENGERS ? 70 : 35)) {
					local action = AITown.TOWN_ACTION_FUND_BUILDINGS;
					if (AITown.IsActionAvailable(town, action) && AITown.GetFundBuildingsDuration(town) == 0) {
						local perform_action = true;
						if (cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//							AILog.Info("Cost of perfoming action: " + TestPerformTownAction().TestCost(town, action) + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
							if (TestPerformTownAction().TestCost(town, action) > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
								perform_action = false;
							}
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
		if (!cvgs.IsCompanyValueGSGame() || cvgs.IsCompanyValueGSInRankingMode()) {
			if (!AIMap.IsValidTile(AICompany.GetCompanyHQ(Utils.MyCID()))) {
//				AILog.Info("We don't have a company HQ yet...");
				local tileN = AIBase.RandRange(AIMap.GetMapSize());
				if (AIMap.IsValidTile(tileN)) {
//					AILog.Info("North tile is valid");
					local tileE = AIMap.GetTileIndex(AIMap.GetTileX(tileN), AIMap.GetTileY(tileN) + 1);
					local tileW = AIMap.GetTileIndex(AIMap.GetTileX(tileN) + 1, AIMap.GetTileY(tileN));
					local tileS = AIMap.GetTileIndex(AIMap.GetTileX(tileN) + 1, AIMap.GetTileY(tileN) + 1);

					if (AIMap.IsValidTile(tileE) && AIMap.IsValidTile(tileW) && AIMap.IsValidTile(tileS) && AITile.IsBuildableRectangle(tileN, 2, 2) &&
							AITile.GetSlope(tileN) == AITile.SLOPE_FLAT && AITile.GetSlope(tileE) == AITile.SLOPE_FLAT &&
							AITile.GetSlope(tileW) == AITile.SLOPE_FLAT && AITile.GetSlope(tileS) == AITile.SLOPE_FLAT) {
//						AILog.Info("All tiles are valid, buildable and flat");
						local clear_costs = AIAccounting();
						AITestMode() && AITile.DemolishTile(tileN) && AITile.DemolishTile(tileE) && AITile.DemolishTile(tileW) && AITile.DemolishTile(tileS)
						AIExecMode();
						if (clear_costs.GetCosts() <= AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) {
							if (TestBuildHQ().TryBuild(tileN)) {
								AILog.Warning("Built company HQ near " + AITown.GetName(AITile.GetClosestTown(tileN)) + ".");
							} else {
//								AILog.Info("Couldn't build HQ at tile " + tileN);
							}
						} else {
//							AILog.Info("Clear costs are too expensive at tile " + tileN + ": " + clear_costs.GetCosts() + " > " + (AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) + ".");
						}
					}
				}
			}
		}
	}

	function FoundTown() {
		if (!cvgs.IsCompanyValueGSGame() || cvgs.IsCompanyValueGSInRankingMode() && cvgs.GetCompanyIDRank(Utils.MyCID()) == 1) {
			local town_tile = AIBase.RandRange(AIMap.GetMapSize());
			if (AIMap.IsValidTile(town_tile) && AITile.IsBuildable(town_tile) && AITile.GetSlope(town_tile) == AITile.SLOPE_FLAT) {
				local perform_action = true;
				if (cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(Utils.MyCID()) == 1 && cvgs.RankingList().Count() > 1) {
//					AILog.Info("Cost of founding town: " + TestFoundTown().TestCost(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null) + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(Utils.MyCID(), false));
					if (TestFoundTown().TestCost(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null) > cvgs.GetCompanyIDDiffToNext(Utils.MyCID(), false)) {
						perform_action = false;
					}
				}
				if (perform_action && TestFoundTown().TryFound(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null)) {
					AILog.Warning("Founded town " + AITown.GetName(AITile.GetTownAuthority(town_tile)) + ".");
				}
			}
		}
	}

	function Save() {
		if (loading) {
			AILog.Error("WARNING! AI didn't finish loading previously saved data. It will be saving partial data!")
		}
//		AILog.Warning("Saving...");

		local table = {};
		table.rawset("town_manager", townManager.saveTownManager());
		table.rawset("route_manager", routeManager.saveRouteManager());
		table.rawset("build_manager", buildManager.saveBuildManager());

		local scheduledRemovalsTable = {};
		for (local tile = scheduledRemovals.Begin(), i = 0; !scheduledRemovals.IsEnd(); tile = scheduledRemovals.Next(), ++i) {
			scheduledRemovalsTable.rawset(i, [tile, scheduledRemovals.GetValue(tile)]);
		}
		table.rawset("scheduled_removes", scheduledRemovalsTable);

		table.rawset("best_routes_built", bestRoutesBuilt);
		table.rawset("all_routes_built", allRoutesBuilt);

		table.rawset("wrightai", wrightAI.save());

		table.rawset("sent_to_depot_air_group", sentToDepotAirGroup);
		table.rawset("sent_to_depot_road_group", sentToDepotRoadGroup);

//		AILog.Warning("Saved!");

		return table;
	}

	function Load(version, data) {
		loading = true;
		loadData = [version, data];
		AILog.Warning("Loading data from version " + version + "...");
	}
}

function LuDiAIAfterFix::Start() {
	local cargoId = Utils.getCargoId(cargoClass);
	local cargostr = AICargo.GetCargoLabel(cargoId);

	if (loading) {
		if (loadData == null) {
			for (local i = 0; i < sentToDepotAirGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotAirGroup[i])) {
					sentToDepotAirGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_AIR);
					wrightAI.vehicle_to_depot[i] = sentToDepotAirGroup[i];
				}
			}

			for (local i = 0; i < sentToDepotRoadGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotRoadGroup[i])) {
					sentToDepotRoadGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_ROAD);
					routeManager.m_sentToDepotRoadGroup[i] = sentToDepotRoadGroup[i];
				}
			}
		}

		if (loadData != null) {
			if (loadData[1].rawin("town_manager")) {
				townManager.loadTownManager(loadData[1].rawget("town_manager"));
			}

			if (loadData[1].rawin("route_manager")) {
				routeManager.loadRouteManager(loadData[1].rawget("route_manager"));
			}

			if (loadData[1].rawin("build_manager")) {
				buildManager.loadBuildManager(loadData[1].rawget("build_manager"));
			}

			if (loadData[1].rawin("scheduled_removes")) {
				local scheduledRemovalsTable = loadData[1].rawget("scheduled_removes");
				local i = 0;
				while(scheduledRemovalsTable.rawin(i)) {
					local tile = scheduledRemovalsTable.rawget(i);
					scheduledRemovals.AddItem(tile[0], tile[1]);
					++i;
				}
			}
			AILog.Info("Loaded " + scheduledRemovals.Count() + " scheduled removals.");

			if (loadData[1].rawin("best_routes_built")) {
				bestRoutesBuilt = loadData[1].rawget("best_routes_built");
			}

			if (loadData[1].rawin("all_routes_built")) {
				allRoutesBuilt = loadData[1].rawget("all_routes_built");
			}

			if (loadData[1].rawin("wrightai")) {
				wrightAI.load(/*loadData[0], */loadData[1].rawget("wrightai"));
			}

			if (loadData[1].rawin("sent_to_depot_air_group")) {
				sentToDepotAirGroup = loadData[1].rawget("sent_to_depot_air_group");
			}

			if (loadData[1].rawin("sent_to_depot_road_group")) {
				sentToDepotRoadGroup = loadData[1].rawget("sent_to_depot_road_group");
			}

			AILog.Warning("Game loaded.");

			loadData = null;
		} else {
			/* Name company */
			if (!AICompany.SetName("LuDiAI AfterFix " + cargostr)) {
				local i = 2;
				while (!AICompany.SetName("LuDiAI AfterFix " + cargostr + " #" + i)) {
					++i;
				}
			}
		}
		loading = false;

		if (AIController.GetSetting("scp_support")) {
			this.scp = SCPLib("LDAF", 8);
//			this.scp.SCPLogging_Info(true);
//			this.scp.SCPLogging_Error(true);
		}
		this.cvgs = SCPClient_CompanyValueGS(this.scp);
		this.ncg = SCPClient_NoCarGoal(this.scp);
	}
	local scp_counter = 0;

	local cityFrom = null;
	while (AIController.Sleep(1)) {
//		local alltiles = AIMap.GetMapSize();
//		for (local type = 0; type <= 8; type++) {
//			AILog.Info("type: " + WrightAI.GetAirportTypeName(type));
//			local percent = -1;
//			for (local tile = 0; tile < alltiles; tile++) {
//				local noise = AIAirport.GetNoiseLevelIncrease(tile, type);
//				local allowed_noise = AITown.GetAllowedNoise(AIAirport.GetNearestTown(tile, type));
//				local old_result = (noise != -1 && allowed_noise != -1 && noise <= allowed_noise);
//				assert(old_result == AIAirport.IsNoiseLevelIncreaseAllowed(tile, type));
//				local new_result = AIAirport.IsNoiseLevelIncreaseAllowed(tile, type);
//				assert(old_result == new_result;);
//				local newpercent = (tile + 1) * 100 / alltiles;
//				if (percent != newpercent) AILog.Info(newpercent + "%");
//				percent = newpercent;
//			}
//		}
//		AIController.Break("Iterated all types and tiles");
		//pay loan
		Utils.RepayLoan();

		if (this.scp != null) {
			do {
				this.scp.Check();
				if (cvgs.IsCompanyValueGSGame() || ncg.IsNoCarGoalGame()) {
					scp_counter = 0;
					break;
				}
				if (scp_counter < 150) scp_counter++;
			} while(scp_counter < 150);
		}

		RemoveLeftovers();

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . updateVehicles");
		updateVehicles();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Updated vehicles in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("road_support")) {
			BuildRoadRoute(cityFrom, buildManager.hasUnfinishedRoute() ? true : false);
		}

		wrightAI.ManageAirRoutes();
		if (AIController.GetSetting("air_support")) {
			if (!AIController.GetSetting ("road_support") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD) ||
				(routeManager.getRoadVehicleCount() > 125 || MAX_TOWN_VEHICLES <= 125 && routeManager.getRoadVehicleCount() > WrightAI.GetAircraftCount() * 4) ||
				(AIDate.GetYear(AIDate.GetCurrentDate()) > 1955 || allRoutesBuilt) ||
				routeManager.getRoadVehicleCount() >= MAX_TOWN_VEHICLES - 10) {
				wrightAI.BuildAirRoute();
			}
		}

		PerformTownActions();
		FoundTown();
		BuildHQ();
	}
}