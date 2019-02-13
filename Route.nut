require("RouteManager.nut");

class Route extends RouteManager {
    MIN_VEHICLE_START_COUNT = 5;
    MAX_VEHICLE_COUNT_MODE = AIController.GetSetting("road_cap_mode");
    START_VEHICLE_COUNT = 10;

    m_cityFrom = null;
    m_cityTo = null;
    m_stationFrom = null;
    m_stationTo = null;
    m_depotTile = null;
	m_bridgeTiles = null;
    m_cargoClass = null;

    m_engine = null;
    m_lastVehicleAdded = null;
    m_lastVehicleRemoved = null;

    m_sentToDepotList = null;
    m_renewList = null;

    m_activeRoute = null;
    m_expandedFromCount = null;
    m_expandedToCount = null;


    constructor(cityFrom, cityTo, stationFrom, stationTo, depotTile, bridgeTiles, cargoClass, isLoaded = 0) {
        m_cityFrom = cityFrom;
        m_cityTo = cityTo;
        m_stationFrom = stationFrom;
        m_stationTo = stationTo;
        m_depotTile = depotTile;
		m_bridgeTiles = bridgeTiles;
        m_cargoClass = cargoClass;

        m_engine = GetTruckEngine(cargoClass);

        m_lastVehicleAdded = 0;
        m_lastVehicleRemoved = AIDate.GetCurrentDate();;

        m_sentToDepotList = AIList();
        m_renewList = AIList();

        m_activeRoute = true;
        m_expandedFromCount = 0;
        m_expandedToCount = 0;

        if(!isLoaded) {
            addVehiclesToNewRoute(cargoClass);
        }
    }

	function updateBridges();
    function updateEngine();
    function addVehicle(return_vehicle);
    function addVehiclesToNewRoute(cargoClass);
    function GetEngineList(cargoClass);
    function GetTruckEngine(cargoClass);

    function GetEngineList(cargoClass) {
        local engineList = AIEngineList(AIVehicle.VT_ROAD);
		engineList.Valuate(AIEngine.IsBuildable);
		engineList.KeepValue(1);
		
        engineList.Valuate(AIEngine.GetRoadType);
        engineList.KeepValue(AIRoad.ROADTYPE_ROAD);

	    local stationType = cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;
		
	    local station1Tiles = AITileList_StationType(AIStation.GetStationID(m_stationFrom), stationType);
	    local articulated_viable = false;
	    for (local tile = station1Tiles.Begin(); !station1Tiles.IsEnd(); tile = station1Tiles.Next()) {
    	    if (AIRoad.IsDriveThroughRoadStationTile(tile)) {
// 			    AILog.Info(AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " is articulated viable!")
		        articulated_viable = true;
			    break;
		    }
	    }
		
	    if (articulated_viable) {
	        local station2Tiles = AITileList_StationType(AIStation.GetStationID(m_stationTo), stationType);
	    	articulated_viable = false;
	   		for (local tile = station2Tiles.Begin(); !station2Tiles.IsEnd(); tile = station2Tiles.Next()) {
    		    if (AIRoad.IsDriveThroughRoadStationTile(tile)) {
//			        AILog.Info(AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " is articulated viable!")
		            articulated_viable = true;
		    	    break;
	    	    }
	   		}
    	}
		
	    if (!articulated_viable) {
	        engineList.Valuate(AIEngine.IsArticulated);
	        engineList.KeepValue(0);
	    }

		local cargo = Utils.getCargoId(cargoClass);
        engineList.Valuate(AIEngine.CanRefitCargo, cargo);
        engineList.KeepValue(1);

        return engineList;
    }

