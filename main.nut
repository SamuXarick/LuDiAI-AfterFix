import("Library.SCPLib", "SCPLib", 45);
import("Library.SCPClient_CompanyValueGS", "SCPClient_CompanyValueGS", 1);

require("RouteManager.nut");
require("Route.nut");

require("TownManager.nut");
require("BuildManager.nut");
require("Utils.nut");

require("WrightAI.nut");

class LuDiAIAfterFix extends AIController {
	MAX_TOWN_VEHICLES = AIGameSettings.GetValue("max_roadveh");
	DAYS_IN_TRANSIT = AIController.GetSetting("road_days_in_transit");
	MAX_DISTANCE_INCREASE = 25;

	townManager = null;
	routeManager = null;
	buildManager = null;
	scheduledRemovals = AIList();

	lastManagedArray = -1;
	lastManagedManagement = -1;

	cargoClass = null;

	bestRoutesBuilt = null;
	allRoutesBuilt = null;

	wrightAI = null;

	sentToDepotAirGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];

	loading = null;
	loadData = null;
	buildTimer = 0;
	reservedMoney = 0;

	scp = null;
	cvgs = null;
	ncg = null;

	constructor() {
		townManager = TownManager();
		bestRoutesBuilt = 0; // bit 0 - Passengers, bit 1 - Mail
		routeManager = RouteManager(this.sentToDepotRoadGroup, bestRoutesBuilt);
		buildManager = BuildManager();

		cargoClass = AIController.GetSetting("select_town_cargo") != 1 ? AICargo.CC_PASSENGERS : AICargo.CC_MAIL;

		allRoutesBuilt = 0; // bit 0 - Passengers, bit 1 - Mail

		wrightAI = WrightAI(cargoClass, this.sentToDepotAirGroup);

		loading = true;
	}

	function Start();

	function BuildRoadRoute(cityFrom, unfinished) {
		if (unfinished || (routeManager.getRoadVehicleCount() < MAX_TOWN_VEHICLES - 10) && allRoutesBuilt != 3) {

			local cityTo = null;
			local articulated;
			local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClass : (!unfinished ? cargoClass : (cargoClass == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
			if (!unfinished) {
				cargoClass = AIController.GetSetting("select_town_cargo") != 2 ? cargoClass : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

				local cargo = Utils.getCargoId(cC);
				local tempList = AIEngineList(AIVehicle.VT_ROAD);
				local engineList = AIList();
				for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
					if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.GetRoadType(engine) == AIRoad.ROADTYPE_ROAD && AIEngine.CanRefitCargo(engine, cargo)) {
						engineList.AddItem(engine, AIEngine.GetPrice(engine));
					}
				}

				if (engineList.Count() == 0) {
					cargoClass = cC;
					return;
				}

				engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

				local bestengineinfo = WrightAI.GetBestEngineIncome(engineList, cargo, Route.START_VEHICLE_COUNT, false);
				local max_distance = (DAYS_IN_TRANSIT * 2 * 3 * 74 * AIEngine.GetMaxSpeed(bestengineinfo[0]) / 4) / (192 * 16);
				local min_distance = max(20, max_distance * 2 / 3);
//				AILog.Info("bestengineinfo: best_engine = " + AIEngine.GetName(bestengineinfo[0]) + "; best_distance = " + bestengineinfo[1] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

				local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
				local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
				local max_dist = min_dist + MAX_DISTANCE_INCREASE > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//				AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

				local estimated_costs = 0;
				local engine_costs = (AIEngine.GetPrice(engineList.Begin()) + 500) * (cC == AICargo.CC_PASSENGERS ? Route.START_VEHICLE_COUNT : Route.MIN_VEHICLE_START_COUNT);
				local road_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_ROAD) * 2 * max_dist;
				local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
				local station_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, cC == AICargo.CC_PASSENGERS ? AIRoad.BT_BUS_STOP : AIRoad.BT_TRUCK_STOP) * 2;
				local depot_cost = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_DEPOT);
				estimated_costs += engine_costs + road_costs + clear_costs + station_costs + depot_cost;
