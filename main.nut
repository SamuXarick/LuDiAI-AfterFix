import("Library.SCPLib", "SCPLib", 45);
import("Library.SCPClient_CompanyValueGS", "SCPClient_CompanyValueGS", 1);

require("RouteManager.nut");
require("ShipRouteManager.nut");
require("AirRouteManager.nut");
require("Route.nut");
require("ShipRoute.nut");
require("AirRoute.nut");

require("TownManager.nut");
require("BuildManager.nut");
require("ShipBuildManager.nut");
require("AirBuildManager.nut");
require("Utils.nut");

require("WrightAI.nut");

class LuDiAIAfterFix extends AIController {
	MAX_TOWN_VEHICLES = AIGameSettings.GetValue("max_roadveh");
	MAX_SHIP_VEHICLES = AIGameSettings.GetValue("max_ships");
	MAX_AIR_VEHICLES = AIGameSettings.GetValue("max_aircraft");
	DAYS_IN_TRANSIT = AIController.GetSetting("road_days_in_transit");
	DAYS_IN_SEA_TRANSIT = AIController.GetSetting("water_days_in_transit");
	MAX_DISTANCE_INCREASE = 25;

	townManager = null;
	routeManager = null;
	buildManager = null;
	scheduledRemovals = AIList();

	lastRoadManagedArray = -1;
	lastRoadManagedManagement = -1;
	lastWaterManagedArray = -1;
	lastWaterManagedManagement = -1;
	lastAirManagedArray = -1;
	lastAirManagedManagement = -1;

	cargoClassRoad = null;
	cargoClassWater = null;
	cargoClassAir = null;

	bestRoutesBuilt = null;
	allRoutesBuilt = null;

	shipTownManager = null;
	shipRouteManager = null;
	shipBuildManager = null;

	airTownManager = null;
	airRouteManager = null;
	airBuildManager = null;

	sentToDepotAirGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	sentToDepotWaterGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];

	loading = null;
	loadData = null;
	buildTimerRoad = 0;
	buildTimerWater = 0;
	buildTimerAir = 0;
	reservedMoney = 0;
	reservedMoneyRoad = 0;
	reservedMoneyWater = 0;
	reservedMoneyAir = 0;

	scp = null;
	cvgs = null;

	constructor() {
		townManager = TownManager();
		shipTownManager = TownManager();
		airTownManager = TownManager();
		bestRoutesBuilt = 0; // bit 0 - Road/Passengers, bit 1 - Road/Mail, bit 2 - Water/Passengers, bit 3 - Water/Mail
		routeManager = RouteManager(this.sentToDepotRoadGroup, false);
		buildManager = BuildManager();

		cargoClassRoad = AIController.GetSetting("select_town_cargo") != 1 ? AICargo.CC_PASSENGERS : AICargo.CC_MAIL;
		cargoClassWater = cargoClassRoad;
		cargoClassAir = cargoClassRoad;


		/**
		 / 'allRoutesBuilt' and 'bestRoutesBuilt' are bits:
		 * bit 0 - Road/Passengers, bit 1 - Road/Mail
		 * bit 2 - Water/Passengers, bit 3 - Water/Mail
		 * bit 4 - Air/Passengers, bit 5 - Air/Mail
		 */
		allRoutesBuilt = 0;
		bestRoutesBuilt = 0

		shipRouteManager = ShipRouteManager(this.sentToDepotWaterGroup, false);
		shipBuildManager = ShipBuildManager();

		airRouteManager = AirRouteManager(this.sentToDepotAirGroup, false);
		airBuildManager = AirBuildManager();

		loading = true;
	}

	function Start();

	function BuildRoadRoute(cityFrom, unfinished) {
		if (unfinished || (routeManager.getRoadVehicleCount() < MAX_TOWN_VEHICLES - 10) && ((allRoutesBuilt >> 0) & 3) != 3) {

			local cityTo = null;
			local articulated;
			local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRoad : (!unfinished ? cargoClassRoad : (cargoClassRoad == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
			if (!unfinished) {
				cargoClassRoad = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRoad : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

				local cargo = Utils.getCargoId(cC);
				local tempList = AIEngineList(AIVehicle.VT_ROAD);
				local engineList = AIList();
				for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
					if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.GetRoadType(engine) == AIRoad.ROADTYPE_ROAD && AIEngine.CanRefitCargo(engine, cargo)) {
						engineList.AddItem(engine, AIEngine.GetPrice(engine));
					}
				}

				if (engineList.Count() == 0) {
//					cargoClassRoad = cC;
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
				if (!Utils.HasMoney(estimated_costs + reservedMoney - reservedMoneyRoad)) {
//					cargoClassRoad = cC;
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
					cityFrom = townManager.getUnusedCity(((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
					if (cityFrom == null) {
						if (AIController.GetSetting("pick_mode") == 1) {
							if (cC == AICargo.CC_PASSENGERS) {
								townManager.m_usedCitiesPassTable.clear();
							} else {
								townManager.m_usedCitiesMailTable.clear();
							}
						} else {
							if ((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								bestRoutesBuilt = bestRoutesBuilt | (1 << (0 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
								if (cC == AICargo.CC_PASSENGERS) {
									townManager.m_usedCitiesPassTable.clear();
								} else {
									townManager.m_usedCitiesMailTable.clear();
								}
//								townManager.ClearCargoClassArray(cC);
								AILog.Warning("Best " + AICargo.GetCargoLabel(cargo) + " road routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
							} else {
//								townManager.ClearCargoClassArray(cC);
								if ((((allRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
									AILog.Warning("All " + AICargo.GetCargoLabel(cargo) + " road routes have been used!");
								}
								allRoutesBuilt = allRoutesBuilt | (1 << (0 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							}
						}
					}
				}

				if (cityFrom != null) {
//					AILog.Info("New city found: " + AITown.GetName(cityFrom));

					townManager.findNearCities(cityFrom, min_dist, max_dist, ((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);

					if (!townManager.HasArrayCargoClassPairs(cC)) {
						AILog.Info("No near city available");
						cityFrom = null;
					}
				}

				if (cityFrom != null) {
					for (local i = 0; i < townManager.m_nearCityPairArray.len(); ++i) {
						if (cityFrom == townManager.m_cityFrom(townManager.m_nearCityPairArray[i]) && cC == townManager.m_cargoClass(townManager.m_nearCityPairArray[i])) {
							if (!routeManager.townRouteExists(cityFrom, townManager.m_cityTo(townManager.m_nearCityPairArray[i]), cC)) {
								cityTo = townManager.m_cityTo(townManager.m_nearCityPairArray[i]);

								if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && routeManager.hasMaxStationCount(cityFrom, cityTo, cC)) {
//									AILog.Info("routeManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + routeManager.hasMaxStationCount(cityFrom, cityTo, cC));
									cityTo = null;
									continue;
								} else {
//									AILog.Info("routeManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + routeManager.hasMaxStationCount(cityFrom, cityTo, cC));
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
				local from = unfinished ? buildManager.m_cityFrom : cityFrom;
				local to = unfinished ? buildManager.m_cityTo : cityTo;
				local cargoC = unfinished ? buildManager.m_cargoClass : cC;
				local artic = unfinished ? buildManager.m_articulated : articulated;
				local best_routes = unfinished ? buildManager.m_best_routes_built : ((((bestRoutesBuilt >> 0) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

				local start_date = AIDate.GetCurrentDate();
				local routeResult = routeManager.buildRoute(buildManager, from, to, cargoC, artic, best_routes);
				buildTimerRoad += AIDate.GetCurrentDate() - start_date;
				if (routeResult[0] != null) {
					if (routeResult[0] != 0) {
						reservedMoney -= reservedMoneyRoad;
						reservedMoneyRoad = 0;
						AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.getCargoId(cargoC)) + " road route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerRoad + " day" + (buildTimerRoad != 1 ? "s" : "") + ".");
					}
				} else {
					reservedMoney -= reservedMoneyRoad;
					reservedMoneyRoad = 0;
					townManager.removeUsedCityPair(from, to, cC, false);
					AILog.Error("r:" + buildTimerRoad + " day" + (buildTimerRoad != 1 ? "s" : "") + " wasted!");
				}

				// cityFrom = cityTo; // use this line to look for a new town from the last town
				cityFrom = null;
			}
		}
	}

	function BuildWaterRoute(cityFrom, unfinished) {
		if (unfinished || (shipRouteManager.getShipCount() < MAX_SHIP_VEHICLES - 10) && ((allRoutesBuilt >> 2) & 3) != 3) {

			local cityTo = null;
			local cheaper_route = false;
			local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassWater : (!unfinished ? cargoClassWater : (cargoClassWater == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
			if (!unfinished) {
				cargoClassWater = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassWater : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

				local cargo = Utils.getCargoId(cC);
				local tempList = AIEngineList(AIVehicle.VT_WATER);
				local engineList = AIList();
				for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
					if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo)) {
						engineList.AddItem(engine, AIEngine.GetPrice(engine));
					}
				}

				if (engineList.Count() == 0) {
//					cargoClassWater = cC;
					return;
				}

				engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

				local bestengineinfo = WrightAI.GetBestEngineIncome(engineList, cargo, ShipRoute.COUNT_INTERVAL, false);
				local max_distance = (DAYS_IN_SEA_TRANSIT * 2 * 74 * AIEngine.GetMaxSpeed(bestengineinfo[0])) / (256 * 16);
				local min_distance = max(20, max_distance * 2 / 3);
//				AILog.Info("bestengineinfo: best_engine = " + AIEngine.GetName(bestengineinfo[0]) + "; best_distance = " + bestengineinfo[1] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

				local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
				local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
				local max_dist = min_dist + MAX_DISTANCE_INCREASE > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//				AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

				local estimated_costs = 0;
				local engine_costs = AIEngine.GetPrice(engineList.Begin());
				local canal_costs = AIMarine.GetBuildCost(AIMarine.BT_CANAL) * 2 * max_dist;
				local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
				local dock_costs = AIMarine.GetBuildCost(AIMarine.BT_DOCK) * 2;
				local depot_cost = AIMarine.GetBuildCost(AIMarine.BT_DEPOT);
				local buoy_costs = AIMarine.GetBuildCost(AIMarine.BT_BUOY) * max_dist / ShipBuildManager.COUNT_BETWEEN_BUOYS;
				estimated_costs += engine_costs + canal_costs + clear_costs + dock_costs + depot_cost + buoy_costs;
//				AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", canal_costs = " + canal_costs + ", clear_costs = " + clear_costs + ", dock_costs = " + dock_costs + ", depot_cost = " + depot_cost + ", buoy_costs = " + buoy_costs);
				if (!Utils.HasMoney(estimated_costs + reservedMoney - reservedMoneyWater)) {
					/* Try a cheaper route */
					if ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 1 || !Utils.HasMoney(estimated_costs - canal_costs - clear_costs + reservedMoney - reservedMoneyWater)) {
//						cargoClassWater = cC;
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
					cityFrom = shipTownManager.getUnusedCity(((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
					if (cityFrom == null) {
						if (AIController.GetSetting("pick_mode") == 1) {
							if (cC == AICargo.CC_PASSENGERS) {
								shipTownManager.m_usedCitiesPassTable.clear();
							} else {
								shipTownManager.m_usedCitiesMailTable.clear();
							}
						} else {
							if ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								bestRoutesBuilt = bestRoutesBuilt | (1 << (2 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
								if (cC == AICargo.CC_PASSENGERS) {
									shipTownManager.m_usedCitiesPassTable.clear();
								} else {
									shipTownManager.m_usedCitiesMailTable.clear();
								}
//								shipTownManager.ClearCargoClassArray(cC);
								AILog.Warning("Best " + AICargo.GetCargoLabel(cargo) + " water routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
							} else {
//								shipTownManager.ClearCargoClassArray(cC);
								if ((((allRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
									AILog.Warning("All " + AICargo.GetCargoLabel(cargo) + " water routes have been used!");
								}
								allRoutesBuilt = allRoutesBuilt | (1 << (2 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							}
						}
					}
				}

				if (cityFrom != null) {
//					AILog.Info("New city found: " + AITown.GetName(cityFrom));

					shipTownManager.findNearCities(cityFrom, min_dist, max_dist, ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);

					if (!shipTownManager.HasArrayCargoClassPairs(cC)) {
						AILog.Info("No near city available");
						cityFrom = null;
					}
				}

				if (cityFrom != null) {
					for (local i = 0; i < shipTownManager.m_nearCityPairArray.len(); ++i) {
						if (cityFrom == shipTownManager.m_cityFrom(shipTownManager.m_nearCityPairArray[i]) && cC == shipTownManager.m_cargoClass(shipTownManager.m_nearCityPairArray[i])) {
							if (!shipRouteManager.townRouteExists(cityFrom, shipTownManager.m_cityTo(shipTownManager.m_nearCityPairArray[i]), cC)) {
								cityTo = shipTownManager.m_cityTo(shipTownManager.m_nearCityPairArray[i]);

								if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && shipRouteManager.hasMaxStationCount(cityFrom, cityTo, cC)) {
//									AILog.Info("shipRouteManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + shipRouteManager.hasMaxStationCount(cityFrom, cityTo, cC));
									cityTo = null;
									continue;
								} else {
//									AILog.Info("shipRouteManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + shipRouteManager.hasMaxStationCount(cityFrom, cityTo, cC));
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
					AILog.Info("c:New city found: " + AITown.GetName(cityFrom));
					AILog.Info("c:New near city found: " + AITown.GetName(cityTo));
				}

				if (!unfinished) buildTimerWater = 0;
				local from = unfinished ? shipBuildManager.m_cityFrom : cityFrom;
				local to = unfinished ? shipBuildManager.m_cityTo : cityTo;
				local cargoC = unfinished ? shipBuildManager.m_cargoClass : cC;
				local cheaper = unfinished ? shipBuildManager.m_cheaperRoute : cheaper_route;
				local best_routes = unfinished ? shipBuildManager.m_best_routes_built : ((((bestRoutesBuilt >> 2) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

				local start_date = AIDate.GetCurrentDate();
				local routeResult = shipRouteManager.buildRoute(shipBuildManager, from, to, cargoC, cheaper, best_routes);
				buildTimerWater += AIDate.GetCurrentDate() - start_date;
				if (routeResult[0] != null) {
					if (routeResult[0] != 0) {
						reservedMoney -= reservedMoneyWater;
						reservedMoneyWater = 0;
						AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.getCargoId(cargoC)) + " water route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerWater + " day" + (buildTimerWater != 1 ? "s" : "") + ".");
					}
				} else {
					reservedMoney -= reservedMoneyWater;
					reservedMoneyWater = 0;
					shipTownManager.removeUsedCityPair(from, to, cC, false);
					AILog.Error("c:" + buildTimerWater + " day" + (buildTimerWater != 1 ? "s" : "") + " wasted!");
				}

				// cityFrom = cityTo; // use this line to look for a new town from the last town
				cityFrom = null;
			}
		}
	}

	function BuildAirRoute(cityFrom, unfinished) {
		if (unfinished || (airRouteManager.getAircraftCount() < MAX_AIR_VEHICLES - 10) && ((allRoutesBuilt >> 4) & 3) != 3) {

			local cityTo = null;
			local cC = cargoClassAir;
			if (!unfinished) {

				local cargo = Utils.getCargoId(cC);

				local tempList = AIEngineList(AIVehicle.VT_AIR);
				local engineList = AIList();
				for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
					if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo)) {
						engineList.AddItem(engine, AIEngine.GetPrice(engine));
					}
				}

				if (engineList.Count() == 0) {
					return;
				}

				engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

//				local bestengineinfo = WrightAI.GetBestEngineIncome(engineList, cargo, AirBuildManager.DAYS_INTERVAL);
//				if (bestengineinfo[0] == null) {
//					return;
//				}

//				local fakedist = bestengineinfo[1];
//				local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");

//				local max_order_dist = WrightAI.GetMaximumOrderDistance(bestengineinfo[0]);
//				local max_dist = max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : max_order_dist;
//				local min_order_dist = (fakedist / 2) * (fakedist / 2);
//				local min_dist = min_order_dist > max_dist * 3 / 4 ? !infrastructure && max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : max_dist * 3 / 4 : min_order_dist;

				if (cityFrom == null) {
					cityFrom = airTownManager.getUnusedCity(((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
					if (cityFrom == null) {
						if (AIController.GetSetting("pick_mode") == 1) {
							if (cC == AICargo.CC_PASSENGERS) {
								airTownManager.m_usedCitiesPassTable.clear();
							} else {
								airTownManager.m_usedCitiesMailTable.clear();
							}
						} else {
							if ((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								bestRoutesBuilt = bestRoutesBuilt | (1 << (4 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
								if (cC == AICargo.CC_PASSENGERS) {
									airTownManager.m_usedCitiesPassTable.clear();
								} else {
									airTownManager.m_usedCitiesMailTable.clear();
								}
//								airTownManager.ClearCargoClassArray(cC);
								AILog.Warning("Best " + AICargo.GetCargoLabel(cargo) + " air routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
							} else {
//								airTownManager.ClearCargoClassArray(cC);
								if ((((allRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
									AILog.Warning("All " + AICargo.GetCargoLabel(cargo) + " air routes have been used!");
								}
								allRoutesBuilt = allRoutesBuilt | (1 << (4 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							}
						}
					}
				}

//				if (cityFrom != null) {
//					AILog.Info("New city found: " + AITown.GetName(cityFrom));

//					airTownManager.findNearCities(cityFrom, min_dist, max_dist, ((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC, fakedist);

//					if (!airTownManager.HasArrayCargoClassPairs(cC)) {
//						AILog.Info("No near city available");
//						cityFrom = null;
//					}
//				}

//				if (cityFrom != null) {
//					for (local i = 0; i < airTownManager.m_nearCityPairArray.len(); ++i) {
//						if (cityFrom == airTownManager.m_cityFrom(airTownManager.m_nearCityPairArray[i]) && cC == airTownManager.m_cargoClass(airTownManager.m_nearCityPairArray[i])) {
//							if (!airRouteManager.townRouteExists(cityFrom, airTownManager.m_cityTo(airTownManager.m_nearCityPairArray[i]), cC)) {
//								cityTo = airTownManager.m_cityTo(airTownManager.m_nearCityPairArray[i]);

//								if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && airRouteManager.hasMaxStationCount(cityFrom, cityTo, cC)) {
//									AILog.Info("airRouteManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + airRouteManager.hasMaxStationCount(cityFrom, cityTo, cC));
//									cityTo = null;
//									continue;
//								} else {
//									AILog.Info("airRouteManager.hasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + airRouteManager.hasMaxStationCount(cityFrom, cityTo, cC));
//									break;
//								}
//							}
//						}
//					}

//					if (cityTo == null) {
//						cityFrom = null;
//					}
//				}

//				if (cityFrom == null && cityTo == null) {
//					reservedMoney -= reservedMoneyAir;
//					reservedMoneyAir = 0;
//				}
			} else {
				if (!Utils.HasMoney(reservedMoneyAir)) {
					return;
				}
			}

			if (unfinished || cityFrom != null/* && cityTo != null*/) {
				if (!unfinished) {
//					AILog.Info("New city found: " + AITown.GetName(cityFrom));
//					AILog.Info("New near city found: " + AITown.GetName(cityTo));
				}

				if (!unfinished) buildTimerAir = 0;
				local from = unfinished ? airBuildManager.m_cityFrom : cityFrom;
				local to = unfinished ? airBuildManager.m_cityTo : cityTo;
				local cargoC = unfinished ? airBuildManager.m_cargoClass : cC;
				local best_routes = unfinished ? airBuildManager.m_best_routes_built : ((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);
				local all_routes = (((allRoutesBuilt >> 4) & 3) & (1 << (cargoC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0;

				local start_date = AIDate.GetCurrentDate();
				local routeResult = airRouteManager.buildRoute(airRouteManager, airBuildManager, airTownManager, from, to, cargoC, best_routes, all_routes);
				buildTimerAir += AIDate.GetCurrentDate() - start_date;
				if (routeResult[0] != null) {
					if (routeResult[0] != 0) {
						reservedMoney -= reservedMoneyAir;
						reservedMoneyAir = 0;
						AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.getCargoId(cargoC)) + " air route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerAir + " day" + (buildTimerAir != 1 ? "s" : "") + ".");
					}
				} else {
					reservedMoney -= reservedMoneyAir;
					reservedMoneyAir = 0;
					if (to != null) airTownManager.removeUsedCityPair(from, to, cC, false);
					AILog.Error("a:" + buildTimerAir + " day" + (buildTimerAir != 1 ? "s" : "") + " wasted!");
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
		local toclearList = AIList();
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
				else if (AIMarine.IsDockTile(tile)) {
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
				else if (AIAirport.IsAirportTile(tile)) {
					if (TestRemoveAirport().TryRemove(tile)) {
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
		scheduledRemovals.AddList(toclearList);
	}

	function ResetRoadManagementVariables() {
		if (lastRoadManagedArray < 0) lastRoadManagedArray = routeManager.m_townRouteArray.len() - 1;
		if (lastRoadManagedManagement < 0) lastRoadManagedManagement = 8;
	}

	function InterruptRoadManagement(cur_date) {
		if (AIDate.GetCurrentDate() - cur_date > 1) {
			if (lastRoadManagedArray == -1) lastRoadManagedManagement--;
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
		ResetRoadManagementVariables();

//		for (local i = lastRoadManagedArray; i >= 0; --i) {
//			if (lastRoadManagedManagement != 9) break;
//			lastRoadManagedArray--;
//			AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(routeManager.m_townRouteArray[i].m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(routeManager.m_townRouteArray[i].m_stationTo)));
//			if (InterruptRoadManagement(cur_date)) return;
//		}
//		ResetRoadManagementVariables();
//		if (lastRoadManagedManagement == 9) lastRoadManagedManagement--;
//
//		local start_tick = AIController.GetTick();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 8) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". renewVehicles");
			routeManager.m_townRouteArray[i].renewVehicles();
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 8) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 7) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". sendNegativeProfitVehiclesToDepot");
			routeManager.m_townRouteArray[i].sendNegativeProfitVehiclesToDepot();
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 7) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		local num_vehs = routeManager.getRoadVehicleCount();
		local maxAllRoutesProfit = routeManager.highestProfitLastYear();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 6) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". sendLowProfitVehiclesToDepot");
			if (MAX_TOWN_VEHICLES * 0.95 < num_vehs) {
				routeManager.m_townRouteArray[i].sendLowProfitVehiclesToDepot(maxAllRoutesProfit);
			}
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 6) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 5) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". updateEngine");
			routeManager.m_townRouteArray[i].updateEngine();
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 5) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 4) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". sellVehiclesInDepot");
			routeManager.m_townRouteArray[i].sellVehiclesInDepot();
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 4) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 3) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". updateBridges")
			routeManager.m_townRouteArray[i].updateBridges();
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 3) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = routeManager.getRoadVehicleCount();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 2) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". addremoveVehicleToRoute");
			if (num_vehs < MAX_TOWN_VEHICLES) {
				num_vehs += routeManager.m_townRouteArray[i].addremoveVehicleToRoute(num_vehs < MAX_TOWN_VEHICLES);
			}
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 2) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = routeManager.getRoadVehicleCount();
		if (AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations")) {
			for (local i = lastRoadManagedArray; i >= 0; --i) {
				if (lastRoadManagedManagement != 1) break;
				lastRoadManagedArray--;
//				AILog.Info("managing route " + i + ". expandStations");
				if (MAX_TOWN_VEHICLES > num_vehs) {
					routeManager.m_townRouteArray[i].expandStations();
				}
				if (InterruptRoadManagement(cur_date)) return;
			}
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 1) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastRoadManagedArray; i >= 0; --i) {
			if (lastRoadManagedManagement != 0) break;
			lastRoadManagedArray--;
//			AILog.Info("managing route " + i + ". removeIfUnserviced");
			local cityFrom = routeManager.m_townRouteArray[i].m_cityFrom;
			local cityTo = routeManager.m_townRouteArray[i].m_cityTo;
			local cargoC = routeManager.m_townRouteArray[i].m_cargoClass;
			if (routeManager.m_townRouteArray[i].removeIfUnserviced()) {
				routeManager.m_townRouteArray.remove(i);
				townManager.removeUsedCityPair(cityFrom, cityTo, cargoC, true);
			}
			if (InterruptRoadManagement(cur_date)) return;
		}
		ResetRoadManagementVariables();
		if (lastRoadManagedManagement == 0) lastRoadManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + routeManager.m_townRouteArray.len() + " road route" + (routeManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}

	function ResetWaterManagementVariables() {
		if (lastWaterManagedArray < 0) lastWaterManagedArray = shipRouteManager.m_townRouteArray.len() - 1;
		if (lastWaterManagedManagement < 0) lastWaterManagedManagement = 6;
	}

	function InterruptWaterManagement(cur_date) {
		if (AIDate.GetCurrentDate() - cur_date > 1) {
			if (lastWaterManagedArray == -1) lastWaterManagedManagement--;
			return true;
		}
		return false;
	}

	function updateShipVehicles() {
		local max_ships = AIGameSettings.GetValue("max_ships");
		if (max_ships != MAX_SHIP_VEHICLES) {
			MAX_SHIP_VEHICLES = max_ships;
			AILog.Info("MAX_SHIP_VEHICLES = " + MAX_SHIP_VEHICLES);
		}

		local cur_date = AIDate.GetCurrentDate();
		ResetWaterManagementVariables();

//		for (local i = lastWaterManagedArray; i >= 0; --i) {
//			if (lastWaterManagedManagement != 7) break;
//			lastWaterManagedArray--;
//			AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(shipRouteManager.m_townRouteArray[i].m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(shipRouteManager.m_townRouteArray[i].m_dockTo)));
//			if (InterruptWaterManagement(cur_date)) return;
//		}
//		ResetWaterManagementVariables();
//		if (lastWaterManagedManagement == 7) lastWaterManagedManagement--;
//
//		local start_tick = AIController.GetTick();
		for (local i = lastWaterManagedArray; i >= 0; --i) {
			if (lastWaterManagedManagement != 6) break;
			lastWaterManagedArray--;
//			AILog.Info("managing route " + i + ". renewVehicles");
			shipRouteManager.m_townRouteArray[i].renewVehicles();
			if (InterruptWaterManagement(cur_date)) return;
		}
		ResetWaterManagementVariables();
		if (lastWaterManagedManagement == 6) lastWaterManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastWaterManagedArray; i >= 0; --i) {
			if (lastWaterManagedManagement != 5) break;
			lastWaterManagedArray--;
//			AILog.Info("managing route " + i + ". sendNegativeProfitVehiclesToDepot");
			shipRouteManager.m_townRouteArray[i].sendNegativeProfitVehiclesToDepot();
			if (InterruptWaterManagement(cur_date)) return;
		}
		ResetWaterManagementVariables();
		if (lastWaterManagedManagement == 5) lastWaterManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		local num_vehs = shipRouteManager.getShipCount();
		local maxAllRoutesProfit = shipRouteManager.highestProfitLastYear();
		for (local i = lastWaterManagedArray; i >= 0; --i) {
			if (lastWaterManagedManagement != 4) break;
			lastWaterManagedArray--;
//			AILog.Info("managing route " + i + ". sendLowProfitVehiclesToDepot");
			if (MAX_SHIP_VEHICLES * 0.95 < num_vehs) {
				shipRouteManager.m_townRouteArray[i].sendLowProfitVehiclesToDepot(maxAllRoutesProfit);
			}
			if (InterruptWaterManagement(cur_date)) return;
		}
		ResetWaterManagementVariables();
		if (lastWaterManagedManagement == 4) lastWaterManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastWaterManagedArray; i >= 0; --i) {
			if (lastWaterManagedManagement != 3) break;
			lastWaterManagedArray--;
//			AILog.Info("managing route " + i + ". updateEngine");
			shipRouteManager.m_townRouteArray[i].updateEngine();
			if (InterruptWaterManagement(cur_date)) return;
		}
		ResetWaterManagementVariables();
		if (lastWaterManagedManagement == 3) lastWaterManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastWaterManagedArray; i >= 0; --i) {
			if (lastWaterManagedManagement != 2) break;
			lastWaterManagedArray--;
//			AILog.Info("managing route " + i + ". sellVehiclesInDepot");
			shipRouteManager.m_townRouteArray[i].sellVehiclesInDepot();
			if (InterruptWaterManagement(cur_date)) return;
		}
		ResetWaterManagementVariables();
		if (lastWaterManagedManagement == 2) lastWaterManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = shipRouteManager.getShipCount();
		for (local i = lastWaterManagedArray; i >= 0; --i) {
			if (lastWaterManagedManagement != 1) break;
			lastWaterManagedArray--;
//			AILog.Info("managing route " + i + ". addremoveVehicleToRoute");
			if (num_vehs < MAX_SHIP_VEHICLES) {
				num_vehs += shipRouteManager.m_townRouteArray[i].addremoveVehicleToRoute(num_vehs < MAX_SHIP_VEHICLES);
			}
			if (InterruptWaterManagement(cur_date)) return;
		}
		ResetWaterManagementVariables();
		if (lastWaterManagedManagement == 1) lastWaterManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastWaterManagedArray; i >= 0; --i) {
			if (lastWaterManagedManagement != 0) break;
			lastWaterManagedArray--;
//			AILog.Info("managing route " + i + ". removeIfUnserviced");
			local cityFrom = shipRouteManager.m_townRouteArray[i].m_cityFrom;
			local cityTo = shipRouteManager.m_townRouteArray[i].m_cityTo;
			local cargoC = shipRouteManager.m_townRouteArray[i].m_cargoClass;
			if (shipRouteManager.m_townRouteArray[i].removeIfUnserviced()) {
				shipRouteManager.m_townRouteArray.remove(i);
				shipTownManager.removeUsedCityPair(cityFrom, cityTo, cargoC, true);
			}
			if (InterruptWaterManagement(cur_date)) return;
		}
		ResetWaterManagementVariables();
		if (lastWaterManagedManagement == 0) lastWaterManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + shipRouteManager.m_townRouteArray.len() + " water route" + (shipRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}

	function ResetAirManagementVariables() {
		if (lastAirManagedArray < 0) lastAirManagedArray = airRouteManager.m_townRouteArray.len() - 1;
		if (lastAirManagedManagement < 0) lastAirManagedManagement = 6;
	}

	function InterruptAirManagement(cur_date) {
		if (AIDate.GetCurrentDate() - cur_date > 1) {
			if (lastAirManagedArray == -1) lastAirManagedManagement--;
			return true;
		}
		return false;
	}

	function updateAirVehicles() {
		local max_aircraft = AIGameSettings.GetValue("max_aircraft");
		if (max_aircraft != MAX_AIR_VEHICLES) {
			MAX_AIR_VEHICLES = max_aircraft;
			AILog.Info("MAX_AIR_VEHICLES = " + MAX_AIR_VEHICLES);
		}

		local cur_date = AIDate.GetCurrentDate();
		ResetAirManagementVariables();

//		for (local i = lastAirManagedArray; i >= 0; --i) {
//			if (lastAirManagedManagement != 7) break;
//			lastAirManagedArray--;
//			AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(airRouteManager.m_townRouteArray[i].m_airportFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(airRouteManager.m_townRouteArray[i].m_airportTo)));
//			if (InterruptAirManagement(cur_date)) return;
//		}
//		ResetAirManagementVariables();
//		if (lastAirManagedManagement == 7) lastAirManagedManagement--;
//
//		local start_tick = AIController.GetTick();
		for (local i = lastAirManagedArray; i >= 0; --i) {
			if (lastAirManagedManagement != 6) break;
			lastAirManagedArray--;
//			AILog.Info("managing route " + i + ". renewVehicles");
			airRouteManager.m_townRouteArray[i].renewVehicles();
			if (InterruptAirManagement(cur_date)) return;
		}
		ResetAirManagementVariables();
		if (lastAirManagedManagement == 6) lastAirManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastAirManagedArray; i >= 0; --i) {
			if (lastAirManagedManagement != 5) break;
			lastAirManagedArray--;
//			AILog.Info("managing route " + i + ". sendNegativeProfitVehiclesToDepot");
			airRouteManager.m_townRouteArray[i].sendNegativeProfitVehiclesToDepot();
			if (InterruptAirManagement(cur_date)) return;
		}
		ResetAirManagementVariables();
		if (lastAirManagedManagement == 5) lastAirManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		local num_vehs = airRouteManager.getAircraftCount();
		local maxAllRoutesProfit = airRouteManager.highestProfitLastYear();
		for (local i = lastAirManagedArray; i >= 0; --i) {
			if (lastAirManagedManagement != 4) break;
			lastAirManagedArray--;
//			AILog.Info("managing route " + i + ". sendLowProfitVehiclesToDepot");
			if (MAX_AIR_VEHICLES * 0.95 < num_vehs) {
				airRouteManager.m_townRouteArray[i].sendLowProfitVehiclesToDepot(maxAllRoutesProfit);
			}
			if (InterruptAirManagement(cur_date)) return;
		}
		ResetAirManagementVariables();
		if (lastAirManagedManagement == 4) lastAirManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastAirManagedArray; i >= 0; --i) {
			if (lastAirManagedManagement != 3) break;
			lastAirManagedArray--;
//			AILog.Info("managing route " + i + ". updateEngine");
			airRouteManager.m_townRouteArray[i].updateEngine();
			if (InterruptAirManagement(cur_date)) return;
		}
		ResetAirManagementVariables();
		if (lastAirManagedManagement == 3) lastAirManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastAirManagedArray; i >= 0; --i) {
			if (lastAirManagedManagement != 2) break;
			lastAirManagedArray--;
//			AILog.Info("managing route " + i + ". sellVehiclesInDepot");
			airRouteManager.m_townRouteArray[i].sellVehiclesInDepot();
			if (InterruptAirManagement(cur_date)) return;
		}
		ResetAirManagementVariables();
		if (lastAirManagedManagement == 2) lastAirManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = airRouteManager.getAircraftCount();
		for (local i = lastAirManagedArray; i >= 0; --i) {
			if (lastAirManagedManagement != 1) break;
			lastAirManagedArray--;
//			AILog.Info("managing route " + i + ". addremoveVehicleToRoute");
			if (num_vehs < MAX_AIR_VEHICLES) {
				num_vehs += airRouteManager.m_townRouteArray[i].addremoveVehicleToRoute(num_vehs < MAX_AIR_VEHICLES);
			}
			if (InterruptAirManagement(cur_date)) return;
		}
		ResetAirManagementVariables();
		if (lastAirManagedManagement == 1) lastAirManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = lastAirManagedArray; i >= 0; --i) {
			if (lastAirManagedManagement != 0) break;
			lastAirManagedArray--;
//			AILog.Info("managing route " + i + ". removeIfUnserviced");
			local cityFrom = airRouteManager.m_townRouteArray[i].m_cityFrom;
			local cityTo = airRouteManager.m_townRouteArray[i].m_cityTo;
			local cargoC = airRouteManager.m_townRouteArray[i].m_cargoClass;
			if (airRouteManager.m_townRouteArray[i].removeIfUnserviced()) {
				airRouteManager.m_townRouteArray.remove(i);
				airTownManager.removeUsedCityPair(cityFrom, cityTo, cargoC, true);
			}
			if (InterruptAirManagement(cur_date)) return;
		}
		ResetAirManagementVariables();
		if (lastAirManagedManagement == 0) lastAirManagedManagement--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}


	function PerformTownActions() {
		local myCID = Utils.MyCID();
		if (!cvgs.IsCompanyValueGSGame() || cvgs.GetCompanyIDRank(myCID) == 1) {
			if (!AIController.GetSetting("fund_buildings") && !AIController.GetSetting("build_statues") && !AIController.GetSetting("advertise")) return;

			local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassRoad : AIBase.Chance(1, 2) ? AICargo.CC_PASSENGERS : AICargo.CC_MAIL;
			local cargoId = Utils.getCargoId(cC);

			local stationList = AIStationList(AIStation.STATION_ANY);
			local stationTowns = AIList();
			local townList = AIList();
			local statuecount = 0;
			for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
				if (AIStation.HasCargoRating(st, cargoId)/* && AIVehicleList_Station(st).Count() > 0*/) { // too slow
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
			if (AIController.GetSetting("build_statues") && statuecount < towncount) {
				for (local town = townList.Begin(); !townList.IsEnd(); town = townList.Next()) {
					local action = AITown.TOWN_ACTION_BUILD_STATUE;
					if (AITown.IsActionAvailable(town, action)) {
						local perform_action = true;
						local cost = TestPerformTownAction().TestCost(town, action);
						if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
							perform_action = false;
						}
						if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.RankingList().Count() > 1) {
							if (cvgs.GetCompanyIDRank(myCID) != 1) {
								perform_action = false;
							}
							if (perform_action) {
//								AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
								if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
									perform_action = false;
								}
							}
						}
						if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
							statuecount++;
							AILog.Warning("Built a statue in " + AITown.GetName(town) + " (" + statuecount + "/" + towncount + " " + AICargo.GetCargoLabel(cargoId) + ")");
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
								if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
									perform_action = false;
								}
								if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.RankingList().Count() > 1) {
									if (cvgs.GetCompanyIDRank(myCID) != 1) {
										perform_action = false;
									}
									if (perform_action) {
//										AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
										if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
											perform_action = false;
										}
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
								if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.RankingList().Count() > 1) {
									if (cvgs.GetCompanyIDRank(myCID) != 1) {
										perform_action = false;
									}
									if (perform_action) {
//										AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
										if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
											perform_action = false;
										}
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
								if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.RankingList().Count() > 1) {
									if (cvgs.GetCompanyIDRank(myCID) != 1) {
										perform_action = false;
									}
									if (perform_action) {
//										AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
										if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
											perform_action = false;
										}
									}
								}
								if (perform_action && TestPerformTownAction().TryPerform(town, action)) {
									AILog.Warning("Initiated a large advertising campaign in " + AITown.GetName(town) + ".");
								}
							}
						}
					}

					if (AIController.GetSetting("fund_buildings") && AITown.GetLastMonthProduction(town, cargoId) <= (cC == AICargo.CC_PASSENGERS ? 70 : 35)) {
						local action = AITown.TOWN_ACTION_FUND_BUILDINGS;
						if (AITown.IsActionAvailable(town, action) && AITown.GetFundBuildingsDuration(town) == 0) {
							local perform_action = true;
							local cost = TestPerformTownAction().TestCost(town, action);
							if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(myCID) <= cost) {
								perform_action = false;
							}
							if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.RankingList().Count() > 1) {
								if (cvgs.GetCompanyIDRank(myCID) != 1) {
									perform_action = false;
								}
								if (perform_action) {
//									AILog.Info("Cost of performing action: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
									if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
										perform_action = false;
									}
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
		if (!AIController.GetSetting("build_hq")) return;

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
		if (!AIController.GetSetting("found_towns")) return;

		if (!cvgs.IsCompanyValueGSGame() || cvgs.IsCompanyValueGSInRankingMode() && cvgs.GetCompanyIDRank(Utils.MyCID()) == 1) {
			local town_tile = AIBase.RandRange(AIMap.GetMapSize());
			if (AIMap.IsValidTile(town_tile) && AITile.IsBuildable(town_tile) && AITile.GetSlope(town_tile) == AITile.SLOPE_FLAT) {
				local perform_action = true;
				local cost = TestFoundTown().TestCost(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null);
				if (cost == 0 || AICompany.GetLoanAmount() != 0 || AICompany.GetBankBalance(Utils.MyCID()) <= cost) {
					perform_action = false;
				}
				if (perform_action && cvgs.IsCompanyValueGSGame() && cvgs.RankingList().Count() > 1) {
					if (cvgs.GetCompanyIDRank(myCID) != 1) {
						perform_action = false;
					}
					if (perform_action) {
//						AILog.Info("Cost of founding town: " + cost + " ; Value difference to company behind: " + cvgs.GetCompanyIDDiffToNext(myCID, false));
						if (cost > cvgs.GetCompanyIDDiffToNext(myCID, false)) {
							perform_action = false;
						}
					}
				}
				if (perform_action && TestFoundTown().TryFound(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null)) {
					AILog.Warning("Founded town " + AITown.GetName(AITile.GetTownAuthority(town_tile)) + ".");
					if (allRoutesBuilt != 0) {
						allRoutesBuilt = 0;
//						townManager.m_nearCityPairArray = [];
						townManager.m_usedCitiesPassTable.clear();
						townManager.m_usedCitiesMailTable.clear();
//						shipTownManager.m_nearCityPairArray = [];
						shipTownManager.m_usedCitiesPassTable.clear();
						shipTownManager.m_usedCitiesMailTable.clear();
//						airTownManager.m_nearCityPairArray = [];
						airTownManager.m_usedCitiesPassTable.clear();
						airTownManager.m_usedCitiesMailTable.clear();
						AILog.Warning("Not all routes have been used at this time.");
					}
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
		table.rawset("town_manager", townManager.saveTownManager());
		table.rawset("route_manager", routeManager.saveRouteManager());
		table.rawset("build_manager", buildManager.saveBuildManager());

		table.rawset("ship_town_manager", shipTownManager.saveTownManager());
		table.rawset("ship_route_manager", shipRouteManager.saveRouteManager());
		table.rawset("ship_build_manager", shipBuildManager.saveBuildManager());

		table.rawset("air_town_manager", airTownManager.saveTownManager());
		table.rawset("air_route_manager", airRouteManager.saveRouteManager());
		table.rawset("air_build_manager", airBuildManager.saveBuildManager());

		local scheduledRemovalsTable = {};
		for (local tile = scheduledRemovals.Begin(), i = 0; !scheduledRemovals.IsEnd(); tile = scheduledRemovals.Next(), ++i) {
			scheduledRemovalsTable.rawset(i, [tile, scheduledRemovals.GetValue(tile)]);
		}
		table.rawset("scheduled_removes", scheduledRemovalsTable);

		table.rawset("best_routes_built", bestRoutesBuilt);
		table.rawset("all_routes_built", allRoutesBuilt);

		table.rawset("sent_to_depot_air_group", sentToDepotAirGroup);
		table.rawset("sent_to_depot_road_group", sentToDepotRoadGroup);
		table.rawset("sent_to_depot_water_group", sentToDepotWaterGroup);

		table.rawset("last_road_managed_array", lastRoadManagedArray);
		table.rawset("last_road_managed_management", lastRoadManagedManagement);

		table.rawset("last_water_managed_array", lastWaterManagedArray);
		table.rawset("last_water_managed_management", lastWaterManagedManagement);

		table.rawset("last_air_managed_array", lastAirManagedArray);
		table.rawset("last_air_managed_management", lastAirManagedManagement);

		table.rawset("reserved_money", reservedMoney);
		table.rawset("reserved_money_road", reservedMoneyRoad);
		table.rawset("reserved_money_water", reservedMoneyWater);
		table.rawset("reserved_money_air", reservedMoneyAir);

		table.rawset("cargo_class_road", cargoClassRoad);
		table.rawset("cargo_class_water", cargoClassWater);
		table.rawset("cargo_class_air", cargoClassAir);

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
	if (AICompany.GetAutoRenewStatus(Utils.MyCID())) AICompany.SetAutoRenewStatus(false);

	if (loading) {
		if (loadData == null) {
			for (local i = 0; i < sentToDepotAirGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotAirGroup[i])) {
					sentToDepotAirGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_AIR, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotAirGroup[i], "0: Aircraft to sell");
					if (i == 1) AIGroup.SetName(sentToDepotAirGroup[i], "1: Aircraft to renew");
					airRouteManager.m_sentToDepotAirGroup[i] = sentToDepotAirGroup[i];
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

			for (local i = 0; i < sentToDepotWaterGroup.len(); ++i) {
				if (!AIGroup.IsValidGroup(sentToDepotWaterGroup[i])) {
					sentToDepotWaterGroup[i] = AIGroup.CreateGroup(AIVehicle.VT_WATER, AIGroup.GROUP_INVALID);
					if (i == 0) AIGroup.SetName(sentToDepotWaterGroup[i], "0: Ships to sell");
					if (i == 1) AIGroup.SetName(sentToDepotWaterGroup[i], "1: Ships to renew");
					shipRouteManager.m_sentToDepotWaterGroup[i] = sentToDepotWaterGroup[i];
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

			if (loadData[1].rawin("ship_town_manager")) {
				shipTownManager.loadTownManager(loadData[1].rawget("ship_town_manager"));
			}

			if (loadData[1].rawin("ship_route_manager")) {
				shipRouteManager.loadRouteManager(loadData[1].rawget("ship_route_manager"));
			}

			if (loadData[1].rawin("ship_build_manager")) {
				shipBuildManager.loadBuildManager(loadData[1].rawget("ship_build_manager"));
			}

			if (loadData[1].rawin("air_town_manager")) {
				airTownManager.loadTownManager(loadData[1].rawget("air_town_manager"));
			}

			if (loadData[1].rawin("air_route_manager")) {
				airRouteManager.loadRouteManager(loadData[1].rawget("air_route_manager"));
			}

			if (loadData[1].rawin("air_build_manager")) {
				airBuildManager.loadBuildManager(loadData[1].rawget("air_build_manager"));
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

			if (loadData[1].rawin("sent_to_depot_air_group")) {
				sentToDepotAirGroup = loadData[1].rawget("sent_to_depot_air_group");
			}

			if (loadData[1].rawin("sent_to_depot_road_group")) {
				sentToDepotRoadGroup = loadData[1].rawget("sent_to_depot_road_group");
			}

			if (loadData[1].rawin("sent_to_depot_water_group")) {
				sentToDepotRoadGroup = loadData[1].rawget("sent_to_depot_water_group");
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

			if (loadData[1].rawin("cargo_class_road")) {
				cargoClassRoad = loadData[1].rawget("cargo_class_road");
			}

			if (loadData[1].rawin("cargo_class_water")) {
				cargoClassWater = loadData[1].rawget("cargo_class_water");
			}

			if (loadData[1].rawin("cargo_class_air")) {
				cargoClassAir = loadData[1].rawget("cargo_class_air");
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

			if (shipBuildManager.hasUnfinishedRoute()) {
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
//					AILog.Info("allStationsTiles has " + allStationsTiles.Count() + " tiles");
					local allTilesFound = AITileList();
					if (dockFrom != -1) allTilesFound.AddTile(dockFrom);
					for (local tile = allStationsTiles.Begin(); !allStationsTiles.IsEnd(); tile = allStationsTiles.Next()) {
						if (scheduledRemovals.HasItem(tile)) {
//							AILog.Info("scheduledRemovals has tile " + tile);
							allTilesFound.AddTile(tile);
							break;
						}
						for (local i = shipRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
							if (shipRouteManager.m_townRouteArray[i].m_dockFrom == tile || shipRouteManager.m_townRouteArray[i].m_dockTo == tile) {
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
							if (AIMarine.IsDockTile(tile) && AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
//								AILog.Info("Tile " + tile + " is missing");
								scheduledRemovals.AddItem(tile, 0);
							}
						}
					}
				}

				if (depotTile == -1) {
					local allDepotsTiles = AIDepotList(AITile.TRANSPORT_WATER);
//					AILog.Info("allDepotsTiles has " + allDepotsTiles.Count() + " tiles");
					local allTilesFound = AITileList();
					for (local tile = allDepotsTiles.Begin(); !allDepotsTiles.IsEnd(); tile = allDepotsTiles.Next()) {
						if (scheduledRemovals.HasItem(tile)) {
//							AILog.Info("scheduledRemovals has tile " + tile);
							allTilesFound.AddTile(tile);
							break;
						}
						for (local i = shipRouteManager.m_townRouteArray.len() - 1; i >= 0; --i) {
							if (shipRouteManager.m_townRouteArray[i].m_depotTile == tile) {
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
				cargostr += " " + AICargo.GetCargoLabel(Utils.getCargoId(cargoClassRoad));
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
//		AILog.Info("main loop . updateAirVehicles");
		updateAirVehicles();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("updateAirVehicles " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("air_support")) {
//			if (!AIController.GetSetting ("road_support") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD) ||
//					(routeManager.getRoadVehicleCount() > 125 || MAX_TOWN_VEHICLES <= 125 && routeManager.getRoadVehicleCount() > airRouteManager.getAircraftCount() * 4) ||
//					(AIDate.GetYear(AIDate.GetCurrentDate()) > 1955 || ((allRoutesBuilt >> 0) & 3)) ||
//					routeManager.getRoadVehicleCount() >= MAX_TOWN_VEHICLES - 10) {
//				local start_tick = AIController.GetTick();
//				AILog.Info("main loop . BuildAirRoute");
				BuildAirRoute(cityFrom, airBuildManager.hasUnfinishedRoute() ? true : false);
//				local management_ticks = AIController.GetTick() - start_tick;
//				AILog.Info("BuildAirRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
//			}
		}

//		AILog.Info("available_ticks = " + (available_ticks - used_ticks));
//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . updateShipVehicles");
		updateShipVehicles();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("updateShipVehicles " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

		if (AIController.GetSetting("water_support")) {
//			local start_tick = AIController.GetTick();
//			AILog.Info("main loop . BuildWaterRoute");
			BuildWaterRoute(cityFrom, shipBuildManager.hasUnfinishedRoute() ? true : false);
//			local management_ticks = AIController.GetTick() - start_tick;
//			AILog.Info("BuildWaterRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
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