    function GetTruckEngine(cargoClass) {
        local engineList = GetEngineList(cargoClass);
		if (engineList.Count() == 0) return m_engine;
		
	    if (AIGameSettings.GetValue("vehicle_breakdowns")) {
	        local reliability_list = AIList();
		    reliability_list.AddList(engineList);
	        reliability_list.Valuate(AIEngine.GetReliability);
	        reliability_list.KeepBelowValue(75);
	        if (reliability_list.Count() < engineList.Count()) {
    	        engineList.RemoveList(reliability_list);
    	    }
	    }
		
		local distance = AIMap.DistanceManhattan(m_stationFrom, m_stationTo);
        local best_income = null;
	    local best_engine = null;
        for (local engine = engineList.Begin(); !engineList.IsEnd(); engine = engineList.Next()) {
		    local max_speed = AIEngine.GetMaxSpeed(engine);
			local days_in_transit = (distance * 192 * 16) / (2 * 3 * 74 * max_speed / 4);
	        local running_cost = AIEngine.GetRunningCost(engine);
	        local capacity = AIEngine.GetCapacity(engine);
            local income = (capacity * AICargo.GetCargoIncome(Utils.getCargoId(cargoClass), distance, days_in_transit) - running_cost * days_in_transit / 365) * 365 / days_in_transit;
//			AILog.Info("Engine: " + AIEngine.GetName(engine) + "; Capacity: " + capacity + "; Max Speed: " + max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + running_cost + "; Distance: " + distance + "; Income: " + income);
		    if (best_income == null || income > best_income) {
			    best_income = income;
				best_engine = engine;
			}
	    }

        return best_engine;
    }

    function updateEngine() {
	    if (!m_activeRoute) return;

        m_engine = GetTruckEngine(m_cargoClass);
    }
	
