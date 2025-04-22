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

class DockStation
{
	m_inclined_dock_tile = null;
	m_dock_tile = null;
	m_ship_docking_tile = null;
	m_slope_dir = null;

	constructor(inclined_dock_tile, dock_tile, ship_docking_tile, slope_dir)
	{
		this.m_inclined_dock_tile = inclined_dock_tile;
		this.m_dock_tile = dock_tile;
		this.m_ship_docking_tile = ship_docking_tile;
		this.m_slope_dir = slope_dir;
	}

	function IsDockBuildableTile(inclined_dock_tile, build_canals)
	{
		local slope_dir = AITile.GetSlope(inclined_dock_tile);
		if (slope_dir == AITile.SLOPE_FLAT) return false;

		local offset = 0;
		local dock_tile = AIMap.TILE_INVALID;
		if (AITile.IsBuildable(inclined_dock_tile) && (
				slope_dir == AITile.SLOPE_NE && (offset = AIMap.GetTileIndex(1, 0)) ||
				slope_dir == AITile.SLOPE_SE && (offset = AIMap.GetTileIndex(0, -1)) ||
				slope_dir == AITile.SLOPE_SW && (offset = AIMap.GetTileIndex(-1, 0)) ||
				slope_dir == AITile.SLOPE_NW && (offset = AIMap.GetTileIndex(0, 1)))) {
			dock_tile = inclined_dock_tile + offset;
			if (!AIMap.IsValidTile(dock_tile)) return false;
			if (AITile.GetSlope(dock_tile) != AITile.SLOPE_FLAT) return false;
			if (!((build_canals && AITile.IsBuildable(dock_tile)) || (AITile.IsWaterTile(dock_tile) && !AIMarine.IsWaterDepotTile(dock_tile) && !AIMarine.IsLockTile(dock_tile)))) return false;
			local ship_docking_tile = dock_tile + offset;
			if (!AIMap.IsValidTile(ship_docking_tile)) return false;
			if (AITile.GetSlope(ship_docking_tile) != AITile.SLOPE_FLAT) return false;
			if (!((build_canals && AITile.IsBuildable(ship_docking_tile)) || (AITile.IsWaterTile(ship_docking_tile) && !AIMarine.IsWaterDepotTile(ship_docking_tile) && !AIMarine.IsLockTile(ship_docking_tile)))) return false;
			return DockStation(inclined_dock_tile, dock_tile, ship_docking_tile, slope_dir);
		}
		return false;
	}

	function GetTopTile()
	{
		if (this.m_inclined_dock_tile > this.m_dock_tile) {
			return this.m_dock_tile;
		}
		return this.m_inclined_dock_tile;
	}

	function GetDockLengthX()
	{
		switch (this.m_slope_dir) {
			case AITile.SLOPE_NE:
			case AITile.SLOPE_SW:
				return 2;
			case AITile.SLOPE_NW:
			case AITile.SLOPE_SE:
				return 1;
		}
	}

	function GetDockLengthY()
	{
		switch (this.m_slope_dir) {
			case AITile.SLOPE_NE:
			case AITile.SLOPE_SW:
				return 1;
			case AITile.SLOPE_NW:
			case AITile.SLOPE_SE:
				return 2;
		}
	}

