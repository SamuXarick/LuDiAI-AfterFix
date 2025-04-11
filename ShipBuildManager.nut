require("CanalPathFinder.nut");

enum WaterTileType
{
	CANAL,
	LOCK,
	AQUEDUCT
};

class WaterTile
{
	m_tile = null;
	m_type = null;

	constructor(tile, type) {
		m_tile = tile;
		m_type = type;
	}

	function SetType(tile, watertype) {
		return {
			m_tile = tile,
			m_type = watertype,
		};
	}
};

class ShipBuildManager
{
	m_city_from = -1;
	m_city_to = -1;
	m_dockFrom = -1;
	m_dockTo = -1;
	m_depotTile = -1;
	m_cargo_class = -1;
	m_cheaperRoute = -1;
	m_pathfinder = null;
	m_pathfinderTries = 0;
	m_builtTiles = [];
	m_sentToDepotWaterGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	function HasUnfinishedRoute()
	{
		return m_city_from != -1 && m_city_to != -1 && m_cargo_class != -1;
	}

	function SetRouteFinished()
	{
		m_city_from = -1;
		m_city_to = -1;
		m_dockFrom = -1;
		m_dockTo = -1;
		m_depotTile = -1;
		m_cargo_class = -1;
		m_cheaperRoute = -1;
		m_builtTiles = [];
		m_sentToDepotWaterGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
		m_best_routes_built = null;
	}

