require("RoadPathfinder.nut");

enum RoadTileType
{
	ROAD,
	TUNNEL,
	BRIDGE
};

class RoadTile
{
	m_tile = null;
	m_type = null;
	m_bridge_type = null;

	constructor(tile, type, bridge_type = -1)
	{
		this.m_tile = tile;
		this.m_type = type;
		this.m_bridge_type = bridge_type;
	}
};

class RoadBuildManager
{
	/* These are saved */
	m_city_from = -1;
	m_city_to = -1;
	m_station_from = -1;
	m_station_to = -1;
	m_depot_tile = -1;
	m_bridge_tiles = null;
	m_cargo_class = -1;
	m_articulated = -1;
	m_pathfinder_profile = -1;
	m_best_routes_built = null;

	/* These are not saved */
	m_pathfinder_instance = null;
	m_pathfinder_tries = -1;
	m_built_tiles = null;
	m_sent_to_depot_road_group = null;
	m_route_dist = -1;
	m_max_pathfinder_tries = -1;
	m_city_from_name = null;
	m_city_to_name = null;

	function HasUnfinishedRoute()
	{
		return this.m_city_from != -1 && this.m_city_to != -1 && this.m_cargo_class != -1;
	}

	function SetRouteFinished()
	{
		this.m_city_from = -1;
		this.m_city_to = -1;
		this.m_station_from = -1;
		this.m_station_to = -1;
		this.m_depot_tile = -1;
		this.m_bridge_tiles = null;
		this.m_cargo_class = -1;
		this.m_articulated = -1;
		this.m_pathfinder_instance = null;
		this.m_pathfinder_tries = -1;
		this.m_pathfinder_profile = -1;
		this.m_built_tiles = null;
		this.m_sent_to_depot_road_group = null;
		this.m_best_routes_built = null;
		this.m_route_dist = -1;
		this.m_max_pathfinder_tries = -1;
		this.m_city_from_name = null;
		this.m_city_to_name = null;
	}

	function RemoveFailedRouteStation(station_tile)
	{
		local station_text = AIRoad.IsDriveThroughRoadStationTile(station_tile) ? " drive through " : " ";
		local counter = 0;
		do {
			if (!TestRemoveRoadStation().TryRemove(station_tile)) {
				++counter;
			} else {
//				AILog.Warning("Removed" + station_text + "road station tile at " + station_tile);
				break;
			}
			AIController.Sleep(1);
		} while (counter < 500);

		if (counter == 500) {
			::scheduledRemovalsTable.Road.rawset(this.m_station_from, 0);
//			AILog.Error("Failed to remove" + station_text + "road station tile at " + station_tile + " - " + AIError.GetLastErrorString());
		}
	}

	function BuildRoadRoute(city_from, city_to, cargo_class, articulated, sent_to_depot_road_group, best_routes_built)
	{
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_cargo_class = cargo_class;
		this.m_articulated = articulated;
		this.m_sent_to_depot_road_group = sent_to_depot_road_group;
		this.m_best_routes_built = best_routes_built;

		if (this.m_bridge_tiles == null) {
			this.m_bridge_tiles = [];
		}

		if (this.m_built_tiles == null) {
			this.m_built_tiles = [];
		}

		if (this.m_pathfinder_profile == -1) {
			this.m_pathfinder_profile = AIController.GetSetting("pf_profile");
		}

		if (this.m_pathfinder_tries == -1) {
			this.m_pathfinder_tries = 0;
		}

		if (this.m_route_dist == -1) {
			this.m_route_dist = AITown.GetDistanceManhattanToTile(city_from, AITown.GetLocation(city_to));
		}

		if (this.m_city_from_name == null) {
			this.m_city_from_name = AITown.GetName(city_from);
		}

		if (this.m_city_to_name == null) {
			this.m_city_to_name = AITown.GetName(city_to);
		}

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_ROAD);
		if (num_vehicles >= AIGameSettings.GetValue("max_roadveh") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		if (this.m_station_from == -1) {
			this.m_station_from = this.BuildTownRoadStation(this.m_city_from, this.m_city_to, this.m_cargo_class, this.m_articulated, this.m_best_routes_built);
			if (this.m_station_from == null) {
				this.SetRouteFinished();
				return null;
			}
		}

		if (this.m_station_to == -1) {
			this.m_station_to = this.BuildTownRoadStation(this.m_city_to, this.m_city_from, this.m_cargo_class, this.m_articulated, this.m_best_routes_built);
			if (this.m_station_to == null) {
				this.RemoveFailedRouteStation(this.m_station_from);
				this.SetRouteFinished();
				return null;
			}
		}

		if (this.m_depot_tile == -1) {
			local road_array = this.PathfindBuildRoad(this.m_station_from, this.m_station_to, this.m_pathfinder_instance);
			this.m_pathfinder_instance = road_array[1];
			if (road_array[0] == null && this.m_pathfinder_instance != null) {
				return 0;
			}
			this.m_depot_tile = this.BuildRouteRoadDepot(road_array[0]);
		}

		if (this.m_depot_tile == null) {
			this.RemoveFailedRouteStation(this.m_station_from);
			this.RemoveFailedRouteStation(this.m_station_to);
			this.SetRouteFinished();
			return null;
		}

		return RoadRoute(this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile, this.m_bridge_tiles, this.m_cargo_class, this.m_sent_to_depot_road_group);
	}

