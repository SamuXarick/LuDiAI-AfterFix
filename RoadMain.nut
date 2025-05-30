function LuDiAIAfterFix::BuildRoadRoute()
{
	if (!AIController.GetSetting("road_support")) return true; // assume true to keep rotating this.transport_mode_rotation

	local unfinished = this.road_build_manager.HasUnfinishedRoute();
	if (unfinished || (this.road_route_manager.GetRoadVehicleCount() < max(AIGameSettings.GetValue("max_roadveh") - 10, 10)) && Utils.ListHasValue(this.road_route_manager.m_routes_built.all, false)) {
		local city_from = null;
		local city_to = null;
		local articulated = true;
		local cargo_class = this.road_route_manager.m_cargo_class;
		if (!unfinished) {
			if (!this.road_route_manager.IsDateTimerRunning()) this.road_route_manager.StartDateTimer();
//			if (this.road_route_manager.m_reserved_money == 0) this.road_route_manager.SwapCargoClass();
			local cargo_type = Utils.GetCargoType(cargo_class);

			local engine_list = AIEngineList(AIVehicle.VT_ROAD);
			foreach (engine_id, _ in engine_list) {
				if (!AIEngine.IsValidEngine(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.IsBuildable(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (AIEngine.GetRoadType(engine_id) != AIRoad.ROADTYPE_ROAD) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.CanRefitCargo(engine_id, cargo_type)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.IsArticulated(engine_id)) {
					articulated = false;
				}
				engine_list[engine_id] = AIEngine.GetPrice(engine_id);
			}

			if (engine_list.IsEmpty()) {
				if (this.road_route_manager.m_reserved_money != 0) {
					this.road_route_manager.ResetMoneyReservation();
				}
				this.road_route_manager.SwapCargoClass();
				return true;
			}

//			engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

			local best_engine_info = Utils.GetBestEngineIncome(engine_list, cargo_type, RoadRoute.START_VEHICLE_COUNT[cargo_class], false);
			local max_distance = (ROAD_DAYS_IN_TRANSIT * 2 * 3 * 74 * AIEngine.GetMaxSpeed(best_engine_info[0]) / 4) / (192 * 16);
			local min_distance = max(20, max_distance * 2 / 3);
//			AILog.Info("best_engine_info: best_engine = " + AIEngine.GetName(best_engine_info[0]) + "; best_distance = " + best_engine_info[1] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

			local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
			local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
			local max_dist = min_dist + MAX_DISTANCE_INCREASE > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//			AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

			local estimated_costs = 0;
			local engine_costs = (AIEngine.GetPrice(engine_list.Begin()) + 500) * RoadRoute.START_VEHICLE_COUNT[cargo_class];
			local road_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_ROAD) * 2 * max_dist;
			local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
			local station_costs = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, cargo_class == AICargo.CC_PASSENGERS ? AIRoad.BT_BUS_STOP : AIRoad.BT_TRUCK_STOP) * 2;
			local depot_cost = AIRoad.GetBuildCost(AIRoad.ROADTYPE_ROAD, AIRoad.BT_DEPOT);
			estimated_costs += engine_costs + road_costs + clear_costs + station_costs + depot_cost;
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", road_costs = " + road_costs + ", clear_costs = " + clear_costs + ", station_costs = " + station_costs + ", depot_cost = " + depot_cost);

			if (this.road_route_manager.m_reserved_money != 0) {
				this.road_route_manager.UpdateMoneyReservation(estimated_costs);
			} else {
				this.road_route_manager.SetMoneyReservation(estimated_costs);
			}
			if (!Utils.HasMoney(estimated_costs + ::caches.m_reserved_money - this.road_route_manager.GetNonPausedReservedMoney())) {
				if (this.road_route_manager.DaysElapsed() < AIController.GetSetting("exclusive_attempt_days")) {
					return 0;
				}
				if (!this.road_route_manager.IsMoneyReservationPaused()) {
					this.road_route_manager.PauseMoneyReservation();
				}
				return 2; // allow skipping to next transport mode
			}

			if (city_from == null) {
				city_from = this.road_town_manager.GetUnusedCity(this.road_route_manager.m_routes_built.best[cargo_class], cargo_class);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						this.road_town_manager.m_used_cities_list[cargo_class].Clear();
					} else if (!this.road_route_manager.m_routes_built.best[cargo_class]) {
						this.road_route_manager.m_routes_built.best[cargo_class] = true;
						this.road_town_manager.m_used_cities_list[cargo_class].Clear();
//						this.road_town_manager.m_near_city_pair_array[cargo_class].clear();
						AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " road routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
					} else {
//						this.road_town_manager.m_near_city_pair_array[cargo_class].clear();
						if (!this.road_route_manager.m_routes_built.all[cargo_class]) {
							AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " road routes have been used!");
						}
						this.road_route_manager.m_routes_built.all[cargo_class] = true;
					}
				}
			}

			if (city_from != null) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));

				this.road_town_manager.FindNearCities(city_from, min_dist, max_dist, this.road_route_manager.m_routes_built.best[cargo_class], cargo_class);

				if (!this.road_town_manager.m_near_city_pair_array[cargo_class].len()) {
					AILog.Info("No near city available");
					city_from = null;
				}
			}

			if (city_from != null) {
				foreach (near_city_pair in this.road_town_manager.m_near_city_pair_array[cargo_class]) {
					if (city_from == near_city_pair[0]) {
						if (!this.road_route_manager.TownRouteExists(city_from, near_city_pair[1], cargo_class)) {
							city_to = near_city_pair[1];

							if (AIController.GetSetting("pick_mode") != 1 && !this.road_route_manager.m_routes_built.all[cargo_class] && this.road_route_manager.HasMaxStationCount(city_from, city_to, cargo_class)) {
//								AILog.Info("this.road_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.road_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
								city_to = null;
								continue;
							} else {
//								AILog.Info("this.road_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.road_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
								break;
							}
						}
					}
				}

				if (city_to == null) {
					city_from = null;
				}
			}

			if (city_from == null && city_to == null) {
				this.road_route_manager.ResetMoneyReservation();
				this.road_route_manager.SwapCargoClass();
			}
		} else {
			if (!Utils.HasMoney(this.road_route_manager.GetReservedMoney())) {
				if (this.road_route_manager.DaysElapsed() < AIController.GetSetting("exclusive_attempt_days")) {
					return 0;
				}
				if (!this.road_route_manager.IsMoneyReservationPaused()) {
					this.road_route_manager.PauseMoneyReservation();
				}
				return 2; // allow skipping to next transport mode
			}
		}

		if (unfinished || city_from != null && city_to != null) {
			if (!unfinished) {
				AILog.Info("r:New city found: " + AITown.GetName(city_from));
				AILog.Info("r:New near city found: " + AITown.GetName(city_to));
			}

			city_from = unfinished ? this.road_build_manager.m_city_from : city_from;
			city_to = unfinished ? this.road_build_manager.m_city_to : city_to;
			cargo_class = unfinished ? this.road_build_manager.m_cargo_class : cargo_class;
			articulated = unfinished ? this.road_build_manager.m_articulated : articulated;

			return this.road_route_manager.BuildRoute(this.road_build_manager, city_from, city_to, cargo_class, articulated);
		}
	}
	return true;
}

