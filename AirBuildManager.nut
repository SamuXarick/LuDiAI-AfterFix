class AirBuildManager
{
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

	m_cargoType = -1;

	function BuildTownAirport(airRouteManager, airTownManager, town, cargoClass, large_aircraft, small_aircraft, helicopter, best_routes_built, all_routes_built)
	function SaveBuildManager();
	function BuildAirRoute(airRouteManager, airTownManager, cityFrom, cityTo, cargoClass, sentToDepotAirGroup, best_routes_built, all_routes_built);

	function HasUnfinishedRoute()
	{
		return m_cityFrom != -1 && m_cityTo != -1 && m_cargoClass != -1;
	}

	function SetRouteFinished()
	{
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
		m_cargoType = -1;
		m_airport_types.Clear();
	}

	function BuildAirRoute(airRouteManager, airTownManager, cityFrom, cityTo, cargoClass, sentToDepotAirGroup, best_routes_built, all_routes_built)
	{
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_cargoClass = cargoClass;
		m_sentToDepotAirGroup = sentToDepotAirGroup;
		m_best_routes_built = best_routes_built;
		m_cargoType = Utils.GetCargoType(cargoClass);

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_AIR);
		if (num_vehicles >= AIGameSettings.GetValue("max_aircraft") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		/* Create a list of available airports */
		m_airport_types[AIAirport.AT_INTERCON] = AIAirport.GetPrice(AIAirport.AT_INTERCON); // 7
		m_airport_types[AIAirport.AT_INTERNATIONAL] = AIAirport.GetPrice(AIAirport.AT_INTERNATIONAL); // 4
		m_airport_types[AIAirport.AT_METROPOLITAN] = AIAirport.GetPrice(AIAirport.AT_METROPOLITAN); // 3
		m_airport_types[AIAirport.AT_LARGE] = AIAirport.GetPrice(AIAirport.AT_LARGE); // 1
		m_airport_types[AIAirport.AT_COMMUTER] = AIAirport.GetPrice(AIAirport.AT_COMMUTER); // 5
		m_airport_types[AIAirport.AT_SMALL] = AIAirport.GetPrice(AIAirport.AT_SMALL); // 0
		m_airport_types[AIAirport.AT_HELISTATION] = AIAirport.GetPrice(AIAirport.AT_HELISTATION); // 8
		m_airport_types[AIAirport.AT_HELIDEPOT] = AIAirport.GetPrice(AIAirport.AT_HELIDEPOT); // 6
		m_airport_types[AIAirport.AT_HELIPORT] = AIAirport.GetPrice(AIAirport.AT_HELIPORT); // 2

		/* Filter out airports larger than the maximum value of a station size */
		local station_spread = AIGameSettings.GetValue("station_spread");
		foreach (a, _ in m_airport_types) {
			if (AIAirport.GetAirportWidth(a) > station_spread) {
				m_airport_types[a] = null;
				continue;
			}
			if (AIAirport.GetAirportHeight(a) > station_spread) {
				m_airport_types[a] = null;
				continue;
			}
			/* Also filter out unavailable airports */
			if (!AIAirport.IsValidAirportType(a)) {
				m_airport_types[a] = null;
				continue;
			}
		}

		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		if (infrastructure) {
//			AILog.Info("Available airport types:");
			local large_airports = AIList();
			local small_airports = AIList();
			local heli_airports = AIList();
			foreach (a, _ in m_airport_types) {
				switch (a) {
					case AIAirport.AT_INTERCON:
					case AIAirport.AT_INTERNATIONAL:
					case AIAirport.AT_METROPOLITAN:
					case AIAirport.AT_LARGE:
						large_airports[a] = AIAirport.GetMonthlyMaintenanceCost(a);
						break;

					case AIAirport.AT_COMMUTER:
					case AIAirport.AT_SMALL:
						small_airports[a] = AIAirport.GetMonthlyMaintenanceCost(a);
						break;

					case AIAirport.AT_HELISTATION:
					case AIAirport.AT_HELIDEPOT:
					case AIAirport.AT_HELIPORT:
						heli_airports[a] = AIAirport.GetMonthlyMaintenanceCost(a);
						break;

					default:
						break;
				}

//				AILog.Info(WrightAI.GetAirportTypeName(a) + " (monthly maintenance cost = " + AIAirport.GetMonthlyMaintenanceCost(a) + ")");
			}
			local large_airports_count = large_airports.Count();
			if (large_airports_count > 1) {
				large_airports.KeepTop(large_airports_count - 1);
				m_airport_types.RemoveList(large_airports);
			}
			local small_airports_count = small_airports.Count();
			if (small_airports_count > 1) {
				small_airports.KeepTop(small_airports_count - 1);
				m_airport_types.RemoveList(small_airports);
			}
			local heli_airports_count = heli_airports.Count();
			if (heli_airports_count == 1 && heli_airports.HasItem(AIAirport.AT_HELIPORT)) {
				m_airport_types[AIAirport.AT_HELIPORT] = null;
			} else if (heli_airports_count > 1) {
				if (heli_airports.HasItem(AIAirport.AT_HELIPORT)) {
					heli_airports[AIAirport.AT_HELIPORT] = null;
					if (--heli_airports_count > 1) {
						heli_airports.KeepTop(heli_airports_count - 1);
						m_airport_types.RemoveList(heli_airports);
					}
				} else {
					heli_airports.KeepTop(heli_airports_count - 1);
					m_airport_types.RemoveList(heli_airports);
				}
			}
		}

		/* No airports available. Abort */
		if (m_airport_types.IsEmpty()) {
			SetRouteFinished();
			return null;
		}

		local available_engines = false;
		local engine_costs = 0;

		UpdateAircraftLists();

		local engine_count = 2;
		if (infrastructure && num_vehicles == 0 && AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_ROAD) == 0 && AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_RAIL) == 0 && AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_WATER) == 0) {
			if (m_airportFrom != -1 && m_airportFrom > 0) {
				local engine_id = GetBestAirportEngine(m_fromType);
				local default_count = 8;
				if (engine_id != null) {
					local count = WrightAI().GetEngineOptimalDaysInTransit(engine_id, m_cargoType, DAYS_INTERVAL, true, m_airportFrom, m_fromType);
					default_count = count[2] > 0 && count[2] != 1000 ? count[2] : default_count;
				}
				engine_count = default_count;
			} else {
				engine_count = 8;
			}
		}
		if (m_big_engine_list.IsEmpty()) {
			if (infrastructure) {
				m_airport_types[AIAirport.AT_INTERCON] = null;
				m_airport_types[AIAirport.AT_INTERNATIONAL] = null;
				m_airport_types[AIAirport.AT_METROPOLITAN] = null;
				m_airport_types[AIAirport.AT_LARGE] = null;
			}
		} else {
			available_engines = true;
			engine_costs = AIEngine.GetPrice(m_big_engine_list.Begin()) * engine_count;
		}

		if (m_small_engine_list.IsEmpty()) {
			if (infrastructure) {
				m_airport_types[AIAirport.AT_COMMUTER] = null;
				m_airport_types[AIAirport.AT_SMALL] = null;
			}
		} else {
			available_engines = true;
			local costs = AIEngine.GetPrice(m_small_engine_list.Begin()) * engine_count;
			if (engine_costs < costs) {
				engine_costs = costs;
			}
		}

		if (m_helicopter_list.IsEmpty()) {
			m_airport_types[AIAirport.AT_HELISTATION] = null;
			m_airport_types[AIAirport.AT_HELIDEPOT] = null;
			m_airport_types[AIAirport.AT_HELIPORT] = null;
		} else {
			available_engines = true;
			local costs = AIEngine.GetPrice(m_helicopter_list.Begin()) * engine_count;
			if (engine_costs < costs) {
				engine_costs = costs;
			}
		}

		/* There are no engines available */
		if (!available_engines) {
			SetRouteFinished();
			return null;
		}

		/* Not enough money */
		local estimated_costs = m_airport_types[m_airport_types.Begin()] + engine_costs + 12500 * engine_count;