	function IsEqual(dock_station)
	{
		if (!dock_station) {
			return false;
		}

		if (dock_station.m_inclined_dock_tile != this.m_inclined_dock_tile) {
			return false;
		}

		if (dock_station.m_dock_tile != this.m_dock_tile) {
			return false;
		}

		if (dock_station.m_ship_docking_tile != this.m_ship_docking_tile) {
			return false;
		}

		return dock_station.m_slope_dir == this.m_slope_dir;
	}
}

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
	m_cargo_type = -1;
	m_coverage_radius = -1;
	m_route_dist = -1;
	m_city_from_name = null;
	m_city_to_name = null;
	m_max_pathfinder_tries = -1;

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
		this.m_cargo_type = -1;
		this.m_coverage_radius = -1;
		this.m_route_dist = -1;
		this.m_city_from_name = null;
		this.m_city_to_name = null;
	}

	/**
	 * Get the tile where ships can use to dock at the given dock.
	 * @param dock_tile A tile that is part of the dock.
	 * @return The tile where ships dock at the given dock.
	 */
	function GetDockDockingTile(dock_tile)
	{
		assert(AIMarine.IsDockTile(dock_tile));

		local inclined_dock_tile = dock_tile;
		if (AITile.GetSlope(dock_tile) == AITile.SLOPE_FLAT) {
			foreach (offset in [AIMap.GetMapSizeX(), -AIMap.GetMapSizeX(), 1, -1]) {
				local offset_tile = dock_tile + offset;
				if (AIMarine.IsDockTile(offset_tile)) {
					local slope = AITile.GetSlope(offset_tile);
					if (slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_NE) {
						inclined_dock_tile = offset_tile;
						assert(AIStation.GetStationID(inclined_dock_tile) == AIStation.GetStationID(dock_tile));
						break;
					}
				}
			}
		}

		local slope = AITile.GetSlope(inclined_dock_tile);
		if (slope == AITile.SLOPE_NE) {
			return inclined_dock_tile + 2;
		} else if (slope == AITile.SLOPE_SE) {
			return inclined_dock_tile - 2 * AIMap.GetMapSizeX();
		} else if (slope == AITile.SLOPE_SW) {
			return inclined_dock_tile - 2;
		} else if (slope == AITile.SLOPE_NW) {
			return inclined_dock_tile + 2 * AIMap.GetMapSizeX();
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

		if ((AIMarine.IsLockTile(t_se) && AITile.GetSlope(t_se) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_se, this.GetLockMiddleTile(t_se))) ||
				(AIMarine.IsLockTile(t_nw) && AITile.GetSlope(t_nw) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_nw, this.GetLockMiddleTile(t_nw))) ||
				(AIMarine.IsLockTile(t_ne) && AITile.GetSlope(t_ne) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_ne, this.GetLockMiddleTile(t_ne))) ||
				(AIMarine.IsLockTile(t_sw) && AITile.GetSlope(t_sw) == AITile.SLOPE_FLAT && this.CheckLockDirection(t_sw, this.GetLockMiddleTile(t_sw)))) {
			return true;
		}

		if ((AIMarine.IsDockTile(t_se) && this.GetDockDockingTile(t_se) == tile) ||
				(AIMarine.IsDockTile(t_nw) && this.GetDockDockingTile(t_nw) == tile) ||
				(AIMarine.IsDockTile(t_ne) && this.GetDockDockingTile(t_ne) == tile) ||
				(AIMarine.IsDockTile(t_sw) && this.GetDockDockingTile(t_sw) == tile)) {
			return true;
		}

		local t_e = tile + AIMap.GetTileIndex(-1, 1);

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_ne)) {
			if (!AIMarine.AreWaterTilesConnected(t_e, t_se) || !AIMarine.AreWaterTilesConnected(t_e, t_ne)) {
				return true;
			}
		}

		local t_n = tile + AIMap.GetTileIndex(-1, -1);

		if (AIMarine.AreWaterTilesConnected(tile, t_nw) && AIMarine.AreWaterTilesConnected(tile, t_ne)) {
			if (!AIMarine.AreWaterTilesConnected(t_n, t_nw) || !AIMarine.AreWaterTilesConnected(t_n, t_ne)) {
				return true;
			}
		}

		local t_s = tile + AIMap.GetTileIndex(1, 1);

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (!AIMarine.AreWaterTilesConnected(t_s, t_se) || !AIMarine.AreWaterTilesConnected(t_s, t_sw)) {
				return true;
			}
		}

		local t_w = tile + AIMap.GetTileIndex(1, -1);

		if (AIMarine.AreWaterTilesConnected(tile, t_nw) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (!AIMarine.AreWaterTilesConnected(t_w, t_nw) || !AIMarine.AreWaterTilesConnected(t_w, t_sw)) {
				return true;
			}
		}

		if (AIMarine.AreWaterTilesConnected(tile, t_se) && AIMarine.AreWaterTilesConnected(tile, t_nw)) {
			if (AIMarine.AreWaterTilesConnected(t_s, t_se) && AIMarine.AreWaterTilesConnected(t_s, t_sw)) {
				if (!AIMarine.AreWaterTilesConnected(t_w, t_nw) || !AIMarine.AreWaterTilesConnected(t_w, t_sw)) {
					return true;
				}
			} else if (AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne)) {
				if (!AIMarine.AreWaterTilesConnected(t_n, t_nw) || !AIMarine.AreWaterTilesConnected(t_n, t_ne)) {
					return true;
				}
			} else {
				return true;
			}
		}

		if (AIMarine.AreWaterTilesConnected(tile, t_ne) && AIMarine.AreWaterTilesConnected(tile, t_sw)) {
			if (AIMarine.AreWaterTilesConnected(t_e, t_se) && AIMarine.AreWaterTilesConnected(t_e, t_ne)) {
				if (!AIMarine.AreWaterTilesConnected(t_s, t_se) || !AIMarine.AreWaterTilesConnected(t_s, t_sw)) {
					return true;
				}
			} else if (AIMarine.AreWaterTilesConnected(t_n, t_nw) && AIMarine.AreWaterTilesConnected(t_n, t_ne)) {
				if (!AIMarine.AreWaterTilesConnected(t_w, t_nw) || !AIMarine.AreWaterTilesConnected(t_w, t_sw)) {
					return true;
				}
			} else {
				return true;
			}
		}

		return false;
	}

	function RemoveFailedRouteStation(inclined_dock_tile)
	{
		local counter = 0;
		do {
			if (!TestRemoveDock().TryRemove(inclined_dock_tile)) {
				++counter;
			} else {
//				AILog.Warning("this.m_dock_to == null; Removed dock tile at " + inclined_dock_tile);
				break;
			}
			AIController.Sleep(1);
		} while (counter < 500);

		if (counter == 500) {
			::scheduled_removals_table.Ship.rawset(inclined_dock_tile, 0);
//			AILog.Error("Failed to remove dock tile at " + inclined_dock_tile + " - " + AIError.GetLastErrorString());
		} else {
			local slope = AITile.GetSlope(inclined_dock_tile);
			assert(slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW);
			/* Check for canal and remove it */
			local offset = 0;
			if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
			if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
			if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
			if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
			local dock_tile = inclined_dock_tile + offset;
			if (AIMarine.IsCanalTile(dock_tile)) {
				local counter = 0;
				do {
					if (!TestRemoveCanal().TryRemove(dock_tile)) {
						++counter;
					} else {
//						AILog.Warning("this.m_dock_to == null; Removed canal tile at " + dock_tile);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduled_removals_table.Ship.rawset(dock_tile, 0);
//					AILog.Error("Failed to remove canal tile at " + dock_tile + " - " + AIError.GetLastErrorString());
				}
			}
			local ship_docking_tile = dock_tile + offset;
			if (AIMarine.IsCanalTile(ship_docking_tile) && !this.RemovingCanalBlocksConnection(ship_docking_tile)) {
				local counter = 0;
				do {
					if (!TestRemoveCanal().TryRemove(ship_docking_tile)) {
						++counter;
					} else {
//						AILog.Warning("this.m_dock_to == null; Removed canal tile at " + ship_docking_tile);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduled_removals_table.Ship.rawset(ship_docking_tile, 0);
//					AILog.Error("Failed to remove canal tile at " + ship_docking_tile + " - " + AIError.GetLastErrorString());
				}
			}
		}
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

		if (this.m_cargo_type == -1) {
			this.m_cargo_type = Utils.GetCargoType(cargo_class);
		}

		if (this.m_coverage_radius == -1) {
			this.m_coverage_radius = AIStation.GetCoverageRadius(AIStation.STATION_DOCK);
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

		if (this.m_pathfinder_tries == -1) {
			this.m_pathfinder_tries = 0;
		}

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_WATER);
		if (num_vehicles >= AIGameSettings.GetValue("max_ships") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_WATER)) {
			/* Don't terminate the route, or it may leave already built docks behind. */
			return 0;
		}

		if (this.m_dock_from == -1) {
			this.m_dock_from = this.BuildTownDock(this.m_city_from);
			if (this.m_dock_from == null) {
				this.SetRouteFinished();
				return null;
			}
		}

		if (this.m_dock_to == -1) {
			this.m_dock_to = this.BuildTownDock(this.m_city_to);
			if (this.m_dock_to == null) {
				this.RemoveFailedRouteStation(this.m_dock_from);
				this.SetRouteFinished();
				return null;
			}
		}

		if (this.m_depot_tile == -1) {
			/* Provide the docking tiles to the pathfinder */
			local ship_docking_tile_from = this.GetDockDockingTile(this.m_dock_from);
			local ship_docking_tile_to = this.GetDockDockingTile(this.m_dock_to);

			local canal_array = this.PathfindBuildCanal(ship_docking_tile_from, ship_docking_tile_to, this.m_pathfinder_instance);
			this.m_pathfinder_instance = canal_array[1];
			if (canal_array[0] == null && this.m_pathfinder_instance != null) {
				return 0;
			}
			this.m_depot_tile = this.BuildRouteShipDepot(canal_array[0]);
		}

		if (this.m_depot_tile == null) {
			this.RemoveFailedRouteStation(this.m_dock_from);
			this.RemoveFailedRouteStation(this.m_dock_to);
			this.SetRouteFinished();
			return null;
		}

		return ShipRoute(this.m_city_from, this.m_city_to, this.m_dock_from, this.m_dock_to, this.m_depot_tile, this.m_cargo_class, this.m_sent_to_depot_water_group);
	}

	function AreOtherDocksNearby(dock_rectangle)
	{
		/* check if there are other docks square_size squares nearby */
		local is_friendly = AIController.GetSetting("is_friendly");
		local square_size = is_friendly ? this.m_coverage_radius * 2 : 2;

		local dock_rectangle_expand = clone dock_rectangle;
		dock_rectangle_expand.Expand(square_size, square_size);

		local tile_list = AITileList();
		tile_list.AddRectangle(dock_rectangle_expand.tile_top, dock_rectangle_expand.tile_bot);

		foreach (tile, _ in tile_list) {
			if (AITile.IsStationTile(tile)) {
				if (AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					/* if another dock of mine is nearby return true */
					if (AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_DOCK)) {
						return true;
					}
				} else if (is_friendly) {
					return true;
				}
				/* don't care about enemy stations when is_friendly is off */
			}
		}

		return false;
	}

	function GetAdjacentNonDockStationID(dock_rectangle, spread_rectangle)
	{
		local tile_list = AITileList();
		tile_list.AddRectangle(spread_rectangle.tile_top, spread_rectangle.tile_bot);

		foreach (tile, _ in tile_list) {
			if (!AITile.IsStationTile(tile)) {
				tile_list[tile] = null;
				continue;
			}
			if (AITile.GetOwner(tile) != ::caches.m_my_company_id) {
				tile_list[tile] = null;
				continue;
			}
			local station_id = AIStation.GetStationID(tile);
			if (AIStation.HasStationType(station_id, AIStation.STATION_DOCK)) {
				tile_list[tile] = null;
				continue;
			}
			tile_list[tile] = station_id;
		}

		local station_list = AIList();
		station_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		foreach (tile, station_id in tile_list) {
			station_list[station_id] = dock_rectangle.DistanceManhattan(tile);
		}

		foreach (station_id, _ in station_list) {
			local station_tiles = AITileList_StationType(station_id, AIStation.STATION_ANY);
			foreach (tile, _ in station_tiles) {
				if (!spread_rectangle.Contains(tile)) {
					station_list[station_id] = null;
					break;
				}
			}
		}

		return station_list.IsEmpty() ? AIStation.STATION_NEW : station_list.Begin();
	}

	function BuildTownDock(town_id)
	{
		local tile_list = AITileList();

		/* build square around @town_id and find suitable tiles for docks */
		local rectangle_coordinates = Utils.EstimateTownRectangle(town_id);

		tile_list.AddRectangle(rectangle_coordinates[0], rectangle_coordinates[1]);

		local dock_stations = AIPriorityQueue();
		foreach (tile, _ in tile_list) {
			local dock_station = DockStation.IsDockBuildableTile(tile, !this.m_cheaper_route);
			if (!dock_station) {
				continue;
			}
			local top_tile = dock_station.GetTopTile();
			local x_length = dock_station.GetDockLengthX();
			local y_length = dock_station.GetDockLengthY();
			if (AITile.GetCargoAcceptance(top_tile, this.m_cargo_type, x_length, y_length, this.m_coverage_radius) < 8) {
				continue;
			}
			local dock_rectangle = OrthogonalTileArea(top_tile, x_length, y_length);
			if (this.AreOtherDocksNearby(dock_rectangle)) {
				continue;
			}
			local cargo_production = AITile.GetCargoProduction(top_tile, this.m_cargo_type, x_length, y_length, this.m_coverage_radius);
			local pick_mode = AIController.GetSetting("pick_mode");
			if (pick_mode != 1 && !this.m_best_routes_built && cargo_production < 8) {
				continue;
			}

			local town_location = AITown.GetLocation(town_id);
			local shortest_dist_town = dock_rectangle.DistanceManhattan(town_location);

			/* store as negative to make priority queue prioritize highest values */
			dock_stations.Insert(dock_station, -((cargo_production << 13) | (0x1FFF - shortest_dist_town)));
		}

		while (!dock_stations.IsEmpty()) {
			local dock_station = dock_stations.Pop();
			local top_tile = dock_station.GetTopTile();
			local x_length = dock_station.GetDockLengthX();
			local y_length = dock_station.GetDockLengthY();
			local dock_rectangle = OrthogonalTileArea(top_tile, x_length, y_length);
			local adjacent_station_id = AIStation.STATION_NEW;
			local spread_rad = AIGameSettings.GetValue("station_spread");
			if (spread_rad && AIGameSettings.GetValue("distant_join_stations")) {
				local remaining_x = spread_rad - x_length;
				local remaining_y = spread_rad - y_length;
				local spread_rectangle = clone dock_rectangle;
				spread_rectangle.Expand(remaining_x, remaining_y);
				adjacent_station_id = this.GetAdjacentNonDockStationID(dock_rectangle, spread_rectangle);
			}

			local inclined_dock_tile = dock_station.m_inclined_dock_tile;
			if (!dock_station.IsEqual(DockStation.IsDockBuildableTile(inclined_dock_tile, !this.m_cheaper_route))) {
				continue;
			}

			local dock_tile = dock_station.m_dock_tile;
			local ship_docking_tile = dock_station.m_ship_docking_tile;
			local slope = dock_station.m_slope_dir;
			local offset = (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SW) ? AIMap.GetTileIndex(0, 1) : AIMap.GetTileIndex(1, 0);

			local dock_tile_south = dock_tile + offset;
			local dock_tile_north = dock_tile - offset;
			local ship_docking_tile_south = ship_docking_tile + offset;
			local ship_docking_tile_north = ship_docking_tile - offset;

//			AILog.Info("inclined_dock_tile = " + inclined_dock_tile + "; dock_tile = " + dock_tile + "; ship_docking_tile = " + ship_docking_tile + "; dock_tile_south = " + dock_tile_south + "; dock_tile_north = " + dock_tile_north + "; ship_docking_tile_south = " + ship_docking_tile_south + "; ship_docking_tile_north = " + ship_docking_tile_north);

			local built_dock_tile_canal = false;
			if (!AITile.IsWaterTile(dock_tile)) {
				if (this.m_cheaper_route) {
					continue;
				}

				local counter = 0;
				do {
					if (!TestBuildCanal().TryBuild(dock_tile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
						++counter;
					} else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					/* Failed to build first canal. Try the next location. */
					continue;
				} else {
					/* The first canal was successfully built. */
					built_dock_tile_canal = true;
				}
			}

			local built_ship_docking_tile_canal = false;
			if (!AITile.IsWaterTile(ship_docking_tile)) {
				if (this.m_cheaper_route) {
					continue;
				}

				local counter = 0;
				do {
					if (!TestBuildCanal().TryBuild(ship_docking_tile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
						++counter;
					} else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					/* Failed to build second canal. Remove the first canal if it was built then. */
					if (built_dock_tile_canal) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(dock_tile)) {
								++counter;
							} else {
//								AILog.Warning("Removed canal tile at " + dock_tile);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);

						if (counter == 500) {
							::scheduled_removals_table.Ship.rawset(dock_tile, 0);
//							AILog.Error("Failed to remove canal tile at " + dock_tile + " - " + AIError.GetLastErrorString());
							continue;
						} else {
							/* The first canal was successfully removed after failing to build the second canal. Try it all over again in the next location */
							continue;
						}
					}
				} else {
					/* The second canal was successfully built. */
					built_ship_docking_tile_canal = true;
				}
			}

			local blocking = false;
			if ((AIMarine.IsLockTile(dock_tile_south) && AITile.GetSlope(dock_tile_south) == AITile.SLOPE_FLAT && this.CheckLockDirection(dock_tile_south, this.GetLockMiddleTile(dock_tile_south))) ||
					(AIMarine.IsLockTile(dock_tile_north) && AITile.GetSlope(dock_tile_north) == AITile.SLOPE_FLAT && this.CheckLockDirection(dock_tile_north, this.GetLockMiddleTile(dock_tile_north)))) {
				blocking = true;
			}

			if (!blocking && ((AIMarine.IsDockTile(dock_tile_south) && this.GetDockDockingTile(dock_tile_south) == dock_tile) ||
					(AIMarine.IsDockTile(dock_tile_north) && this.GetDockDockingTile(dock_tile_north) == dock_tile))) {
				blocking = true;
			}

			if (!blocking && (AIMarine.AreWaterTilesConnected(dock_tile, dock_tile_south) && AIMarine.AreWaterTilesConnected(dock_tile, ship_docking_tile))) {
				if (!AIMarine.AreWaterTilesConnected(ship_docking_tile_south, dock_tile_south) || !AIMarine.AreWaterTilesConnected(ship_docking_tile_south, ship_docking_tile)) {
					blocking = true;
				}
			}

			if (!blocking && (AIMarine.AreWaterTilesConnected(dock_tile, dock_tile_north) && AIMarine.AreWaterTilesConnected(dock_tile, ship_docking_tile))) {
				if (!AIMarine.AreWaterTilesConnected(ship_docking_tile_north, dock_tile_north) || !AIMarine.AreWaterTilesConnected(ship_docking_tile_north, ship_docking_tile)) {
					blocking = true;
				}
			}

			if (!blocking) {
				local counter = 0;
				do {
					if (!TestBuildDock().TryBuild(inclined_dock_tile, adjacent_station_id)) {
						++counter;
					} else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 1);

				if (counter == 1) {
					if (built_dock_tile_canal) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(dock_tile)) {
								++counter;
							} else {
//								AILog.Warning("Removed canal tile at " + dock_tile);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);

						if (counter == 500) {
							::scheduled_removals_table.Ship.rawset(dock_tile, 0);
//							AILog.Error("Failed to remove canal tile at " + dock_tile + " - " + AIError.GetLastErrorString());
//						} else {
//							/* The first canal was successfully removed after failing to build the dock. Try it all over again in the next location */
						}
					}

					if (built_ship_docking_tile_canal) {
						local counter = 0;
						do {
							if (!TestRemoveCanal().TryRemove(ship_docking_tile)) {
								++counter;
							} else {
//								AILog.Warning("Removed canal tile at " + ship_docking_tile);
								break;
							}
							AIController.Sleep(1);
						} while (counter < 500);

						if (counter == 500) {
							::scheduled_removals_table.Ship.rawset(ship_docking_tile, 0);
//							AILog.Error("Failed to remove canal tile at " + ship_docking_tile + " - " + AIError.GetLastErrorString());
//						} else {
//							/* The second canal was successfully removed after failing to build the dock. Try it all over again in the next location */
						}
					}
					continue;
				} else {
					AILog.Info("Dock built in " + AITown.GetName(town_id) + " at tile " + inclined_dock_tile + "!");
					return inclined_dock_tile;
				}
			}

			if (blocking) {
				if (built_dock_tile_canal) {
					local counter = 0;
					do {
						if (!TestRemoveCanal().TryRemove(dock_tile)) {
							++counter;
						} else {
//							AILog.Warning("Removed canal tile at " + dock_tile);
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);

					if (counter == 500) {
						::scheduled_removals_table.Ship.rawset(dock_tile, 0);
//						AILog.Error("Failed to remove canal tile at " + dock_tile + " - " + AIError.GetLastErrorString());
//					} else {
//						/* The first canal was successfully removed after detecting a block. Try it all over again in the next location */
					}
				}

				if (built_ship_docking_tile_canal) {
					local counter = 0;
					do {
						if (!TestRemoveCanal().TryRemove(ship_docking_tile)) {
							++counter;
						} else {
//							AILog.Warning("Removed canal tile at " + ship_docking_tile);
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);

					if (counter == 500) {
						::scheduled_removals_table.Ship.rawset(ship_docking_tile, 0);
//						AILog.Error("Failed to remove canal tile at " + ship_docking_tile + " - " + AIError.GetLastErrorString());
//					} else {
//						/* The second canal was successfully removed after detecting a block. Try it all over again in the next location */
					}
				}

				continue;
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

	/* find canal way between from_tile and to_tile */
	function PathfindBuildCanal(from_tile, to_tile, pathfinder_instance, cost_so_far = 0)
	{
		if (from_tile != to_tile) {
			if (this.m_max_pathfinder_tries == -1) {
				this.m_max_pathfinder_tries = 333 * this.m_route_dist;
			}

			/* Print the names of the towns we'll try to connect. */
			AILog.Info("s:Connecting " + this.m_city_from_name + " (tile " + from_tile + ") and " + this.m_city_to_name + " (tile " + to_tile + ") (iteration " + (this.m_pathfinder_tries + 1) + "/" + this.m_max_pathfinder_tries + ")");

			if (pathfinder_instance == null) {
				/* Create an instance of the pathfinder. */
				pathfinder_instance = Canal();

				AILog.Info("canal pathfinder: default");
/*defaults*/
/*10000000*/	pathfinder_instance.cost.max_cost;
/*100*/			pathfinder_instance.cost.tile;
/*200*/			pathfinder_instance.cost.no_existing_water = this.m_cheaper_route ? pathfinder_instance.cost.max_cost : 100;
/*70*/			pathfinder_instance.cost.diagonal_tile;
/*100*/			pathfinder_instance.cost.turn45;
/*600*/			pathfinder_instance.cost.turn90;
/*400*/			pathfinder_instance.cost.aqueduct_per_tile;
/*925*/			pathfinder_instance.cost.lock;
/*150*/			pathfinder_instance.cost.depot;
/*6*/			pathfinder_instance.cost.max_aqueduct_length = AIGameSettings.GetValue("infinite_money") ? AIGameSettings.GetValue("max_bridge_length") + 2 : pathfinder_instance.cost.max_aqueduct_length;
/*1*/			pathfinder_instance.cost.estimate_multiplier = 1.0 + this.m_route_dist / 333.3;
/*0*/			pathfinder_instance.cost.search_range = max(33, this.m_route_dist / 10);

				/* Give the source and goal tiles to the pathfinder. */
				pathfinder_instance.InitializePath([from_tile], [to_tile]);
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
//							AILog.Info("canal pathfinder: FindPath iterated: " + count);
//							local sign_list = AISignList();
//							foreach (sign, _ in sign_list) {
//								if (sign_list.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder_instance];
						}
					} else {
						/* Timed out */
						AILog.Error("canal pathfinder: FindPath return false (timed out)");
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					AILog.Error("canal pathfinder: FindPath return null (no path)");
					return [null, null];
				}
			} while (path == false);

//			if (this.m_pathfinder_tries != count) AILog.Info("canal pathfinder: FindPath iterated: " + count);
			AILog.Info("Canal path found! FindPath iterated: " + this.m_pathfinder_tries + ". Building canal... ");
			AILog.Info("canal pathfinder: FindPath cost: " + path.GetCost());
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
//										AILog.Info("Built lock at " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
										break;
									} else {
										if (Canal()._LockBlocksConnection(par.GetTile(), next_tile)) {
											if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
												AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - LockBlocksConnection = true - Retrying...");
												return this.PathfindBuildCanal(from_tile, last_node, null, canal_cost);
											}
										} else if (AIMarine.IsLockTile(next_tile) && this.GetLockMiddleTile(next_tile) == next_tile &&
												AIMarine.IsLockTile(path.GetTile()) && this.GetOtherLockEnd(path.GetTile()) == par.GetTile()) {
//											AILog.Warning("We found a lock already built at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
											built_last_node = false;
											break;
										} else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
												AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - LockBlocksConnection = true - Retrying...");
												return this.PathfindBuildCanal(from_tile, last_node, null, canal_cost);
											}
										}
										++counter;
//										AILog.Warning("Failed lock at " + path.GetTile() + ", " + next_tile + " and " + par.GetTile());
									}
									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									AILog.Warning("Couldn't build lock at tiles " + path.GetTile() + ", " + next_tile + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
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
//										AILog.Info("Built aqueduct at " + par.GetTile() + " and " + path.GetTile());
										break;
									} else {
										if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT") {
//											AILog.Warning("We found an aqueduct already built between tiles " + par.GetTile() + " and " + path.GetTile());
											built_last_node = false;
											break;
										} else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG") {
											if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
												AILog.Warning("Couldn't build aqueduct between tiles " + par.GetTile() + " and " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return this.PathfindBuildCanal(from_tile, last_node, null, canal_cost);
											}
										}
										++counter;