function LuDiAIAfterFix::CheckForUnfinishedRoadRoute()
{
	if (this.road_build_manager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered road station or depot tiles during save */
		local station_from = this.road_build_manager.m_station_from;
		local station_to = this.road_build_manager.m_station_to;
		local depot_tile = this.road_build_manager.m_depot_tile;
		local station_type = this.road_build_manager.m_cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;

		if (station_from == -1 || station_to == -1) {
			local station_list = AIStationList(station_type);
			local all_stations_tiles = AITileList();
			foreach (station_id, _ in station_list) {
				local station_tiles = AITileList_StationType(station_id, station_type);
				all_stations_tiles.AddList(station_tiles);
			}
//			AILog.Info("all_stations_tiles has " + all_stations_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			if (station_from != -1) {
				all_tiles_found.AddTile(station_from);
			}
			foreach (tile, _ in all_stations_tiles) {
				if (::scheduled_removals[AITile.TRANSPORT_ROAD].rawin(tile)) {
//					AILog.Info("scheduled_removals[AITile.TRANSPORT_ROAD] has tile " + tile);
					all_tiles_found[tile] = 0;
					break;
				}
				foreach (i, route in this.road_route_manager.m_town_route_array) {
					if (route.m_station_from == tile || route.m_station_to == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), station_type);
						all_tiles_found.AddList(station_tiles);
						break;
					}
				}
			}

			if (all_tiles_found.Count() != all_stations_tiles.Count()) {
//				AILog.Info(all_tiles_found.Count() + " != " + all_stations_tiles.Count());
				local all_tiles_missing = AITileList();
				all_tiles_missing.AddList(all_stations_tiles);
				all_tiles_missing.RemoveList(all_tiles_found);
				foreach (tile, _ in all_tiles_missing) {
//					AILog.Info("Tile " + tile + " is missing");
					::scheduled_removals[AITile.TRANSPORT_ROAD].rawset(tile, 0);
				}
			}
		}

		if (depot_tile == -1) {
			local all_depots_tiles = AIDepotList(AITile.TRANSPORT_ROAD);
//			AILog.Info("all_depots_tiles has " + all_depots_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			foreach (tile, _ in all_depots_tiles) {
				if (::scheduled_removals[AITile.TRANSPORT_ROAD].rawin(tile)) {
//					AILog.Info("scheduled_removals[AITile.TRANSPORT_ROAD] has tile " + tile);
					all_tiles_found[tile] = 0;
					break;
				}
				foreach (i, route in this.road_route_manager.m_town_route_array) {
					if (route.m_depot_tile == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						all_tiles_found[tile] = 0;
						break;
					}
				}
			}

			if (all_tiles_found.Count() != all_depots_tiles.Count()) {
//				AILog.Info(all_tiles_found.Count() + " != " + all_depots_tiles.Count());
				local all_tiles_missing = AITileList();
				all_tiles_missing.AddList(all_depots_tiles);
				all_tiles_missing.RemoveList(all_tiles_found);
				foreach (tile, _ in all_tiles_missing) {
//					AILog.Info("Tile " + tile + " is missing");
					::scheduled_removals[AITile.TRANSPORT_ROAD].rawset(tile, 0);
				}
			}
		}
	}
}