	function BuildWaterRoute(cityFrom, cityTo, cargoClass, cheaperRoute, sentToDepotWaterGroup, best_routes_built)
	{
		m_city_from = cityFrom;
		m_city_to = cityTo;
		m_cargo_class = cargoClass;
		m_cheaperRoute = cheaperRoute;
		m_sentToDepotWaterGroup = sentToDepotWaterGroup;
		m_best_routes_built = best_routes_built;

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_WATER);
		if (num_vehicles >= AIGameSettings.GetValue("max_ships") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_WATER)) {
			/* Don't terminate the route, or it may leave already built docks behind. */
			return 0;
		}

		if (m_dockFrom == -1) {
			m_dockFrom = BuildTownDock(m_city_from, m_cargo_class, m_cheaperRoute, m_best_routes_built);
			if (m_dockFrom == null) {
				SetRouteFinished();
				return null;
			}
		}

		if (m_dockTo == -1) {
			m_dockTo = BuildTownDock(m_city_to, m_cargo_class, m_cheaperRoute, m_best_routes_built);
			if (m_dockTo == null) {
				if (m_dockFrom != null) {
					local counter = 0;
					do {
						if (!TestRemoveDock().TryRemove(m_dockFrom)) {
							++counter;
						}
						else {
//							AILog.Warning("m_dockTo == null; Removed dock tile at " + m_dockFrom);
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);
					if (counter == 500) {
						::scheduledRemovalsTable.Ship.rawset(m_dockFrom, 0);
//						AILog.Error("Failed to remove dock tile at " + m_dockFrom + " - " + AIError.GetLastErrorString());
					} else {
						local slope = AITile.GetSlope(m_dockFrom);
						assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
						/* Check for canal and remove it */
						local offset = 0;
						if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
						if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
						if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
						if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
						local tile2 = m_dockFrom + offset;
						if (AIMarine.IsCanalTile(tile2)) {
							local counter = 0;
							do {
								if (!TestRemoveCanal().TryRemove(tile2)) {
									++counter;
								}
								else {
//									AILog.Warning("m_dockTo == null; Removed canal tile at " + tile2);
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);
							if (counter == 500) {
								::scheduledRemovalsTable.Ship.rawset(tile2, 0);
//								AILog.Error("Failed to remove canal tile at " + tile2 + " - " + AIError.GetLastErrorString());
							}
						}
						local tile3 = tile2 + offset;
						if (AIMarine.IsCanalTile(tile3) && !Utils.RemovingCanalBlocksConnection(tile3)) {
							local counter = 0;
							do {
								if (!TestRemoveCanal().TryRemove(tile3)) {
									++counter;
								}
								else {
//									AILog.Warning("m_dockTo == null; Removed canal tile at " + tile3);
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);
							if (counter == 500) {
								::scheduledRemovalsTable.Ship.rawset(tile3, 0);
//								AILog.Error("Failed to remove canal tile at " + tile3 + " - " + AIError.GetLastErrorString());
							}
						}
					}
				}
				SetRouteFinished();
				return null;
			}
		}

		if (m_depotTile == -1) {
			/* Provide the docking tiles to the pathfinder */
			local slope = AITile.GetSlope(m_dockFrom);
			assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
			local offset = 0;
			if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(2, 0);
			if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -2);
			if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-2, 0);
			if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 2);
			local tile2From = m_dockFrom + offset;

			slope = AITile.GetSlope(m_dockTo);
			assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
			if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(2, 0);
			if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -2);
			if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-2, 0);
			if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 2);
			local tile2To = m_dockTo + offset;

			local canalArray = PathfindBuildCanal(tile2From, tile2To, false, m_pathfinder, m_builtTiles);
			m_pathfinder = canalArray[1];
			if (canalArray[0] == null && m_pathfinder != null) {
				return 0;
			}
			m_depotTile = BuildRouteShipDepot(canalArray[0]);
		}

		if (m_depotTile == null) {
			if (m_dockFrom != null) {
				local counter = 0;
				do {
					if (!TestRemoveDock().TryRemove(m_dockFrom)) {
						++counter;
					}
					else {
//						AILog.Warning("m_depotTile == null; Removed dock tile at " + m_dockFrom);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Ship.rawset(m_dockFrom, 0);
//					AILog.Error("Failed to remove dock tile at " + m_dockFrom + " - " + AIError.GetLastErrorString());
				} else {
					local slope = AITile.GetSlope(m_dockFrom);
					assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
					/* Check for canal and remove it */
					local offset = 0;
					if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
					if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
					if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
					if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
					local tile2 = m_dockFrom + offset;
					if (AIMarine.IsCanalTile(tile2)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile2)) {
								++counter;
							}
							else {
//								AILog.Warning("m_depotTile == null; Removed canal tile at " + tile2);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);
						if (counter == 500) {
							::scheduledRemovalsTable.Ship.rawset(tile2, 0);
//							AILog.Error("Failed to remove canal tile at " + tile2 + " - " + AIError.GetLastErrorString());
						}
					}
					local tile3 = tile2 + offset;
					if (AIMarine.IsCanalTile(tile3) && !Utils.RemovingCanalBlocksConnection(tile3)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								++counter;
							}
							else {
//								AILog.Warning("m_depotTile == null; Removed canal tile at " + tile3);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);
						if (counter == 500) {
							::scheduledRemovalsTable.Ship.rawset(tile3, 0);
//							AILog.Error("Failed to remove canal tile at " + tile3 + " - " + AIError.GetLastErrorString());
						}
					}
				}
			}

			if (m_dockTo != null) {
				local counter = 0;
				do {
					if (!TestRemoveDock().TryRemove(m_dockTo)) {
						++counter;
					}
					else {
//						AILog.Warning("m_depotTile == null; Removed dock tile at " + m_dockTo);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Ship.rawset(m_dockTo, 0);
//					AILog.Error("Failed to remove dock tile at " + m_dockTo + " - " + AIError.GetLastErrorString());
				} else {
					local slope = AITile.GetSlope(m_dockTo);
					assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
					/* Check for canal and remove it */
					local offset = 0;
					if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
					if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
					if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
					if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
					local tile2 = m_dockTo + offset;
					if (AIMarine.IsCanalTile(tile2)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile2)) {
								++counter;
							}
							else {
//								AILog.Warning("m_depotTile == null; Removed canal tile at " + tile2);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);
						if (counter == 500) {
							::scheduledRemovalsTable.Ship.rawset(tile2, 0);
//							AILog.Error("Failed to remove canal tile at " + tile2 + " - " + AIError.GetLastErrorString());
						}
					}
					local tile3 = tile2 + offset;
					if (AIMarine.IsCanalTile(tile3) && !Utils.RemovingCanalBlocksConnection(tile3)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								++counter;
							}
							else {
//								AILog.Warning("m_depotTile == null; Removed canal tile at " + tile3);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);
						if (counter == 500) {
							::scheduledRemovalsTable.Ship.rawset(tile3, 0);
//							AILog.Error("Failed to remove canal tile at " + tile3 + " - " + AIError.GetLastErrorString());
						}
					}
				}
			}

			SetRouteFinished();
			return null;
		}

		m_builtTiles = [];
		return ShipRoute(m_city_from, m_city_to, m_dockFrom, m_dockTo, m_depotTile, m_cargo_class, m_sentToDepotWaterGroup);
	}

	function BuildTownDock(town_id, cargoClass, cheaperRoute, best_routes_built)
	{
		local cargoType = Utils.GetCargoType(cargoClass);
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);

		local tileList = AITileList();

		/* build square around @town_id and find suitable tiles for docks */
		local rectangleCoordinates = Utils.EstimateTownRectangle(town_id);

		tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);

		local templist = AITileList();
		templist.AddList(tileList);
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			local buildable = Utils.IsDockBuildableTile(tile, cheaperRoute);
			if (!buildable[0]) {
				templist.RemoveTile(tile);
				continue;
			}
			local temp_tile1 = tile;
			local temp_tile2 = buildable[1];
			if (temp_tile1 > temp_tile2) {
				local swap = temp_tile1;
				temp_tile1 = temp_tile2;
				temp_tile2 = swap;
			}

			local x_length = 1;
			local y_length = 1;
			if (temp_tile2 - temp_tile1 == 1) {
				x_length = 2;
			} else {
				y_length = 2;
			}

			if (AITile.GetCargoAcceptance(temp_tile1, cargoType, x_length, y_length, radius) < 8) {
				templist.RemoveTile(tile);
				continue;
			}

			if (Utils.AreOtherDocksNearby(temp_tile1, temp_tile2)) {
				templist.RemoveTile(tile);
				continue;
			}
			local cargo_production = AITile.GetCargoProduction(temp_tile1, cargoType, x_length, y_length, radius);
			local pick_mode = AIController.GetSetting("pick_mode");
			if (pick_mode != 1 && !best_routes_built && cargo_production < 8) {
				templist.RemoveTile(tile);
				continue;
			} else {
				templist.SetValue(tile, cargo_production);
			}