//										AILog.Warning("Failed aqueduct at " + par.GetTile() + " and " + path.GetTile());
									}
									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									AILog.Warning("Couldn't build aqueduct between tiles " + par.GetTile() + " and " + path.GetTile() + " - " + AIError.GetLastErrorString());
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
						if (!AITile.HasTransportType(path.GetTile(), AITile.TRANSPORT_WATER) || (last_node != null && AIMap.DistanceManhattan(last_node, path.GetTile()) == 1 && !this.CheckAqueductSlopes(last_node, path.GetTile()) && !AIMarine.AreWaterTilesConnected(last_node, path.GetTile()))) {
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (TestBuildCanal().TryBuild(path.GetTile())) {
									canal_cost += costs.GetCosts();
									built_last_node = true;
//									AILog.Info("Built canal 'path' at " + path.GetTile());
									break;
								} else {
									if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_FLAT_LAND_REQUIRED" || AIMarine.IsWaterDepotTile(path.GetTile()) || AIMarine.IsLockTile(path.GetTile()) || AIMarine.IsDockTile(path.GetTile()) || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_LOCAL_AUTHORITY_REFUSES") {
										if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && last_node != null) {
											AILog.Warning("Couldn't build canal 'path' at tile " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
											return this.PathfindBuildCanal(from_tile, last_node, null, canal_cost);
										}
									} else if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT" && AIMarine.IsCanalTile(path.GetTile())) {
//										AILog.Warning("We found a canal already built at tile " + path.GetTile());
										built_last_node = false;
										break;
									}
									++counter;
