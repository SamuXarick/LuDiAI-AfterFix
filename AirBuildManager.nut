class AirBuildManager {
	DAYS_INTERVAL = 10;

	m_cityFrom = -1;
	m_cityTo = -1;
	m_airportFrom = -1;
	m_airportTo = -1;
	m_cargoClass = -1;
	m_sentToDepotAirGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	m_airport_types = AIList();
	m_big_engine_list = AIList();
	m_small_engine_list = AIList();
	m_helicopter_list = AIList();

	m_fromType = AIAirport.AT_INVALID;
	m_toType = AIAirport.AT_INVALID;
	m_fromStationID = AIStation.STATION_INVALID;
	m_toStationID = AIStation.STATION_INVALID;
	m_small_aircraft_route = false;
	m_large_aircraft_route = false;
	m_helicopter_route = false;

	m_cargoID = -1;

	function BuildTownAirport(airRouteManager, airTownManager, town, cargoClass, large_aircraft, small_aircraft, helicopter, best_routes_built, all_routes_built)
	function SaveBuildManager();
	function BuildAirRoute(airRouteManager, airTownManager, cityFrom, cityTo, cargoClass, sentToDepotAirGroup, best_routes_built, all_routes_built);

	function HasUnfinishedRoute() {
		if (m_cityFrom != -1 && m_cityTo != -1 && m_cargoClass != -1) {
			return 1;
		}

		return 0;
	}

	function SetRouteFinished() {
		m_cityFrom = -1;
		m_cityTo = -1;
		m_airportFrom = -1;
		m_airportTo = -1;
		m_cargoClass = -1;
		m_sentToDepotAirGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
		m_best_routes_built = null;
		m_fromType = AIAirport.AT_INVALID;
		m_toType = AIAirport.AT_INVALID;
		m_fromStationID = AIStation.STATION_INVALID;
		m_toStationID = AIStation.STATION_INVALID;
		m_small_aircraft_route = false;
		m_large_aircraft_route = false;
		m_helicopter_route = false;
		m_cargoID = -1;
		m_airport_types = AIList();
	}

	function BuildAirRoute(airRouteManager, airTownManager, cityFrom, cityTo, cargoClass, sentToDepotAirGroup, best_routes_built, all_routes_built) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_cargoClass = cargoClass;
		m_sentToDepotAirGroup = sentToDepotAirGroup;
		m_best_routes_built = best_routes_built;
		m_cargoID = Utils.GetCargoID(cargoClass);

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_AIR);
		if (num_vehicles >= AIGameSettings.GetValue("max_aircraft") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		/* Create a list of available airports */
		m_airport_types.AddItem(AIAirport.AT_INTERCON, AIAirport.GetPrice(AIAirport.AT_INTERCON));            // 7
		m_airport_types.AddItem(AIAirport.AT_INTERNATIONAL, AIAirport.GetPrice(AIAirport.AT_INTERNATIONAL));  // 4
		m_airport_types.AddItem(AIAirport.AT_METROPOLITAN, AIAirport.GetPrice(AIAirport.AT_METROPOLITAN));    // 3
		m_airport_types.AddItem(AIAirport.AT_LARGE, AIAirport.GetPrice(AIAirport.AT_LARGE));                  // 1
		m_airport_types.AddItem(AIAirport.AT_COMMUTER, AIAirport.GetPrice(AIAirport.AT_COMMUTER));            // 5
		m_airport_types.AddItem(AIAirport.AT_SMALL, AIAirport.GetPrice(AIAirport.AT_SMALL));                  // 0
		m_airport_types.AddItem(AIAirport.AT_HELISTATION, AIAirport.GetPrice(AIAirport.AT_HELISTATION));      // 8
		m_airport_types.AddItem(AIAirport.AT_HELIDEPOT, AIAirport.GetPrice(AIAirport.AT_HELIDEPOT));          // 6
		m_airport_types.AddItem(AIAirport.AT_HELIPORT, AIAirport.GetPrice(AIAirport.AT_HELIPORT));            // 2

		/* Filter out airports larger than the maximum value of a station size */
		local list = AIList();
		list.AddList(m_airport_types);
		local station_spread = AIGameSettings.GetValue("station_spread");
		for (local i = list.Begin(); !list.IsEnd(); i = list.Next()) {
//			AILog.Info("i = " + i);
			local airport_x = AIAirport.GetAirportWidth(i);
//			AILog.Info("airport_x = " + airport_x);
			local airport_y = AIAirport.GetAirportHeight(i);
//			AILog.Info("airport_y = " + airport_y);
			if (airport_x > station_spread || airport_y > station_spread) {
//				AILog.Info("Removing non-valid airport of type " + WrightAI.GetAirportTypeName(i));
				m_airport_types.RemoveItem(i);
				continue;
			}
			/* Also filter out unavailable airports */
			if (!AIAirport.IsValidAirportType(i)) {
//				AILog.Info("Removing non-valid airport of type " + WrightAI.GetAirportTypeName(i));
				m_airport_types.RemoveItem(i);
				continue;
			}
		}

		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		if (infrastructure) {
//			AILog.Info("Available airport types:");
			local large_airports = AIList();
			local small_airports = AIList();
			local heli_airports = AIList();
			for (local a = m_airport_types.Begin(); !m_airport_types.IsEnd(); a = m_airport_types.Next()) {
				switch (a) {
					case AIAirport.AT_INTERCON:
					case AIAirport.AT_INTERNATIONAL:
					case AIAirport.AT_METROPOLITAN:
					case AIAirport.AT_LARGE:
						large_airports.AddItem(a, AIAirport.GetMonthlyMaintenanceCost(a));
						break;

					case AIAirport.AT_COMMUTER:
					case AIAirport.AT_SMALL:
						small_airports.AddItem(a, AIAirport.GetMonthlyMaintenanceCost(a));
						break;

					case AIAirport.AT_HELISTATION:
					case AIAirport.AT_HELIDEPOT:
					case AIAirport.AT_HELIPORT:
						heli_airports.AddItem(a, AIAirport.GetMonthlyMaintenanceCost(a));
						break;

					default:
						break;
				}

//				AILog.Info(WrightAI.GetAirportTypeName(a) + " (monthly maintenance cost = " + AIAirport.GetMonthlyMaintenanceCost(a) + ")");
			}
			large_airports.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
			small_airports.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
			heli_airports.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
			if (large_airports.Count() > 1) {
				large_airports.KeepBottom(large_airports.Count() - 1);
				m_airport_types.RemoveList(large_airports);
			}
			if (small_airports.Count() > 1) {
				small_airports.KeepBottom(small_airports.Count() - 1);
				m_airport_types.RemoveList(small_airports);
			}
			if (heli_airports.Count() == 1 && heli_airports.HasItem(AIAirport.AT_HELIPORT)) {
				m_airport_types.RemoveList(heli_airports);
			} else if (heli_airports.Count() > 1) {
				if (!heli_airports.HasItem(AIAirport.AT_HELIPORT)) {
					heli_airports.KeepBottom(heli_airports.Count() - 1);
					m_airport_types.RemoveList(heli_airports);
				} else {
					heli_airports.RemoveItem(AIAirport.AT_HELIPORT);
					if (heli_airports.Count() > 1) {
						heli_airports.KeepBottom(heli_airports.Count() - 1);
						m_airport_types.RemoveList(heli_airports);
					}
				}
			}
		}

		/* No airports available. Abort */
		if (m_airport_types.Count() == 0) {
			SetRouteFinished();
			return null;
		}

		local available_engines = false;
		local engine_costs = 0;

		UpdateAircraftLists();

		local engine_count = 2;
		if (infrastructure && AIVehicleList().Count()) {
			if (m_airportFrom != -1 && m_airportFrom > 0) {
				local engine_id = GetBestAirportEngine(m_fromType);
				local default_count = 8;
				if (engine_id != null) {
					local count = WrightAI.GetEngineOptimalDaysInTransit(engine_id, m_cargoID, DAYS_INTERVAL, true, m_airportFrom, m_fromType);
					default_count = count[2] > 0 && count[2] != 1000 ? count[2] : default_count;
				}
				engine_count = default_count;
			} else {
				engine_count = 8;
			}
		}
		if (m_big_engine_list.Count() == 0) {
			if (infrastructure) {
				m_airport_types.RemoveItem(AIAirport.AT_INTERCON);
				m_airport_types.RemoveItem(AIAirport.AT_INTERNATIONAL);
				m_airport_types.RemoveItem(AIAirport.AT_METROPOLITAN);
				m_airport_types.RemoveItem(AIAirport.AT_LARGE);
			}
		} else {
			available_engines = true;
			engine_costs = AIEngine.GetPrice(m_big_engine_list.Begin()) * engine_count;
		}

		if (m_small_engine_list.Count() == 0) {
			if (infrastructure) {
				m_airport_types.RemoveItem(AIAirport.AT_COMMUTER);
				m_airport_types.RemoveItem(AIAirport.AT_SMALL);
			}
		} else {
			available_engines = true;
			if (engine_costs < AIEngine.GetPrice(m_small_engine_list.Begin()) * engine_count) engine_costs = AIEngine.GetPrice(m_small_engine_list.Begin()) * engine_count;
		}

		if (m_helicopter_list.Count() == 0) {
			m_airport_types.RemoveItem(AIAirport.AT_HELISTATION);
			m_airport_types.RemoveItem(AIAirport.AT_HELIDEPOT);
			m_airport_types.RemoveItem(AIAirport.AT_HELIPORT);
		} else {
			available_engines = true;
			if (engine_costs < AIEngine.GetPrice(m_helicopter_list.Begin()) * engine_count) engine_costs = AIEngine.GetPrice(m_helicopter_list.Begin()) * engine_count;
		}

		/* There are no engines available */
		if (!available_engines) {
			SetRouteFinished();
			return null;
		}

		/* Not enough money */
		local estimated_costs = m_airport_types.GetValue(m_airport_types.Begin()) + engine_costs + 12500 * engine_count;
//		AILog.Info("estimated_costs = " + estimated_costs + "; airport = " + WrightAI.GetAirportTypeName(m_airport_types.Begin()) + ", " + m_airport_types.GetValue(m_airport_types.Begin()) + "; engine_costs = " + engine_costs + " + 12500 * " + engine_count);
		if (!Utils.HasMoney(estimated_costs)) {
//			SetRouteFinished();
			return 0;
		}

		if (m_airportFrom == -1) {
			m_airportFrom = BuildTownAirport(airRouteManager, airTownManager, m_cityFrom, m_cargoClass, m_large_aircraft_route, m_small_aircraft_route, m_helicopter_route, m_best_routes_built, all_routes_built);
			if (m_airportFrom == null) {
				SetRouteFinished();
				return null;
			}

			return 0;
		}

		if (m_fromType == AIAirport.AT_HELIPORT) {
			m_airport_types.RemoveItem(AIAirport.AT_HELIPORT);
			m_airport_types.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		}

		if (infrastructure) {
			if (m_fromType == AIAirport.AT_HELISTATION && m_airport_types.HasItem(AIAirport.AT_HELIPORT)) {
				if (AIAirport.GetMonthlyMaintenanceCost(AIAirport.AT_HELISTATION) > AIAirport.GetMonthlyMaintenanceCost(AIAirport.AT_HELIPORT)) {
					m_airport_types.RemoveItem(AIAirport.AT_HELISTATION);
					m_airport_types.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
				}
			} else if (m_fromType == AIAirport.AT_HELIDEPOT && m_airport_types.HasItem(AIAirport.AT_HELIPORT)) {
				if (AIAirport.GetMonthlyMaintenanceCost(AIAirport.AT_HELIDEPOT) > AIAirport.GetMonthlyMaintenanceCost(AIAirport.AT_HELIPORT)) {
					m_airport_types.RemoveItem(AIAirport.AT_HELIDEPOT);
					m_airport_types.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
				}
			}
		}

		if (m_airportTo == -1) {
			m_airportTo = BuildTownAirport(airRouteManager, airTownManager, m_cityTo, m_cargoClass, m_large_aircraft_route, m_small_aircraft_route, m_helicopter_route, m_best_routes_built, all_routes_built);
			if (m_airportTo == null) {
				SetRouteFinished();
				return null;
			}
		}

		if (m_fromType != AIAirport.AT_INVALID && m_toType != AIAirport.AT_INVALID) {
			/* Build the airports for real */
			if (!(TestBuildAirport().TryBuild(m_airportFrom, m_fromType, m_fromStationID))) {
				AILog.Error("a:Although the testing told us we could build 2 airports, it still failed on the first airport at tile " + m_airportFrom + ".");
				SetRouteFinished();
				return null;
			}

			if (!(TestBuildAirport().TryBuild(m_airportTo, m_toType, m_toStationID))) {
				AILog.Error("a:Although the testing told us we could build 2 airports, it still failed on the second airport at tile " + m_airportTo + ".");

				local counter = 0;
				do {
					if (!TestRemoveAirport().TryRemove(m_airportFrom)) {
						++counter;
					}
					else {
//						AILog.Warning("m_airportTo; Removed airport at tile " + m_airportFrom);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Aircraft.rawset(m_airportFrom, 0);
//					AILog.Error("Failed to remove airport at tile " + m_airportFrom + " - " + AIError.GetLastErrorString());
				}
				SetRouteFinished();
				return null;
			}
		}

		return AirRoute(m_cityFrom, m_cityTo, m_airportFrom, m_airportTo, m_cargoClass, m_sentToDepotAirGroup);
	}

	function BuildTownAirport(airRouteManager, airTownManager, town, cargoClass, large_aircraft, small_aircraft, helicopter, best_routes_built, all_routes_built) {
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		local pick_mode = AIController.GetSetting("pick_mode");

		local large_engine_list = GetBestAirportEngine(AIAirport.AT_LARGE, true);
		local small_engine_list = GetBestAirportEngine(AIAirport.AT_SMALL, true);
		local heli_engine_list = GetBestAirportEngine(AIAirport.AT_HELIPORT, true);
		if (large_engine_list == null && small_engine_list == null && heli_engine_list == null) {
			return null;
		}

		local large_available = true;
		local large_fakedist;
		local large_max_dist;
		local large_min_dist;
		local large_cityTo = null;
		local large_closestTowns = AIList();

		local small_available = true;
		local small_fakedist;
		local small_max_dist;
		local small_min_dist;
		local small_cityTo = null;
		local small_closestTowns = AIList();

		local heli_available = true;
		local heli_fakedist;
		local heli_max_dist;
		local heli_min_dist;
		local heli_cityTo = null;
		local heli_closestTowns = AIList();

		if (m_airportFrom > 0) {
			if (!(large_aircraft && (AIAirport.IsValidAirportType(AIAirport.AT_INTERCON) || AIAirport.IsValidAirportType(AIAirport.AT_INTERNATIONAL) || AIAirport.IsValidAirportType(AIAirport.AT_METROPOLITAN) || AIAirport.IsValidAirportType(AIAirport.AT_LARGE)))) {
//				AILog.Info("large_available = false [1]");
				large_available = false;
			}

			if (large_available) {
				if (large_engine_list == null) {
//					AILog.Info("large_available = false [2]");
					large_available = false;
				}
			}

			local large_engine;
			if (large_available) {
				large_engine = WrightAI.GetBestEngineIncome(large_engine_list, m_cargoID, DAYS_INTERVAL);
				if (large_engine[0] == null) {
//					AILog.Info("large_available = false [3]");
					large_available = false;
				}
			}

			if (large_available) {
				large_fakedist = large_engine[1];

				/* Best engine is unprofitable enough */
				if (large_fakedist == 0) {
//					AILog.Info("large_available = false [4]");
					large_available = false;
				}
			}

			if (large_available) {
				/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
				local large_max_order_dist = WrightAI.GetMaximumOrderDistance(large_engine[0]);
				large_max_dist = large_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : large_max_order_dist;
				local large_min_order_dist = (large_fakedist / 2) * (large_fakedist / 2);
				large_min_dist = large_min_order_dist > large_max_dist * 3 / 4 ? !infrastructure && large_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : large_max_dist * 3 / 4 : large_min_order_dist;

				airTownManager.FindNearCities(m_cityFrom, large_min_dist, large_max_dist, best_routes_built, cargoClass, large_fakedist);
				if (!airTownManager.HasArrayCargoClassPairs(cargoClass)) {
					large_available = false;
				}
			}

			if (large_available) {
				for (local i = 0; i < airTownManager.m_nearCityPairArray.len(); ++i) {
					if (m_cityFrom == airTownManager.m_nearCityPairArray[i][0] && cargoClass == airTownManager.m_nearCityPairArray[i][2]) {
						if (!airRouteManager.TownRouteExists(m_cityFrom, airTownManager.m_nearCityPairArray[i][1], cargoClass)) {
							large_cityTo = airTownManager.m_nearCityPairArray[i][1];

							if (pick_mode != 1 && all_routes_built && airRouteManager.HasMaxStationCount(m_cityFrom, large_cityTo, cargoClass)) {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(m_cityFrom) + ", " + AITown.GetName(large_cityTo) + ", " + cargoClass + ") == " + airRouteManager.HasMaxStationCount(m_cityFrom, large_cityTo, cargoClass));
								large_cityTo = null;
								continue;
							} else {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(m_cityFrom) + ", " + AITown.GetName(large_cityTo) + ", " + cargoClass + ") == " + airRouteManager.HasMaxStationCount(m_cityFrom, large_cityTo, cargoClass));
								break;
							}
						}
					}
				}

				if (large_cityTo == null) {
					large_available = false;
				}
			}

			if (large_available) {
				local town_tile = AITown.GetLocation(large_cityTo);
				local dist = AITile.GetDistanceSquareToTile(town_tile, m_airportFrom);
				local fake = WrightAI.DistanceRealFake(town_tile, m_airportFrom);
				if (!(dist <= large_max_dist && dist >= large_min_dist && fake <= large_fakedist)) {
//					AILog.Info("large_available distances null");
					large_available = false;
				} else {
					large_closestTowns.AddItem(large_cityTo, 0);
				}
			}


			if (!(small_aircraft && (AIAirport.IsValidAirportType(AIAirport.AT_COMMUTER) || AIAirport.IsValidAirportType(AIAirport.AT_SMALL)))) {
//				AILog.Info("small_available = false [1]");
				small_available = false;
			}

			if (small_available) {
				if (small_engine_list == null) {
//					AILog.Info("small_available = false [2]");
					small_available = false;
				}
			}

			local small_engine;
			if (small_available) {
				small_engine = WrightAI.GetBestEngineIncome(small_engine_list, m_cargoID, DAYS_INTERVAL);
				if (small_engine[0] == null) {
//					AILog.Info("small_available = false [3]");
					small_available = false;
				}
			}

			if (small_available) {
				small_fakedist = small_engine[1];

				/* Best engine is unprofitable enough */
				if (small_fakedist == 0) {
//					AILog.Info("small_available = false [4]");
					small_available = false;
				}
			}

			if (small_available) {
				/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
				local small_max_order_dist = WrightAI.GetMaximumOrderDistance(small_engine[0]);
				small_max_dist = small_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : small_max_order_dist;
				local small_min_order_dist = (small_fakedist / 2) * (small_fakedist / 2);
				small_min_dist = small_min_order_dist > small_max_dist * 3 / 4 ? !infrastructure && small_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : small_max_dist * 3 / 4 : small_min_order_dist;

				airTownManager.FindNearCities(m_cityFrom, small_min_dist, small_max_dist, best_routes_built, cargoClass, small_fakedist);
				if (!airTownManager.HasArrayCargoClassPairs(cargoClass)) {
					small_available = false;
				}
			}

			if (small_available) {
				for (local i = 0; i < airTownManager.m_nearCityPairArray.len(); ++i) {
					if (m_cityFrom == airTownManager.m_nearCityPairArray[i][0] && cargoClass == airTownManager.m_nearCityPairArray[i][2]) {
						if (!airRouteManager.TownRouteExists(m_cityFrom, airTownManager.m_nearCityPairArray[i][1], cargoClass)) {
							small_cityTo = airTownManager.m_nearCityPairArray[i][1];

							if (pick_mode != 1 && all_routes_built && airRouteManager.HasMaxStationCount(m_cityFrom, small_cityTo, cargoClass)) {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(m_cityFrom) + ", " + AITown.GetName(small_cityTo) + ", " + cargoClass + ") == " + airRouteManager.HasMaxStationCount(m_cityFrom, small_cityTo, cargoClass));
								small_cityTo = null;
								continue;
							} else {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(m_cityFrom) + ", " + AITown.GetName(small_cityTo) + ", " + cargoClass + ") == " + airRouteManager.HasMaxStationCount(m_cityFrom, small_cityTo, cargoClass));
								break;
							}
						}
					}
				}

				if (small_cityTo == null) {
					small_available = false;
				}
			}

			if (small_available) {
				local town_tile = AITown.GetLocation(small_cityTo);
				local dist = AITile.GetDistanceSquareToTile(town_tile, m_airportFrom);
				local fake = WrightAI.DistanceRealFake(town_tile, m_airportFrom);
				if (!(dist <= small_max_dist && dist >= small_min_dist && fake <= small_fakedist)) {
//					AILog.Info("small_available distances null");
					small_available = false;
				} else {
					small_closestTowns.AddItem(small_cityTo, 0);
				}
			}


			if (!(helicopter && (AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) || AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT) || AIAirport.IsValidAirportType(AIAirport.AT_HELIPORT)))) {
//				AILog.Info("heli_available = false [1]");
				heli_available = false;
			}
			if (heli_available) {
				if (heli_engine_list == null) {
//					AILog.Info("heli_available = false [2]");
					heli_available = false;
				}
			}

			local heli_engine;
			if (heli_available) {
				heli_engine = WrightAI.GetBestEngineIncome(heli_engine_list, m_cargoID, DAYS_INTERVAL);
				if (heli_engine[0] == null) {
//					AILog.Info("heli_available = false [3]");
					heli_available = false;
				}
			}

			if (heli_available) {
				heli_fakedist = heli_engine[1];

				/* Best engine is unprofitable enough */
				if (heli_fakedist == 0) {
//					AILog.Info("heli_available = false [4]");
					heli_available = false;
				}
			}

			if (heli_available) {
				/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
				local heli_max_order_dist = WrightAI.GetMaximumOrderDistance(heli_engine[0]);
				heli_max_dist = heli_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : heli_max_order_dist;
				local heli_min_order_dist = (heli_fakedist / 2) * (heli_fakedist / 2);
				heli_min_dist = heli_min_order_dist > heli_max_dist * 3 / 4 ? !infrastructure && heli_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : heli_max_dist * 3 / 4 : heli_min_order_dist;

				airTownManager.FindNearCities(m_cityFrom, heli_min_dist, heli_max_dist, best_routes_built, cargoClass, heli_fakedist);
				if (!airTownManager.HasArrayCargoClassPairs(cargoClass)) {
					heli_available = false;
				}
			}

			if (heli_available) {
				for (local i = 0; i < airTownManager.m_nearCityPairArray.len(); ++i) {
					if (m_cityFrom == airTownManager.m_nearCityPairArray[i][0] && cargoClass == airTownManager.m_nearCityPairArray[i][2]) {
						if (!airRouteManager.TownRouteExists(m_cityFrom, airTownManager.m_nearCityPairArray[i][1], cargoClass)) {
							heli_cityTo = airTownManager.m_nearCityPairArray[i][1];

							if (pick_mode != 1 && all_routes_built && airRouteManager.HasMaxStationCount(m_cityFrom, heli_cityTo, cargoClass)) {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(m_cityFrom) + ", " + AITown.GetName(heli_cityTo) + ", " + cargoClass + ") == " + airRouteManager.HasMaxStationCount(m_cityFrom, heli_cityTo, cargoClass));
								heli_cityTo = null;
								continue;
							} else {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(m_cityFrom) + ", " + AITown.GetName(heli_cityTo) + ", " + cargoClass + ") == " + airRouteManager.HasMaxStationCount(m_cityFrom, heli_cityTo, cargoClass));
								break;
							}
						}
					}
				}

				if (heli_cityTo == null) {
					heli_available = false;
				}
			}

			if (heli_available) {
				local town_tile = AITown.GetLocation(heli_cityTo);
				local dist = AITile.GetDistanceSquareToTile(town_tile, m_airportFrom);
				local fake = WrightAI.DistanceRealFake(town_tile, m_airportFrom);
				if (!(dist <= heli_max_dist && dist >= heli_min_dist && fake <= heli_fakedist)) {
//					AILog.Info("heli_available distances null");
					heli_available = false;
				} else {
					heli_closestTowns.AddItem(heli_cityTo, 0);
				}
			}


			if (!large_available && !small_available && !heli_available) {
//				AILog.Info("!large_available && !small_available && !heli_available");
				return null;
			}
		}

		/* Now find a suitable town */
		local town_list = AIList();
		if (m_airportFrom > 0) {
			town_list.AddList(large_closestTowns);
			town_list.AddList(small_closestTowns);
			town_list.AddList(heli_closestTowns);
		} else {
			town_list.AddItem(town, 0);
		}
		for (local t = town_list.Begin(); !town_list.IsEnd(); t = town_list.Next()) {
			local town_tile = AITown.GetLocation(t);

			for (local a = m_airport_types.Begin(); !m_airport_types.IsEnd(); a = m_airport_types.Next()) {
				if (!AIAirport.IsValidAirportType(a)) continue;

				if (large_aircraft && a != AIAirport.AT_INTERCON && a != AIAirport.AT_INTERNATIONAL && a != AIAirport.AT_METROPOLITAN && a != AIAirport.AT_LARGE) {
					continue;
				}
				if (small_aircraft && a != AIAirport.AT_INTERCON && a != AIAirport.AT_INTERNATIONAL && a != AIAirport.AT_METROPOLITAN && a != AIAirport.AT_LARGE && a != AIAirport.AT_SMALL && a != AIAirport.AT_COMMUTER) {
					continue;
				}
				if (helicopter && a != AIAirport.AT_HELISTATION && a != AIAirport.AT_HELIDEPOT && a != AIAirport.AT_HELIPORT) {
					if (AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) || AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
						continue;
					}
				}

				if (infrastructure) {
					if (!large_available && (a == AIAirport.AT_INTERCON || a == AIAirport.AT_INTERNATIONAL || a == AIAirport.AT_METROPOLITAN || a == AIAirport.AT_LARGE)) {
						continue;
					}
					if (!small_available && (a == AIAirport.AT_COMMUTER || a == AIAirport.AT_SMALL)) {
						continue;
					}
					if (!heli_available && (a == AIAirport.AT_HELISTATION || a == AIAirport.AT_HELIDEPOT || a == AIAirport.AT_HELIPORT)) {
						continue;
					}
					if (heli_available && a == AIAirport.AT_HELIPORT && !AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) && !AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
						continue;
					}
				}

				local fakedist;
				local max_dist;
				local min_dist;
				if (m_airportFrom > 0) {
					local closestTowns = AIList();
					if (a == AIAirport.AT_INTERCON || a == AIAirport.AT_INTERNATIONAL || a == AIAirport.AT_METROPOLITAN || a == AIAirport.AT_LARGE) {
						if (large_aircraft) {
							if (large_available) {
								closestTowns.AddList(large_closestTowns);
								fakedist = large_fakedist;
								max_dist = large_max_dist;
								min_dist = large_min_dist;
							} else {
								continue;
							}
						}
						if (small_aircraft && !infrastructure) {
							if (small_available) {
								closestTowns.AddList(small_closestTowns);
								fakedist = small_fakedist;
								max_dist = small_max_dist;
								min_dist = small_min_dist;
							} else {
								continue;
							}
						}
						if (helicopter && !infrastructure) {
							if (heli_available) {
								closestTowns.AddList(heli_closestTowns);
								fakedist = heli_fakedist;
								max_dist = heli_max_dist;
								min_dist = heli_min_dist;
							} else {
								continue;
							}
						}
					} else if (a == AIAirport.AT_COMMUTER || a == AIAirport.AT_SMALL) {
						if (large_aircraft && !infrastructure || small_aircraft) {
							if (small_available) {
								closestTowns.AddList(small_closestTowns);
								fakedist = small_fakedist;
								max_dist = small_max_dist;
								min_dist = small_min_dist;
							} else {
								continue;
							}
						}
						if (helicopter && !infrastructure) {
							if (heli_available) {
								closestTowns.AddList(heli_closestTowns);
								fakedist = heli_fakedist;
								max_dist = heli_max_dist;
								min_dist = heli_min_dist;
							} else {
								continue;
							}
						}
					} else {
						if (heli_available) {
							closestTowns.AddList(heli_closestTowns);
							fakedist = heli_fakedist;
							max_dist = heli_max_dist;
							min_dist = heli_min_dist;
						} else {
							continue;
						}
					}

					if (!closestTowns.HasItem(t)) continue;
				}

				local airport_x = AIAirport.GetAirportWidth(a);
				local airport_y = AIAirport.GetAirportHeight(a);
				local airport_rad = AIAirport.GetAirportCoverageRadius(a);

				AILog.Info("a:Checking " + AITown.GetName(t) + " for an airport of type " + WrightAI.GetAirportTypeName(a));

				local rectangleCoordinates = WrightAI.TownAirportRadRect(a, t);
				local tileList = AITileList();
				tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);

				local tempList = AITileList();
				tempList.AddList(tileList);
				for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
					if (m_airportFrom > 0) {
						/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
						local distance_square = AITile.GetDistanceSquareToTile(tile, m_airportFrom);
						if (!(distance_square > min_dist)) {
							tempList.RemoveItem(tile);
							continue;
						}
						if (!(distance_square < max_dist)) {
							tempList.RemoveItem(tile);
							continue;
						}
						if (!(WrightAI.DistanceRealFake(tile, m_airportFrom) < fakedist)) {
							tempList.RemoveItem(tile);
							continue;
						}
					}

					if (!(AITile.IsBuildableRectangle(tile, airport_x, airport_y))) {
						tempList.RemoveItem(tile);
						continue;
					}

					/* Sort on acceptance, remove places that don't have acceptance */
					if (AITile.GetCargoAcceptance(tile, m_cargoID, airport_x, airport_y, airport_rad) < 10) {
						tempList.RemoveItem(tile);
						continue;
					}

					local secondary_cargo = Utils.GetCargoID(AICargo.CC_MAIL);
					if (AIController.GetSetting("select_town_cargo") == 2 && AICargo.IsValidCargo(secondary_cargo) && secondary_cargo != m_cargoID) {
						if (AITile.GetCargoAcceptance(tile, secondary_cargo, airport_x, airport_y, airport_rad) < 10) {
							tempList.RemoveItem(tile);
							continue;
						}
					}

					local cargo_production = AITile.GetCargoProduction(tile, m_cargoID, airport_x, airport_y, airport_rad);
					if (pick_mode != 1 && (!best_routes_built || infrastructure) && cargo_production < 18) {
						tempList.RemoveItem(tile);
						continue;
					} else {
						tempList.SetValue(tile, (cargo_production << 13) | (0x1FFF - WrightAI.GetMinAirportDistToTile(tile, a, town_tile)));
					}
				}
				tileList.Clear();
				tileList.AddList(tempList);

				/* Couldn't find a suitable place for this town */
				if (tileList.Count() == 0) {
					continue;
				}
				tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

				/* Walk all the tiles and see if we can build the airport at all */
				local good_tile = 0;
				for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
					local noise = AIAirport.GetNoiseLevelIncrease(tile, a);
					local allowed_noise = AITown.GetAllowedNoise(AIAirport.GetNearestTown(tile, a));
					if (noise > allowed_noise) continue;