//			templist.SetValue(tile, AITile.GetCargoProduction(temp_tile1, cargoType, x_length, y_length, radius));
		}
		tileList.Clear();
		tileList.AddList(templist);
		/* valuate and sort by the number of cargo tiles the dock covers */
		tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // starts from corners if without sort

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
//			AILog.Info("We're at tile " + tile);
			local adjacentNonDock = Utils.CheckAdjacentNonDock(tile);

			local slope = AITile.GetSlope(tile);
			if (slope == AITile.SLOPE_FLAT) continue;

			local offset = 0;
			local tile2 = AIMap.TILE_INVALID;
			local tile3 = AIMap.TILE_INVALID;
			if (AITile.IsBuildable(tile) && (
					slope == AITile.SLOPE_NE && (offset = AIMap.GetTileIndex(1, 0)) ||
					slope == AITile.SLOPE_SE && (offset = AIMap.GetTileIndex(0, -1)) ||
					slope == AITile.SLOPE_SW && (offset = AIMap.GetTileIndex(-1, 0)) ||
					slope == AITile.SLOPE_NW && (offset = AIMap.GetTileIndex(0, 1)))) {
				tile2 = tile + offset;
				if (!AIMap.IsValidTile(tile2)) continue;
				if (AITile.GetSlope(tile2) != AITile.SLOPE_FLAT) continue;
				if (!(!cheaperRoute && AITile.IsBuildable(tile2) || AITile.IsWaterTile(tile2) && !AIMarine.IsWaterDepotTile(tile2) && !AIMarine.IsLockTile(tile2))) continue;

				tile3 = tile2 + offset;
				if (!AIMap.IsValidTile(tile3)) continue;
				if (AITile.GetSlope(tile3) != AITile.SLOPE_FLAT) continue;
				if (!(!cheaperRoute && AITile.IsBuildable(tile3) || AITile.IsWaterTile(tile3) && !AIMarine.IsWaterDepotTile(tile3) && !AIMarine.IsLockTile(tile3))) continue;

				local offset2 = (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW) ? AIMap.GetTileIndex(0, 1) : AIMap.GetTileIndex(1, 0);

				local tile2_1 = tile2 + offset2;
				local tile2_2 = tile2 - offset2;
				local tile3_1 = tile3 + offset2;
				local tile3_2 = tile3 - offset2;

//				AILog.Info("tile = " + tile + "; tile2 = " + tile2 + "; tile3 = " + tile3 + "; tile2_1 = " + tile2_1 + "; tile2_2 = " + tile2_2 + "; tile3_1 = " + tile3_1 + "; tile3_2 = " + tile3_2);

				local built_canal1 = false;
				if (!AITile.IsWaterTile(tile2)) {
					if (cheaperRoute) continue;

					local counter = 0;
					do {
						if (!TestBuildCanal().TryBuild(tile2) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);
					if (counter == 500) {
						/* Failed to build first canal. Try the next location. */
						continue;
					}
					else {
						/* The first canal was successfully built. */
						built_canal1 = true;
					}
				}

				local built_canal2 = false;
				if (!AITile.IsWaterTile(tile3)) {
					if (cheaperRoute) continue;

					local counter = 0;
					do {
						if (!TestBuildCanal().TryBuild(tile3) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);
					if (counter == 500) {
						/* Failed to build second canal. Remove the first canal if it was built then. */
						if (built_canal1) {
							local counter = 0;
							do {
								if (!TestRemoveCanal().TryRemove(tile2)) {
									++counter;
								}
								else {
//									AILog.Warning("Removed canal tile at " + tile2);
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);
							if (counter == 500) {
								::scheduledRemovalsTable.Ship.rawset(tile2, 0);
//								AILog.Error("Failed to remove canal tile at " + tile2 + " - " + AIError.GetLastErrorString());
								continue;
							} else {
								/* The first canal was successfully removed after failing to build the second canal. Try it all over again in the next location */
								continue;
							}
						}
					}
					else {
						/* The second canal was successfully built. */
						built_canal2 = true;
					}
				}

				local blocking = false;
				if (AIMarine.IsLockTile(tile2_1) && AITile.GetSlope(tile2_1) == AITile.SLOPE_FLAT && Utils.CheckLockDirection(tile2_1, Utils.GetLockMiddleTile(tile2_1)) ||
						AIMarine.IsLockTile(tile2_2) && AITile.GetSlope(tile2_2) == AITile.SLOPE_FLAT && Utils.CheckLockDirection(tile2_2, Utils.GetLockMiddleTile(tile2_2))) {
					blocking = true;
				}

				if (!blocking && (AIMarine.IsDockTile(tile2_1) && Utils.GetDockDockingTile(tile2_1) == tile2 ||
						AIMarine.IsDockTile(tile2_2) && Utils.GetDockDockingTile(tile2_2) == tile2)) {
					blocking = true;
				}

				if (!blocking && (AIMarine.AreWaterTilesConnected(tile2, tile2_1) && AIMarine.AreWaterTilesConnected(tile2, tile3))) {
					if (!(AIMarine.AreWaterTilesConnected(tile3_1, tile2_1) && AIMarine.AreWaterTilesConnected(tile3_1, tile3))) {
						blocking = true;
					}
				}

				if (!blocking && (AIMarine.AreWaterTilesConnected(tile2, tile2_2) && AIMarine.AreWaterTilesConnected(tile2, tile3))) {
					if (!(AIMarine.AreWaterTilesConnected(tile3_2, tile2_2) && AIMarine.AreWaterTilesConnected(tile3_2, tile3))) {
						blocking = true;
					}
				}

				if (!blocking) {
					local counter = 0;
					do {
						if (!TestBuildDock().TryBuild(tile, adjacentNonDock)) {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);
					if (counter == 1) {
						if (built_canal1) {
							local counter = 0;
							do {
								if (!TestRemoveCanal().TryRemove(tile2)) {
									++counter;
								}
								else {
//									AILog.Warning("Removed canal tile at " + tile2);
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);
							if (counter == 500) {
								::scheduledRemovalsTable.Ship.rawset(tile2, 0);
//								AILog.Error("Failed to remove canal tile at " + tile2 + " - " + AIError.GetLastErrorString());
//							} else {
//								/* The first canal was successfully removed after failing to build the dock. Try it all over again in the next location */
							}
						}
						if (built_canal2) {
							local counter = 0;
							do {
								if (!TestRemoveCanal().TryRemove(tile3)) {
									++counter;
								}
								else {
//									AILog.Warning("Removed canal tile at " + tile3);
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);
							if (counter == 500) {
								::scheduledRemovalsTable.Ship.rawset(tile3, 0);
//								AILog.Error("Failed to remove canal tile at " + tile3 + " - " + AIError.GetLastErrorString());
//							} else {
//								/* The second canal was successfully removed after failing to build the dock. Try it all over again in the next location */
							}
						}
						continue;
					}
					else {
						AILog.Info("Dock built in " + AITown.GetName(town_id) + " at tile " + tile + "!");
						return tile;
					}
				}

				if (blocking) {
					if (built_canal1) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile2)) {
								++counter;
							}
							else {
//								AILog.Warning("Removed canal tile at " + tile2);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);
						if (counter == 500) {
							::scheduledRemovalsTable.Ship.rawset(tile2, 0);
//							AILog.Error("Failed to remove canal tile at " + tile2 + " - " + AIError.GetLastErrorString());
//						} else {
//							/* The first canal was successfully removed after detecting a block. Try it all over again in the next location */
						}
					}
					if (built_canal2) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								++counter;
							}
							else {
//								AILog.Warning("Removed canal tile at " + tile3);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);
						if (counter == 500) {
							::scheduledRemovalsTable.Ship.rawset(tile3, 0);
//							AILog.Error("Failed to remove canal tile at " + tile3 + " - " + AIError.GetLastErrorString());
//						} else {
//							/* The second canal was successfully removed after detecting a block. Try it all over again in the next location */
						}
					}
					continue;
				}
			}
		}

		return null;
	}

	/* find canal way between fromTile and toTile */
	function PathfindBuildCanal(fromTile, toTile, silent_mode = false, pathfinder = null, builtTiles = [], cost_so_far = 0)
	{
		/* can store canal tiles into array */

		if (fromTile != toTile) {
			local route_dist = AIMap.DistanceManhattan(AITown.GetLocation(m_city_from), AITown.GetLocation(m_city_to));
			local max_pathfinderTries = 333 * route_dist;

			/* Print the names of the towns we'll try to connect. */
			if (!silent_mode) AILog.Info("s:Connecting " + AITown.GetName(m_city_from) + " (tile " + fromTile + ") and " + AITown.GetName(m_city_to) + " (tile " + toTile + ") (iteration " + (m_pathfinderTries + 1) + "/" + max_pathfinderTries + ")");

			if (pathfinder == null) {
				/* Create an instance of the pathfinder. */
				pathfinder = Canal();

				AILog.Info("canal pathfinder: default");
/*defaults*/
/*10000000*/	pathfinder.cost.max_cost;
/*100*/			pathfinder.cost.tile;
/*200*/			pathfinder.cost.no_existing_water = m_cheaperRoute ? pathfinder.cost.max_cost : 100;
/*70*/			pathfinder.cost.diagonal_tile;
/*100*/			pathfinder.cost.turn45;
/*600*/			pathfinder.cost.turn90;
/*400*/			pathfinder.cost.aqueduct_per_tile;
/*925*/			pathfinder.cost.lock;
/*150*/			pathfinder.cost.depot;
/*6*/			pathfinder.cost.max_aqueduct_length = AIGameSettings.GetValue("infinite_money") ? AIGameSettings.GetValue("max_bridge_length") + 2 : pathfinder.cost.max_aqueduct_length;
/*1*/			pathfinder.cost.estimate_multiplier = 1.0 + route_dist / 333.3;
/*0*/			pathfinder.cost.search_range = max(33, route_dist / 10);

				/* Give the source and goal tiles to the pathfinder. */
				pathfinder.InitializePath([fromTile], [toTile]);
			}

			local cur_date = AIDate.GetCurrentDate();
			local path;

//			local count = 0;
			do {
				++m_pathfinderTries;
//				++count;
				path = pathfinder.FindPath(1);

				if (path == false) {
					if (m_pathfinderTries < max_pathfinderTries) {
						if (AIDate.GetCurrentDate() - cur_date > 1) {
//							if (!silent_mode) AILog.Info("canal pathfinder: FindPath iterated: " + count);
//							local signList = AISignList();
//							for (local sign = signList.Begin(); !signList.IsEnd(); sign = signList.Next()) {
//								if (signList.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder];
						}
					} else {
						/* Timed out */
						if (!silent_mode) AILog.Error("canal pathfinder: FindPath return false (timed out)");
						m_pathfinderTries = 0;
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					if (!silent_mode) AILog.Error("canal pathfinder: FindPath return null (no path)");
					m_pathfinderTries = 0;
					return [null, null];
				}
			} while (path == false);

//			if (!silent_mode && m_pathfinderTries != count) AILog.Info("canal pathfinder: FindPath iterated: " + count);
			if (!silent_mode) AILog.Info("Canal path found! FindPath iterated: " + m_pathfinderTries + ". Building canal... ");
			if (!silent_mode) AILog.Info("canal pathfinder: FindPath cost: " + path.GetCost());
			local canal_cost = cost_so_far;
			/* If a path was found, build a canal over it. */
			local last_node = null;
			local built_last_node = false;
			while (path != null) {
				local par = path.GetParent();
//				AILog.Info("built_last_node = " + built_last_node + "; last_node = " + last_node + "; par.GetTile() = " + (par == null ? par : par.GetTile()) + "; path.GetTile() = " + path.GetTile());
				if (par != null) {
					if (AIMap.DistanceManhattan(par.GetTile(), path.GetTile()) > 1 || Utils.CheckAqueductSlopes(par.GetTile(), path.GetTile())) {
						if (AIMap.DistanceManhattan(par.GetTile(), path.GetTile()) == 2 && AITile.GetSlope(par.GetTile()) == AITile.SLOPE_FLAT && AITile.GetSlope(path.GetTile()) == AITile.SLOPE_FLAT) {
							/* We want to build a lock. */
							local next_tile = par.GetTile() - (par.GetTile() - path.GetTile()) / 2;
							if (!AITile.HasTransportType(next_tile, AITile.TRANSPORT_WATER)) {
								local counter = 0;
								do {
									local costs = AIAccounting();
									if ((!Canal()._LockBlocksConnection(par.GetTile(), next_tile) || built_last_node) && TestBuildLock().TryBuild(next_tile)) {
										canal_cost += costs.GetCosts();
										built_last_node = true;
//										if (!silent_mode) AILog.Info("Built lock at " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
										break;
									} else {
										if (Canal()._LockBlocksConnection(par.GetTile(), next_tile)) {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - LockBlocksConnection = true - Retrying...");
												return PathfindBuildCanal(fromTile, last_node, silent_mode, null, m_builtTiles, canal_cost);
											}
										} else if (AIMarine.IsLockTile(next_tile) && Utils.GetLockMiddleTile(next_tile) == next_tile &&
												AIMarine.IsLockTile(path.GetTile()) && Utils.GetOtherLockEnd(path.GetTile()) == par.GetTile()) {
//											if (!silent_mode) AILog.Warning("We found a lock already built at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
											built_last_node = false;
											break;
										} else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - LockBlocksConnection = true - Retrying...");
												return PathfindBuildCanal(fromTile, last_node, silent_mode, null, m_builtTiles, canal_cost);
											}
										}
										++counter;
//										if (!silent_mode) AILog.Warning("Failed lock at " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
									}
									AIController.Sleep(1);
								} while (counter < 500);
								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}
							} else {
								built_last_node = false;
							}
							/* add lock piece into the canal array */
							m_builtTiles.append(WaterTile.SetType(next_tile, WaterTileType.LOCK));
							last_node = path.GetTile();
							path = par;
							par = path.GetParent();
						} else {
							/* We want to build an aqueduct. */
							if (!AITile.HasTransportType(par.GetTile(), AITile.TRANSPORT_WATER)) {
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (TestBuildBridge().TryBuild(AIVehicle.VT_WATER, 0, par.GetTile(), path.GetTile())) {
										canal_cost += costs.GetCosts();
										built_last_node = true;
//										if (!silent_mode) AILog.Info("Built aqueduct at " + par.GetTile() + " and " + path.GetTile());
										break;
									} else {
										if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT") {
//											if (!silent_mode) AILog.Warning("We found an aqueduct already built between tiles " + par.GetTile() + " and " + path.GetTile());
											built_last_node = false;
											break;
										} else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG") {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build aqueduct between tiles " + par.GetTile() + " and " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return PathfindBuildCanal(fromTile, last_node, silent_mode, null, m_builtTiles, canal_cost);
											}
										}
										++counter;
//										if (!silent_mode) AILog.Warning("Failed aqueduct at " + par.GetTile() + " and " + path.GetTile());
									}
									AIController.Sleep(1);
								} while (counter < 500);
								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build aqueduct between tiles " + par.GetTile() + " and " + path.GetTile() + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}
							} else {
								built_last_node = false;
							}
							/* add aqueduct pieces into the canal array */
							m_builtTiles.append(WaterTile.SetType(par.GetTile(), WaterTileType.AQUEDUCT));
							m_builtTiles.append(WaterTile.SetType(path.GetTile(), WaterTileType.AQUEDUCT));
							last_node = path.GetTile();
							path = par;
							par = path.GetParent();
						}
					} else {
						/* We want to build a canal tile. */
						if (!AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_WATER) || last_node != null && AIMap.DistanceManhattan(last_node, path.GetTile()) == 1 && !Utils.CheckAqueductSlopes(last_node, path.GetTile()) && !AIMarine.AreWaterTilesConnected(last_node, path.GetTile())) {
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (TestBuildCanal().TryBuild(path.GetTile())) {
									canal_cost += costs.GetCosts();
									built_last_node = true;
//									if (!silent_mode) AILog.Info("Built canal 'path' at " + path.GetTile());
									break;
								} else {
									if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_FLAT_LAND_REQUIRED" || AIMarine.IsWaterDepotTile(path.GetTile()) || AIMarine.IsLockTile(path.GetTile()) || AIMarine.IsDockTile(path.GetTile()) || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_LOCAL_AUTHORITY_REFUSES") {
										if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
											if (!silent_mode) AILog.Warning("Couldn't build canal 'path' at tile " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
											return PathfindBuildCanal(fromTile, last_node, silent_mode, null, m_builtTiles, canal_cost);
										}
									} else if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT" && AIMarine.IsCanalTile(path.GetTile())) {
//										if (!silent_mode) AILog.Warning("We found a canal already built at tile " + path.GetTile());
										built_last_node = false;
										break;
									}
									++counter;