	function IsStationBuildableTile(tile)
	{
		return AITile.GetSlope(tile) == AITile.SLOPE_FLAT && (AITile.IsBuildable(tile) || (AIRoad.IsRoadTile(tile) && !AIRoad.IsDriveThroughRoadStationTile(tile) && !AIRail.IsLevelCrossingTile(tile)));
	}

	function AreOtherStationsNearby(tile, cargo_class, station_id)
	{
		local station_type = cargo_class == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;

		/* check if there are other stations square_size squares nearby */
		local square_size = AIStation.GetCoverageRadius(station_type);
		if (station_id == AIStation.STATION_NEW) {
			square_size *= 2;
		}

		local tile_list = AITileList();
		tile_list.AddRectangle(Utils.GetValidOffsetTile(tile, -1 * square_size, -1 * square_size), Utils.GetValidOffsetTile(tile, square_size, square_size));

		foreach (tile, _ in tile_list) {
			if (AITile.IsStationTile(tile)) {
				if (AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					/* if another road station of mine is nearby return true */
					if (AIStation.HasStationType(AIStation.GetStationID(tile), station_type)) {
						return true;
					}
				} else if (AIController.GetSetting("is_friendly")) {
					return true;
				}
				/* don't care about enemy stations when is_friendly is off */
			}
		}

		return false;
	}

	/* Warning: this function can also be called from RoadRoute class. Do not use 'this' members variables */
	function BuildTownRoadStation(city_from, city_to, cargo_class, articulated, best_routes_built, station_tile = null)
	{
		local station_id = station_tile == null ? AIStation.STATION_NEW : AIStation.GetStationID(station_tile);
		local road_vehicle_type = cargo_class == AICargo.CC_MAIL ? AIRoad.ROADVEHTYPE_TRUCK : AIRoad.ROADVEHTYPE_BUS;

		local cargo_type = Utils.GetCargoType(cargo_class);
		local coverage_radius = cargo_class == AICargo.CC_PASSENGERS ? AIStation.GetCoverageRadius(AIStation.STATION_BUS_STOP) : AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);

		local tile_list = AITileList();
		if (station_tile == null) {
			/* build square around @city_from and find suitable tiles for truck stops */
			local rectangle_coordinates = Utils.EstimateTownRectangle(city_from);
			tile_list.AddRectangle(rectangle_coordinates[0], rectangle_coordinates[1]);
			local pick_mode = AIController.GetSetting("pick_mode");
			foreach (tile, _ in tile_list) {
				if (!this.IsStationBuildableTile(tile)) {
					tile_list[tile] = null;
					continue;
				}

				if (AITile.GetCargoAcceptance(tile, cargo_type, 1, 1, coverage_radius) < 8) {
					tile_list[tile] = null;
					continue;
				}

				if (this.AreOtherStationsNearby(tile, cargo_class, station_id)) {
					tile_list[tile] = null;
					continue;
				}
				local cargo_production = AITile.GetCargoProduction(tile, cargo_type, 1, 1, coverage_radius);
				if (pick_mode != 1 && !best_routes_built && cargo_production < 8) {
					tile_list[tile] = null;
					continue;
				}
				tile_list[tile] = cargo_production;
			}
		} else {
			/* expanding existing station */
			if (!AIStation.IsValidStation(station_id)) {
				return null;
			}

			local square_size = AIGameSettings.GetValue("station_spread") / 2;

			tile_list.AddRectangle(Utils.GetValidOffsetTile(station_tile, -1 * square_size, -1 * square_size), Utils.GetValidOffsetTile(station_tile, square_size, square_size));

			foreach (tile, _ in tile_list) {
				if (!this.IsStationBuildableTile(tile)) {
					tile_list[tile] = null;
					continue;
				}

				if (this.AreOtherStationsNearby(tile, cargo_class, station_id)) {
					tile_list[tile] = null;
					continue;
				}

				local cargo_production = AITile.GetCargoProduction(tile, cargo_type, 1, 1, coverage_radius);
				if (cargo_production == 0) {
					tile_list[tile] = null;
					continue;
				}
				tile_list[tile] = cargo_production;
			}
		}

