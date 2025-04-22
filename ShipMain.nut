function LuDiAIAfterFix::BuildWaterRoute()
{
	if (!AIController.GetSetting("water_support")) return;

	local unfinished = this.ship_build_manager.HasUnfinishedRoute();
	if (unfinished || (this.ship_route_manager.GetShipCount() < max(AIGameSettings.GetValue("max_ships") - 10, 10)) && ((this.allRoutesBuilt >> 2) & 3) != 3) {
		local city_from = null;
		local city_to = null;
		local cheaper_route = false;
		local cargo_class = this.ship_route_manager.m_cargo_class;
		if (!unfinished) {
			this.ship_route_manager.SwapCargoClass();
			local cargo_type = Utils.GetCargoType(cargo_class);

			local engine_list = AIEngineList(AIVehicle.VT_WATER);
			foreach (engine_id, _ in engine_list) {
				if (!AIEngine.IsValidEngine(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.IsBuildable(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.CanRefitCargo(engine_id, cargo_type)) {
					engine_list[engine_id] = null;
					continue;
				}
				engine_list[engine_id] = AIEngine.GetPrice(engine_id);
			}

			if (engine_list.IsEmpty()) {
				return;
			}

			local best_engine_info = WrightAI().GetBestEngineIncome(engine_list, cargo_type, ShipRoute.COUNT_INTERVAL, false);
			local max_distance = (WATER_DAYS_IN_TRANSIT * 2 * 74 * AIEngine.GetMaxSpeed(best_engine_info[0])) / (256 * 16);
			local min_distance = max(20, max_distance * 2 / 3);
//			AILog.Info("best_engine_info: best_engine = " + AIEngine.GetName(best_engine_info[0]) + "; best_distance = " + best_engine_info[1] + "; max_distance = " + max_distance + "; min_distance = " + min_distance);

			local map_size = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();
			local min_dist = min_distance > map_size / 3 ? map_size / 3 : min_distance;
			local max_dist = min_dist + MAX_DISTANCE_INCREASE > max_distance ? min_dist + MAX_DISTANCE_INCREASE : max_distance;
//			AILog.Info("map_size = " + map_size + " ; min_dist = " + min_dist + " ; max_dist = " + max_dist);

			local estimated_costs = 0;
			local engine_costs = AIEngine.GetPrice(engine_list.Begin());
			local canal_costs = AIMarine.GetBuildCost(AIMarine.BT_CANAL) * 2 * max_dist;
			local clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * max_dist;
			local dock_costs = AIMarine.GetBuildCost(AIMarine.BT_DOCK) * 2;
			local depot_cost = AIMarine.GetBuildCost(AIMarine.BT_DEPOT);
			estimated_costs += engine_costs + canal_costs + clear_costs + dock_costs + depot_cost;
//			AILog.Info("estimated_costs = " + estimated_costs + "; engine_costs = " + engine_costs + ", canal_costs = " + canal_costs + ", clear_costs = " + clear_costs + ", dock_costs = " + dock_costs + ", depot_cost = " + depot_cost);
			if (!Utils.HasMoney(estimated_costs + this.reservedMoney - this.reservedMoneyWater)) {
				/* Try a cheaper route */
				if ((((this.bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 1 || !Utils.HasMoney(estimated_costs - canal_costs - clear_costs + this.reservedMoney - this.reservedMoneyWater)) {
					return;
				} else {
					cheaper_route = true;
					this.reservedMoneyWater = estimated_costs - canal_costs - clear_costs;
					this.reservedMoney += this.reservedMoneyWater;
				}
			} else {
				this.reservedMoneyWater = estimated_costs;
				this.reservedMoney += this.reservedMoneyWater;
			}

			if (city_from == null) {
				city_from = this.shipTownManager.GetUnusedCity(((((this.bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						this.shipTownManager.m_used_cities_list[cargo_class].Clear();
					} else if ((((this.bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
						this.bestRoutesBuilt = this.bestRoutesBuilt | (1 << (2 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
						this.shipTownManager.m_used_cities_list[cargo_class].Clear();
//						this.shipTownManager.m_near_city_pair_array[cargo_class].clear();
						AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " water routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
					} else {
//						this.shipTownManager.m_near_city_pair_array[cargo_class].clear();
						if ((((this.allRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " water routes have been used!");
						}
						this.allRoutesBuilt = this.allRoutesBuilt | (1 << (2 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
					}
				}
			}

			if (city_from != null) {
//				AILog.Info("s:New city found: " + AITown.GetName(city_from));

				this.shipTownManager.FindNearCities(city_from, min_dist, max_dist, ((((this.bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);

				if (!this.shipTownManager.m_near_city_pair_array[cargo_class].len()) {
					AILog.Info("No near city available");
					city_from = null;
				}
			}

			if (city_from != null) {
				foreach (near_city_pair in this.shipTownManager.m_near_city_pair_array[cargo_class]) {
					if (city_from == near_city_pair[0]) {
						if (!this.ship_route_manager.TownRouteExists(city_from, near_city_pair[1], cargo_class)) {
							city_to = near_city_pair[1];

							if (AIController.GetSetting("pick_mode") != 1 && ((((this.allRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && this.ship_route_manager.HasMaxStationCount(city_from, city_to, cargo_class)) {
//								AILog.Info("this.ship_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.ship_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
								city_to = null;
								continue;
							} else {
//								AILog.Info("this.ship_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.ship_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
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
				this.reservedMoney -= this.reservedMoneyWater;
				this.reservedMoneyWater = 0;
			}
		} else {
			if (!Utils.HasMoney(this.reservedMoneyWater)) {
				return;
			}
		}

		if (unfinished || city_from != null && city_to != null) {
			if (!unfinished) {
				AILog.Info("s:New city found: " + AITown.GetName(city_from));
				AILog.Info("s:New near city found: " + AITown.GetName(city_to));
			}

			if (!unfinished) this.buildTimerWater = 0;
			city_from = unfinished ? this.ship_build_manager.m_city_from : city_from;
			city_to = unfinished ? this.ship_build_manager.m_city_to : city_to;
			cargo_class = unfinished ? this.ship_build_manager.m_cargo_class : cargo_class;
			cheaper_route = unfinished ? this.ship_build_manager.m_cheaper_route : cheaper_route;
			local best_routes = unfinished ? this.ship_build_manager.m_best_routes_built : ((((this.bestRoutesBuilt >> 2) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);

			local start_date = AIDate.GetCurrentDate();
			local route_result = this.ship_route_manager.BuildRoute(this.ship_build_manager, city_from, city_to, cargo_class, cheaper_route, best_routes);
			this.buildTimerWater += AIDate.GetCurrentDate() - start_date;
			if (route_result[0] != null) {
				if (route_result[0] != 0) {
					this.reservedMoney -= this.reservedMoneyWater;
					this.reservedMoneyWater = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + " water route between " + AIBaseStation.GetName(AIStation.GetStationID(route_result[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(route_result[2])) + " in " + this.buildTimerWater + " day" + (this.buildTimerWater != 1 ? "s" : "") + ".");
				}
			} else {
				this.reservedMoney -= this.reservedMoneyWater;
				this.reservedMoneyWater = 0;
				this.shipTownManager.ResetCityPair(city_from, city_to, cargo_class, false);
				AILog.Error("s:" + this.buildTimerWater + " day" + (this.buildTimerWater != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::CheckForUnfinishedWaterRoute()
{
	if (this.ship_build_manager.HasUnfinishedRoute()) {
		/* Look for potentially unregistered dock or ship depot tiles during save */
		local dock_from = this.ship_build_manager.m_dock_from;
		local dock_to = this.ship_build_manager.m_dock_to;
		local depot_tile = this.ship_build_manager.m_depot_tile;
		local station_type = AIStation.STATION_DOCK;

		if (dock_from == -1 || dock_to == -1) {
			local station_list = AIStationList(station_type);
			local all_station_tiles = AITileList();
			foreach (station_id, _ in station_list) {
				local station_tiles = AITileList_StationType(station_id, station_type);
				all_station_tiles.AddList(station_tiles);
			}
//			AILog.Info("all_station_tiles has " + all_station_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			if (dock_from != -1) all_tiles_found[dock_from] = 0;
			foreach (tile, _ in all_station_tiles) {
				if (::scheduled_removals_table.Ship.rawin(tile)) {
//					AILog.Info("scheduled_removals_table.Ship has tile " + tile);
					all_tiles_found[tile] = 0;
					break;
				}
				foreach (route in this.ship_route_manager.m_town_route_array) {
					if (route.m_dock_from == tile || route.m_dock_to == tile) {
//						AILog.Info("Route " + i + " has tile " + tile);
						local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), station_type);
						all_tiles_found.AddList(station_tiles);
						break;
					}
				}
			}

			if (all_tiles_found.Count() != all_station_tiles.Count()) {
//				AILog.Info(all_tiles_found.Count() + " != " + all_station_tiles.Count());
				local all_tiles_missing = AITileList();
				all_tiles_missing.AddList(all_station_tiles);
				all_tiles_missing.RemoveList(all_tiles_found);
				foreach (tile, _ in all_tiles_missing) {
					if (AIMarine.IsDockTile(tile) && AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
//						AILog.Info("Tile " + tile + " is missing");
						::scheduled_removals_table.Ship.rawset(tile, 0);
					}
				}
			}
		}

		if (depot_tile == -1) {
			local all_depots_tiles = AIDepotList(AITile.TRANSPORT_WATER);
//			AILog.Info("all_depots_tiles has " + all_depots_tiles.Count() + " tiles");
			local all_tiles_found = AITileList();
			foreach (tile, _ in all_depots_tiles) {
				if (::scheduled_removals_table.Ship.rawin(tile)) {
//					AILog.Info("scheduled_removals_table.Ship has tile " + tile);
					all_tiles_found[tile] = 0;
					break;
				}
				foreach (route in this.ship_route_manager.m_town_route_array) {
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
					::scheduled_removals_table.Ship.rawset(tile, 0);
				}
			}
		}
	}
}
