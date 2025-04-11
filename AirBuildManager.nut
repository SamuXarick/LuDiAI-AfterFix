class AirBuildManager
{
	static DAYS_INTERVAL = 10;

	/* These are saved */
	m_city_from = -1;
	m_city_to = -1;
	m_airport_from = -1;
	m_airport_to = -1;
	m_cargo_class = -1;
	m_best_routes_built = null;
	m_airport_type_from = AIAirport.AT_INVALID;
	m_airport_type_to = AIAirport.AT_INVALID;
	m_station_id_from = AIStation.STATION_INVALID;
	m_station_id_to = AIStation.STATION_INVALID;
	m_small_aircraft_route = false;
	m_large_aircraft_route = false;
	m_helicopter_route = false;

	/* These are not saved */
	m_airport_types = AIList();
	m_big_engine_list = AIList();
	m_small_engine_list = AIList();
	m_helicopter_list = AIList();
	m_sent_to_depot_air_group = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_cargo_type = -1;

	function HasUnfinishedRoute()
	{
		return this.m_city_from != -1 && this.m_city_to != -1 && this.m_cargo_class != -1;
	}

	function SetRouteFinished()
	{
		this.m_city_from = -1;
		this.m_city_to = -1;
		this.m_airport_from = -1;
		this.m_airport_to = -1;
		this.m_cargo_class = -1;
		this.m_sent_to_depot_air_group = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
		this.m_best_routes_built = null;
		this.m_airport_type_from = AIAirport.AT_INVALID;
		this.m_airport_type_to = AIAirport.AT_INVALID;
		this.m_station_id_from = AIStation.STATION_INVALID;
		this.m_station_id_to = AIStation.STATION_INVALID;
		this.m_small_aircraft_route = false;
		this.m_large_aircraft_route = false;
		this.m_helicopter_route = false;
		this.m_cargo_type = -1;
		this.m_airport_types.Clear();
	}

	function BuildAirRoute(air_route_manager, air_town_manager, city_from, city_to, cargo_class, sent_to_depot_air_group, best_routes_built, all_routes_built)
	{
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_cargo_class = cargo_class;
		this.m_sent_to_depot_air_group = sent_to_depot_air_group;
		this.m_best_routes_built = best_routes_built;
		this.m_cargo_type = Utils.GetCargoType(cargo_class);

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_AIR);
		if (num_vehicles >= AIGameSettings.GetValue("max_aircraft") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		/* Create a list of available airports */
		this.m_airport_types[AIAirport.AT_INTERCON] = AIAirport.GetPrice(AIAirport.AT_INTERCON); // 7
		this.m_airport_types[AIAirport.AT_INTERNATIONAL] = AIAirport.GetPrice(AIAirport.AT_INTERNATIONAL); // 4
		this.m_airport_types[AIAirport.AT_METROPOLITAN] = AIAirport.GetPrice(AIAirport.AT_METROPOLITAN); // 3
		this.m_airport_types[AIAirport.AT_LARGE] = AIAirport.GetPrice(AIAirport.AT_LARGE); // 1
		this.m_airport_types[AIAirport.AT_COMMUTER] = AIAirport.GetPrice(AIAirport.AT_COMMUTER); // 5
		this.m_airport_types[AIAirport.AT_SMALL] = AIAirport.GetPrice(AIAirport.AT_SMALL); // 0
		this.m_airport_types[AIAirport.AT_HELISTATION] = AIAirport.GetPrice(AIAirport.AT_HELISTATION); // 8
		this.m_airport_types[AIAirport.AT_HELIDEPOT] = AIAirport.GetPrice(AIAirport.AT_HELIDEPOT); // 6
		this.m_airport_types[AIAirport.AT_HELIPORT] = AIAirport.GetPrice(AIAirport.AT_HELIPORT); // 2

		/* Filter out airports larger than the maximum value of a station size */
		local station_spread = AIGameSettings.GetValue("station_spread");
		foreach (a, _ in this.m_airport_types) {
			if (AIAirport.GetAirportWidth(a) > station_spread) {
				this.m_airport_types[a] = null;
				continue;
			}
			if (AIAirport.GetAirportHeight(a) > station_spread) {
				this.m_airport_types[a] = null;
				continue;
			}
			/* Also filter out unavailable airports */
			if (!AIAirport.IsValidAirportType(a)) {
				this.m_airport_types[a] = null;
				continue;
			}
		}

		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		if (infrastructure) {
//			AILog.Info("Available airport types:");
			local large_airports = AIList();
			local small_airports = AIList();
			local heli_airports = AIList();
			foreach (a, _ in this.m_airport_types) {
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
				this.m_airport_types.RemoveList(large_airports);
			}
			local small_airports_count = small_airports.Count();
			if (small_airports_count > 1) {
				small_airports.KeepTop(small_airports_count - 1);
				this.m_airport_types.RemoveList(small_airports);
			}
			local heli_airports_count = heli_airports.Count();
			if (heli_airports_count == 1 && heli_airports.HasItem(AIAirport.AT_HELIPORT)) {
				this.m_airport_types[AIAirport.AT_HELIPORT] = null;
			} else if (heli_airports_count > 1) {
				if (heli_airports.HasItem(AIAirport.AT_HELIPORT)) {
					heli_airports[AIAirport.AT_HELIPORT] = null;
					if (--heli_airports_count > 1) {
						heli_airports.KeepTop(heli_airports_count - 1);
						this.m_airport_types.RemoveList(heli_airports);
					}
				} else {
					heli_airports.KeepTop(heli_airports_count - 1);
					this.m_airport_types.RemoveList(heli_airports);
				}
			}
		}

		/* No airports available. Abort */
		if (this.m_airport_types.IsEmpty()) {
			this.SetRouteFinished();
			return null;
		}

		local available_engines = false;
		local engine_costs = 0;

		this.UpdateAircraftLists();

		local engine_count = 2;
		if (infrastructure && num_vehicles == 0 && AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_ROAD) == 0 && AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_RAIL) == 0 && AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_WATER) == 0) {
			if (this.m_airport_from != -1 && this.m_airport_from > 0) {
				local engine_id = this.GetBestAirportEngine(this.m_airport_type_from);
				local default_count = 8;
				if (engine_id != null) {
					local count = WrightAI().GetEngineOptimalDaysInTransit(engine_id, this.m_cargo_type, DAYS_INTERVAL, true, this.m_airport_from, this.m_airport_type_from);
					default_count = count[2] > 0 && count[2] != 1000 ? count[2] : default_count;
				}
				engine_count = default_count;
			} else {
				engine_count = 8;
			}
		}
		if (this.m_big_engine_list.IsEmpty()) {
			if (infrastructure) {
				this.m_airport_types[AIAirport.AT_INTERCON] = null;
				this.m_airport_types[AIAirport.AT_INTERNATIONAL] = null;
				this.m_airport_types[AIAirport.AT_METROPOLITAN] = null;
				this.m_airport_types[AIAirport.AT_LARGE] = null;
			}
		} else {
			available_engines = true;
			engine_costs = AIEngine.GetPrice(this.m_big_engine_list.Begin()) * engine_count;
		}

		if (this.m_small_engine_list.IsEmpty()) {
			if (infrastructure) {
				this.m_airport_types[AIAirport.AT_COMMUTER] = null;
				this.m_airport_types[AIAirport.AT_SMALL] = null;
			}
		} else {
			available_engines = true;
			local costs = AIEngine.GetPrice(this.m_small_engine_list.Begin()) * engine_count;
			if (engine_costs < costs) {
				engine_costs = costs;
			}
		}

		if (this.m_helicopter_list.IsEmpty()) {
			this.m_airport_types[AIAirport.AT_HELISTATION] = null;
			this.m_airport_types[AIAirport.AT_HELIDEPOT] = null;
			this.m_airport_types[AIAirport.AT_HELIPORT] = null;
		} else {
			available_engines = true;
			local costs = AIEngine.GetPrice(this.m_helicopter_list.Begin()) * engine_count;
			if (engine_costs < costs) {
				engine_costs = costs;
			}
		}

		/* There are no engines available */
		if (!available_engines) {
			this.SetRouteFinished();
			return null;
		}

		/* Not enough money */
		local estimated_costs = this.m_airport_types[this.m_airport_types.Begin()] + engine_costs + 12500 * engine_count;