//		AILog.Info("estimated_costs = " + estimated_costs + "; airport = " + WrightAI.GetAirportTypeName(m_airport_types.Begin()) + ", " + m_airport_types[m_airport_types.Begin()] + "; engine_costs = " + engine_costs + " + 12500 * " + engine_count);
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
			m_airport_types[m_fromType] = null;
			m_airport_types.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		}

		if (infrastructure && (m_fromType == AIAirport.AT_HELISTATION || m_fromType == AIAirport.AT_HELIDEPOT) && m_airport_types.HasItem(AIAirport.AT_HELIPORT)) {
			if (AIAirport.GetMonthlyMaintenanceCost(m_fromType) > AIAirport.GetMonthlyMaintenanceCost(AIAirport.AT_HELIPORT)) {
				m_airport_types[m_fromType] = null;
				m_airport_types.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
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

	function BuildTownAirport(airRouteManager, airTownManager, town, cargoClass, large_aircraft, small_aircraft, helicopter, best_routes_built, all_routes_built)
	{
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
			if (!large_aircraft || (!AIAirport.IsValidAirportType(AIAirport.AT_INTERCON) && !AIAirport.IsValidAirportType(AIAirport.AT_INTERNATIONAL) && !AIAirport.IsValidAirportType(AIAirport.AT_METROPOLITAN) && !AIAirport.IsValidAirportType(AIAirport.AT_LARGE))) {
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
				large_engine = WrightAI().GetBestEngineIncome(large_engine_list, m_cargoType, DAYS_INTERVAL);
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
				if (!airTownManager.m_nearCityPairArray[cargoClass].len()) {
					large_available = false;
				}
			}

			if (large_available) {
				foreach (near_city_pair in airTownManager.m_nearCityPairArray[cargoClass]) {
					if (m_cityFrom == near_city_pair[0]) {
						if (!airRouteManager.TownRouteExists(m_cityFrom, near_city_pair[1], cargoClass)) {
							large_cityTo = near_city_pair[1];

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
				if (dist > large_max_dist || dist < large_min_dist || fake > large_fakedist) {
//					AILog.Info("large_available distances null");
					large_available = false;
				} else {
					large_closestTowns[large_cityTo] = 0;
				}
			}


			if (!small_aircraft || (!AIAirport.IsValidAirportType(AIAirport.AT_COMMUTER) && !AIAirport.IsValidAirportType(AIAirport.AT_SMALL))) {
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
				small_engine = WrightAI().GetBestEngineIncome(small_engine_list, m_cargoType, DAYS_INTERVAL);
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
				if (!airTownManager.m_nearCityPairArray[cargoClass].len()) {
					small_available = false;
				}
			}

			if (small_available) {
				foreach (near_city_pair in airTownManager.m_nearCityPairArray[cargoClass]) {
					if (m_cityFrom == near_city_pair[0]) {
						if (!airRouteManager.TownRouteExists(m_cityFrom, near_city_pair[1], cargoClass)) {
							small_cityTo = near_city_pair[1];

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
				if (dist > small_max_dist || dist < small_min_dist || fake > small_fakedist) {
//					AILog.Info("small_available distances null");
					small_available = false;
				} else {
					small_closestTowns[small_cityTo] = 0;
				}
			}


			if (!helicopter || (!AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) && !AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT) && !AIAirport.IsValidAirportType(AIAirport.AT_HELIPORT))) {
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
				heli_engine = WrightAI().GetBestEngineIncome(heli_engine_list, m_cargoType, DAYS_INTERVAL);
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
				if (!airTownManager.m_nearCityPairArray[cargoClass].len()) {
					heli_available = false;
				}
			}

			if (heli_available) {
				foreach (near_city_pair in airTownManager.m_nearCityPairArray[cargoClass]) {
					if (m_cityFrom == near_city_pair[0]) {
						if (!airRouteManager.TownRouteExists(m_cityFrom, near_city_pair[1], cargoClass)) {
							heli_cityTo = near_city_pair[1];

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
				if (dist > heli_max_dist || dist < heli_min_dist || fake > heli_fakedist) {
//					AILog.Info("heli_available distances null");
					heli_available = false;
				} else {
					heli_closestTowns[heli_cityTo] = 0;
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
			town_list[town] = 0;
		}
		foreach (t, _ in town_list) {
			local town_tile = AITown.GetLocation(t);

			foreach (a, _ in m_airport_types) {
				if (!AIAirport.IsValidAirportType(a)) {
					continue;
				}

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

					if (!closestTowns.HasItem(t)) {
						continue;
					}
				}

				AILog.Info("a:Checking " + AITown.GetName(t) + " for an airport of type " + WrightAI.GetAirportTypeName(a));

				local airport_x = AIAirport.GetAirportWidth(a);
				local airport_y = AIAirport.GetAirportHeight(a);
				local airport_rad = AIAirport.GetAirportCoverageRadius(a);

				local town_rectangle = Utils.EstimateTownRectangle(t);
				local town_rectangle_expanded = OrthogonalTileArea.CreateArea(town_rectangle[0], town_rectangle[1]);
				town_rectangle_expanded.Expand(airport_x - 1, airport_y - 1, false);
				town_rectangle_expanded.Expand(airport_rad, airport_rad);

				local tileList = AITileList();
				tileList.AddRectangle(town_rectangle_expanded.tile_top, town_rectangle_expanded.tile_bot);

				foreach (tile, _ in tileList) {
					if (m_airportFrom > 0) {
						/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
						local distance_square = AITile.GetDistanceSquareToTile(tile, m_airportFrom);
						if (distance_square <= min_dist) {
							tileList[tile] = null;
							continue;
						}
						if (distance_square >= max_dist) {
							tileList[tile] = null;
							continue;
						}
						if (WrightAI.DistanceRealFake(tile, m_airportFrom) >= fakedist) {
							tileList[tile] = null;
							continue;
						}
					}

					if (!AITile.IsBuildableRectangle(tile, airport_x, airport_y)) {
						tileList[tile] = null;
						continue;
					}

					/* Sort on acceptance, remove places that don't have acceptance */
					if (AITile.GetCargoAcceptance(tile, m_cargoType, airport_x, airport_y, airport_rad) < 10) {
						tileList[tile] = null;
						continue;
					}

					local secondary_cargo = Utils.GetCargoType(AICargo.CC_MAIL);
					if (AIController.GetSetting("select_town_cargo") == 2 && AICargo.IsValidCargo(secondary_cargo) && secondary_cargo != m_cargoType) {
						if (AITile.GetCargoAcceptance(tile, secondary_cargo, airport_x, airport_y, airport_rad) < 10) {
							tileList[tile] = null;
							continue;
						}
					}

					local cargo_production = AITile.GetCargoProduction(tile, m_cargoType, airport_x, airport_y, airport_rad);
					if (pick_mode != 1 && (!best_routes_built || infrastructure) && cargo_production < 18) {
						tileList[tile] = null;
						continue;
					} else {
						local airport_rectangle = OrthogonalTileArea(tile, airport_x, airport_y);
						tileList[tile] = (cargo_production << 13) | (0x1FFF - airport_rectangle.DistanceManhattan(town_tile));
					}
				}

				/* Couldn't find a suitable place for this town */
				if (tileList.IsEmpty()) {
					continue;
				}

				/* Walk all the tiles and see if we can build the airport at all */
				local good_tile = 0;
				foreach (tile, _ in tileList) {
					local noise = AIAirport.GetNoiseLevelIncrease(tile, a);
					local allowed_noise = AITown.GetAllowedNoise(AIAirport.GetNearestTown(tile, a));
					if (noise > allowed_noise) {
						continue;
					}
//					AISign.BuildSign(tile, ("" + noise + " <= " + allowed_noise + ""));

					local airport_rectangle = OrthogonalTileArea(tile, airport_x, airport_y);

					local adjacent_station_id = AIStation.STATION_NEW;
					local spread_rad = AIGameSettings.GetValue("station_spread");
					if (spread_rad && AIGameSettings.GetValue("distant_join_stations")) {
						local remaining_x = spread_rad - airport_x;
						local remaining_y = spread_rad - airport_y;
						local spread_rectangle = clone airport_rectangle;
						spread_rectangle.Expand(remaining_x, remaining_y);
						adjacent_station_id = WrightAI.GetAdjacentNonAirportStationID(airport_rectangle, spread_rectangle);
					}

					local nearest_town;
					if (adjacent_station_id == AIStation.STATION_NEW) {
						nearest_town = AITile.GetClosestTown(tile);
						if (nearest_town != t) {
							continue;
						}
					} else {
						nearest_town = AIStation.GetNearestTown(adjacent_station_id);
						if (nearest_town != t) {
							adjacent_station_id = AIStation.STATION_NEW;
							nearest_town = AITile.GetClosestTown(tile);
							if (nearest_town != t) {
								continue;
							}
						}
					}

					if (AITestMode() && !AIAirport.BuildAirport(tile, a, adjacent_station_id)) {
						continue;
					}
					good_tile = tile;

					/* Don't build airport if there is any competitor station in the vicinity, or an airport of mine */
					local airport_coverage = clone airport_rectangle;
					airport_coverage.Expand(airport_rad, airport_rad);
					local tileList2 = AITileList();
					tileList2.AddRectangle(airport_coverage.tile_top, airport_coverage.tile_bot);
					tileList2.RemoveRectangle(airport_rectangle.tile_top, airport_rectangle.tile_bot);
					local nearby_station = false;
					foreach (tile2, _ in tileList2) {
						if (!AITile.IsStationTile(tile2)) {
							continue;
						}
						if (AIAirport.IsAirportTile(tile2) || (AITile.GetOwner(tile2) != ::caches.myCID && AIController.GetSetting("is_friendly"))) {
							nearby_station = true;
							break;
						}
					}
					if (nearby_station) {
						continue;
					}

					if (m_airportFrom == -1) {
						m_fromType = a;
						m_fromStationID = adjacent_station_id;

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
						m_toStationID = adjacent_station_id;
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

	function UpdateAircraftLists()
	{
		m_big_engine_list.Clear();
		m_small_engine_list.Clear();
		m_helicopter_list.Clear();

		local from_location = (m_airportFrom != null && m_airportFrom > 0) ? m_airportFrom : null;
		local from_type = from_location == null ? null : m_fromType

		local all_engines = AIEngineList(AIVehicle.VT_AIR);
		foreach (engine, _ in all_engines) {
			if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, m_cargoType)) {
				local income = WrightAI().GetEngineOptimalDaysInTransit(engine, m_cargoType, DAYS_INTERVAL, true, from_location, from_type);
				switch (AIEngine.GetPlaneType(engine)) {
					case AIAirport.PT_BIG_PLANE: {
						m_big_engine_list[engine] = income[0];
						break;
					}
					case AIAirport.PT_SMALL_PLANE: {
						m_small_engine_list[engine] = income[0];
						break;
					}
					case AIAirport.PT_HELICOPTER: {
						m_helicopter_list[engine] = income[0];
						break;
					}
				}
			}
		}
	}

	function GetBestAirportEngine(type, return_list = false)
	{
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

		if (engine_list.IsEmpty()) {
			return null;
		} else if (return_list) {
			return engine_list;
		}
		return engine_list.Begin();
	}

	function SaveBuildManager()
	{
		if (m_cityFrom == null) m_cityFrom = -1;
		if (m_cityTo == null) m_cityTo = -1;
		if (m_airportFrom == null) m_airportFrom = -1;
		if (m_airportTo == null) m_airportTo = -1;

		return [m_cityFrom, m_cityTo, m_airportFrom, m_airportTo, m_cargoClass, m_best_routes_built, m_fromType, m_toType, m_fromStationID, m_toStationID, m_large_aircraft_route, m_small_aircraft_route, m_helicopter_route];
	}

	function LoadBuildManager(data)
	{
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
};