//					AISign.BuildSign(tile, ("" + noise + " <= " + allowed_noise + ""));

					local adjacentStationId = WrightAI.CheckAdjacentNonAirport(tile, a);
					local nearest_town;
					if (adjacentStationId == AIStation.STATION_NEW) {
						nearest_town = AITile.GetClosestTown(tile);
						if (nearest_town != t) continue;
					} else {
						nearest_town = AIStation.GetNearestTown(adjacentStationId);
						if (nearest_town != t) {
							adjacentStationId = AIStation.STATION_NEW;
							nearest_town = AITile.GetClosestTown(tile);
							if (nearest_town != t) continue;
						}
					}

					if (AITestMode() && !AIAirport.BuildAirport(tile, a, adjacentStationId)) continue;
					good_tile = tile;

					/* Don't build airport if there is any competitor station in the vicinity, or an airport of mine */
					local airportcoverage = WrightAI.TownAirportRadRect(a, tile, false);
					local tileList2 = AITileList();
					tileList2.AddRectangle(airportcoverage[0], airportcoverage[1]);
					tileList2.RemoveRectangle(tile, AIMap.GetTileIndex(AIMap.GetTileX(tile + airport_x - 1), AIMap.GetTileY(tile + airport_y - 1)));
					local nearby_station = false;
					for (local t = tileList2.Begin(); !tileList2.IsEnd(); t = tileList2.Next()) {
						if (AITile.IsStationTile(t) && (AIAirport.IsAirportTile(t) || AITile.GetOwner(t) != Utils.MyCID() && AIController.GetSetting("is_friendly"))) {
							nearby_station = true;
							break;
						}
					}
					if (nearby_station) continue;

					if (m_airportFrom == -1) {
						m_fromType = a;
						m_fromStationID = adjacentStationId;

						if (a == AIAirport.AT_INTERCON || a == AIAirport.AT_INTERNATIONAL || a == AIAirport.AT_METROPOLITAN || a == AIAirport.AT_LARGE) {
							m_large_aircraft_route = true;
						}
						if (a == AIAirport.AT_COMMUTER || a == AIAirport.AT_SMALL) {
							m_small_aircraft_route = true;
						}
						if (a == AIAirport.AT_HELISTATION || a == AIAirport.AT_HELIDEPOT || a == AIAirport.AT_HELIPORT) {
							m_helicopter_route = true;
						}
					} else {
						m_toType = a;
						m_toStationID = adjacentStationId;
						m_cityTo = t;
					}

					return good_tile;
				}
			}

			/* All airport types were tried on this town and no suitable location was found */
		}

		/* We haven't found a suitable location for any airport type in any town */
		return null;
	}

	function UpdateAircraftLists() {
		m_big_engine_list.Clear();
		m_small_engine_list.Clear();
		m_helicopter_list.Clear();

		local from_location = (m_airportFrom != null && m_airportFrom > 0) ? m_airportFrom : null;
		local from_type = from_location == null ? null : m_fromType

		local all_engines = AIEngineList(AIVehicle.VT_AIR);
		for (local engine = all_engines.Begin(); !all_engines.IsEnd(); engine = all_engines.Next()) {
			if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, m_cargoID)) {
				local income = WrightAI.GetEngineOptimalDaysInTransit(engine, m_cargoID, DAYS_INTERVAL, true, from_location, from_type);
				switch (AIEngine.GetPlaneType(engine)) {
					case AIAirport.PT_BIG_PLANE:
						m_big_engine_list.AddItem(engine, income[0]);
						break;
					case AIAirport.PT_SMALL_PLANE:
						m_small_engine_list.AddItem(engine, income[0]);
						break;
					case AIAirport.PT_HELICOPTER:
						m_helicopter_list.AddItem(engine, income[0]);
						break;
				}
			}
		}
	}

	function GetBestAirportEngine(type, return_list = false, squared_dist = null) {
//		UpdateAircraftLists();
		local engine_list = AIList();
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");

		if (type == AIAirport.AT_INTERCON || type == AIAirport.AT_INTERNATIONAL || type == AIAirport.AT_METROPOLITAN || type == AIAirport.AT_LARGE) {
			engine_list.AddList(m_big_engine_list);
			if (!infrastructure) engine_list.AddList(m_small_engine_list);
			if (!infrastructure) engine_list.AddList(m_helicopter_list);
		}

		if (type == AIAirport.AT_SMALL || type == AIAirport.AT_COMMUTER) {
			engine_list.AddList(m_small_engine_list);
			if (!infrastructure) engine_list.AddList(m_helicopter_list);
		}

		if (type == AIAirport.AT_HELISTATION || type == AIAirport.AT_HELIDEPOT || type == AIAirport.AT_HELIPORT) {
			engine_list.AddList(m_helicopter_list);
		}

		if (squared_dist != null) {
			local templist = AIList();
			for (local engine = engine_list.Begin(); !engine_list.IsEnd(); engine = engine_list.Next()) {
				local maximumorderdistance = WrightAI.GetMaximumOrderDistance(engine);
				if (maximumorderdistance >= squared_dist) {
					engine_list.SetValue(engine, maximumorderdistance);
				} else {
					templist.AddItem(engine, 0);
				}
			}
			engine_list.RemoveList(templist);
		}

		if (engine_list.Count() == 0) {
			return null;
		} else {
			if (return_list) {
				return engine_list;
			} else {
				return engine_list.Begin();
			}
		}
	}

	function SaveBuildManager() {
		if (m_cityFrom == null) m_cityFrom = -1;
		if (m_cityTo == null) m_cityTo = -1;
		if (m_airportFrom == null) m_airportFrom = -1;
		if (m_airportTo == null) m_airportTo = -1;

		return [m_cityFrom, m_cityTo, m_airportFrom, m_airportTo, m_cargoClass, m_best_routes_built, m_fromType, m_toType, m_fromStationID, m_toStationID, m_large_aircraft_route, m_small_aircraft_route, m_helicopter_route];
	}

	function LoadBuildManager(data) {
		m_cityFrom = data[0];
		m_cityTo = data[1];
		m_airportFrom = data[2];
		m_airportTo = data[3];
		m_cargoClass = data[4];
		m_best_routes_built = data[5];
		m_fromType = data[6];
		m_toType = data[7];
		m_fromStationID = data[8];
		m_toStationID = data[9];
		m_large_aircraft_route = data[10];
		m_small_aircraft_route = data[11];
		m_helicopter_route = data[12];
	}
}