//									if (!silent_mode) AILog.Warning("Failed canal 'path' at " + path.GetTile());
								}
								AIController.Sleep(1);
							} while (counter < 500);
							if (counter == 500) {
								if (!silent_mode) AILog.Warning("Couldn't build canal 'path' at tile " + path.GetTile() + " - " + AIError.GetLastErrorString());
								m_pathfinderTries = 0;
								return [null, null];
							}
						} else {
							built_last_node = false;
						}
						/* add canal piece into the canal array */
						m_builtTiles.append(WaterTile.SetType(path.GetTile(), WaterTileType.CANAL));
					}
				}
				last_node = path.GetTile();
				path = par;
			}
			if (!silent_mode) AILog.Info("Canal built! Actual cost for building canal: " + canal_cost);
		}

		m_pathfinderTries = 0;
		return [builtTiles, null];
	}

	function BuildingShipDepotBlocksConnection(top_tile, bot_tile)
	{
		assert(AIMap.DistanceManhattan(top_tile, bot_tile) == 1);

		local offset = AIMap.GetTileX(top_tile) == AIMap.GetTileX(bot_tile) ? AIMap.GetTileIndex(1, 0) : AIMap.GetTileIndex(0, 1);

		local top_exit = top_tile + (top_tile - bot_tile);
		local bot_exit = bot_tile + (bot_tile - top_tile);
		local t_sp = top_tile + offset;
		local t_sn = top_tile - offset;
		local b_sp = bot_tile + offset;
		local b_sn = bot_tile - offset;
		local te_sp = top_exit + offset;
		local te_sn = top_exit - offset;
		local be_sp = bot_exit + offset;
		local be_sn = bot_exit - offset;

		local top_tile_top_exit = AIMarine.AreWaterTilesConnected(top_tile, top_exit);
		local bot_tile_bot_exit = AIMarine.AreWaterTilesConnected(bot_tile, bot_exit);
		local top_tile_t_sp = AIMarine.AreWaterTilesConnected(top_tile, t_sp);
		local top_tile_t_sn = AIMarine.AreWaterTilesConnected(top_tile, t_sn);
		local bot_tile_b_sp = AIMarine.AreWaterTilesConnected(bot_tile, b_sp);
		local bot_tile_b_sn = AIMarine.AreWaterTilesConnected(bot_tile, b_sn);
		local top_exit_te_sp = AIMarine.AreWaterTilesConnected(top_exit, te_sp);
		local top_exit_te_sn = AIMarine.AreWaterTilesConnected(top_exit, te_sn);
		local bot_exit_be_sp = AIMarine.AreWaterTilesConnected(bot_exit, be_sp);
		local bot_exit_be_sn = AIMarine.AreWaterTilesConnected(bot_exit, be_sn);
		local te_sp_t_sp = AIMarine.AreWaterTilesConnected(te_sp, t_sp);
		local te_sn_t_sn = AIMarine.AreWaterTilesConnected(te_sn, t_sn);
		local be_sp_b_sp = AIMarine.AreWaterTilesConnected(be_sp, b_sp);
		local be_sn_b_sn = AIMarine.AreWaterTilesConnected(be_sn, b_sn);
		local t_sp_b_sp = AIMarine.AreWaterTilesConnected(t_sp, b_sp);
		local t_sn_b_sn = AIMarine.AreWaterTilesConnected(t_sn, b_sn);

		if (!te_sn_t_sn && top_exit_te_sn && top_tile_top_exit && top_tile_t_sn) {
			if (!be_sn_b_sn || !bot_exit_be_sn) return true;
		}
		if (!top_exit_te_sn && top_tile_top_exit && top_tile_t_sn) {
			if (!t_sn_b_sn || !be_sn_b_sn || !bot_exit_be_sn) return true;
		}
		if (!top_exit_te_sp && top_tile_top_exit && top_tile_t_sp) {
			if (!t_sp_b_sp || !be_sp_b_sp || !bot_exit_be_sp) return true;
		}
		if (!te_sp_t_sp && top_exit_te_sp && top_tile_top_exit && top_tile_t_sp) {
			if (!be_sp_b_sp || !bot_exit_be_sp) return true;
		}

		if (!be_sn_b_sn && bot_exit_be_sn && bot_tile_bot_exit && bot_tile_b_sn) {
			if (!te_sn_t_sn || !top_exit_te_sn) return true;
		}
		if (!bot_exit_be_sn && bot_tile_bot_exit && bot_tile_b_sn) {
			if (!t_sn_b_sn || !te_sn_t_sn || !top_exit_te_sn) return true;
		}
		if (!bot_exit_be_sp && bot_tile_bot_exit && bot_tile_b_sp) {
			if (!t_sp_b_sp || !te_sp_t_sp || !top_exit_te_sp) return true;
		}

		if (!be_sp_b_sp && bot_exit_be_sp && bot_tile_bot_exit && bot_tile_b_sp) {
			if (!te_sp_t_sp || !top_exit_te_sp) return true;
		}

		if (!top_tile_top_exit) {
			if (top_tile_t_sp) {
				if (bot_tile_b_sp && !t_sp_b_sp) return true;
				if (bot_tile_bot_exit && (!t_sp_b_sp || !be_sp_b_sp || !bot_exit_be_sp)) return true;
				if (bot_tile_b_sn && (!t_sp_b_sp || !be_sp_b_sp || !bot_exit_be_sp || !bot_exit_be_sn || !be_sn_b_sn)) return true;
			}
			if (top_tile_t_sn) {
				if (bot_tile_b_sn && !t_sn_b_sn) return true;
				if (bot_tile_bot_exit && (!t_sn_b_sn || !be_sn_b_sn || !bot_exit_be_sn)) return true;
				if (bot_tile_b_sp && (!t_sn_b_sn || !be_sn_b_sn || !bot_exit_be_sn || !bot_exit_be_sp || !be_sp_b_sp)) return true;
			}
			if (bot_tile_b_sp) {
				if (!be_sp_b_sp || !bot_exit_be_sp || !bot_tile_bot_exit) return true;
			}
			if (bot_tile_b_sn) {
				if (!be_sn_b_sn || !bot_exit_be_sn || !bot_tile_bot_exit) return true;
			}
		}

		if (!bot_tile_bot_exit) {
			if (bot_tile_b_sp) {
				if (top_tile_t_sp && !t_sp_b_sp) return true;
				if (top_tile_top_exit && (!t_sp_b_sp || !te_sp_t_sp || !top_exit_te_sp)) return true;
				if (top_tile_t_sn && (!t_sp_b_sp || !te_sp_t_sp || !top_exit_te_sp || !top_exit_te_sn || !te_sn_t_sn)) return true;
			}
			if (bot_tile_b_sn) {
				if (top_tile_t_sn && !t_sn_b_sn) return true;
				if (top_tile_top_exit && (!t_sn_b_sn || !te_sn_t_sn || !top_exit_te_sn)) return true;
				if (top_tile_t_sp && (!t_sn_b_sn || !te_sn_t_sn || !top_exit_te_sn || !top_exit_te_sp || !te_sp_t_sp)) return true;
			}
			if (top_tile_t_sp) {
				if (!te_sp_t_sp || !top_exit_te_sp || !top_tile_top_exit) return true;
			}
			if (top_tile_t_sn) {
				if (!te_sn_t_sn || !top_exit_te_sn || !top_tile_top_exit) return true;
			}
		}

		if (AIBridge.IsBridgeTile(t_sp) && AITile.HasTransportType(t_sp, AITile.TRANSPORT_WATER)) return true;
		if (AIBridge.IsBridgeTile(t_sn) && AITile.HasTransportType(t_sn, AITile.TRANSPORT_WATER)) return true;
		if (AIBridge.IsBridgeTile(b_sp) && AITile.HasTransportType(b_sp, AITile.TRANSPORT_WATER)) return true;
		if (AIBridge.IsBridgeTile(b_sn) && AITile.HasTransportType(b_sn, AITile.TRANSPORT_WATER)) return true;

		if (AIMarine.IsDockTile(t_sp) && AITile.GetSlope(t_sp) == AITile.SLOPE_FLAT && Utils.GetDockDockingTile(t_sp) == top_tile) return true;
		if (AIMarine.IsDockTile(t_sn) && AITile.GetSlope(t_sn) == AITile.SLOPE_FLAT && Utils.GetDockDockingTile(t_sn) == top_tile) return true;
		if (AIMarine.IsDockTile(b_sp) && AITile.GetSlope(b_sp) == AITile.SLOPE_FLAT && Utils.GetDockDockingTile(b_sp) == bot_tile) return true;
		if (AIMarine.IsDockTile(b_sn) && AITile.GetSlope(b_sn) == AITile.SLOPE_FLAT && Utils.GetDockDockingTile(b_sn) == bot_tile) return true;

		if (top_tile_t_sp) {
			if (AIMarine.IsWaterDepotTile(t_sp)) return true;
			local slope = AITile.GetSlope(t_sp);
			if (AIMarine.IsLockTile(t_sp) && slope == AITile.SLOPE_FLAT) return true;
			if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_S || slope == AITile.SLOPE_E || slope == AITile.SLOPE_W) {
				if (t_sp_b_sp) return true;
			}
		}

		if (top_tile_t_sn) {
			if (AIMarine.IsWaterDepotTile(t_sn)) return true;
			local slope = AITile.GetSlope(t_sn);
			if (AIMarine.IsLockTile(t_sn) && slope == AITile.SLOPE_FLAT) return true;
			if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_S || slope == AITile.SLOPE_E || slope == AITile.SLOPE_W) {
				if (t_sn_b_sn) return true;
			}
		}

		if (bot_tile_b_sp) {
			if (AIMarine.IsWaterDepotTile(b_sp)) return true;
			local slope = AITile.GetSlope(b_sp);
			if (AIMarine.IsLockTile(b_sp) && slope == AITile.SLOPE_FLAT) return true;
			if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_S || slope == AITile.SLOPE_E || slope == AITile.SLOPE_W) {
				if (t_sp_b_sp) return true;
			}
		}

		if (bot_tile_b_sn) {
			if (AIMarine.IsWaterDepotTile(b_sn)) return true;
			local slope = AITile.GetSlope(b_sn);
			if (AIMarine.IsLockTile(b_sn) && slope == AITile.SLOPE_FLAT) return true;
			if (slope == AITile.SLOPE_N || slope == AITile.SLOPE_S || slope == AITile.SLOPE_E || slope == AITile.SLOPE_W) {
				if (t_sn_b_sn) return true;
			}
		}

		if (top_tile_top_exit) {
			if (top_tile_t_sp) {
				if (!te_sp_t_sp || !top_exit_te_sp) return true;
			}
			if (top_tile_t_sn) {
				if (!te_sn_t_sn || !top_exit_te_sn) return true;
			}
		}

		if (bot_tile_bot_exit) {
			if (bot_tile_b_sp) {
				if (!be_sp_b_sp || !bot_exit_be_sp) return true;
			}
			if (bot_tile_b_sn) {
				if (!be_sn_b_sn || !bot_exit_be_sn) return true;
			}
		}

		if (top_tile_t_sp && top_tile_t_sn) {
			if (!top_tile_top_exit) {
				return true;
			} else if (!top_exit_te_sp) {
				return true;
			} else if (!top_exit_te_sn) {
				return true;
			} else if (!te_sp_t_sp) {
				return true;
			} else if (!te_sn_t_sn) {
				return true;
			}
		}

		if (bot_tile_b_sp && bot_tile_b_sn) {
			if (!bot_tile_bot_exit) {
				return true;
			} else if (!bot_exit_be_sp) {
				return true;
			} else if (!bot_exit_be_sn) {
				return true;
			} else if (!be_sp_b_sp) {
				return true;
			} else if (!be_sn_b_sn) {
				return true;
			}
		}

		return false;
	}

	function BuildRouteShipDepot(canalArray)
	{
		if (canalArray == null) {
			return null;
		}

		local depotTile = null;
		local arrayMiddleTile = canalArray[canalArray.len() / 2].m_tile;
		local canalTiles = AIList();

		for (local i = 0; i < canalArray.len() - 1; ++i) {
			local tile_top = canalArray[i].m_tile;
			local tile_bot = canalArray[i + 1].m_tile;
			if (canalArray[i].m_type != WaterTileType.CANAL || canalArray[i + 1].m_type != WaterTileType.CANAL || AIMap.DistanceManhattan(tile_top, tile_bot) != 1) continue;

			if (tile_top > tile_bot) {
				local swap = tile_top;
				tile_top = tile_bot;
				tile_bot = swap;
			}
			local distance = min(AIMap.DistanceManhattan(tile_top, arrayMiddleTile), AIMap.DistanceManhattan(tile_bot, arrayMiddleTile));
			canalTiles.AddItem(tile_top | (tile_bot << 24), distance);
//			AILog.Info("Added " + tile_top + " and " + tile_bot);
		}
		canalTiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		for (local tiles = canalTiles.Begin(); !canalTiles.IsEnd(); tiles = canalTiles.Next()) {
			local tile_top = tiles & 0xFFFFFF;
			local tile_bot = tiles >> 24;
//			AILog.Info("Extracted " + tile_top + " and " + tile_bot);
			if (!BuildingShipDepotBlocksConnection(tile_top, tile_bot)) {
				local counter = 0;
				do {
					if (!TestBuildWaterDepot().TryBuild(tile_top, tile_bot)) {
						++counter;
					}
					else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 1);
				if (counter == 1) {
					continue;
				} else {
					depotTile = tile_top;
					break;
				}
			} else {
				continue;
			}
		}

		if (depotTile == null) AILog.Warning("Couldn't built ship depot!");
		return depotTile;
	}

	function SaveBuildManager()
	{
		if (m_city_from == null) m_city_from = -1;
		if (m_city_to == null) m_city_to = -1;
		if (m_dockFrom == null) m_dockFrom = -1;
		if (m_dockTo == null) m_dockTo = -1;
		if (m_depotTile == null) m_depotTile = -1;
		if (m_cheaperRoute == null) m_cheaperRoute = -1;

		return [m_city_from, m_city_to, m_dockFrom, m_dockTo, m_depotTile, m_cargo_class, m_cheaperRoute, m_best_routes_built, m_builtTiles];
	}

	function LoadBuildManager(data)
	{
		m_city_from = data[0];
		m_city_to = data[1];
		m_dockFrom = data[2];
		m_dockTo = data[3];
		m_depotTile = data[4];
		m_cargo_class = data[5];
		m_cheaperRoute = data[6];
		m_best_routes_built = data[7];
		m_builtTiles = data[8];
	}
};
