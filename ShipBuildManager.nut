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

	constructor(tile, type)
	{
		this.m_tile = tile;
		this.m_type = type;
	}

	function SetType(tile, watertype)
	{
		return {
			m_tile = tile,
			m_type = watertype,
		};
	}
};

class ShipBuildManager
{
	/* These are saved */
	m_city_from = -1;
	m_city_to = -1;
	m_dock_from = -1;
	m_dock_to = -1;
	m_depot_tile = -1;
	m_cargo_class = -1;
	m_cheaper_route = null;
	m_built_tiles = null;
	m_best_routes_built = null;

	/* These are not saved */
	m_pathfinder_instance = null;
	m_pathfinder_tries = -1;
	m_sent_to_depot_water_group = null;

	function HasUnfinishedRoute()
	{
		return this.m_city_from != -1 && this.m_city_to != -1 && this.m_cargo_class != -1;
	}

	function SetRouteFinished()
	{
		this.m_city_from = -1;
		this.m_city_to = -1;
		this.m_dock_from = -1;
		this.m_dock_to = -1;
		this.m_depot_tile = -1;
		this.m_cargo_class = -1;
		this.m_cheaper_route = null;
		this.m_built_tiles = null;
		this.m_best_routes_built = null;
		this.m_pathfinder_instance = null;
		this.m_pathfinder_tries = -1;
		this.m_sent_to_depot_water_group = null;
	}

	/**
	 * Get the tile where ships can use to dock at the given dock.
	 * @param dock_tile A tile that is part of the dock.
	 * @return The tile where ships dock at the given dock.
	 */
	function GetDockDockingTile(dock_tile)
	{
		assert(AIMarine.IsDockTile(dock_tile));

		local dock_slope;
		if (AITile.GetSlope(dock_tile) == AITile.SLOPE_FLAT) {
			foreach (offset in [AIMap.GetMapSizeX(), -AIMap.GetMapSizeX(), 1, -1]) {
				local offset_tile = dock_tile + offset;
				if (AIMarine.IsDockTile(offset_tile)) {
					local slope = AITile.GetSlope(offset_tile);
					if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE) {
						dock_slope = offset_tile;
						break;
					}
				}
			}
		} else {
			dock_slope = dock_tile;
		}

