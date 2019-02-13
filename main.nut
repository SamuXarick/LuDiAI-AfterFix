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
	MAX_MANAGEMENT_TICKS = 2220; // 30 days

    townManager = null;
    routeManager = null;
    buildManager = null;
	scheduledRemovals = AIList();
	
	lastManaged = 0;

    cargoClass = null;

    bestRoutesBuilt = null;
    allRoutesBuilt = null;

    wrightAI = null;
	
	loading = null;
	loadData = null;
	buildTimer = 0;

    constructor() {
        townManager = TownManager();
        routeManager = RouteManager();
        buildManager = BuildManager();

        if(!AIController.GetSetting("select_town_cargo")) {
            cargoClass = AICargo.CC_PASSENGERS;
        }
        else {
            cargoClass = AICargo.CC_MAIL;
        }

        bestRoutesBuilt = false;
        allRoutesBuilt = false;

        wrightAI = WrightAI(cargoClass);
		
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
//                                  townManager.m_nearCityPairArray = [];
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

		local start_tick = AIController.GetTick();
		local managed_counter = 0;
		for (local i = (lastManaged ? lastManaged : routeManager.m_townRouteArray.len()) - 1; i >= 0; --i) {
			managed_counter++;
            AIController.Sleep(1);

//			AILog.Info("managing route " + i + ". sellVehiclesInDepot");
            routeManager.m_townRouteArray[i].sellVehiclesInDepot();
			
//			AILog.Info("managing route " + i + ". sendNegativeProfitVehiclesToDepot");
            routeManager.m_townRouteArray[i].sendNegativeProfitVehiclesToDepot();
			
//		    AILog.Info("managing route " + i + ". updateBridges")
		    routeManager.m_townRouteArray[i].updateBridges();

//          AILog.Info("managing route " + i + ". updateEngine");
            routeManager.m_townRouteArray[i].updateEngine();
				
//		    AILog.Info("managing route " + i + ". renewVehicles");
            routeManager.m_townRouteArray[i].renewVehicles();
			
            if (MAX_TOWN_VEHICLES < routeManager.getRoadVehicleCount()) {
//			    AILog.Info("managing route " + i + ". sendLowProfitVehiclesToDepot");
                routeManager.m_townRouteArray[i].sendLowProfitVehiclesToDepot(routeManager);
            }

//			AILog.Info("managing route " + i + ". addremoveVehicleToRoute");
            routeManager.m_townRouteArray[i].addremoveVehicleToRoute();

			local cityFrom = routeManager.m_townRouteArray[i].m_cityFrom;
			local cityTo = routeManager.m_townRouteArray[i].m_cityTo;
			if (MAX_TOWN_VEHICLES > routeManager.getRoadVehicleCount()) {
//			    AILog.Info("managing route " + i + ". expandStations");
                if (AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations") &&
			        routeManager.m_townRouteArray[i].expandStations()) {
//                  AILog.Info("Expanded stations in " + AITown.GetName(cityFrom) + " and " + AITown.GetName(cityTo));
                }
			}
			
//			AILog.Info("managing route " + i + ". removeIfUnserviced");
			if (routeManager.m_townRouteArray[i].removeIfUnserviced()) {
			     routeManager.m_townRouteArray.remove(i);
				 townManager.removeUsedCityPair(cityFrom, cityTo, true);
		    }
			
			local management_ticks = AIController.GetTick() - start_tick;
			if (i == 0 || MAX_MANAGEMENT_TICKS != 0 && management_ticks > MAX_MANAGEMENT_TICKS) {
//				AILog.Info("Managed " + managed_counter + " road route" + (managed_counter != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
				lastManaged = i;
				break;
			} 
        }
    }

    function BuildStatues() {
		local cargoId = Utils.getCargoId(cargoClass);

		local stationList = AIStationList(AIStation.STATION_ANY);
		stationList.Valuate(AIStation.HasCargoRating, cargoId);
		stationList.KeepValue(1);
		stationList.Valuate(AIStation.GetCargoRating, cargoId);
		stationList.KeepBelowValue(50);
		local stationTowns = AIList();
		for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
			if (AIVehicleList_Station(st).Count()) {
				stationTowns.AddItem(AIStation.GetNearestTown(st), st);
			}
		}
		for (local town = stationTowns.Begin(); !stationTowns.IsEnd(); town = stationTowns.Next()) {
			if (!AITown.HasStatue(town) && AITown.IsActionAvailable(town, AITown.TOWN_ACTION_BUILD_STATUE)) {
				if (TestBuildStatue().TryBuild(town)) {
					AILog.Warning("Built a statue in " + AITown.GetName(town) + ".");
				}
			}
		}
	}
	
	function BuildHQ() {
		if (!AIMap.IsValidTile(AICompany.GetCompanyHQ(AICompany.ResolveCompanyID(AICompany.COMPANY_SELF)))) {
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
					AITestMode() && AITile.DemolishTile(tileN) && AITile.DemolishTile(tileE) && AITile.DemolishTile(tileW) && AITile.DemolishTile(tileS)
					AIExecMode();
					if (clear_costs.GetCosts() <= AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) {
						if (TestBuildHQ().TryBuild(tileN)) {
							AILog.Warning("Built company HQ near " + AITown.GetName(AITile.GetClosestTown(tileN)) + ".");
						} else {
//							AILog.Info("Couldn't build HQ at tile " + tileN);
						}
					} else {
//						AILog.Info("Clear costs are too expensive at tile " + tileN + ": " + clear_costs.GetCosts() + " > " + (AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4) + ".");
					}
				}
			}
		}
	}

	function FoundTown() {
		local town_tile = AIBase.RandRange(AIMap.GetMapSize());
		if (AIMap.IsValidTile(town_tile) && AITile.IsBuildable(town_tile) && AITile.GetSlope(town_tile) == AITile.SLOPE_FLAT) {
			if (TestFoundTown().TryFound(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null)) {
				AILog.Warning("Found town " + AITown.GetName(AITile.GetTownAuthority(town_tile)) + ".");
				townManager.m_townList.AddItem(AITile.GetTownAuthority(town_tile), 0);
			}
		}
	}

    function Save() {
	    if (loading) {
		    AILog.Error("WARNING! AI didn't finish loading previously saved data. It will be saving partial data!")
		}
//      AILog.Warning("Saving...");

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

//      AILog.Warning("Saved!");

        return table;
    }

    function Load(version, data) {
	    loading = true;
		loadData = data;
        AILog.Warning("Loading...");
    }
}