	function updateBridges() {
	    if (!m_activeRoute) return;
		
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
	    for (local i = m_bridgeTiles.Begin(); !m_bridgeTiles.IsEnd(); i = m_bridgeTiles.Next()) {
		    local north_tile = i;
			local south_tile = m_bridgeTiles.GetValue(i);

			if (AIBridge.IsBridgeTile(north_tile) && (AIBridge.GetOtherBridgeEnd(north_tile) == south_tile)) {
			    local old_bridge = AIBridge.GetBridgeID(north_tile);

                local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(north_tile, south_tile) + 1);
                bridge_list.Valuate(AIBridge.GetMaxSpeed);
                bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
				if (bridge_list.Count() > 0) {
			        local new_bridge = bridge_list.Begin();
			        if (TestBuildBridge().TryBuild(AIVehicle.VT_ROAD, new_bridge, north_tile, south_tile)) {
			            AILog.Info("Bridge at tiles " + north_tile + " and " + south_tile + " upgraded from " + AIBridge.GetName(old_bridge) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(old_bridge)) + ") to " + AIBridge.GetName(new_bridge) + " (" + Utils.ConvertKmhishSpeedToDisplaySpeed(AIBridge.GetMaxSpeed(new_bridge)) + ")");
					}
				}
			}
		}
	}

    function addVehicle(return_vehicle = false) {
        if (MAX_VEHICLE_COUNT_MODE != 2 && AIVehicleList_Depot(this.m_depotTile).Count() >= optimalVehicleCount()) {
            return null;
        }

		if (m_engine != null && AIEngine.IsValidEngine(m_engine) && AIEngine.IsBuildable(m_engine)) {
            local vehicle = TestBuildRoadVehicle().TryBuild(this.m_depotTile, this.m_engine);
	        if (vehicle != null && TestRefitRoadVehicle().TryRefit(vehicle, Utils.getCargoId(m_cargoClass))) {
    		    if (AIOrder.AppendOrder(vehicle, m_depotTile, AIOrder.OF_SERVICE_IF_NEEDED | AIOrder.OF_NON_STOP_INTERMEDIATE) &&
						AIOrder.AppendOrder(vehicle, m_stationFrom, AIOrder.OF_NON_STOP_INTERMEDIATE) &&
						AIOrder.AppendOrder(vehicle, m_depotTile, AIOrder.OF_SERVICE_IF_NEEDED | AIOrder.OF_NON_STOP_INTERMEDIATE) &&
						AIOrder.AppendOrder(vehicle, m_stationTo, AIOrder.OF_NON_STOP_INTERMEDIATE)) {

                    AIVehicle.StartStopVehicle(vehicle);

			        m_lastVehicleAdded = AIDate.GetCurrentDate();
             		m_sentToDepotList.RemoveItem(vehicle);
		            m_renewList.RemoveItem(vehicle);

                    if (return_vehicle) {
		                return vehicle;
		            } else {
		                return 1;
		            }
	    		}
		    	else {
			        AIVehicle.SellVehicle(vehicle);
					Utils.RepayLoan();
			        return null;
			    }
            }
            else {
                return null;
            }
		}
		else {
		    return null;
		}
    }

	function optimalVehicleCount() {
		if (MAX_VEHICLE_COUNT_MODE == 0) return 25;

        local stationDistance = AITile.GetDistanceManhattanToTile(m_stationFrom, m_stationTo);
//		AILog.Info("stationDistance = " + stationDistance);
		local articulatedEngine = AIEngine.IsArticulated(this.m_engine);
		local count_interval = ((AIEngine.GetMaxSpeed(this.m_engine) * 2 * 3 * 74 * MIN_VEHICLE_START_COUNT / 4) / 192) / 16;
//		AILog.Info("count_interval = " + count_interval + "; MaxSpeed = " + AIEngine.GetMaxSpeed(this.m_engine));
		local vehicleCount = stationDistance / count_interval;
//		AILog.Info("vehicleCount = " + vehicleCount);

		local fromCount = 0;
		local fromTiles = AITileList_StationType(AIStation.GetStationID(m_stationFrom), m_cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
		for (local tile = fromTiles.Begin(); !fromTiles.IsEnd(); tile = fromTiles.Next()) {
			if (AIRoad.IsDriveThroughRoadStationTile(m_stationFrom)) {
				fromCount += articulatedEngine ? 2 : 4;
			} else {
				fromCount += articulatedEngine ? 0 : 2;
			}
		}

		local toCount = 0;
		local toTiles = AITileList_StationType(AIStation.GetStationID(m_stationTo), m_cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
		for (local tile = toTiles.Begin(); !toTiles.IsEnd(); tile = toTiles.Next()) {
			if (AIRoad.IsDriveThroughRoadStationTile(m_stationTo)) {
				toCount += articulatedEngine ? 2 : 4;
			} else {
				toCount += articulatedEngine ? 0 : 2;
			}
		}

//		AILog.Info("fromCount = " + fromCount);
//		AILog.Info("toCount = " + toCount);
		vehicleCount += 2 * (fromCount < toCount ? fromCount : toCount);
		
		return vehicleCount;
	}

    function addVehiclesToNewRoute(cargoClass) {
		local optimalVehicleCount = optimalVehicleCount();

		local numvehicles = AIVehicleList_Depot(this.m_depotTile).Count();
        if (numvehicles >= optimalVehicleCount) {
            return null;
        }
		
		local routedist = AITile.GetDistanceManhattanToTile(m_stationFrom, m_stationTo);

		local buyVehicleCount = cargoClass == AICargo.CC_PASSENGERS ? START_VEHICLE_COUNT : MIN_VEHICLE_START_COUNT;
		buyVehicleCount += MAX_VEHICLE_COUNT_MODE == 0 ? routedist / 20 : optimalVehicleCount / (cargoClass == AICargo.CC_PASSENGERS ? 2 : 4);

		if (buyVehicleCount > optimalVehicleCount - numvehicles) {
			buyVehicleCount = optimalVehicleCount - numvehicles;
		}

        local swap_m_stationFrom = m_stationFrom;
		local swap_m_stationTo = m_stationTo;
        for (local i = 0; i < buyVehicleCount; ++i) {
            if (i % 2 == 1) {
                local swap = m_stationFrom;
                m_stationFrom = m_stationTo;
                m_stationTo = swap;
            }

            if (addVehicle()) {
				local numvehicles = AIVehicleList_Depot(this.m_depotTile).Count();
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + "! (" + numvehicles + "/" + optimalVehicleCount + " road vehicle" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
            }
        }
		if (AIVehicleList_Depot(this.m_depotTile).Count() < (MAX_VEHICLE_COUNT_MODE == 0 ? 1 : optimalVehicleCount)) {
		    m_lastVehicleAdded = 0;
		}

        //swap back
        m_stationFrom = swap_m_stationFrom;
        m_stationTo = swap_m_stationTo;
    }

    function sendVehicleToDepot(vehicle) {
        if ((!m_sentToDepotList.HasItem(vehicle)) && (!m_renewList.HasItem(vehicle)) && AIVehicle.GetState(vehicle) != AIVehicle.VS_CRASHED) {

            AIVehicle.SendVehicleToDepot(vehicle);

            m_lastVehicleRemoved = AIDate.GetCurrentDate();

            AIOrder.SetOrderFlags(vehicle, 0, AIOrder.OF_STOP_IN_DEPOT | AIOrder.OF_NON_STOP_INTERMEDIATE);

            AILog.Info(AIVehicle.GetName(vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " has been sent to its depot!");

            return 1;
        }

        return 0;
    }

    function sendNegativeProfitVehiclesToDepot() {
        local vehicleList = AIVehicleList_Depot(m_depotTile);
        vehicleList.Valuate(AIVehicle.GetAge);
        vehicleList.KeepAboveValue(2 * 365);

        for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
//          AIController.Sleep(1);
            if ((AIVehicle.GetProfitLastYear(vehicle)) < 0) {
                if (sendVehicleToDepot(vehicle)) {
                    m_sentToDepotList.AddItem(vehicle, 0);
                }
            }
        }
    }

    function sendLowProfitVehiclesToDepot(routeManager) {
//      local roadVehicleList = AIVehicleList();
//      roadVehicleList.Valuate(AIVehicle.GetVehicleType);
//      roadVehicleList.KeepValue(AIVehicle.VT_ROAD);

//      if (LuDiAIAfterFix.MAX_TOWN_VEHICLES - 50 > roadVehicleList.Count()) {
//          return;
//      }

        if ((AIDate.GetCurrentDate() - m_lastVehicleRemoved) > 60) {
            local vehicleList = AIVehicleList_Depot(m_depotTile);
            vehicleList.Valuate(AIVehicle.GetAge);
            vehicleList.KeepAboveValue(2 * 365);

            for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
                AIController.Sleep(1);
                local cargoId = Utils.getCargoId(m_cargoClass);
		        local station1 = AIStation.GetStationID(m_stationTo);
		        local station2 = AIStation.GetStationID(m_stationFrom);
		        local cargoWaiting1via2 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargoId);
		        local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargoId);
                local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		        local cargoWaiting2via1 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargoId);
		        local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargoId);
                local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

                if ((cargoWaiting1 + cargoWaiting2 < 150) ||
                    (AIVehicle.GetProfitLastYear(vehicle) < (highestProfitLastYear(routeManager) / 6))) {
                    if (sendVehicleToDepot(vehicle)) {
                        m_sentToDepotList.AddItem(vehicle, 0);
                    }
                }
            }
        }
    }

    function sellVehiclesInDepot() {
        for (local vehicle = m_sentToDepotList.Begin(); !m_sentToDepotList.IsEnd(); vehicle = m_sentToDepotList.Next()) {
            if (AIVehicle.IsStoppedInDepot(vehicle)) {

                local vehicle_name = AIVehicle.GetName(vehicle);
    			m_sentToDepotList.RemoveItem(vehicle);
                AIVehicle.SellVehicle(vehicle);
				Utils.RepayLoan();

                AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " has been sold!");
            }
        }

        for (local vehicle = m_renewList.Begin(); !m_renewList.IsEnd(); vehicle = m_renewList.Next()) {
            if (AIVehicle.IsStoppedInDepot(vehicle)) {

                m_renewList.RemoveItem(vehicle);
                AIVehicle.SellVehicle(vehicle)
				Utils.RepayLoan();

				local renewed_vehicle = addVehicle(true);
                if (renewed_vehicle != null) {
                    AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " has been renewed!");
                }
            }
        }
    }

    function addremoveVehicleToRoute() {
		if (!m_activeRoute) {
			return null;
		}
		
		if (m_lastVehicleAdded == 0) {
			return addVehiclesToNewRoute(m_cargoClass);
		}
		
		if (MAX_VEHICLE_COUNT_MODE != AIController.GetSetting("road_cap_mode")) {
		    MAX_VEHICLE_COUNT_MODE = AIController.GetSetting("road_cap_mode");
//			AILog.Info("MAX_VEHICLE_COUNT_MODE = " + MAX_VEHICLE_COUNT_MODE);
		}

		local vehicleList = AIVehicleList_Depot(this.m_depotTile);
		if (MAX_VEHICLE_COUNT_MODE == 2 && AIDate.GetCurrentDate() -  m_lastVehicleAdded > 30) {
			local stoppedList = AIList()
			stoppedList.AddList(vehicleList);
			stoppedList.Valuate(AIVehicle.GetCurrentSpeed);
			stoppedList.KeepValue(0);
			stoppedList.Valuate(AIVehicle.GetState);
			stoppedList.KeepValue(AIVehicle.VS_RUNNING);

			local stoppedCount = stoppedList.Count();
			local max_num_stopped = MIN_VEHICLE_START_COUNT + AIGameSettings.GetValue("vehicle_breakdowns") * 2;
			if (stoppedCount >= max_num_stopped) {
				AILog.Info("Some vehicles on existing route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " aren't moving. (" + stoppedCount + "/" + vehicleList.Count() + " road vehicles)");
				
				for (local vehicle = stoppedList.Begin(); !stoppedList.IsEnd(); vehicle = stoppedList.Next()) {
					if (stoppedCount >= max_num_stopped && sendVehicleToDepot(vehicle)) {
						m_sentToDepotList.AddItem(vehicle, 0);
						m_lastVehicleAdded = AIDate.GetCurrentDate();
						stoppedCount--;
					}
				}
				return null;
			}
		}
		
		if (AIDate.GetCurrentDate() -  m_lastVehicleAdded < 90) {
			return null;
		}

		if (LuDiAIAfterFix.MAX_TOWN_VEHICLES > RouteManager.getRoadVehicleCount()) {
			local optimalVehicleCount = optimalVehicleCount();
			
			if (MAX_VEHICLE_COUNT_MODE != 2 && vehicleList.Count() >= optimalVehicleCount) {
				return null;
			}

			local cargoId = Utils.getCargoId(m_cargoClass);
			local station1 = AIStation.GetStationID(m_stationTo);
			local station2 = AIStation.GetStationID(m_stationFrom);
			local cargoWaiting1via2 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargoId);
			local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargoId);
			local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
			local cargoWaiting2via1 = AICargo.GetDistributionType(cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargoId);
			local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargoId);
			local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;
			
			local engine_capacity = AIEngine.GetCapacity(this.m_engine);

			if (cargoWaiting1 > engine_capacity || cargoWaiting2 > engine_capacity) {
				local number_to_add = 1 + (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / engine_capacity;
				local routedist = AITile.GetDistanceManhattanToTile(m_stationFrom, m_stationTo);
				while(number_to_add) {
					number_to_add--;
					if (addVehicle()) {
						local numvehicles = AIVehicleList_Depot(this.m_depotTile).Count();
						AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on existing route from " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + "! (" + numvehicles + (MAX_VEHICLE_COUNT_MODE != 2 ? "/" + optimalVehicleCount : "") + " road vehicle" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
						if (numvehicles >= MAX_VEHICLE_COUNT_MODE != 2 ? 1 : optimalVehicleCount) {
							number_to_add = 0;
						}
					}
				}
			}
		}
	}

    function renewVehicles() {
        local vehicleList = AIVehicleList_Depot(m_depotTile);
//      vehicleList.Valuate(AIVehicle.GetAgeLeft);
//      vehicleList.KeepBelowValue(365);

        for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
			if (AIVehicle.GetAgeLeft(vehicle) < 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine) {
				AIController.Sleep(1);
				if (sendVehicleToDepot(vehicle)) {
					m_renewList.AddItem(vehicle, 0);
				}
			}
        }
    }

    function expandStations() {
	    local result = 0;
	    if (!m_activeRoute) return result;
		
		local vehicleList = AIVehicleList_Depot(m_depotTile);
		if (MAX_VEHICLE_COUNT_MODE != 0 && vehicleList.Count() < optimalVehicleCount()) return result;

        vehicleList.Valuate(AIVehicle.IsArticulated);
		vehicleList.KeepValue(1);
		local articulated = vehicleList.Count() != 0;
		
        local population = AITown.GetPopulation(m_cityFrom);
		
        if (population / 1000 > m_expandedFromCount + 1) {
			if (BuildManager().buildTownStation(m_cityFrom, m_cargoClass, m_stationFrom, m_cityTo, articulated)) {
                ++m_expandedFromCount;
                result = 1;
				AILog.Info("Expanded " + AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom)) + " station.");
            }
        }

        population = AITown.GetPopulation(m_cityTo);

        if (population / 1000 > m_expandedToCount + 1) {
            if (BuildManager().buildTownStation(m_cityTo, m_cargoClass, m_stationTo, m_cityFrom, articulated)) {
                ++m_expandedToCount;
                result = 1;
				AILog.Info("Expanded " + AIBaseStation.GetName(AIStation.GetStationID(m_stationTo)) + " station.");
            }
        }

        return result;
    }
	
	function removeIfUnserviced() {
	    local vehicleList = AIVehicleList_Depot(m_depotTile);
		local fully_removed = true;
		if (vehicleList.Count() == 0 && (AIDate.GetCurrentDate() -  m_lastVehicleAdded >= 90) && m_lastVehicleAdded != 0) {
		    m_activeRoute = false;

			local stationFrom_name = AIBaseStation.GetName(AIStation.GetStationID(m_stationFrom));
		    local fromTiles = AITileList_StationType(AIStation.GetStationID(m_stationFrom), m_cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
			for (local tile = fromTiles.Begin(); !fromTiles.IsEnd(); tile = fromTiles.Next()) {
			    if (!TestRemoveRoadStation().TryRemove(tile)) {
				    m_stationFrom = AIBaseStation.GetLocation(AIStation.GetStationID(tile));
				    fully_removed = false;
				}
			}

			local stationTo_name = AIBaseStation.GetName(AIStation.GetStationID(m_stationTo));
			local toTiles = AITileList_StationType(AIStation.GetStationID(m_stationTo), m_cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP);
			for (local tile = toTiles.Begin(); !toTiles.IsEnd(); tile = toTiles.Next()) {
			    if (!TestRemoveRoadStation().TryRemove(tile)) {
				    m_stationTo = AIBaseStation.GetLocation(AIStation.GetStationID(tile));
				    fully_removed = false;
				}
			}
			
			if (!TestRemoveRoadDepot().TryRemove(m_depotTile)) {
			    fully_removed = false;
			}
			
			if (fully_removed) {
			    AILog.Warning("Removed unserviced road route from " + stationFrom_name + " to " + stationTo_name);
		        return true;
			}
		}
		return false;
	}

    function saveRoute() {
        local route = [];

        route.append(m_cityFrom);
        route.append(m_cityTo);
        route.append(m_stationFrom);
        route.append(m_stationTo);
        route.append(m_depotTile);

        local bridgeTilesTable = {};
		for (local bridge = m_bridgeTiles.Begin(), i = 0; !m_bridgeTiles.IsEnd(); bridge = m_bridgeTiles.Next(), ++i) {
		    bridgeTilesTable.rawset(i, [bridge, m_bridgeTiles.GetValue(bridge)]);
		}
		route.append(bridgeTilesTable);
		
        route.append(m_cargoClass);

        route.append(m_lastVehicleAdded);
        route.append(m_lastVehicleRemoved);
        route.append(m_activeRoute);
		route.append(m_expandedFromCount);
		route.append(m_expandedToCount);

        return route;
    }

    function loadRoute(data) {
        local cityFrom = data[0];
        local cityTo = data[1];
        local stationFrom = data[2];
        local stationTo = data[3];
        local depotTile = data[4];
		
		local bridgeTiles = AIList();
		local bridgeTable = data[5];
		local i = 0;
		while(bridgeTable.rawin(i)) {
		    local tile = bridgeTable.rawget(i);
			bridgeTiles.AddItem(tile[0], tile[1]);
			++i;
		}

        local cargoClass = data[6];
        local route = Route(cityFrom, cityTo, stationFrom, stationTo, depotTile, bridgeTiles, cargoClass, 1);

        route.m_lastVehicleAdded = data[7];
        route.m_lastVehicleRemoved = data[8];
        route.m_activeRoute = data[9];
		route.m_expandedFromCount = data[10];
		route.m_expandedToCount = data[11];

        return [route, i];
    }
}