//		AILog.Info("estimated_costs = " + estimated_costs + "; airport = " + WrightAI.GetAirportTypeName(this.m_airport_types.Begin()) + ", " + this.m_airport_types[this.m_airport_types.Begin()] + "; engine_costs = " + engine_costs + " + 12500 * " + engine_count);
		if (!Utils.HasMoney(estimated_costs)) {
//			this.SetRouteFinished();
			return 0;
		}

		if (this.m_airport_from == -1) {
			this.m_airport_from = this.BuildTownAirport(air_route_manager, air_town_manager, this.m_city_from, all_routes_built);
			if (this.m_airport_from == null) {
				this.SetRouteFinished();
				return null;
			}

			return 0;
		}

		if (this.m_airport_type_from == AIAirport.AT_HELIPORT) {
			this.m_airport_types[this.m_airport_type_from] = null;
			this.m_airport_types.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		}

		if (infrastructure && (this.m_airport_type_from == AIAirport.AT_HELISTATION || this.m_airport_type_from == AIAirport.AT_HELIDEPOT) && this.m_airport_types.HasItem(AIAirport.AT_HELIPORT)) {
			if (AIAirport.GetMonthlyMaintenanceCost(this.m_airport_type_from) > AIAirport.GetMonthlyMaintenanceCost(AIAirport.AT_HELIPORT)) {
				this.m_airport_types[this.m_airport_type_from] = null;
				this.m_airport_types.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
			}
		}

		if (this.m_airport_to == -1) {
			this.m_airport_to = this.BuildTownAirport(air_route_manager, air_town_manager, this.m_city_to, all_routes_built);
			if (this.m_airport_to == null) {
				this.SetRouteFinished();
				return null;
			}
		}

		if (this.m_airport_type_from != AIAirport.AT_INVALID && this.m_airport_type_to != AIAirport.AT_INVALID) {
			/* Build the airports for real */
			if (!TestBuildAirport().TryBuild(this.m_airport_from, this.m_airport_type_from, this.m_station_id_from)) {
				AILog.Error("a:Although the testing told us we could build 2 airports, it still failed on the first airport at tile " + this.m_airport_from + ".");
				this.SetRouteFinished();
				return null;
			}

			if (!TestBuildAirport().TryBuild(this.m_airport_to, this.m_airport_type_to, this.m_station_id_to)) {
				AILog.Error("a:Although the testing told us we could build 2 airports, it still failed on the second airport at tile " + this.m_airport_to + ".");

				local counter = 0;
				do {
					if (!TestRemoveAirport().TryRemove(this.m_airport_from)) {
						++counter;
					}
					else {
//						AILog.Warning("this.m_airport_to; Removed airport at tile " + this.m_airport_from);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Aircraft.rawset(this.m_airport_from, 0);
//					AILog.Error("Failed to remove airport at tile " + this.m_airport_from + " - " + AIError.GetLastErrorString());
				}
				this.SetRouteFinished();
				return null;
			}
		}

		return AirRoute(this.m_city_from, this.m_city_to, this.m_airport_from, this.m_airport_to, this.m_cargo_class, this.m_sent_to_depot_air_group);
	}

	function BuildTownAirport(air_route_manager, air_town_manager, town_id, all_routes_built)
	{
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		local pick_mode = AIController.GetSetting("pick_mode");

		local large_engine_list = this.GetBestAirportEngine(AIAirport.AT_LARGE, true);
		local small_engine_list = this.GetBestAirportEngine(AIAirport.AT_SMALL, true);
		local heli_engine_list = this.GetBestAirportEngine(AIAirport.AT_HELIPORT, true);
		if (large_engine_list == null && small_engine_list == null && heli_engine_list == null) {
			return null;
		}

		local large_available = true;
		local large_fake_dist;
		local large_max_dist;
		local large_min_dist;
		local large_city_to = null;
		local large_closest_towns = AIList();

		local small_available = true;
		local small_fake_dist;
		local small_max_dist;
		local small_min_dist;
		local small_city_to = null;
		local small_closest_towns = AIList();

		local heli_available = true;
		local heli_fake_dist;
		local heli_max_dist;
		local heli_min_dist;
		local heli_city_to = null;
		local heli_closest_towns = AIList();

		if (this.m_airport_from > 0) {
			if (!this.m_large_aircraft_route || (!AIAirport.IsValidAirportType(AIAirport.AT_INTERCON) && !AIAirport.IsValidAirportType(AIAirport.AT_INTERNATIONAL) && !AIAirport.IsValidAirportType(AIAirport.AT_METROPOLITAN) && !AIAirport.IsValidAirportType(AIAirport.AT_LARGE))) {
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
				large_engine = WrightAI().GetBestEngineIncome(large_engine_list, this.m_cargo_type, DAYS_INTERVAL);
				if (large_engine[0] == null) {
//					AILog.Info("large_available = false [3]");
					large_available = false;
				}
			}

			if (large_available) {
				large_fake_dist = large_engine[1];

				/* Best engine is unprofitable enough */
				if (large_fake_dist == 0) {
//					AILog.Info("large_available = false [4]");
					large_available = false;
				}
			}

			if (large_available) {
				/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
				local large_max_order_dist = WrightAI.GetMaximumOrderDistance(large_engine[0]);
				large_max_dist = large_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : large_max_order_dist;
				local large_min_order_dist = (large_fake_dist / 2) * (large_fake_dist / 2);
				large_min_dist = large_min_order_dist > large_max_dist * 3 / 4 ? !infrastructure && large_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : large_max_dist * 3 / 4 : large_min_order_dist;

				air_town_manager.FindNearCities(this.m_city_from, large_min_dist, large_max_dist, this.m_best_routes_built, this.m_cargo_class, large_fake_dist);
				if (!air_town_manager.m_near_city_pair_array[this.m_cargo_class].len()) {
					large_available = false;
				}
			}

			if (large_available) {
				foreach (near_city_pair in air_town_manager.m_near_city_pair_array[this.m_cargo_class]) {
					if (this.m_city_from == near_city_pair[0]) {
						if (!air_route_manager.TownRouteExists(this.m_city_from, near_city_pair[1], this.m_cargo_class)) {
							large_city_to = near_city_pair[1];

							if (pick_mode != 1 && all_routes_built && air_route_manager.HasMaxStationCount(this.m_city_from, large_city_to, this.m_cargo_class)) {
//								AILog.Info("air_route_manager.HasMaxStationCount(" + AITown.GetName(this.m_city_from) + ", " + AITown.GetName(large_city_to) + ", " + this.m_cargo_class + ") == " + air_route_manager.HasMaxStationCount(this.m_city_from, large_city_to, this.m_cargo_class));
								large_city_to = null;
								continue;
							} else {
//								AILog.Info("air_route_manager.HasMaxStationCount(" + AITown.GetName(this.m_city_from) + ", " + AITown.GetName(large_city_to) + ", " + this.m_cargo_class + ") == " + air_route_manager.HasMaxStationCount(this.m_city_from, large_city_to, this.m_cargo_class));
								break;
							}
						}
					}
				}

				if (large_city_to == null) {
					large_available = false;
				}
			}

			if (large_available) {
				local town_tile = AITown.GetLocation(large_city_to);
				local dist = AITile.GetDistanceSquareToTile(town_tile, this.m_airport_from);
				local fake = WrightAI.DistanceRealFake(town_tile, this.m_airport_from);
				if (dist > large_max_dist || dist < large_min_dist || fake > large_fake_dist) {
//					AILog.Info("large_available distances null");
					large_available = false;
				} else {
					large_closest_towns[large_city_to] = 0;
				}
			}


			if (!this.m_small_aircraft_route || (!AIAirport.IsValidAirportType(AIAirport.AT_COMMUTER) && !AIAirport.IsValidAirportType(AIAirport.AT_SMALL))) {
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
				small_engine = WrightAI().GetBestEngineIncome(small_engine_list, this.m_cargo_type, DAYS_INTERVAL);
				if (small_engine[0] == null) {
//					AILog.Info("small_available = false [3]");
					small_available = false;
				}
			}

			if (small_available) {
				small_fake_dist = small_engine[1];

				/* Best engine is unprofitable enough */
				if (small_fake_dist == 0) {
//					AILog.Info("small_available = false [4]");
					small_available = false;
				}
			}

			if (small_available) {
				/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
				local small_max_order_dist = WrightAI.GetMaximumOrderDistance(small_engine[0]);
				small_max_dist = small_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : small_max_order_dist;
				local small_min_order_dist = (small_fake_dist / 2) * (small_fake_dist / 2);
				small_min_dist = small_min_order_dist > small_max_dist * 3 / 4 ? !infrastructure && small_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : small_max_dist * 3 / 4 : small_min_order_dist;

				air_town_manager.FindNearCities(this.m_city_from, small_min_dist, small_max_dist, this.m_best_routes_built, this.m_cargo_class, small_fake_dist);
				if (!air_town_manager.m_near_city_pair_array[this.m_cargo_class].len()) {
					small_available = false;
				}
			}

			if (small_available) {
				foreach (near_city_pair in air_town_manager.m_near_city_pair_array[this.m_cargo_class]) {
					if (this.m_city_from == near_city_pair[0]) {
						if (!air_route_manager.TownRouteExists(this.m_city_from, near_city_pair[1], this.m_cargo_class)) {
							small_city_to = near_city_pair[1];

							if (pick_mode != 1 && all_routes_built && air_route_manager.HasMaxStationCount(this.m_city_from, small_city_to, this.m_cargo_class)) {
//								AILog.Info("air_route_manager.HasMaxStationCount(" + AITown.GetName(this.m_city_from) + ", " + AITown.GetName(small_city_to) + ", " + this.m_cargo_class + ") == " + air_route_manager.HasMaxStationCount(this.m_city_from, small_city_to, this.m_cargo_class));
								small_city_to = null;
								continue;
							} else {
//								AILog.Info("air_route_manager.HasMaxStationCount(" + AITown.GetName(this.m_city_from) + ", " + AITown.GetName(small_city_to) + ", " + this.m_cargo_class + ") == " + air_route_manager.HasMaxStationCount(this.m_city_from, small_city_to, this.m_cargo_class));
								break;
							}
						}
					}
				}

				if (small_city_to == null) {
					small_available = false;
				}
			}

			if (small_available) {
				local town_tile = AITown.GetLocation(small_city_to);
				local dist = AITile.GetDistanceSquareToTile(town_tile, this.m_airport_from);
				local fake = WrightAI.DistanceRealFake(town_tile, this.m_airport_from);
				if (dist > small_max_dist || dist < small_min_dist || fake > small_fake_dist) {
//					AILog.Info("small_available distances null");
					small_available = false;
				} else {
					small_closest_towns[small_city_to] = 0;
				}
			}


			if (!this.m_helicopter_route || (!AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) && !AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT) && !AIAirport.IsValidAirportType(AIAirport.AT_HELIPORT))) {
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
				heli_engine = WrightAI().GetBestEngineIncome(heli_engine_list, this.m_cargo_type, DAYS_INTERVAL);
				if (heli_engine[0] == null) {
//					AILog.Info("heli_available = false [3]");
					heli_available = false;
				}
			}

			if (heli_available) {
				heli_fake_dist = heli_engine[1];

				/* Best engine is unprofitable enough */
				if (heli_fake_dist == 0) {
//					AILog.Info("heli_available = false [4]");
					heli_available = false;
				}
			}

			if (heli_available) {
				/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
				local heli_max_order_dist = WrightAI.GetMaximumOrderDistance(heli_engine[0]);
				heli_max_dist = heli_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : heli_max_order_dist;
				local heli_min_order_dist = (heli_fake_dist / 2) * (heli_fake_dist / 2);
				heli_min_dist = heli_min_order_dist > heli_max_dist * 3 / 4 ? !infrastructure && heli_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : heli_max_dist * 3 / 4 : heli_min_order_dist;

				air_town_manager.FindNearCities(this.m_city_from, heli_min_dist, heli_max_dist, this.m_best_routes_built, this.m_cargo_class, heli_fake_dist);
				if (!air_town_manager.m_near_city_pair_array[this.m_cargo_class].len()) {
					heli_available = false;
				}
			}

			if (heli_available) {
				foreach (near_city_pair in air_town_manager.m_near_city_pair_array[this.m_cargo_class]) {
					if (this.m_city_from == near_city_pair[0]) {
						if (!air_route_manager.TownRouteExists(this.m_city_from, near_city_pair[1], this.m_cargo_class)) {
							heli_city_to = near_city_pair[1];

							if (pick_mode != 1 && all_routes_built && air_route_manager.HasMaxStationCount(this.m_city_from, heli_city_to, this.m_cargo_class)) {
//								AILog.Info("air_route_manager.HasMaxStationCount(" + AITown.GetName(this.m_city_from) + ", " + AITown.GetName(heli_city_to) + ", " + this.m_cargo_class + ") == " + air_route_manager.HasMaxStationCount(this.m_city_from, heli_city_to, this.m_cargo_class));
								heli_city_to = null;
								continue;
							} else {
//								AILog.Info("air_route_manager.HasMaxStationCount(" + AITown.GetName(this.m_city_from) + ", " + AITown.GetName(heli_city_to) + ", " + this.m_cargo_class + ") == " + air_route_manager.HasMaxStationCount(this.m_city_from, heli_city_to, this.m_cargo_class));
								break;
							}
						}
					}
				}

				if (heli_city_to == null) {
					heli_available = false;
				}
			}

			if (heli_available) {
				local town_tile = AITown.GetLocation(heli_city_to);
				local dist = AITile.GetDistanceSquareToTile(town_tile, this.m_airport_from);
				local fake = WrightAI.DistanceRealFake(town_tile, this.m_airport_from);
				if (dist > heli_max_dist || dist < heli_min_dist || fake > heli_fake_dist) {
//					AILog.Info("heli_available distances null");
					heli_available = false;
				} else {
					heli_closest_towns[heli_city_to] = 0;
				}
			}


			if (!large_available && !small_available && !heli_available) {
//				AILog.Info("!large_available && !small_available && !heli_available");
				return null;
			}
		}

		/* Now find a suitable town */
		local town_list = AIList();
		if (this.m_airport_from > 0) {
			town_list.AddList(large_closest_towns);
			town_list.AddList(small_closest_towns);
			town_list.AddList(heli_closest_towns);
		} else {
			town_list[town_id] = 0;
		}
		foreach (t, _ in town_list) {
			local town_tile = AITown.GetLocation(t);

			foreach (a, _ in this.m_airport_types) {
				if (!AIAirport.IsValidAirportType(a)) {
					continue;
				}

				if (this.m_large_aircraft_route && a != AIAirport.AT_INTERCON && a != AIAirport.AT_INTERNATIONAL && a != AIAirport.AT_METROPOLITAN && a != AIAirport.AT_LARGE) {
					continue;
				}
				if (this.m_small_aircraft_route && a != AIAirport.AT_INTERCON && a != AIAirport.AT_INTERNATIONAL && a != AIAirport.AT_METROPOLITAN && a != AIAirport.AT_LARGE && a != AIAirport.AT_SMALL && a != AIAirport.AT_COMMUTER) {
					continue;
				}
				if (this.m_helicopter_route && a != AIAirport.AT_HELISTATION && a != AIAirport.AT_HELIDEPOT && a != AIAirport.AT_HELIPORT) {
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

				local fake_dist;
				local max_dist;
				local min_dist;
				if (this.m_airport_from > 0) {
					local closest_towns = AIList();
					if (a == AIAirport.AT_INTERCON || a == AIAirport.AT_INTERNATIONAL || a == AIAirport.AT_METROPOLITAN || a == AIAirport.AT_LARGE) {
						if (this.m_large_aircraft_route) {
							if (large_available) {
								closest_towns.AddList(large_closest_towns);
								fake_dist = large_fake_dist;
								max_dist = large_max_dist;
								min_dist = large_min_dist;
							} else {
								continue;
							}
						}
						if (this.m_small_aircraft_route && !infrastructure) {
							if (small_available) {
								closest_towns.AddList(small_closest_towns);
								fake_dist = small_fake_dist;
								max_dist = small_max_dist;
								min_dist = small_min_dist;
							} else {
								continue;
							}
						}
						if (this.m_helicopter_route && !infrastructure) {
							if (heli_available) {
								closest_towns.AddList(heli_closest_towns);
								fake_dist = heli_fake_dist;
								max_dist = heli_max_dist;
								min_dist = heli_min_dist;
							} else {
								continue;
							}
						}
					} else if (a == AIAirport.AT_COMMUTER || a == AIAirport.AT_SMALL) {
						if (this.m_large_aircraft_route && !infrastructure || this.m_small_aircraft_route) {
							if (small_available) {
								closest_towns.AddList(small_closest_towns);
								fake_dist = small_fake_dist;
								max_dist = small_max_dist;
								min_dist = small_min_dist;
							} else {
								continue;
							}
						}
						if (this.m_helicopter_route && !infrastructure) {
							if (heli_available) {
								closest_towns.AddList(heli_closest_towns);
								fake_dist = heli_fake_dist;
								max_dist = heli_max_dist;
								min_dist = heli_min_dist;
							} else {
								continue;
							}
						}
					} else {
						if (heli_available) {
							closest_towns.AddList(heli_closest_towns);
							fake_dist = heli_fake_dist;
							max_dist = heli_max_dist;
							min_dist = heli_min_dist;
						} else {
							continue;
						}
					}

					if (!closest_towns.HasItem(t)) {
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

				local tile_list = AITileList();
				tile_list.AddRectangle(town_rectangle_expanded.tile_top, town_rectangle_expanded.tile_bot);

				foreach (tile, _ in tile_list) {
					if (this.m_airport_from > 0) {
						/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
						local distance_square = AITile.GetDistanceSquareToTile(tile, this.m_airport_from);
						if (distance_square <= min_dist) {
							tile_list[tile] = null;
							continue;
						}
						if (distance_square >= max_dist) {
							tile_list[tile] = null;
							continue;
						}
						if (WrightAI.DistanceRealFake(tile, this.m_airport_from) >= fake_dist) {
							tile_list[tile] = null;
							continue;
						}
					}

					if (!AITile.IsBuildableRectangle(tile, airport_x, airport_y)) {
						tile_list[tile] = null;
						continue;
					}

					/* Sort on acceptance, remove places that don't have acceptance */
					if (AITile.GetCargoAcceptance(tile, this.m_cargo_type, airport_x, airport_y, airport_rad) < 10) {
						tile_list[tile] = null;
						continue;
					}

					local secondary_cargo = Utils.GetCargoType(AICargo.CC_MAIL);
					if (AIController.GetSetting("select_town_cargo") == 2 && AICargo.IsValidCargo(secondary_cargo) && secondary_cargo != this.m_cargo_type) {
						if (AITile.GetCargoAcceptance(tile, secondary_cargo, airport_x, airport_y, airport_rad) < 10) {
							tile_list[tile] = null;
							continue;
						}
					}

					local cargo_production = AITile.GetCargoProduction(tile, this.m_cargo_type, airport_x, airport_y, airport_rad);
					if (pick_mode != 1 && (!this.m_best_routes_built || infrastructure) && cargo_production < 18) {
						tile_list[tile] = null;
						continue;
					} else {
						local airport_rectangle = OrthogonalTileArea(tile, airport_x, airport_y);
						tile_list[tile] = (cargo_production << 13) | (0x1FFF - airport_rectangle.DistanceManhattan(town_tile));
					}
				}

				/* Couldn't find a suitable place for this town */
				if (tile_list.IsEmpty()) {
					continue;
				}

				/* Walk all the tiles and see if we can build the airport at all */
				local good_tile = 0;
				foreach (tile, _ in tile_list) {
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
					local tile_list2 = AITileList();
					tile_list2.AddRectangle(airport_coverage.tile_top, airport_coverage.tile_bot);
					tile_list2.RemoveRectangle(airport_rectangle.tile_top, airport_rectangle.tile_bot);
					local nearby_station = false;
					foreach (tile2, _ in tile_list2) {
						if (!AITile.IsStationTile(tile2)) {
							continue;
						}
						if (AIAirport.IsAirportTile(tile2) || (AITile.GetOwner(tile2) != ::caches.m_my_company_id && AIController.GetSetting("is_friendly"))) {
							nearby_station = true;
							break;
						}
					}
					if (nearby_station) {
						continue;
					}

					if (this.m_airport_from == -1) {
						this.m_airport_type_from = a;
						this.m_station_id_from = adjacent_station_id;

						if (a == AIAirport.AT_INTERCON || a == AIAirport.AT_INTERNATIONAL || a == AIAirport.AT_METROPOLITAN || a == AIAirport.AT_LARGE) {
							this.m_large_aircraft_route = true;
						}
						if (a == AIAirport.AT_COMMUTER || a == AIAirport.AT_SMALL) {
							this.m_small_aircraft_route = true;
						}
						if (a == AIAirport.AT_HELISTATION || a == AIAirport.AT_HELIDEPOT || a == AIAirport.AT_HELIPORT) {
							this.m_helicopter_route = true;
						}
					} else {
						this.m_airport_type_to = a;
						this.m_station_id_to = adjacent_station_id;
						this.m_city_to = t;
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
		this.m_big_engine_list.Clear();
		this.m_small_engine_list.Clear();
		this.m_helicopter_list.Clear();

		local from_location = (this.m_airport_from != null && this.m_airport_from > 0) ? this.m_airport_from : null;
		local from_type = from_location == null ? null : this.m_airport_type_from

		local all_engines = AIEngineList(AIVehicle.VT_AIR);
		foreach (engine, _ in all_engines) {
			if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, this.m_cargo_type)) {
				local income = WrightAI().GetEngineOptimalDaysInTransit(engine, this.m_cargo_type, DAYS_INTERVAL, true, from_location, from_type);
				switch (AIEngine.GetPlaneType(engine)) {
					case AIAirport.PT_BIG_PLANE: {
						this.m_big_engine_list[engine] = income[0];
						break;
					}
					case AIAirport.PT_SMALL_PLANE: {
						this.m_small_engine_list[engine] = income[0];
						break;
					}
					case AIAirport.PT_HELICOPTER: {
						this.m_helicopter_list[engine] = income[0];
						break;
					}
				}
			}
		}
	}

	function GetBestAirportEngine(type, return_list = false)
	{
//		this.UpdateAircraftLists();
		local engine_list = AIList();
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");

		if (type == AIAirport.AT_INTERCON || type == AIAirport.AT_INTERNATIONAL || type == AIAirport.AT_METROPOLITAN || type == AIAirport.AT_LARGE) {
			engine_list.AddList(this.m_big_engine_list);
			if (!infrastructure) engine_list.AddList(this.m_small_engine_list);
			if (!infrastructure) engine_list.AddList(this.m_helicopter_list);
		}

		if (type == AIAirport.AT_SMALL || type == AIAirport.AT_COMMUTER) {
			engine_list.AddList(this.m_small_engine_list);
			if (!infrastructure) engine_list.AddList(this.m_helicopter_list);
		}

		if (type == AIAirport.AT_HELISTATION || type == AIAirport.AT_HELIDEPOT || type == AIAirport.AT_HELIPORT) {
			engine_list.AddList(this.m_helicopter_list);
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
		if (this.m_city_from == null) this.m_city_from = -1;
		if (this.m_city_to == null) this.m_city_to = -1;
		if (this.m_airport_from == null) this.m_airport_from = -1;
		if (this.m_airport_to == null) this.m_airport_to = -1;

		return [this.m_city_from, this.m_city_to, this.m_airport_from, this.m_airport_to, this.m_cargo_class, this.m_best_routes_built, this.m_airport_type_from, this.m_airport_type_to, this.m_station_id_from, this.m_station_id_to, this.m_large_aircraft_route, this.m_small_aircraft_route, this.m_helicopter_route];
	}

	function LoadBuildManager(data)
	{
		this.m_city_from = data[0];
		this.m_city_to = data[1];
		this.m_airport_from = data[2];
		this.m_airport_to = data[3];
		this.m_cargo_class = data[4];
		this.m_best_routes_built = data[5];
		this.m_airport_type_from = data[6];
		this.m_airport_type_to = data[7];
		this.m_station_id_from = data[8];
		this.m_station_id_to = data[9];
		this.m_large_aircraft_route = data[10];
		this.m_small_aircraft_route = data[11];
		this.m_helicopter_route = data[12];
	}
};