function LuDiAIAfterFix::Start() {
	if (loading) {
        if (loadData != null) {
		    if (loadData.rawin("town_manager")) {
                townManager.loadTownManager(loadData.rawget("town_manager"));
            }

            if (loadData.rawin("route_manager")) {
                routeManager.loadRouteManager(loadData.rawget("route_manager"));
            }

            if (loadData.rawin("build_manager")) {
                buildManager.loadBuildManager(loadData.rawget("build_manager"));
            }

		    if (loadData.rawin("scheduled_removes")) {
		        local scheduledRemovalsTable = loadData.rawget("scheduled_removes");
		        local i = 0;
		        while(scheduledRemovalsTable.rawin(i)) {
		            local tile = scheduledRemovalsTable.rawget(i);
			        scheduledRemovals.AddItem(tile[0], tile[1]);
			        ++i;
			    }
		    }
		    AILog.Info("Loaded " + scheduledRemovals.Count() + " scheduled removals.");

            if (loadData.rawin("best_routes_built")) {
                bestRoutesBuilt = loadData.rawget("best_routes_built");
            }

            if (loadData.rawin("all_routes_built")) {
                allRoutesBuilt = loadData.rawget("all_routes_built");
            }

            if (loadData.rawin("wrightai")) {
                wrightAI.load(loadData.rawget("wrightai"));
            }

            AILog.Warning("Game loaded.");
			loadData = null;
		} else {
			/* Name company */
			local cargoId = Utils.getCargoId(cargoClass);
			local cargostr = AICargo.GetCargoLabel(cargoId);
			if (!AICompany.SetName("LuDiAI AfterFix " + cargostr)) {
				local i = 2;
				while (!AICompany.SetName("LuDiAI AfterFix " + cargostr + " #" + i)) {
					++i;
				}
			}
		}
		loading = false;
    }

	local cityFrom = null;
    while (AIController.Sleep(1)) {
        //pay loan
        Utils.RepayLoan();
        RemoveLeftovers();
        updateVehicles();
		if (AIController.GetSetting("road_support")) {
		    BuildRoadRoute(cityFrom, buildManager.hasUnfinishedRoute() ? true : false);
		}

        //****
        //**** WrightAI functions from Wright.nut (https://wiki.openttd.org/AI:WrightAI) with major modifications
        //****
		wrightAI.ManageAirRoutes();
        if (AIController.GetSetting("air_support")) {
            if (!AIController.GetSetting ("road_support") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD) ||
			    (routeManager.getRoadVehicleCount() > 125 || MAX_TOWN_VEHICLES <= 125 && routeManager.getRoadVehicleCount() > WrightAI.GetAircraftCount() * 4) ||
                (AIDate.GetYear(AIDate.GetCurrentDate()) > 1955 || allRoutesBuilt) ||
				routeManager.getRoadVehicleCount() >= MAX_TOWN_VEHICLES - 10) {
                wrightAI.BuildAirRoute();
            }
        }
        //****
		
		BuildStatues();
		BuildHQ();
		FoundTown();
    }
}