//				AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", road_costs = " + road_costs + ", clear_costs = " + clear_costs + ", station_costs = " + station_costs + ", depot_cost = " + depot_cost);
				if (!Utils.HasMoney(estimated_costs)) {
					cargoClass = cC;
					return;
				} else {
					reservedMoney = estimated_costs;
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
					cityFrom = townManager.getUnusedCity(((bestRoutesBuilt & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
					if (cityFrom == null) {
						if (AIController.GetSetting("pick_mode") == 1) {
							if (cC == AICargo.CC_PASSENGERS) {
								townManager.m_usedCitiesPass.Clear();
							} else {
								townManager.m_usedCitiesMail.Clear();
							}
						} else {
							if ((bestRoutesBuilt & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								bestRoutesBuilt = bestRoutesBuilt | (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1));
								if (cC == AICargo.CC_PASSENGERS) {
									townManager.m_usedCitiesPass.Clear();
								} else {
									townManager.m_usedCitiesMail.Clear();
								}
//								townManager.ClearCargoClassArray(cC);
								AILog.Warning("Best " + AICargo.GetCargoLabel(cargo) + " road routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
							} else {
								townManager.ClearCargoClassArray(cC);
								if ((allRoutesBuilt & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
									AILog.Warning("All " + AICargo.GetCargoLabel(cargo) + " road routes have been used!");
								}
								allRoutesBuilt = allRoutesBuilt | (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1));
							}
						}
					}
				}

				if (cityFrom != null) {
//					AILog.Info("New city found: " + AITown.GetName(cityFrom));

					townManager.findNearCities(cityFrom, min_dist, max_dist, ((bestRoutesBuilt & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);

					if (!townManager.HasArrayCargoClassPairs(cC)) {
						AILog.Info("No near city available");
						cityFrom = null;
					}
				}

				if (cityFrom != null) {
					for (local i = 0; i < townManager.m_nearCityPairArray.len(); ++i) {
						if (cityFrom == townManager.m_nearCityPairArray[i].m_cityFrom && cC == townManager.m_nearCityPairArray[i].m_cargoClass) {
							if (!routeManager.townRouteExists(cityFrom, townManager.m_nearCityPairArray[i].m_cityTo, cC)) {
								cityTo = townManager.m_nearCityPairArray[i].m_cityTo;

								if ((AIController.GetSetting("pick_mode") != 1 && !allRoutesBuilt) && routeManager.hasMaxStationCount(cityFrom, cityTo, cC)) {
//									AILog.Info("routeManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ") == " + routeManager.hasMaxStationCount(cityFrom, cityTo));
									cityTo = null;
									continue;
								} else {
//									AILog.Info("routeManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ") == " + routeManager.hasMaxStationCount(cityFrom, cityTo));
									break;
								}
							}
						}
					}

					if (cityTo == null) {
						cityFrom = null;
					}
				}
			} else {
				if (!Utils.HasMoney(reservedMoney)) {
					return;
				}
			}

			if (unfinished || cityFrom != null && cityTo != null) {
				if (!unfinished) {
					AILog.Info("New city found: " + AITown.GetName(cityFrom));
					AILog.Info("New near city found: " + AITown.GetName(cityTo));
				}

				if (!unfinished) buildTimer = 0;
				local from = unfinished ? buildManager.m_cityFrom : cityFrom;
				local to = unfinished ? buildManager.m_cityTo : cityTo;
				local cargoC = unfinished ? buildManager.m_cargoClass : cC;
				local artic = unfinished ? buildManager.m_articulated : articulated;
				local best_routes = unfinished ? buildManager.m_best_routes_built : ((bestRoutesBuilt & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

				local start_date = AIDate.GetCurrentDate();
				local routeResult = routeManager.buildRoute(buildManager, from, to, cargoC, artic, best_routes);
				buildTimer += AIDate.GetCurrentDate() - start_date;
				if (routeResult[0] != null) {
					if (routeResult[0] != 0) {
						reservedMoney = 0;
						AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.getCargoId(cargoC)) + " road route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimer + " day" + (buildTimer != 1 ? "s" : "") + ".");
					}
				} else {
					reservedMoney = 0;
					townManager.removeUsedCityPair(from, to, cC, false);
					AILog.Error(buildTimer + " day" + (buildTimer != 1 ? "s" : "") + " wasted!");
				}

				// cityFrom = cityTo; // use this line to look for a new town from the last town
				cityFrom = null;
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
		scheduledRemovals.RemoveList(clearedList);
	}

	function ResetManagementVariables() {
		if (lastManagedArray < 0) lastManagedArray = routeManager.m_townRouteArray.len() - 1;
		if (lastManagedManagement < 0) lastManagedManagement = 8;
	}

	function InterruptManagement(cur_date) {
		if (AIDate.GetCurrentDate() - cur_date > 1) {
			if (lastManagedArray == -1) lastManagedManagement--;
			return true;
		}
		return false;
	}

	function updateVehicles() {
		local max_roadveh = AIGameSettings.GetValue("max_roadveh");
		if (max_roadveh != MAX_TOWN_VEHICLES) {
			MAX_TOWN_VEHICLES = max_roadveh;
			AILog.Info("MAX_TOWN_VEHICLES = " + MAX_TOWN_VEHICLES);
		}

		local cur_date = AIDate.GetCurrentDate();
		ResetManagementVariables();

//		for (local i = lastManagedArray; i >= 0; --i) {
//			if (lastManagedManagement != 9) break;
//			lastManagedArray--;
//			AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(routeManager.m_townRouteArray[i].m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(routeManager.m_townRouteArray[i].m_stationTo)));
//			if (InterruptManagement(cur_date)) return;
//		}
//		ResetManagementVariables();
//		if (lastManagedManagement == 9) lastManagedManagement--;
//
//		local start_tick = AIController.GetTick();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 8) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". renewVehicles");
			routeManager.m_townRouteArray[i].renewVehicles();
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 8) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 7) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". sendNegativeProfitVehiclesToDepot");
			routeManager.m_townRouteArray[i].sendNegativeProfitVehiclesToDepot();
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 7) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		local num_vehs = routeManager.getRoadVehicleCount();
		local maxAllRoutesProfit = routeManager.highestProfitLastYear();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 6) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". sendLowProfitVehiclesToDepot");
			if (MAX_TOWN_VEHICLES < num_vehs) {
				routeManager.m_townRouteArray[i].sendLowProfitVehiclesToDepot(maxAllRoutesProfit);
			}
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 6) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 5) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". updateEngine");
			routeManager.m_townRouteArray[i].updateEngine();
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 5) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 4) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". sellVehiclesInDepot");
			routeManager.m_townRouteArray[i].sellVehiclesInDepot();
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 4) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 3) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". updateBridges")
			routeManager.m_townRouteArray[i].updateBridges();
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 3) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = routeManager.getRoadVehicleCount();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 2) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". addremoveVehicleToRoute");
			if (num_vehs < MAX_TOWN_VEHICLES) {
				num_vehs += routeManager.m_townRouteArray[i].addremoveVehicleToRoute(num_vehs < MAX_TOWN_VEHICLES);
			}
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 2) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = routeManager.getRoadVehicleCount();
		if (AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations")) {
			for (local i = lastManagedArray; i >= 0; --i) {
				if (lastManagedManagement != 1) break;
				lastManagedArray--;
//				AILog.Info("managing route " + i + ". expandStations");
				if (MAX_TOWN_VEHICLES > num_vehs) {
					routeManager.m_townRouteArray[i].expandStations();
				}
				if (InterruptManagement(cur_date)) return;
			}
		}
		ResetManagementVariables();
		if (lastManagedManagement == 1) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastManagedArray; i >= 0; --i) {
			if (lastManagedManagement != 0) break;
			lastManagedArray--;
//			AILog.Info("managing route " + i + ". removeIfUnserviced");
			local cityFrom = routeManager.m_townRouteArray[i].m_cityFrom;
			local cityTo = routeManager.m_townRouteArray[i].m_cityTo;
			local cargoC = routeManager.m_townRouteArray[i].m_cargoClass;
			if (routeManager.m_townRouteArray[i].removeIfUnserviced()) {
				routeManager.m_townRouteArray.remove(i);
				townManager.removeUsedCityPair(cityFrom, cityTo, cargoC, true);
			}
			if (InterruptManagement(cur_date)) return;
		}
		ResetManagementVariables();
		if (lastManagedManagement == 0) lastManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}

	function PerformTownActions() {
		local myCID = Utils.MyCID();
		if (!cvgs.IsCompanyValueGSGame() || cvgs.GetCompanyIDRank(myCID) == 1) {
			local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClass : AIBase.Chance(1, 2) ? AICargo.CC_PASSENGERS : AICargo.CC_MAIL;
			local cargoId = Utils.getCargoId(cC);

			local stationList = AIStationList(AIStation.STATION_ANY);
			local stationTowns = AIList();
			local townList = AIList();
			local statuecount = 0;
			for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
				if (AIStation.HasCargoRating(st, cargoId) && AIVehicleList_Station(st).Count() > 0) {
					local neartown = AIStation.GetNearestTown(st);
					if (!townList.HasItem(neartown)) {
						townList.AddItem(neartown, 0);
						if (AITown.HasStatue(neartown)) {
							statuecount++;
						}
					}
					if (AIStation.GetCargoRating(st, cargoId) < 50 && AIStation.GetCargoWaiting(st, cargoId) <= 100) {
						if (!stationTowns.HasItem(neartown)) {
							stationTowns.AddItem(neartown, st);
						} else {
//							AILog.Info(AITown.GetName(neartown) + " to existing station " + AIBaseStation.GetName(stationTowns.GetValue(neartown)) + " (" + AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(stationTowns.GetValue(neartown))) + " manhattan tiles)");
//							AILog.Info(AITown.GetName(neartown) + " to checking station " + AIBaseStation.GetName(st) + " (" + AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(st)) + " manhattan tiles)");
							if (AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(stationTowns.GetValue(neartown))) < AITown.GetDistanceManhattanToTile(neartown, AIBaseStation.GetLocation(st))) {
								stationTowns.SetValue(neartown, st);
							}
						}
					}
				}
			}

			local towncount = townList.Count();
			if (statuecount < towncount) {
				for (local town = townList.Begin(); !townList.IsEnd(); town = townList.Next()) {
					local action = AITown.TOWN_ACTION_BUILD_STATUE;
					if (AITown.IsActionAvailable(town, action)) {
						local perform_action = true;
						local cost = TestPerformTownAction().TestCost(town, action);
						if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
							perform_action = false;
						}
						if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//							AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
							if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
								perform_action = false;
							}
						}
						if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
							statuecount++;
							AILog.Warning("Built a statue in " + AITown.GetName(town) + " (" + statuecount + "/" + towncount + ")");
						}
					}
				}
			} else {
				for (local town = stationTowns.Begin(); !stationTowns.IsEnd(); town = stationTowns.Next()) {
					if (!AIController.GetSetting("is_friendly")) {
						local station_location = AIBaseStation.GetLocation(stationTowns.GetValue(town));
						local distance = AITown.GetDistanceManhattanToTile(town, station_location);
						if (distance <= 10) {
							local action = AITown.TOWN_ACTION_ADVERTISE_SMALL;
							if (AITown.IsActionAvailable(town, action)) {
								local perform_action = true;
								local cost = TestPerformTownAction().TestCost(town, action);
								if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
									perform_action = false;
								}
								if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//									AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
									if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
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
								local cost = TestPerformTownAction().TestCost(town, action);
								if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
									perform_action = false;
								}
								if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//									AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
									if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
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
								local cost = TestPerformTownAction().TestCost(town, action);
								if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
									perform_action = false;
								}
								if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//									AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
									if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
										perform_action = false;
									}
								}
								if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
									AILog.Warning("Initiated a large advertising campaign in " + AITown.GetName(town) + ".");
								}
							}
						}
					}

					if (AITown.GetLastMonthProduction(town, cargoId) <= (cC == AICargo.CC_PASSENGERS ? 70 : 35)) {
						local action = AITown.TOWN_ACTION_FUND_BUILDINGS;
						if (AITown.IsActionAvailable(town, action) && AITown.GetFundBuildingsDuration(town) == 0) {
							local perform_action = true;
							local cost = TestPerformTownAction().TestCost(town, action);
							if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
								perform_action = false;
							}
							if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(myCID) == 1 && cvgs.RankingList().Count() > 1) {
//								AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
								if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
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
				local cost = TestFoundTown().TestCost(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null);
				if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(Utils.MyCID()) <= cost) {
					perform_action = false;
				}
				if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.GetCompanyIDRank(Utils.MyCID()) == 1 && cvgs.RankingList().Count() > 1) {
//					AILog.Info("Cost of founding town: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(Utils.MyCID(), false));
					if (cost > cvgs.GetCompanyIDDiffToNext(Utils.MyCID(), false)) {
						perform_action = false;
					}
				}
				if (perform_action && TestFoundTown().TryFound(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null)) {
					AILog.Warning("Founded town " + AITown.GetName(AITile.GetTownAuthority(town_tile)) + ".");
					if (allRoutesBuilt != 0) {
						allRoutesBuilt = 0;
						townManager.m_nearCityPairArray = [];
						townManager.m_usedCitiesPass.Clear();
						townManager.m_usedCitiesMail.Clear();
						AILog.Warning("Not all road routes have been used at this time.");
					}
				}
			}
		}
	}

	function Save() {
		if (loading) {
			if (loadData != null) return loadData;
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

		table.rawset("last_managed_array", lastManagedArray);
		table.rawset("last_managed_management", lastManagedManagement);

		table.rawset("reserved_money", reservedMoney);

		table.rawset("cargo_class", cargoClass);

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
	if (AICompany.GetAutoRenewStatus(Utils.MyCID())) AICompany.SetAutoRenewStatus(false);

	if (loading) {
		if (loadData == null) {
			for (local i = 0; i < sentToDepotAirGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotAirGroup[i])) {
					sentToDepotAirGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_AIR, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotAirGroup[i], "0: Aircraft to sell");
					if (i == 1) AIGroup.SetName(sentToDepotAirGroup[i], "1: Aircraft to renew");
					wrightAI.vehicle_to_depot[i] = sentToDepotAirGroup[i];
				}
			}

			for (local i = 0; i < sentToDepotRoadGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotRoadGroup[i])) {
					sentToDepotRoadGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_ROAD, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotRoadGroup[i], "0: Road vehicles to sell");
					if (i == 1) AIGroup.SetName(sentToDepotRoadGroup[i], "1: Road vehicles to renew");
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
				wrightAI.load(loadData[1].rawget("wrightai"));
			}

			if (loadData[1].rawin("sent_to_depot_air_group")) {
				sentToDepotAirGroup = loadData[1].rawget("sent_to_depot_air_group");
			}

			if (loadData[1].rawin("sent_to_depot_road_group")) {
				sentToDepotRoadGroup = loadData[1].rawget("sent_to_depot_road_group");
			}

			if (loadData[1].rawin("last_managed_array")) {
				lastManagedArray = loadData[1].rawget("last_managed_array");
			}

			if (loadData[1].rawin("last_managed_management")) {
				lastManagedManagement = loadData[1].rawget("last_managed_management");
			}

			if (loadData[1].rawin("reserved_money")) {
				reservedMoney = loadData[1].rawget("reserved_money");
			}

			if (loadData[1].rawin("cargo_class")) {
				cargoClass = loadData[1].rawget("cargo_class");
			}

			if (buildManager.hasUnfinishedRoute()) {
				/* Look for potentially unregistered road station or depot tiles during save */
				local stationFrom = buildManager.m_stationFrom;
				local stationTo = buildManager.m_stationTo;
				local depotTile = buildManager.m_depotTile;
				local stationType = buildManager.m_cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;

				if (stationFrom == -1 || stationTo == -1) {
					local stationList = AIStationList(stationType);
					local allStationsTiles = AITileList();
					for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
						local stationTiles = AITileList_StationType(st, stationType);
						allStationsTiles.AddList(stationTiles);
					}
//					AILog.Info("allStationsTiles has " + allStationsTiles.Count() + " tiles");
					local allTilesFound = AITileList();
					if (stationFrom != -1) allTilesFound.AddTile(stationFrom);
					for (local tile = allStationsTiles.Begin(); !allStationsTiles.IsEnd(); tile = allStationsTiles.Next()) {
						if (scheduledRemovals.HasItem(tile)) {
//							AILog.Info("scheduledRemovals has tile " + tile);
							allTilesFound.AddTile(tile);
							break;
						}
						for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
							if (routeManager.m_townRouteArray[i].m_stationFrom == tile || routeManager.m_townRouteArray[i].m_stationTo == tile) {
//								AILog.Info("Route " + i + " has tile " + tile);
								local stationTiles = AITileList_StationType(AIStation.GetStationID(tile), stationType);
								allTilesFound.AddList(stationTiles);
								break;
							}
						}
					}

					if (allTilesFound.Count() != allStationsTiles.Count()) {
//						AILog.Info(allTilesFound.Count() + " != " + allStationsTiles.Count());
						local allTilesMissing = AITileList();
						allTilesMissing.AddList(allStationsTiles);
						allTilesMissing.RemoveList(allTilesFound);
						for (local tile = allTilesMissing.Begin(); !allTilesMissing.IsEnd(); tile = allTilesMissing.Next()) {
//							AILog.Info("Tile " + tile + " is missing");
							scheduledRemovals.AddItem(tile, 0);
						}
					}
				}

				if (depotTile == -1) {
					local allDepotsTiles = AIDepotList(AITile.TRANSPORT_ROAD);
//					AILog.Info("allDepotsTiles has " + allDepotsTiles.Count() + " tiles");
					local allTilesFound = AITileList();
					for (local tile = allDepotsTiles.Begin(); !allDepotsTiles.IsEnd(); tile = allDepotsTiles.Next()) {
						if (scheduledRemovals.HasItem(tile)) {
//							AILog.Info("scheduledRemovals has tile " + tile);
							allTilesFound.AddTile(tile);
							break;
						}
						for (local i = routeManager.m_townRouteArray.len() - 1; i >= 0; --i) {
							if (routeManager.m_townRouteArray[i].m_depotTile == tile) {
//								AILog.Info("Route " + i + " has tile " + tile);
								allTilesFound.AddTile(tile);
								break;
							}
						}
					}

					if (allTilesFound.Count() != allDepotsTiles.Count()) {
//						AILog.Info(allTilesFound.Count() + " != " + allDepotsTiles.Count());
						local allTilesMissing = AITileList();
						allTilesMissing.AddList(allDepotsTiles);
						allTilesMissing.RemoveList(allTilesFound);
						for (local tile = allTilesMissing.Begin(); !allTilesMissing.IsEnd(); tile = allTilesMissing.Next()) {
//							AILog.Info("Tile " + tile + " is missing");
							scheduledRemovals.AddItem(tile, 0);
						}
					}
				}
			}

			AILog.Warning("Game loaded.");
			loadData = null;

		} else {
			/* Name company */
			local cargostr = "";
			if (AIController.GetSetting("select_town_cargo") != 2) {
				cargostr += " " + AICargo.GetCargoLabel(Utils.getCargoId(cargoClass));
			}
			if (!AICompany.SetName("LuDiAI AfterFix" + cargostr)) {
				local i = 2;
				while (!AICompany.SetName("LuDiAI AfterFix" + cargostr + " #" + i)) {
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
	}
//	local scp_counter = 0;

	local cityFrom = null;
	while (AIController.Sleep(1)) {
//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RepayLoan");
		Utils.RepayLoan();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RepayLoan " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (this.scp != null) {
			this.scp.Check();
		}

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RemoveLeftovers");
		RemoveLeftovers();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RemoveLeftovers " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . updateVehicles");
		updateVehicles();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("updateVehicles " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("road_support")) {
//			local start_tick = AIController.GetTick();
//			AILog.Info("main loop . BuildRoadRoute");
			BuildRoadRoute(cityFrom, buildManager.hasUnfinishedRoute() ? true : false);
//			local management_ticks = AIController.GetTick() - start_tick;
//			AILog.Info("BuildRoadRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
		}

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageAirRoutes");
		wrightAI.ManageAirRoutes();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageAirRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("air_support")) {
			if (!AIController.GetSetting ("road_support") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD) ||
					(routeManager.getRoadVehicleCount() > 125 || MAX_TOWN_VEHICLES <= 125 && routeManager.getRoadVehicleCount() > WrightAI.GetAircraftCount() * 4) ||
					(AIDate.GetYear(AIDate.GetCurrentDate()) > 1955 || allRoutesBuilt) ||
					routeManager.getRoadVehicleCount() >= MAX_TOWN_VEHICLES - 10) {
//				local start_tick = AIController.GetTick();
//				AILog.Info("main loop . BuildAirRoute");
				wrightAI.BuildAirRoute();
//				local management_ticks = AIController.GetTick() - start_tick;
//				AILog.Info("BuildAirRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
			}
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