		foreach (tile, _ in tile_list) {
			if (station_tile == null && AITile.GetClosestTown(tile) != city_from) {
				continue;
			}

			/* get adjacent tiles */
			local adjacent_tile_list = Utils.GetAdjacentTiles(tile);
			local adjacent_road_tiles = AITileList();
			foreach (tile2, _ in adjacent_tile_list) {
				if (AIRoad.IsRoadTile(tile2)) {
					adjacent_road_tiles.AddTile(tile2);
				}
			}

			AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
			local num_adjacent_road_tiles = adjacent_road_tiles.Count();
			local adjacent_station_id = Utils.CheckAdjacentNonRoadStation(tile, station_id);
			local max_num_tries = station_tile == null ? 1 : 500;
			local tile_has_road = AIRoad.IsRoadTile(tile);

			switch (num_adjacent_road_tiles) {
				case 0: {
					/* case where station tile has no adjacent road tiles */
					if (station_tile != null) {
						continue;
					}

					if (articulated) {
						continue;
					}

					/* avoid blocking other station exits */
					local blocking = false;
					foreach (adjacent_tile, _ in adjacent_tile_list) {
						if (AIRoad.IsRoadStationTile(adjacent_tile) && AIRoad.GetRoadStationFrontTile(adjacent_tile) == tile) {
							blocking = true;
							break;
						}
					}

					if (blocking) {
						continue;
					}

					local closest_adjacent_tile = null;
					foreach (adjacent_tile, _ in adjacent_tile_list) {
						if (!AITile.IsBuildable(adjacent_tile)) {
							continue;
						}
						if (AITile.HasTransportType(adjacent_tile, AITile.TRANSPORT_WATER) && AICompany.GetLoanAmount() != 0) {
							continue;
						}

						if (closest_adjacent_tile == null) {
							closest_adjacent_tile = adjacent_tile;
						}

						if (AITown.GetDistanceManhattanToTile(city_to, adjacent_tile) < AITown.GetDistanceManhattanToTile(city_to, closest_adjacent_tile)) {
							closest_adjacent_tile = adjacent_tile;
						}
					}

					if (closest_adjacent_tile == null) {
						continue;
					}

					local counter = 0;
					do {
						if (!TestBuildRoadStation().TryBuild(tile, closest_adjacent_tile, road_vehicle_type, adjacent_station_id)) {
							++counter;
						} else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						continue;
					} else {
						AILog.Info("Station built in " + AITown.GetName(city_from) + " at tile " + tile + "! " + num_adjacent_road_tiles + " adjacent road tiles.");
						return tile;
					}
				}

				case 1: {
					/* avoid blocking other station exits */
					local blocking = false;
					foreach (adjacent_tile, _ in adjacent_tile_list) {
						if (AIRoad.IsRoadStationTile(adjacent_tile) && AIRoad.GetRoadStationFrontTile(adjacent_tile) == tile) {
							blocking = true;
							break;
						}
					}

					if (blocking) {
						continue;
					}

					local adjacent_tile = adjacent_road_tiles.Begin();
					if (AIRoad.IsDriveThroughRoadStationTile(adjacent_tile)) {
						continue;
					}

					if (abs(AITile.GetMaxHeight(tile) - AITile.GetMaxHeight(adjacent_tile)) != 0) {
						continue;
					}

					if (!articulated) {
						local counter = 0;
						do {
							/* Try to build a road station */
							if (!TestBuildRoadStation().TryBuild(tile, adjacent_tile, road_vehicle_type, adjacent_station_id)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							/* Failed to build station, try the next location */
							continue;
						} else {
							/* With the road station built, try to connect it to the road */
							local counter = 0;
							do {
								if (!TestBuildRoad().TryBuild(tile, adjacent_tile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < max_num_tries);

							if (counter == max_num_tries) {
								/* Failed to connect road to the station. Try to remove the station we had built then */
								local counter = 0;
								do {
									if (!TestRemoveRoadStation().TryRemove(tile)) {
										++counter;
									} else {
//										AILog.Warning("case" + num_adjacent_road_tiles + "; Removed road station tile at " + tile);
										break;
									}
									AIController.Sleep(1);
								} while (counter < max_num_tries);

								if (counter == max_num_tries) {
									::scheduledRemovalsTable.Road.rawset(tile, 0);
//									AILog.Error("Failed to remove road station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									/* The station was successfully removed after failing to connect it to the road. Try it all over again in the next location */
									continue;
								}
							} else {
								/* The road was successfully connected to the station */
								AILog.Info("Station built in " + AITown.GetName(city_from) + " at tile " + tile + "! " + num_adjacent_road_tiles + " adjacent road tile.");
//								AISign.BuildSign(tile, "" + num_adjacent_road_tiles);
								return tile;
							}
						}
					} else {
						/* articulated == true, num_adjacent_road_tiles == 1 */
						if (!tile_has_road) {
							continue;
						}

						local counter = 0;
						do {
							/* Try to build a drive through road station */
							if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjacent_tile, road_vehicle_type, adjacent_station_id)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							/* Failed to build station, try the next location */
							continue;
						} else {
							/* With the road station built, try to connect it to the road */
							local counter = 0;
							do {
								if (!TestBuildRoad().TryBuild(tile, adjacent_tile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < max_num_tries);

							if (counter == max_num_tries) {
								/* Failed to connect road to the station. Try to remove the station we had built then */
								local counter = 0;
								do {
									if (!TestRemoveRoadStation().TryRemove(tile)) {
										++counter;
									} else {
//										AILog.Warning("case" + num_adjacent_road_tiles + "; Removed drive through station tile at " + tile);
										break;
									}
									AIController.Sleep(1);
								} while (counter < max_num_tries);

								if (counter == max_num_tries) {
									::scheduledRemovalsTable.Road.rawset(tile, 0);
//									AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									/* The station was successfully removed after failing to connect it to the road. Try it all over again in the next location */
									continue;
								}
							} else {
								/* The road was successfully connected to the station */
								AILog.Info("Drive through station built in " + AITown.GetName(city_from) + " at tile " + tile + "! " + num_adjacent_road_tiles + " adjacent road tile.");
								return tile;
							}
						}
					}
				}

				case 2: {
					local adjacent_tile1 = adjacent_road_tiles.Begin();
					local adjacent_tile2 = adjacent_road_tiles.Next();

					/* don't build drive through station next to regular station */
					adjacent_tile_list[adjacent_tile1] = null;
					adjacent_tile_list[adjacent_tile2] = null;
					local blocking = false;
					foreach (adjacent_tile, _ in adjacent_tile_list) {
						if (AIRoad.IsRoadStationTile(adjacent_tile) && AIRoad.GetRoadStationFrontTile(adjacent_tile) == tile) {
							blocking = true;
							break;
						}
						if (AIRoad.IsRoadDepotTile(adjacent_tile) && AIRoad.GetRoadDepotFrontTile(adjacent_tile) == tile) {
							blocking = true;
							break;
						}
						if (!AIRoad.IsDriveThroughRoadStationTile(adjacent_tile)) {
							continue;
						}
						if (AIRoad.GetRoadStationFrontTile(adjacent_tile) != tile) {
							blocking = true;
							break;
						}
						if (AIRoad.GetDriveThroughBackTile(adjacent_tile) != tile) {
							blocking = true;
							break;
						}
					}
					if (blocking) {
						continue;
					}

					/* check whether adjacent tiles are opposites */
					if (AIMap.GetTileX(adjacent_tile1) == AIMap.GetTileX(adjacent_tile2) || AIMap.GetTileY(adjacent_tile1) == AIMap.GetTileY(adjacent_tile2)) {
						/* check height difference */
						if (abs(AITile.GetMaxHeight(adjacent_tile2) - AITile.GetMaxHeight(adjacent_tile1)) != 0) {
							continue;
						}

						local counter = 0;
						do {
							if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjacent_tile1, road_vehicle_type, adjacent_station_id)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1)
						} while (counter < 1);

						if (counter == 1) {
							continue;
						} else {
							local counter = 0;
							do {
								if (!TestBuildRoad().TryBuild(adjacent_tile1, adjacent_tile2) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < max_num_tries);

							if (counter == max_num_tries) {
								local counter = 0;
								local removed = false;
								do {
									if (tile_has_road) {
										if (!TestRemoveRoadStation().TryRemove(tile)) {
											++counter;
										} else {
											removed = true;
										}
									} else {
										if (!TestDemolishTile().TryDemolish(tile)) {
											++counter;
										} else {
											removed = true;
										}
									}
									if (removed) {
//										AILog.Warning("case" + num_adjacent_road_tiles + "; Removed drive through station tile at " + tile);
										break;
									}
									AIController.Sleep(1);
								} while (counter < max_num_tries);

								if (counter == max_num_tries) {
									::scheduledRemovalsTable.Road.rawset(tile, tile_has_road ? 0 : 1);
//									AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									continue;
								}
							} else {
								AILog.Info("Drive through station built in " + AITown.GetName(city_from) + " at tile " + tile + "! " + num_adjacent_road_tiles + " adjacent road tiles.");
								return tile;
							}
						}
					} else {
						/* similar to case 1 if adjacent tiles are not opposites */
						if (tile_has_road) {
							continue;
						}

						if (articulated) {
							continue;
						}

						local tile_height = AITile.GetMaxHeight(tile);
						if (abs(tile_height - AITile.GetMaxHeight(adjacent_tile1)) != 0) {
							if (abs(tile_height - AITile.GetMaxHeight(adjacent_tile2)) != 0) {
								continue;
							} else {
								adjacent_tile1 = adjacent_tile2;
							}
						}

						local counter = 0;
						do {
							if (!TestBuildRoadStation().TryBuild(tile, adjacent_tile1, road_vehicle_type, adjacent_station_id)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							continue;
						} else {
							local counter = 0;
							do {
								if (!TestBuildRoad().TryBuild(tile, adjacent_tile1) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < max_num_tries);

							if (counter == max_num_tries) {
								local counter = 0;
								do {
									if (!TestRemoveRoadStation().TryRemove(tile)) {
										++counter;
									} else {
//										AILog.Warning("case" + num_adjacent_road_tiles + "; Removed road station tile at " + tile);
										break;
									}
									AIController.Sleep(1);
								} while (counter < max_num_tries);

								if (counter == max_num_tries) {
									::scheduledRemovalsTable.Road.rawset(tile, 0);
//									AILog.Error("Failed to remove road station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									continue;
								}
							} else {
								AILog.Info("Station built in " + AITown.GetName(city_from) + " at tile " + tile + "! " + num_adjacent_road_tiles + " adjacent road tiles.");
//								AISign.BuildSign(tile, "" + num_adjacent_road_tiles);
								return tile;
							}
						}
					}
				}

				case 3:
				case 4: {
					/* similar to case 2 but always builds drive through station */

					if (tile_has_road) {
						continue;
					}

					/* avoid blocking other station exits */
					local blocking = false;
					foreach (adjacent_tile, _ in adjacent_tile_list) {
						if (AIRoad.IsRoadStationTile(adjacent_tile) && AIRoad.GetRoadStationFrontTile(adjacent_tile) == tile) {
							blocking = true;
							break;
						}
					}

					if (blocking) {
						continue;
					}

					/* check which adjacent tiles are opposites */
					local adjacent_tile1 = Utils.GetOffsetTile(tile, -1, 0);
					local adjacent_tile2 = Utils.GetOffsetTile(tile, 1, 0);
					if (!adjacent_road_tiles.HasItem(adjacent_tile1) || !adjacent_road_tiles.HasItem(adjacent_tile2)) {
						adjacent_tile1 = Utils.GetOffsetTile(tile, 0, -1);
						adjacent_tile2 = Utils.GetOffsetTile(tile, 0, 1);
					}

					if (abs(AITile.GetMaxHeight(adjacent_tile2) - AITile.GetMaxHeight(adjacent_tile1)) != 0) {
						continue;
					}

					local counter = 0;
					do {
						if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjacent_tile1, road_vehicle_type, adjacent_station_id)) {
							++counter;
						} else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						continue;
					} else {
						local counter = 0;
						do {
							if (!TestBuildRoad().TryBuild(adjacent_tile1, adjacent_tile2) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < max_num_tries);

						if (counter == max_num_tries) {
							local counter = 0;
							do {
								if (!TestDemolishTile().TryDemolish(tile)) {
									++counter;
								} else {
//									AILog.Warning("case" + num_adjacent_road_tiles + "; Removed drive through station tile at " + tile);
									break;
								}
								AIController.Sleep(1);
							} while (counter < max_num_tries);

							if (counter == max_num_tries) {
								::scheduledRemovalsTable.Road.rawset(tile, 1);
//								AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
								continue;
							} else {
								continue;
							}
						} else {
							AILog.Info("Drive through station built in " + AITown.GetName(city_from) + " at tile " + tile + "! " + num_adjacent_road_tiles + " adjacent road tiles.");
							return tile;
						}
					}
				}

				default: {
					break;
				}
			}
		}

		return null;
	}

	/* find road way between from_tile and to_tile */
	function PathfindBuildRoad(from_tile, to_tile, pathfinder_instance, cost_so_far = 0)
	{
		if (from_tile != to_tile) {
			if (this.m_max_pathfinder_tries == -1) {
				switch (this.m_pathfinder_profile) {
					case 0: {
						this.m_max_pathfinder_tries = 1250 * this.m_route_dist;
						break;
					}
					case 1: {
						this.m_max_pathfinder_tries = 500 * this.m_route_dist;
						break;
					}
					case 2: {
						this.m_max_pathfinder_tries = 5000 * this.m_route_dist / 15 + 5000 * this.m_route_dist % 15;
						break;
					}
					default: {
						this.m_max_pathfinder_tries = this.m_route_dist;
						break;
					}
				}
			}

			/* Print the names of the towns we'll try to connect. */
			AILog.Info("r:Connecting " + this.m_city_from_name + " (tile " + from_tile + ") and " + this.m_city_to_name + " (tile " + to_tile + ") (iteration " + (this.m_pathfinder_tries + 1) + "/" + this.m_max_pathfinder_tries + ")");

			/* Tell OpenTTD we want to build normal road (no tram tracks). */
			AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

			if (pathfinder_instance == null) {
				/* Create an instance of the pathfinder. */
				pathfinder_instance = Road();

				switch (this.m_pathfinder_profile) {
					case 0: {
						AILog.Info("road pathfinder: custom");
/*defaults*/
/*10000000*/			pathfinder_instance.cost.max_cost;
/*100*/					pathfinder_instance.cost.tile;
/*20*/					pathfinder_instance.cost.no_existing_road = 40;
/*100*/					pathfinder_instance.cost.turn;
/*200*/					pathfinder_instance.cost.slope = AIGameSettings.GetValue("roadveh_acceleration_model") ? AIGameSettings.GetValue("roadveh_slope_steepness") * 20 : pathfinder_instance.cost.slope;
/*150*/					pathfinder_instance.cost.bridge_per_tile = 50;
/*120*/					pathfinder_instance.cost.tunnel_per_tile = 60;
/*20*/					pathfinder_instance.cost.coast = (AICompany.GetLoanAmount() == 0) ? pathfinder_instance.cost.coast : 5000;
/*0*/					pathfinder_instance.cost.drive_through = 800;
/*10*/					pathfinder_instance.cost.max_bridge_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*20*/					pathfinder_instance.cost.max_tunnel_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
/*0*/					pathfinder_instance.cost.search_range = min(this.m_route_dist / 5, 25);
						break;
					}
					case 2: {
						AILog.Info("road pathfinder: fastest");

						pathfinder_instance.cost.max_cost;
						pathfinder_instance.cost.tile;
						pathfinder_instance.cost.no_existing_road = 10;
						pathfinder_instance.cost.turn = 250;
						pathfinder_instance.cost.slope = 50;
						pathfinder_instance.cost.bridge_per_tile;
						pathfinder_instance.cost.tunnel_per_tile;
						pathfinder_instance.cost.coast = 5000;
						pathfinder_instance.cost.drive_through;
						pathfinder_instance.cost.max_bridge_length = 3;
						pathfinder_instance.cost.max_tunnel_length = 0;
						pathfinder_instance.cost.search_range = 3;
						break;
					}
					case 1:
					default: {
						AILog.Info("road pathfinder: default");

						pathfinder_instance.cost.max_cost;
						pathfinder_instance.cost.tile;
						pathfinder_instance.cost.no_existing_road;
						pathfinder_instance.cost.turn;
						pathfinder_instance.cost.slope;
						pathfinder_instance.cost.bridge_per_tile;
						pathfinder_instance.cost.tunnel_per_tile;
						pathfinder_instance.cost.coast;
						pathfinder_instance.cost.drive_through;
						pathfinder_instance.cost.max_bridge_length;
						pathfinder_instance.cost.max_tunnel_length;
						pathfinder_instance.cost.search_range;
						break;
					}
				}
				/* Give the source and goal tiles to the pathfinder. */
				pathfinder_instance.InitializePath(from_tile, to_tile);
			}

			local cur_date = AIDate.GetCurrentDate();
			local path;

//			local count = 0;
			do {
				++this.m_pathfinder_tries;
//				++count;
				path = pathfinder_instance.FindPath(1);

				if (path == false) {
					if (this.m_pathfinder_tries < this.m_max_pathfinder_tries) {
						if (AIDate.GetCurrentDate() - cur_date > 1) {
//							AILog.Info("road pathfinder: FindPath iterated: " + count);
//							local signList = AISignList();
//							for (local sign = signList.Begin(); !signList.IsEnd(); sign = signList.Next()) {
//								if (signList.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder_instance];
						}
					} else {
						/* Timed out */
						AILog.Error("road pathfinder: FindPath return false (timed out)");
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					AILog.Error("road pathfinder: FindPath return null (no path)");
					return [null, null];
				}
			} while (path == false);

//			if (this.m_pathfinder_tries != count) AILog.Info("road pathfinder: FindPath iterated: " + count);
			AILog.Info("Road path found! FindPath iterated: " + this.m_pathfinder_tries + ". Building road... ");
			AILog.Info("road pathfinder: FindPath cost: " + path.GetCost());
			local road_cost = cost_so_far;
			/* If a path was found, build a road over it. */
			local last_node = null;
			while (path != null) {
				local par = path.GetParent();
				if (par != null) {
					if (AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) == 1) {
						if (!AIRail.IsRailTile(par.GetTile()) || (AITestMode() && !AIRoad.BuildRoad(path.GetTile(), par.GetTile()) || AIError.GetLastErrorString() == "ERR_ALREADY_BUILT") && !AIRail.IsLevelCrossingTile(par.GetTile())) {
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (!TestBuildRoad().TryBuild(path.GetTile(), par.GetTile())) {
									if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT"/* || (AIError.GetLastErrorString() == "ERR_UNKNOWN" && AIBridge.IsBridgeTile(path.GetTile()))*/) {
//										AILog.Warning("We found a road already built at tiles " + path.GetTile() + " and " + par.GetTile());
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" && AITunnel.IsTunnelTile(path.GetTile()) && AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
//										AILog.Warning("We found a road tunnel already built at tiles " + path.GetTile() + " and " + par.GetTile());
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" && AIBridge.IsBridgeTile(path.GetTile()) && AIBridge.GetOtherBridgeEnd(path.GetTile()) == par.GetTile()) {
//										AILog.Warning("We found a road bridge already built at tiles " + path.GetTile() + " and " + par.GetTile());
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
										if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
											AILog.Warning("Couldn't build road at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
											return this.PathfindBuildRoad(from_tile, last_node, null, road_cost);
										}
									}
									++counter;
								}
								else {
									road_cost += costs.GetCosts();
//									AILog.Warning("We built a road at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
									break;
								}

								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								AILog.Warning("Couldn't build road at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
								return [null, null];
							}

							/* add road piece into the road array */
							this.m_built_tiles.append(RoadTile(path.GetTile(), RoadTileType.ROAD));
						}
						else {
							if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
								AILog.Warning("Won't build a road crossing a rail at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
								return this.PathfindBuildRoad(from_tile, last_node, null, road_cost);
							}
							else {
								AILog.Warning("Won't build a road crossing a rail at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
								return [null, null];
							}
						}
					}
					else {
						/* Build a bridge or tunnel. */
						if (!AIBridge.IsBridgeTile(path.GetTile()) || !AITunnel.IsTunnelTile(path.GetTile())) {
							/* If it was a road tile, demolish it first. Do this to work around expended roadbits. */
							if (AIRoad.IsRoadTile(path.GetTile()) && !AIRoad.IsDriveThroughRoadStationTile(path.GetTile()) && AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (!TestDemolishTile().TryDemolish(path.GetTile())) {
										if (AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
												AILog.Warning("Couldn't demolish road at tile " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return this.PathfindBuildRoad(from_tile, last_node, null, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										AILog.Warning("We demolished a road at tile " + path.GetTile() + ". ec: 0, ac: " + costs.GetCosts());
										break;
									}

									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									AILog.Warning("Couldn't demolish road at tile " + path.GetTile() + " - " + AIError.GetLastErrorString());
									return [null, null];
								}
							}
							if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (!TestBuildTunnel().TryBuild(AIVehicle.VT_ROAD, path.GetTile())) {
										if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" && AITunnel.IsTunnelTile(path.GetTile()) && (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) && last_node != null && AIRoad.AreRoadTilesConnected(path.GetTile(), last_node)) {
//											AILog.Warning("We found a road tunnel already built at tiles " + path.GetTile() + " and " + par.GetTile());
											break;
										}
										else if (AIError.GetLastErrorString() == "ERR_ANOTHER_TUNNEL_IN_THE_WAY") {
											if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
												AILog.Warning("Couldn't build road tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return this.PathfindBuildRoad(from_tile, last_node, null, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										AILog.Warning("We built a road tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
										break;
									}

									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									AILog.Warning("Couldn't build road tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									return [null, null];
								}

								this.m_built_tiles.append(RoadTile(path.GetTile(), RoadTileType.TUNNEL));

							}
							else {
								local bridge_length = AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1;
								local bridge_list = AIBridgeList_Length(bridge_length);
								for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
									bridge_list.SetValue(bridge, AIBridge.GetMaxSpeed(bridge));
								}
								bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (!TestBuildBridge().TryBuild(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
										if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT" || AIBridge.IsBridgeTile(path.GetTile()) && (AIBridge.GetOtherBridgeEnd(path.GetTile()) == par.GetTile()) && last_node != null && AIRoad.AreRoadTilesConnected(path.GetTile(), last_node)) {
//											AILog.Warning("We found a road bridge already built at tiles " + path.GetTile() + " and " + par.GetTile());
											this.m_bridge_tiles.append(path.GetTile() < par.GetTile() ? [path.GetTile(), par.GetTile()] : [par.GetTile(), path.GetTile()]);
											break;
										}
										else if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
											for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
												bridge_list.SetValue(bridge, AIBridge.GetPrice(bridge, bridge_length));
											}
											bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
										}
										else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
												AILog.Warning("Couldn't build road bridge at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return this.PathfindBuildRoad(from_tile, last_node, null, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										AILog.Warning("We built a road bridge at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
										this.m_bridge_tiles.append(path.GetTile() < par.GetTile() ? [path.GetTile(), par.GetTile()] : [par.GetTile(), path.GetTile()]);
										break;
									}

									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									AILog.Warning("Couldn't build road bridge at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									return [null, null];
								}

								this.m_built_tiles.append(RoadTile(path.GetTile(), RoadTileType.BRIDGE, bridge_list.Begin()));
								this.m_built_tiles.append(RoadTile(par.GetTile(), RoadTileType.ROAD));
							}
						}
					}
				}
				last_node = path.GetTile();
				path = par;
			}
			AILog.Info("Road built! Actual cost for building road: " + road_cost);
		}

		return [this.m_built_tiles, null];
	}

	function FindSuitableRoadDepotTile(tile)
	{
		if (!AIRoad.IsRoadTile(tile)) {
			return null;
		}

		local adjacent_tiles = Utils.GetAdjacentTiles(tile);
		local road_tiles = AITileList();
		for (local adjacent_tile = adjacent_tiles.Begin(); !adjacent_tiles.IsEnd(); adjacent_tile = adjacent_tiles.Next()) {
			if (AIRoad.IsRoadTile(adjacent_tile)) {
				road_tiles.AddTile(adjacent_tile);
			}
		}
		adjacent_tiles.RemoveList(road_tiles);

		for (local roadTile = road_tiles.Begin(); !road_tiles.IsEnd(); roadTile = road_tiles.Next()) {
			if (!AIRoad.AreRoadTilesConnected(roadTile, tile)) continue;

			for (local adjacent_tile = adjacent_tiles.Begin(); !adjacent_tiles.IsEnd(); adjacent_tile = adjacent_tiles.Next()) {
				if ((AIRoad.AreRoadTilesConnected(tile, adjacent_tile) && !AIRoad.IsRoadDepotTile(adjacent_tile))
					|| (AITile.IsBuildable(adjacent_tile)
					&& (AITile.GetSlope(adjacent_tile) == AITile.SLOPE_FLAT || !AITile.IsCoastTile(adjacent_tile) || !AITile.HasTransportType(adjacent_tile, AITile.TRANSPORT_WATER) || AICompany.GetLoanAmount() == 0))
					&& AIRoad.CanBuildConnectedRoadPartsHere(tile, roadTile, adjacent_tile) == 1) {
					return adjacent_tile;
				}
			}
		}

		return null;
	}

	function BuildRoadDepotOnTile(t)
	{
		local square = AITileList();
		square.AddRectangle(Utils.GetValidOffsetTile(t, -1, -1), Utils.GetValidOffsetTile(t, 1, 1));

		local depot_tile = this.FindSuitableRoadDepotTile(t);
		local depotFrontTile = t;

		if (depot_tile != null) {
			local counter = 0;
			do {
				if (!TestBuildRoadDepot().TryBuild(depot_tile, depotFrontTile)) {
					++counter;
				}
				else {
					break;
				}
				AIController.Sleep(1);
			} while (counter < 1);

			if (counter == 1) {
				return null;
			}
			else {
				local counter = 0;
				do {
					if (!TestBuildRoad().TryBuild(depot_tile, depotFrontTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
						++counter;
					}
					else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					local counter = 0;
					do {
						if (!TestRemoveRoadDepot().TryRemove(depot_tile)) {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);

					if (counter == 500) {
						::scheduledRemovalsTable.Road.rawset(depot_tile, 0);
						return null;
					}
					else {
						return null;
					}
				}
				else {
					return depot_tile;
				}
			}
		}
	}

	function BuildRouteRoadDepot(road_array)
	{
		if (road_array == null) {
			return null;
		}

		local depot_tile = null;

		/* first attempt, build next to the road route */
		local arrayMiddleTile = road_array[road_array.len() / 2].m_tile;
		local roadTiles = AITileList();
		for (local index = 1; index < road_array.len() - 1; ++index) {
			roadTiles.AddItem(road_array[index].m_tile, AIMap.DistanceManhattan(road_array[index].m_tile, arrayMiddleTile));
		}
		roadTiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		for (local tile = roadTiles.Begin(); !roadTiles.IsEnd(); tile = roadTiles.Next()) {
			depot_tile = this.BuildRoadDepotOnTile(tile);
			if (depot_tile != null) {
				return depot_tile;
			}
		}

		local squareSize = AIGameSettings.GetValue("station_spread");

		/* second attempt, build closer to the destination */
		local tileList = AITileList();
		tileList.AddRectangle(Utils.GetValidOffsetTile(this.m_station_to, -1 * squareSize, -1 * squareSize), Utils.GetValidOffsetTile(this.m_station_to, squareSize, squareSize));

		local removelist = AITileList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (!AIRoad.IsRoadTile(tile)) {
				removelist.AddTile(tile);
			} else {
				tileList.SetValue(tile, AIMap.DistanceManhattan(tile, this.m_station_to));
			}
		}
		tileList.RemoveList(removelist);
		tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			depot_tile = this.BuildRoadDepotOnTile(tile);
			if (depot_tile != null) {
				return depot_tile;
			}
		}

		/* third attempt, build closer to the source */
		tileList.Clear();

		tileList.AddRectangle(Utils.GetValidOffsetTile(this.m_station_from, -1 * squareSize, -1 * squareSize), Utils.GetValidOffsetTile(this.m_station_from, squareSize, squareSize));

		removelist.Clear();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (!AIRoad.IsRoadTile(tile)) {
				removelist.AddTile(tile);
			} else {
				tileList.SetValue(tile, AIMap.DistanceManhattan(tile, this.m_station_from));
			}
		}
		tileList.RemoveList(removelist);
		tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			depot_tile = this.BuildRoadDepotOnTile(tile);
			if (depot_tile != null) {
				return depot_tile;
			}
		}

		AILog.Warning("Couldn't built road depot!");
		return depot_tile;
	}

	function SaveBuildManager()
	{
		return [this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile, this.m_bridge_tiles, this.m_cargo_class, this.m_articulated, this.m_best_routes_built, this.m_pathfinder_profile];
	}

	function LoadBuildManager(data)
	{
		this.m_city_from = data[0];
		this.m_city_to = data[1];
		this.m_station_from = data[2];
		this.m_station_to = data[3];
		this.m_depot_tile = data[4];
		this.m_bridge_tiles = data[5];
		this.m_cargo_class = data[6];
		this.m_articulated = data[7];
		this.m_best_routes_built = data[8];
		this.m_pathfinder_profile = data[9];
	}
};