		local slope = AITile.GetSlope(dock_slope);
		if (slope == AITile.SLOPE_NE) {
			return dock_slope + 2;
		} else if (slope == AITile.SLOPE_SE) {
			return dock_slope - 2 * AIMap.GetMapSizeX();
		} else if (slope == AITile.SLOPE_SW) {
			return dock_slope - 2;
		} else if (slope == AITile.SLOPE_NW) {
			return dock_slope + 2 * AIMap.GetMapSizeX();
		}
	}

	/**
	 * Get the tile of the other end of a lock.
	 * @param tile The tile of the entrance of a lock.
	 * @return The tile of the other end of the same lock.
	 */
	function GetOtherLockEnd(tile)
	{
		assert(AIMarine.IsLockTile(tile) && AITile.GetSlope(tile) == AITile.SLOPE_FLAT);

		foreach (offset in [AIMap.GetMapSizeX(), -AIMap.GetMapSizeX(), 1, -1]) {
			local middle_tile = tile + offset;
			local slope = AITile.GetSlope(middle_tile);
			if (AIMarine.IsLockTile(middle_tile) && (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE)) {
				return middle_tile + offset;
			}
		}
	}

	/**
	 * Get the tile of the middle part of a lock.
	 * @param tile The tile of a part of a lock.
	 * @return The tile of the middle part of the same lock.
	 */
	function GetLockMiddleTile(tile)
	{
		assert(AIMarine.IsLockTile(tile));

		local slope = AITile.GetSlope(tile);
		if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE) return tile;

		assert(slope == AITile.SLOPE_FLAT);

		local other_end = this.GetOtherLockEnd(tile);
		return tile - (tile - other_end) / 2;
	}

	/**
	 * Check whether the tile we're coming from is compatible with the axis of a
	 *  lock planned in this location.
	 * @param prev_tile The tile we're coming from.
	 * @param middle_tile The tile of the middle part of a planned lock.
	 * @return true if the previous tile is compatible with the axis of the planned lock.
	 */
	function CheckLockDirection(prev_tile, middle_tile)
	{
		local slope = AITile.GetSlope(middle_tile);
		assert(slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE);

		if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NE) {
			return prev_tile == middle_tile + 1 || prev_tile == middle_tile - 1;
		} else if (slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NW) {
			return prev_tile == middle_tile + AIMap.GetMapSizeX() || prev_tile == middle_tile - AIMap.GetMapSizeX();
		}

		return false;
	}

	function RemovingCanalBlocksConnection(tile)
	{
		local t_sw = tile + AIMap.GetTileIndex(1, 0);
		local t_ne = tile + AIMap.GetTileIndex(-1, 0);
		local t_se = tile + AIMap.GetTileIndex(0, 1);
		local t_nw = tile + AIMap.GetTileIndex(0, -1);

		if (AIMarine.IsLockTile(t_se) && AITile.GetSlope(t_se) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_se, this.GetLockMiddleTile(t_se)) ||
				AIMarine.IsLockTile(t_nw) && AITile.GetSlope(t_nw) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_nw, this.GetLockMiddleTile(t_nw)) ||
				AIMarine.IsLockTile(t_ne) && AITile.GetSlope(t_ne) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_ne, this.GetLockMiddleTile(t_ne)) ||
				AIMarine.IsLockTile(t_sw) && AITile.GetSlope(t_sw) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_sw, this.GetLockMiddleTile(t_sw))) {
			return true;
		}

		if (AIMarine.IsDockTile(t_se) && this.GetDockDockingTile(t_se) == tile ||
				AIMarine.IsDockTile(t_nw) && this.GetDockDockingTile(t_nw) == tile ||
				AIMarine.IsDockTile(t_ne) && this.GetDockDockingTile(t_ne) == tile ||
				AIMarine.IsDockTile(t_sw) && this.GetDockDockingTile(t_sw) == tile) {
			return true;
		}

		local t_e = tile + AIMap.GetTileIndex(-1, 1);

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_ne)) {
			if (!(AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne))) {
				return true;
			}
		}

		local t_n = tile + AIMap.GetTileIndex(-1, -1);

		if (AIMarine.AreWaterTilesConnected(tile, t_nw) && AIMarine.AreWaterTilesConnected(tile, t_ne)) {
			if (!(AIMarine.AreWaterTilesConnected(t_n, t_nw) && AIMarine.AreWaterTilesConnected(t_n, t_ne))) {
				return true;
			}
		}

		local t_s = tile + AIMap.GetTileIndex(1, 1);

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (!(AIMarine.AreWaterTilesConnected(t_s, t_se) && AIMarine.AreWaterTilesConnected(t_s, t_sw))) {
				return true;
			}
		}

		local t_w = tile + AIMap.GetTileIndex(1, -1);

		if (AIMarine.AreWaterTilesConnected(tile, t_nw) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (!(AIMarine.AreWaterTilesConnected(t_w, t_nw) && AIMarine.AreWaterTilesConnected(t_w, t_sw))) {
				return true;
			}
		}

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_nw)) {
			if (AIMarine.AreWaterTilesConnected(t_s, t_se) && AIMarine.AreWaterTilesConnected(t_s, t_sw)) {
				if (!(AIMarine.AreWaterTilesConnected(t_w, t_nw) && AIMarine.AreWaterTilesConnected(t_w, t_sw))) {
					return true;
				}
			} else if (AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne)) {
				if (!(AIMarine.AreWaterTilesConnected(t_n, t_nw) && AIMarine.AreWaterTilesConnected(t_n, t_ne))) {
					return true;
				}
			} else {
				return true;
			}
		}

		if (AIMarine.AreWaterTilesConnected(tile, t_ne) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne)) {
				if (!(AIMarine.AreWaterTilesConnected(t_s, t_se) && AIMarine.AreWaterTilesConnected(t_s, t_sw))) {
					return true;
				}
			} else if (AIMarine.AreWaterTilesConnected(t_n, t_nw) && AIMarine.AreWaterTilesConnected(t_n, t_ne)) {
				if (!(AIMarine.AreWaterTilesConnected(t_w, t_nw) && AIMarine.AreWaterTilesConnected(t_w, t_sw))) {
					return true;
				}
			} else {
				return true;
			}
		}

		return false;
	}

	function BuildWaterRoute(city_from, city_to, cargo_class, cheaper_route, sent_to_depot_water_group, best_routes_built)
	{
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_cargo_class = cargo_class;
		this.m_cheaper_route = cheaper_route;
		this.m_sent_to_depot_water_group = sent_to_depot_water_group;
		this.m_best_routes_built = best_routes_built;

		if (this.m_built_tiles == null) {
			this.m_built_tiles = [];
		}

		if (this.m_pathfinder_tries == -1) {
			this.m_pathfinder_tries = 0;
		}

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_WATER);
		if (num_vehicles >= AIGameSettings.GetValue("max_ships") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_WATER)) {
			/* Don't terminate the route, or it may leave already built docks behind. */
			return 0;
		}

		if (this.m_dock_from == -1) {
			this.m_dock_from = this.BuildTownDock(this.m_city_from, this.m_cargo_class, this.m_cheaper_route, this.m_best_routes_built);
			if (this.m_dock_from == null) {
				this.SetRouteFinished();
				return null;
			}
		}

		if (this.m_dock_to == -1) {
			this.m_dock_to = this.BuildTownDock(this.m_city_to, this.m_cargo_class, this.m_cheaper_route, this.m_best_routes_built);
			if (this.m_dock_to == null) {
				if (this.m_dock_from != null) {
					local counter = 0;
					do {
						if (!TestRemoveDock().TryRemove(this.m_dock_from)) {
							++counter;
						} else {
//							AILog.Warning("this.m_dock_to == null; Removed dock tile at " + this.m_dock_from);
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);

					if (counter == 500) {
						::scheduledRemovalsTable.Ship.rawset(this.m_dock_from, 0);
//						AILog.Error("Failed to remove dock tile at " + this.m_dock_from + " - " + AIError.GetLastErrorString());
					} else {
						local slope = AITile.GetSlope(this.m_dock_from);
						assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
						/* Check for canal and remove it */
						local offset = 0;
						if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
						if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
						if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
						if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
						local tile2 = this.m_dock_from + offset;
						if (AIMarine.IsCanalTile(tile2)) {
							local counter = 0;
							do {
								if (!TestRemoveCanal().TryRemove(tile2)) {
									++counter;
								} else {
//									AILog.Warning("this.m_dock_to == null; Removed canal tile at " + tile2);
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
						if (AIMarine.IsCanalTile(tile3) && !this.RemovingCanalBlocksConnection(tile3)) {
							local counter = 0;
							do {
								if (!TestRemoveCanal().TryRemove(tile3)) {
									++counter;
								} else {
//									AILog.Warning("this.m_dock_to == null; Removed canal tile at " + tile3);
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
				this.SetRouteFinished();
				return null;
			}
		}

		if (this.m_depot_tile == -1) {
			/* Provide the docking tiles to the pathfinder */
			local slope = AITile.GetSlope(this.m_dock_from);
			assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
			local offset = 0;
			if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(2, 0);
			if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -2);
			if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-2, 0);
			if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 2);
			local tile2From = this.m_dock_from + offset;

			slope = AITile.GetSlope(this.m_dock_to);
			assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
			if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(2, 0);
			if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -2);
			if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-2, 0);
			if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 2);
			local tile2To = this.m_dock_to + offset;

			local canalArray = this.PathfindBuildCanal(tile2From, tile2To, false, this.m_pathfinder_instance, this.m_built_tiles);
			this.m_pathfinder_instance = canalArray[1];
			if (canalArray[0] == null && this.m_pathfinder_instance != null) {
				return 0;
			}
			this.m_depot_tile = this.BuildRouteShipDepot(canalArray[0]);
		}

		if (this.m_depot_tile == null) {
			if (this.m_dock_from != null) {
				local counter = 0;
				do {
					if (!TestRemoveDock().TryRemove(this.m_dock_from)) {
						++counter;
					} else {
//						AILog.Warning("this.m_depot_tile == null; Removed dock tile at " + this.m_dock_from);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduledRemovalsTable.Ship.rawset(this.m_dock_from, 0);
//					AILog.Error("Failed to remove dock tile at " + this.m_dock_from + " - " + AIError.GetLastErrorString());
				} else {
					local slope = AITile.GetSlope(this.m_dock_from);
					assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
					/* Check for canal and remove it */
					local offset = 0;
					if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
					if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
					if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
					if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
					local tile2 = this.m_dock_from + offset;
					if (AIMarine.IsCanalTile(tile2)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile2)) {
								++counter;
							} else {
//								AILog.Warning("this.m_depot_tile == null; Removed canal tile at " + tile2);
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
					if (AIMarine.IsCanalTile(tile3) && !this.RemovingCanalBlocksConnection(tile3)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								++counter;
							} else {
//								AILog.Warning("this.m_depot_tile == null; Removed canal tile at " + tile3);
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

			if (this.m_dock_to != null) {
				local counter = 0;
				do {
					if (!TestRemoveDock().TryRemove(this.m_dock_to)) {
						++counter;
					} else {
//						AILog.Warning("this.m_depot_tile == null; Removed dock tile at " + this.m_dock_to);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduledRemovalsTable.Ship.rawset(this.m_dock_to, 0);
//					AILog.Error("Failed to remove dock tile at " + this.m_dock_to + " - " + AIError.GetLastErrorString());
				} else {
					local slope = AITile.GetSlope(this.m_dock_to);
					assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
					/* Check for canal and remove it */
					local offset = 0;
					if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
					if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
					if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
					if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
					local tile2 = this.m_dock_to + offset;
					if (AIMarine.IsCanalTile(tile2)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile2)) {
								++counter;
							} else {
//								AILog.Warning("this.m_depot_tile == null; Removed canal tile at " + tile2);
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
					if (AIMarine.IsCanalTile(tile3) && !this.RemovingCanalBlocksConnection(tile3)) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								++counter;
							} else {
//								AILog.Warning("this.m_depot_tile == null; Removed canal tile at " + tile3);
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

			this.SetRouteFinished();
			return null;
		}

		this.m_built_tiles = [];
		return ShipRoute(this.m_city_from, this.m_city_to, this.m_dock_from, this.m_dock_to, this.m_depot_tile, this.m_cargo_class, this.m_sent_to_depot_water_group);
	}

	function IsDockBuildableTile(tile, cheaper_route)
	{
		local slope = AITile.GetSlope(tile);
		if (slope == AITile.SLOPE_FLAT) return [false, null];

		local offset = 0;
		local tile2 = AIMap.TILE_INVALID;
		if (AITile.IsBuildable(tile) && (
				slope == AITile.SLOPE_NE && (offset = AIMap.GetTileIndex(1, 0)) ||
				slope == AITile.SLOPE_SE && (offset = AIMap.GetTileIndex(0, -1)) ||
				slope == AITile.SLOPE_SW && (offset = AIMap.GetTileIndex(-1, 0)) ||
				slope == AITile.SLOPE_NW && (offset = AIMap.GetTileIndex(0, 1)))) {
			tile2 = tile + offset;
			if (!AIMap.IsValidTile(tile2)) return [false, null];
			if (AITile.GetSlope(tile2) != AITile.SLOPE_FLAT) return [false, null];
			if (!((!cheaper_route && AITile.IsBuildable(tile2)) || (AITile.IsWaterTile(tile2) && !AIMarine.IsWaterDepotTile(tile2) && !AIMarine.IsLockTile(tile2)))) return [false, null];
			local tile3 = tile2 + offset;
			if (!AIMap.IsValidTile(tile3)) return [false, null];
			if (AITile.GetSlope(tile3) != AITile.SLOPE_FLAT) return [false, null];
			if (!((!cheaper_route && AITile.IsBuildable(tile3)) || (AITile.IsWaterTile(tile3) && !AIMarine.IsWaterDepotTile(tile3) && !AIMarine.IsLockTile(tile3)))) return [false, null];
		}

		return [true, tile2];
	}

	function BuildTownDock(town_id, cargo_class, cheaper_route, best_routes_built)
	{
		local cargoType = Utils.GetCargoType(cargo_class);
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);

		local tileList = AITileList();

		/* build square around @town_id and find suitable tiles for docks */
		local rectangleCoordinates = Utils.EstimateTownRectangle(town_id);

		tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);

		local templist = AITileList();
		templist.AddList(tileList);
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			local buildable = this.IsDockBuildableTile(tile, cheaper_route);
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
				if (!(!cheaper_route && AITile.IsBuildable(tile2) || AITile.IsWaterTile(tile2) && !AIMarine.IsWaterDepotTile(tile2) && !AIMarine.IsLockTile(tile2))) continue;

				tile3 = tile2 + offset;
				if (!AIMap.IsValidTile(tile3)) continue;
				if (AITile.GetSlope(tile3) != AITile.SLOPE_FLAT) continue;
				if (!(!cheaper_route && AITile.IsBuildable(tile3) || AITile.IsWaterTile(tile3) && !AIMarine.IsWaterDepotTile(tile3) && !AIMarine.IsLockTile(tile3))) continue;

				local offset2 = (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW) ? AIMap.GetTileIndex(0, 1) : AIMap.GetTileIndex(1, 0);

				local tile2_1 = tile2 + offset2;
				local tile2_2 = tile2 - offset2;
				local tile3_1 = tile3 + offset2;
				local tile3_2 = tile3 - offset2;

//				AILog.Info("tile = " + tile + "; tile2 = " + tile2 + "; tile3 = " + tile3 + "; tile2_1 = " + tile2_1 + "; tile2_2 = " + tile2_2 + "; tile3_1 = " + tile3_1 + "; tile3_2 = " + tile3_2);

				local built_canal1 = false;
				if (!AITile.IsWaterTile(tile2)) {
					if (cheaper_route) continue;

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
					if (cheaper_route) continue;

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
				if (AIMarine.IsLockTile(tile2_1) && AITile.GetSlope(tile2_1) == AITile.SLOPE_FLAT && this.CheckLockDirection(tile2_1, this.GetLockMiddleTile(tile2_1)) ||
						AIMarine.IsLockTile(tile2_2) && AITile.GetSlope(tile2_2) == AITile.SLOPE_FLAT && this.CheckLockDirection(tile2_2, this.GetLockMiddleTile(tile2_2))) {
					blocking = true;
				}

				if (!blocking && (AIMarine.IsDockTile(tile2_1) && this.GetDockDockingTile(tile2_1) == tile2 ||
						AIMarine.IsDockTile(tile2_2) && this.GetDockDockingTile(tile2_2) == tile2)) {
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

	/**
	 * Special check determining the possibility of a two tile sized
	 *  aqueduct sharing the same edge to be built here.
	 *  Checks wether the slopes are suitable and in the correct
	 *  direction for such aqueduct.
	 * @param tile_a The starting tile of a two tile sized aqueduct.
	 * @param tile_b The ending tile of a two tile sized aqueduct.
	 * @return true if the slopes are suitable for a two tile sized aqueduct.
	 */
	function CheckAqueductSlopes(tile_a, tile_b)
	{
		if (AIMap.DistanceManhattan(tile_a, tile_b) != 1) return false;
		local slope_a = AITile.GetSlope(tile_a);
		local slope_b = AITile.GetSlope(tile_b);
		if ((slope_a != AITile.SLOPE_SW && slope_a != AITile.SLOPE_NW && slope_a != AITile.SLOPE_SE && slope_a != AITile.SLOPE_NE) ||
				(slope_b != AITile.SLOPE_SW && slope_b != AITile.SLOPE_NW && slope_b != AITile.SLOPE_SE && slope_b != AITile.SLOPE_NE)) {
			return false;
		}

		if (AITile.GetComplementSlope(slope_a) != slope_b) return false;

		local offset;
		if (slope_a == AITile.SLOPE_NE) {
			offset = 1;
		} else if (slope_a == AITile.SLOPE_SE) {
			offset = -AIMap.GetMapSizeX();
		} else if (slope_a == AITile.SLOPE_SW) {
			offset = -1;
		} else if (slope_a == AITile.SLOPE_NW) {
			offset = AIMap.GetMapSizeX();
		}

		return tile_a + offset == tile_b;
	}

	/* find canal way between fromTile and toTile */
	function PathfindBuildCanal(fromTile, toTile, silent_mode = false, pathfinder = null, builtTiles = [], cost_so_far = 0)
	{
		/* can store canal tiles into array */

		if (fromTile != toTile) {
			local route_dist = AIMap.DistanceManhattan(AITown.GetLocation(this.m_city_from), AITown.GetLocation(this.m_city_to));
			local max_pathfinderTries = 333 * route_dist;

			/* Print the names of the towns we'll try to connect. */
			if (!silent_mode) AILog.Info("s:Connecting " + AITown.GetName(this.m_city_from) + " (tile " + fromTile + ") and " + AITown.GetName(this.m_city_to) + " (tile " + toTile + ") (iteration " + (this.m_pathfinder_tries + 1) + "/" + max_pathfinderTries + ")");

			if (pathfinder == null) {
				/* Create an instance of the pathfinder. */
				pathfinder = Canal();

				AILog.Info("canal pathfinder: default");
/*defaults*/
/*10000000*/	pathfinder.cost.max_cost;
/*100*/			pathfinder.cost.tile;
/*200*/			pathfinder.cost.no_existing_water = this.m_cheaper_route ? pathfinder.cost.max_cost : 100;
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
				++this.m_pathfinder_tries;
//				++count;
				path = pathfinder.FindPath(1);

				if (path == false) {
					if (this.m_pathfinder_tries < max_pathfinderTries) {
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
						this.m_pathfinder_tries = 0;
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					if (!silent_mode) AILog.Error("canal pathfinder: FindPath return null (no path)");
					this.m_pathfinder_tries = 0;
					return [null, null];
				}
			} while (path == false);

//			if (!silent_mode && this.m_pathfinder_tries != count) AILog.Info("canal pathfinder: FindPath iterated: " + count);
			if (!silent_mode) AILog.Info("Canal path found! FindPath iterated: " + this.m_pathfinder_tries + ". Building canal... ");
			if (!silent_mode) AILog.Info("canal pathfinder: FindPath cost: " + path.GetCost());
			local canal_cost = cost_so_far;
			/* If a path was found, build a canal over it. */
			local last_node = null;
			local built_last_node = false;
			while (path != null) {
				local par = path.GetParent();
//				AILog.Info("built_last_node = " + built_last_node + "; last_node = " + last_node + "; par.GetTile() = " + (par == null ? par : par.GetTile()) + "; path.GetTile() = " + path.GetTile());
				if (par != null) {
					if (AIMap.DistanceManhattan(par.GetTile(), path.GetTile()) > 1 || this.CheckAqueductSlopes(par.GetTile(), path.GetTile())) {
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
											if (this.m_pathfinder_tries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - LockBlocksConnection = true - Retrying...");
												return this.PathfindBuildCanal(fromTile, last_node, silent_mode, null, this.m_built_tiles, canal_cost);
											}
										} else if (AIMarine.IsLockTile(next_tile) && this.GetLockMiddleTile(next_tile) == next_tile &&
												AIMarine.IsLockTile(path.GetTile()) && this.GetOtherLockEnd(path.GetTile()) == par.GetTile()) {
//											if (!silent_mode) AILog.Warning("We found a lock already built at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
											built_last_node = false;
											break;
										} else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (this.m_pathfinder_tries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - LockBlocksConnection = true - Retrying...");
												return this.PathfindBuildCanal(fromTile, last_node, silent_mode, null, this.m_built_tiles, canal_cost);
											}
										}
										++counter;
//										if (!silent_mode) AILog.Warning("Failed lock at " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
									}
									AIController.Sleep(1);
								} while (counter < 500);
								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									this.m_pathfinder_tries = 0;
									return [null, null];
								}
							} else {
								built_last_node = false;
							}
							/* add lock piece into the canal array */
							this.m_built_tiles.append(WaterTile.SetType(next_tile, WaterTileType.LOCK));
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
											if (this.m_pathfinder_tries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build aqueduct between tiles " + par.GetTile() + " and " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return this.PathfindBuildCanal(fromTile, last_node, silent_mode, null, this.m_built_tiles, canal_cost);
											}
										}
										++counter;
//										if (!silent_mode) AILog.Warning("Failed aqueduct at " + par.GetTile() + " and " + path.GetTile());
									}
									AIController.Sleep(1);
								} while (counter < 500);
								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build aqueduct between tiles " + par.GetTile() + " and " + path.GetTile() + " - " + AIError.GetLastErrorString());
									this.m_pathfinder_tries = 0;
									return [null, null];
								}
							} else {
								built_last_node = false;
							}
							/* add aqueduct pieces into the canal array */
							this.m_built_tiles.append(WaterTile.SetType(par.GetTile(), WaterTileType.AQUEDUCT));
							this.m_built_tiles.append(WaterTile.SetType(path.GetTile(), WaterTileType.AQUEDUCT));
							last_node = path.GetTile();
							path = par;
							par = path.GetParent();
						}
					} else {
						/* We want to build a canal tile. */
						if (!AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_WATER) || last_node != null && AIMap.DistanceManhattan(last_node, path.GetTile()) == 1 && !this.CheckAqueductSlopes(last_node, path.GetTile()) && !AIMarine.AreWaterTilesConnected(last_node, path.GetTile())) {
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
										if (this.m_pathfinder_tries < max_pathfinderTries && last_node != null) {
											if (!silent_mode) AILog.Warning("Couldn't build canal 'path' at tile " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
											return this.PathfindBuildCanal(fromTile, last_node, silent_mode, null, this.m_built_tiles, canal_cost);
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
								this.m_pathfinder_tries = 0;
								return [null, null];
							}
						} else {
							built_last_node = false;
						}
						/* add canal piece into the canal array */
						this.m_built_tiles.append(WaterTile.SetType(path.GetTile(), WaterTileType.CANAL));
					}
				}
				last_node = path.GetTile();
				path = par;
			}
			if (!silent_mode) AILog.Info("Canal built! Actual cost for building canal: " + canal_cost);
		}

		this.m_pathfinder_tries = 0;
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

		if (AIMarine.IsDockTile(t_sp) && AITile.GetSlope(t_sp) == AITile.SLOPE_FLAT && this.GetDockDockingTile(t_sp) == top_tile) return true;
		if (AIMarine.IsDockTile(t_sn) && AITile.GetSlope(t_sn) == AITile.SLOPE_FLAT && this.GetDockDockingTile(t_sn) == top_tile) return true;
		if (AIMarine.IsDockTile(b_sp) && AITile.GetSlope(b_sp) == AITile.SLOPE_FLAT && this.GetDockDockingTile(b_sp) == bot_tile) return true;
		if (AIMarine.IsDockTile(b_sn) && AITile.GetSlope(b_sn) == AITile.SLOPE_FLAT && this.GetDockDockingTile(b_sn) == bot_tile) return true;

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

		local depot_tile = null;
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
			if (!this.BuildingShipDepotBlocksConnection(tile_top, tile_bot)) {
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
					depot_tile = tile_top;
					break;
				}
			} else {
				continue;
			}
		}

		if (depot_tile == null) AILog.Warning("Couldn't built ship depot!");
		return depot_tile;
	}

	function SaveBuildManager()
	{
		if (this.m_city_from == null) this.m_city_from = -1;
		if (this.m_city_to == null) this.m_city_to = -1;
		if (this.m_dock_from == null) this.m_dock_from = -1;
		if (this.m_dock_to == null) this.m_dock_to = -1;
		if (this.m_depot_tile == null) this.m_depot_tile = -1;
		if (this.m_cheaper_route == null) this.m_cheaper_route = -1;

		return [this.m_city_from, this.m_city_to, this.m_dock_from, this.m_dock_to, this.m_depot_tile, this.m_cargo_class, this.m_cheaper_route, this.m_best_routes_built, this.m_built_tiles];
	}

	function LoadBuildManager(data)
	{
		this.m_city_from = data[0];
		this.m_city_to = data[1];
		this.m_dock_from = data[2];
		this.m_dock_to = data[3];
		this.m_depot_tile = data[4];
		this.m_cargo_class = data[5];
		this.m_cheaper_route = data[6];
		this.m_best_routes_built = data[7];
		this.m_built_tiles = data[8];
	}
};