//									AILog.Warning("Failed canal 'path' at " + path.GetTile());
								}
								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								AILog.Warning("Couldn't build canal 'path' at tile " + path.GetTile() + " - " + AIError.GetLastErrorString());
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
			AILog.Info("Canal built! Actual cost for building canal: " + canal_cost);
		}

		return [this.m_built_tiles, null];
	}

	function BuildingShipDepotBlocksConnection(top_tile, bot_tile)
	{
		assert(AIMap.DistanceManhattan(top_tile, bot_tile) == 1);

		local offset = AIMap.GetTileX(top_tile) == AIMap.GetTileX(bot_tile) ? AIMap.GetTileIndex(1, 0) : AIMap.GetTileIndex(0, 1);

		local top_exit = 2 * top_tile - bot_tile;
		local bot_exit = 2 * bot_tile - top_tile;
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

	function BuildRouteShipDepot(canal_array)
	{
		if (canal_array == null) {
			return null;
		}

		local depot_tile = null;

		local depot_rectangles = AIPriorityQueue();

		for (local i = 0; i < canal_array.len() - 1; ++i) {
			local tile_top = canal_array[i].m_tile;
			local tile_bot = canal_array[i + 1].m_tile;
			if (canal_array[i].m_type != WaterTileType.CANAL) {
				continue;
			}
			if (canal_array[i + 1].m_type != WaterTileType.CANAL) {
				continue;
			}
			if (AIMap.DistanceManhattan(tile_top, tile_bot) != 1) {
				continue;
			}

			local depot_rectangle = OrthogonalTileArea.CreateArea(tile_top, tile_bot);
			local distance = depot_rectangle.DistanceManhattan(canal_array[canal_array.len() / 2].m_tile);
			depot_rectangles.Insert(depot_rectangle, distance);
//			AILog.Info("Added " + depot_rectangle.tile_top + " and " + depot_rectangle.tile_bot);
		}

		while (!depot_rectangles.IsEmpty()) {
			local depot_rectangle = depot_rectangles.Pop();
			local tile_top = depot_rectangle.tile_top;
			local tile_bot = depot_rectangle.tile_bot;
//			AILog.Info("Extracted " + tile_top + " and " + tile_bot);
			if (!this.BuildingShipDepotBlocksConnection(tile_top, tile_bot)) {
				local counter = 0;
				do {
					if (!TestBuildWaterDepot().TryBuild(tile_top, tile_bot)) {
						++counter;
					} else {
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
