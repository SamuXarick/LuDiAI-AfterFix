require("DoubleRailPathfinder.nut");
require("SingleRailPathfinder.nut");

enum RailStationDir
{
	NE,
	SW,
	NW,
	SE
};

class RailStation
{
	m_tile = null;
	m_dir = null;
	m_num_plat = null;
	m_length = null;

	m_width = null;
	m_height = null;

	constructor(tile, dir, num_plat, length)
	{
		this.m_tile = tile;
		this.m_dir = dir;
		this.m_num_plat = num_plat;
		this.m_length = length;

		this.m_width = (dir == RailStationDir.NE || dir == RailStationDir.SW) ? length : num_plat;
		this.m_height = (dir == RailStationDir.NE || dir == RailStationDir.SW) ? num_plat : length;
	}

	function GetValidRectangle(extra_range)
	{
		if (extra_range == 0) return [this.GetTopTile(), this.m_width, this.m_height];

		local rail_station_tiles = AITileList();
		rail_station_tiles.AddRectangle(this.GetTopTile(), this.GetBottomTile());

		local offset_x;
		local offset_y;
		switch (this.m_dir) {
			case RailStationDir.NE:
				offset_x = -1;
				offset_y = 0;
				break;

			case RailStationDir.SW:
				offset_x = 1;
				offset_y = 0;
				break;

			case RailStationDir.NW:
				offset_x = 0;
				offset_y = -1;
				break;

			case RailStationDir.SE:
				offset_x = 0;
				offset_y = 1;
				break;
		}

		local new_top_tile = this.GetTopTile();
		foreach (platform in [1, this.m_num_plat]) {
			local entry_tile = this.GetEntryTile(platform);
			local entry_tile_x = AIMap.GetTileX(entry_tile);
			local entry_tile_y = AIMap.GetTileY(entry_tile);
			local tile_x = entry_tile_x + offset_x * extra_range;
			local tile_y = entry_tile_y + offset_y * extra_range;

			local tile = AIMap.GetTileIndex(tile_x, tile_y);
			if (!AIMap.IsValidTile(tile)) return null;

			if (tile < new_top_tile) {
				new_top_tile = tile;
			}
		}

		local new_width = (this.m_dir == RailStationDir.NE || this.m_dir == RailStationDir.SW) ? this.m_length + extra_range : this.m_num_plat;
		local new_height = (this.m_dir == RailStationDir.NE || this.m_dir == RailStationDir.SW) ? this.m_num_plat : this.m_length + extra_range;
		return [new_top_tile, new_width, new_height];
	}

	function GetExitTile(platform, extra_range = 0)
	{
		switch (this.m_dir) {
			case RailStationDir.NE:
				return this.m_tile + AIMap.GetMapSizeX() * (platform - 1) - 1 - extra_range;

			case RailStationDir.SW:
				return this.m_tile + AIMap.GetMapSizeX() * (platform - 1) + this.m_length + extra_range;

			case RailStationDir.NW:
				return this.m_tile + (platform - 1) - AIMap.GetMapSizeX() - extra_range * AIMap.GetMapSizeX();

			case RailStationDir.SE:
				return this.m_tile + (platform - 1) + this.m_length * AIMap.GetMapSizeX() + extra_range * AIMap.GetMapSizeX();
		}
	}

	function GetEntryTile(platform)
	{
		switch (this.m_dir) {
			case RailStationDir.NE:
				return this.m_tile + AIMap.GetMapSizeX() * (platform - 1);

			case RailStationDir.SW:
				return this.m_tile + AIMap.GetMapSizeX() * (platform - 1) + this.m_length - 1;

			case RailStationDir.NW:
				return this.m_tile + (platform - 1);

			case RailStationDir.SE:
				return this.m_tile + (platform - 1) + (this.m_length - 1) * AIMap.GetMapSizeX();
		}
	}

	function GetTrackDirection()
	{
		switch (this.m_dir) {
			case RailStationDir.NE:
			case RailStationDir.SW:
				return AIRail.RAILTRACK_NE_SW;

			case RailStationDir.NW:
			case RailStationDir.SE:
				return AIRail.RAILTRACK_NW_SE;
		}
	}

	function GetTopTile()
	{
		return this.m_tile;
	}

	function GetBottomTile()
	{
		switch (this.m_dir) {
			case RailStationDir.NE:
			case RailStationDir.SW:
				return this.m_tile + AIMap.GetMapSizeX() * (this.m_num_plat - 1) + this.m_length - 1;

			case RailStationDir.NW:
			case RailStationDir.SE:
				return this.m_tile + (this.m_num_plat - 1) + (this.m_length - 1) * AIMap.GetMapSizeX();
		}
	}

	function CreateFromTile(tile, dir = null)
	{
		assert(AIRail.IsRailStationTile(tile));
		assert(dir == null || dir == RailStationDir.NE || dir == RailStationDir.SW || dir = RailStationDir.NW || dir = RailStationDir.SE);

		local rail_station_tiles = AITileList_StationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN);
		rail_station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
		local top_tile = rail_station_tiles.Begin();
		rail_station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_DESCENDING);
		local bot_tile = rail_station_tiles.Begin();
		local rail_track = AIRail.GetRailStationDirection(top_tile);
		local length = rail_track == AIRail.RAILTRACK_NE_SW ? AIMap.GetTileX(bot_tile) - AIMap.GetTileX(top_tile) + 1 : AIMap.GetTileY(bot_tile) - AIMap.GetTileY(top_tile) + 1;
		local num_platforms = rail_track == AIRail.RAILTRACK_NE_SW ? AIMap.GetTileY(bot_tile) - AIMap.GetTileY(top_tile) + 1 : AIMap.GetTileX(bot_tile) - AIMap.GetTileX(top_tile) + 1;

		if (dir == null) {
			/* Try to guess direction based on the rail tracks at the exit */
			switch (rail_track) {
				case AIRail.RAILTRACK_NE_SW: {
					local exit_tile_NE_1 = top_tile - 1;
					local exit_tile_SW_1 = top_tile + length;
					if (AIRail.IsRailTile(exit_tile_NE_1) && AITile.GetOwner(exit_tile_NE_1) == ::caches.m_my_company_id) {
						local tracks = AIRail.GetRailTracks(exit_tile_NE_1);
						if ((tracks & AIRail.RAILTRACK_NE_SW) != 0) {
							dir = RailStationDir.NE;
							break;
						}
					} else if (AIRail.IsRailTile(exit_tile_SW_1) && AITile.GetOwner(exit_tile_SW_1) == ::caches.m_my_company_id) {
						local tracks = AIRail.GetRailTracks(exit_tile_SW_1);
						if ((tracks & AIRail.RAILTRACK_NE_SW) != 0) {
							dir = RailStationDir.SW;
							break;
						}
					}
					break;
				}

				case AIRail.RAILTRACK_NW_SE: {
					local exit_tile_NW_1 = top_tile - AIMap.GetMapSizeX();
					local exit_tile_SE_1 = top_tile + length * AIMap.GetMapSizeX();
					if (AIRail.IsRailTile(exit_tile_NW_1) && AITile.GetOwner(exit_tile_NW_1) == ::caches.m_my_company_id) {
						local tracks = AIRail.GetRailTracks(exit_tile_NW_1);
						if ((tracks & AIRail.RAILTRACK_NW_SE) != 0) {
							dir = RailStationDir.NW;
							break;
						}
					} else if (AIRail.IsRailTile(exit_tile_SE_1) && AITile.GetOwner(exit_tile_SE_1) == ::caches.m_my_company_id) {
						local tracks = AIRail.GetRailTracks(exit_tile_SE_1);
						if ((tracks & AIRail.RAILTRACK_NW_SE) != 0) {
							dir = RailStationDir.SE;
							break;
						}
					}
					break;
				}
			}
		}
		assert(dir != null); // Could not guess station direction
		return RailStation(top_tile, dir, num_platforms, length);
	}

	function GetPlatformLine(num)
	{
		assert(num == 1 || num == 2);

		switch (this.m_dir) {
			case RailStationDir.NE:
			case RailStationDir.SE:
				return num == 1 ? 1 : 2;

			case RailStationDir.NW:
			case RailStationDir.SW:
				return num == 1 ? 2 : 1;
		}
	}
};

class RailStationPlatforms
{
	m_from1 = null;
	m_to1 = null;
	m_from2 = null;
	m_to2 = null;

	constructor(station_from, station_to)
	{
		if (typeof(station_to) == "bool") {
			switch (station_from.m_dir) {
				case RailStationDir.NE:
				case RailStationDir.SE: {
					switch (station_to) {
						case false:
							this.m_from1 = 1;
							this.m_from2 = 2;
							break;

						case true:
							this.m_from1 = 2;
							this.m_from2 = 1;
							break;
					}
					break;
				}
				case RailStationDir.NW:
				case RailStationDir.SW: {
					switch (station_to) {
						case false:
							this.m_from1 = 2;
							this.m_from2 = 1;
							break;

						case true:
							this.m_from1 = 1;
							this.m_from2 = 2;
							break;
					}
					break;
				}
			}
		} else if (typeof(station_to) == "instance") {
			switch (station_from.m_dir) {
				case RailStationDir.NE:
					switch (station_to.m_dir) {
						case RailStationDir.NE:
							this.m_from1 = 1;
							this.m_to1 = 2;
							this.m_from2 = 2;
							this.m_to2 = 1;
							break;

						case RailStationDir.NW:
							this.m_from1 = 1;
							this.m_to1 = 1;
							this.m_from2 = 2;
							this.m_to2 = 2;
							break;

						case RailStationDir.SE:
							this.m_from1 = 1;
							this.m_to1 = 2;
							this.m_from2 = 2;
							this.m_to2 = 1;
							break;

						case RailStationDir.SW:
							this.m_from1 = 1;
							this.m_to1 = 1;
							this.m_from2 = 2;
							this.m_to2 = 2;
							break;
					}
					break;

				case RailStationDir.NW:
					switch (station_to.m_dir) {
						case RailStationDir.NE:
							this.m_from1 = 2;
							this.m_to1 = 2;
							this.m_from2 = 1;
							this.m_to2 = 1;
							break;

						case RailStationDir.NW:
							this.m_from1 = 2;
							this.m_to1 = 1;
							this.m_from2 = 1;
							this.m_to2 = 2;
							break;

						case RailStationDir.SE:
							this.m_from1 = 2;
							this.m_to1 = 2;
							this.m_from2 = 1;
							this.m_to2 = 1;
							break;

						case RailStationDir.SW:
							this.m_from1 = 2;
							this.m_to1 = 1;
							this.m_from2 = 1;
							this.m_to2 = 2;
							break;
					}
					break;

				case RailStationDir.SE:
					switch (station_to.m_dir) {
						case RailStationDir.NE:
							this.m_from1 = 1;
							this.m_to1 = 2;
							this.m_from2 = 2;
							this.m_to2 = 1;
							break;

						case RailStationDir.NW:
							this.m_from1 = 1;
							this.m_to1 = 1;
							this.m_from2 = 2;
							this.m_to2 = 2;
							break;

						case RailStationDir.SE:
							this.m_from1 = 1;
							this.m_to1 = 2;
							this.m_from2 = 2;
							this.m_to2 = 1;
							break;

						case RailStationDir.SW:
							this.m_from1 = 1;
							this.m_to1 = 1;
							this.m_from2 = 2;
							this.m_to2 = 2;
							break;
					}
					break;

				case RailStationDir.SW:
					switch (station_to.m_dir) {
						case RailStationDir.NE:
							this.m_from1 = 2;
							this.m_to1 = 2;
							this.m_from2 = 1;
							this.m_to2 = 1;
							break;

						case RailStationDir.NW:
							this.m_from1 = 2;
							this.m_to1 = 1;
							this.m_from2 = 1;
							this.m_to2 = 2;
							break;

						case RailStationDir.SE:
							this.m_from1 = 2;
							this.m_to1 = 2;
							this.m_from2 = 1;
							this.m_to2 = 1;
							break;

						case RailStationDir.SW:
							this.m_from1 = 2;
							this.m_to1 = 1;
							this.m_from2 = 1;
							this.m_to2 = 2;
							break;
					}
					break;
			}
		}
	}
};

class RailStructType {
	RAIL = 0;
	TUNNEL = 1;
	BRIDGE = 2;
	STATION = 3;
	DEPOT = 4;
};

class RailStruct {
	m_tile = null;
	m_struct = null;
	m_rail_type = null;
	m_tile2 = null;
	m_tile3 = null;

	constructor(tile, struct, rail_type = -1, tile2 = -1, tile3 = -1) {
		this.m_tile = tile;
		this.m_struct = struct;
		this.m_rail_type = rail_type;
		this.m_tile2 = tile2;
		this.m_tile3 = tile3;
	}

	function SetRail(tile, rail_type, tile2, tile3)
	{
		return {
			m_tile = tile,
			m_struct = RailStructType.RAIL,
			m_rail_type = rail_type,
			m_tile2 = tile2,
			m_tile3 = tile3,
		};
	}

	function SetStruct(tile, struct, rail_type, tile2 = -1)
	{
		assert(struct != RailStructType.RAIL);
		assert(struct == RailStructType.DEPOT || tile2 != -1);

		return {
			m_tile = tile,
			m_struct = struct,
			m_rail_type = rail_type,
			m_tile2 = tile2,
		};
	}
};

class RailBuildManager
{
	/* These are saved */
	m_city_from = -1;
	m_city_to = -1;
	m_station_from = -1;
	m_station_to = -1;
	m_depot_tile_from = -1;
	m_depot_tile_to = -1;
	m_bridge_tiles = null;
	m_cargo_class = -1;
	m_rail_type = -1;
	m_best_routes_built = null;
	m_station_from_dir = -1;
	m_station_to_dir = -1;
	m_built_tiles = null;
	m_pathfinder_profile = -1;
	m_built_ways = -1;

	/* These are not saved */
	m_pathfinder_instance = null;
	m_pathfinder_tries = -1;
	m_sent_to_depot_rail_group = null;
	m_coverage_radius = -1;
	m_cargo_type = -1;
	m_route_dist = -1;
	m_city_from_name = null;
	m_city_to_name = null;
	m_max_pathfinder_tries = -1;
	m_num_signals = -1;

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
		this.m_depot_tile_from = -1;
		this.m_depot_tile_to = -1;
		this.m_bridge_tiles = null;
		this.m_cargo_class = -1;
		this.m_rail_type = -1;
		this.m_best_routes_built = null;
		this.m_station_from_dir = -1;
		this.m_station_to_dir = -1;
		this.m_built_tiles = null;
		this.m_pathfinder_profile = -1;
		this.m_built_ways = -1;

		this.m_pathfinder_instance = null;
		this.m_pathfinder_tries = -1;
		this.m_sent_to_depot_rail_group = null;
		this.m_coverage_radius = -1;
		this.m_cargo_type = -1;
		this.m_route_dist = -1;
		this.m_city_from_name = null;
		this.m_city_to_name = null;
		this.m_max_pathfinder_tries = -1;
		this.m_num_signals = -1;
	}

	function RemoveFailedRouteStation(station_tile, station_dir, depot_tile = null)
	{
		if (station_tile != null) {
			local rail_station = RailStation.CreateFromTile(station_tile, station_dir);
			local top_tile = rail_station.GetTopTile();
			local bot_tile = rail_station.GetBottomTile();
			local entry_tile_2 = rail_station.GetEntryTile(2);
			local exit_tile_2 = rail_station.GetExitTile(2);
			local exit_tile_1 = rail_station.GetExitTile(1);
			local entry_tile_1 = rail_station.GetEntryTile(1);
			local exit_tile_1_1 = 2 * exit_tile_1 - entry_tile_1;
			local exit_tile_2_1 = 2 * exit_tile_2 - entry_tile_2;

			local counter = 0;
			do {
				if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
					++counter;
				} else {
//					AILog.Warning("Removed railway station tile at " + station_tile + " from tile " + top_tile + " to tile " + bot_tile);
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);

			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
//				AILog.Error("Failed to remove railway station tile at " + station_tile + " from tile " + top_tile + " to tile " + bot_tile " - " + AIError.GetLastErrorString());
			}

			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, exit_tile_1_1)) {
					++counter;
				} else {
//					AILog.Warning("Removed rail track crossing from platform 2 to 1 at tile " + exit_tile_2);
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);

			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, exit_tile_1_1));
//				AILog.Error("Failed to remove rail track crossing from platform 2 to 1 at tile " + exit_tile_2);
			}

			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, exit_tile_2_1)) {
					++counter;
				} else {
//					AILog.Warning("Removed rail track crossing from platform 1 to 2 at tile " + rail_station.GetExitTile(1));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);

			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, exit_tile_2_1));
//				AILog.Error("Failed to remove rail track crossing from platform 1 to 2 at tile " + rail_station.GetExitTile(1));
			}

			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, exit_tile_2_1)) {
					++counter;
				} else {
//					AILog.Warning("Removed rail track in front of platform 2 at tile " + exit_tile_2);
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);

			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, exit_tile_2_1));
//				AILog.Error("Failed to remove rail track in front of platform 2 at tile " + exit_tile_2);
			}

			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, exit_tile_1_1)) {
					++counter;
				} else {
//					AILog.Warning("Removed rail track in front of platform 1 at tile " + rail_station.GetExitTile(1));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);

			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, exit_tile_1_1));
//				AILog.Error("Failed to remove rail track in front of platform 1 at tile " + rail_station.GetExitTile(1));
			}

			if (depot_tile != null) {
				local depot_front_tile = AIRail.GetRailDepotFrontTile(depot_tile);
				local depot_rail_a = abs(depot_tile - depot_front_tile) == 1 ? depot_front_tile - AIMap.GetMapSizeX() : depot_front_tile - 1;
				local depot_rail_b = 2 * depot_front_tile - depot_rail_a;
				local depot_rail_c = 2 * depot_front_tile - depot_tile;

				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot_tile, depot_front_tile, depot_rail_a)) {
						++counter;
					} else {
//						AILog.Warning("Removed rail track in front of depot towards the station at tile " + depot_front_tile);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduled_removals_table.Train.append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_a));
//					AILog.Error("Failed to remove rail track in front of depot towards the station at tile " + depot_front_tile);
				}

				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot_tile, depot_front_tile, depot_rail_b)) {
						++counter;
					} else {
//						AILog.Warning("Removed rail track in front of depot towards the railroad at tile " + depot_front_tile);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduled_removals_table.Train.append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_b));
//					AILog.Error("Failed to remove rail track in front of depot towards the railroad at tile " + depot_front_tile);
				}

				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot_tile, depot_front_tile, depot_rail_c)) {
						++counter;
					} else {
//						AILog.Warning("Removed rail track in front of depot accross the lines at tile " + depot_front_tile);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduled_removals_table.Train.append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_c));
//					AILog.Error("Failed to remove rail track in front of depot towards accross the lines at tile " + depot_front_tile);
				}

				local counter = 0;
				do {
					if (!TestDemolishTile().TryDemolish(depot_tile)) {
						++counter;
					} else {
//						AILog.Warning("Removed rail depot at tile " + depot_tile);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);

				if (counter == 500) {
					::scheduled_removals_table.Train.append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
//					AILog.Error("Failed to remove rail depot at tile " + depot_tile);
				}
			}
		}
	}

	function RemoveFailedRouteTracks(line = null)
	{
		assert(line == null || line == 0 || line == 1);

		local lines = line == null ? [0, 1] : [line];
		foreach (j in lines) {
			while (this.m_built_tiles[j].len() != 0) {
				local i = this.m_built_tiles[j].pop();
				local tile = i.m_tile;
				local struct = i.m_struct;
				local rail_type = i.m_rail_type;
				AIRail.SetCurrentRailType(rail_type);
				if (struct == RailStructType.RAIL) {
					if (AIRail.IsRailTile(tile)) {
						local tile_from = i.m_tile2;
						local tile_to = i.m_tile3;
						if (!TestRemoveRail().TryRemove(tile_from, tile, tile_to)) {
//							AILog.Info("Failed to remove rail at tile " + tile + ", connecting " + tile_from + " to " + tile_to + ".");
							::scheduled_removals_table.Train.append(RailStruct.SetRail(tile, rail_type, tile_from, tile_to));
						}
//					} else {
//						AILog.Info("No rail tile found to remove at tile " + tile + ", connecting " + tile_from + " to " + tile_to + ".");
					}
				} else if (struct == RailStructType.BRIDGE) {
					local tile2 = i.m_tile2;
					if (AIBridge.IsBridgeTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) && AIBridge.GetOtherBridgeEnd(tile) == tile2) {
						if (!TestRemoveBridge().TryRemove(tile)) {
//							AILog.Info("Failed to demolish bridge at tiles " + tile + " and " + tile2 + ".");
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(tile, RailStructType.BRIDGE, rail_type, tile2));
						}
//					} else {
//						AILog.Info("No bridge found to demolish at tiles " + tile + " and " + tile2 + ".");
					}
				} else if (struct == RailStructType.TUNNEL) {
					local tile2 = i.m_tile2;
					if (AITunnel.IsTunnelTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) && AITunnel.GetOtherTunnelEnd(tile) == tile2) {
						if (!TestRemoveTunnel().TryRemove(tile)) {
//							AILog.Info("Failed to demolish tunnel at tiles " + tile + " and " + tile2 + ".");
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(tile, RailStructType.TUNNEL, rail_type, tile2));
						}
//					} else {
//						AILog.Info("No tunnel found to demolish at tiles " + tile + " and " + tile2 + ".");
					}
				}
			}
		}
	}

	function BuildRailRoute(city_from, city_to, cargo_class, sent_to_depot_rail_group, best_routes_built, rail_type)
	{
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_cargo_class = cargo_class;
		this.m_sent_to_depot_rail_group = sent_to_depot_rail_group;
		this.m_best_routes_built = best_routes_built;
		this.m_rail_type = rail_type;

		if (this.m_built_ways == -1) {
			this.m_built_ways = 0;
		}

		if (this.m_pathfinder_profile == -1) {
			this.m_pathfinder_profile = AIController.GetSetting("rail_pf_profile");
		}

		if (this.m_bridge_tiles == null) {
			this.m_bridge_tiles = [];
		}

		if (this.m_pathfinder_tries == -1) {
			this.m_pathfinder_tries = 0;
		}

		if (this.m_built_tiles == null) {
			this.m_built_tiles = [[], []];
		}

		if (this.m_coverage_radius == -1) {
			this.m_coverage_radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		}

		if (this.m_cargo_type == -1) {
			this.m_cargo_type = Utils.GetCargoType(cargo_class);
		}

		if (this.m_route_dist == -1) {
			this.m_route_dist = AIMap.DistanceManhattan(AITown.GetLocation(this.m_city_from), AITown.GetLocation(this.m_city_to));
		}

		if (this.m_city_from_name == null) {
			this.m_city_from_name = AITown.GetName(this.m_city_from);
		}

		if (this.m_city_to_name == null) {
			this.m_city_to_name = AITown.GetName(this.m_city_to);
		}

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_RAIL);
		if (num_vehicles >= AIGameSettings.GetValue("max_trains") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_RAIL)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		if (this.m_station_from == -1) {
			local station_from = this.BuildTownRailStation(this.m_city_from, this.m_city_to, this.m_best_routes_built, this.m_rail_type);
			if (station_from == null) {
				this.SetRouteFinished();
				return null;
			}
			this.m_station_from = station_from[0];
			this.m_station_from_dir = station_from[1];
		}

		if (this.m_depot_tile_from == -1) {
			local depot_tile_from = this.BuildRouteRailDepot(this.m_station_from, this.m_station_from_dir);
			if (depot_tile_from == null) {
				this.RemoveFailedRouteStation(this.m_station_from, this.m_station_from_dir);
				this.SetRouteFinished();
				return null;
			}
			this.m_depot_tile_from = depot_tile_from;
		}

		if (this.m_station_to == -1) {
			local station_to = this.BuildTownRailStation(this.m_city_to, this.m_city_from, this.m_best_routes_built, this.m_rail_type);
			if (station_to == null) {
				this.RemoveFailedRouteStation(this.m_station_from, this.m_station_from_dir, this.m_depot_tile_from);
				this.SetRouteFinished();
				return null;
			}
			this.m_station_to = station_to[0];
			this.m_station_to_dir = station_to[1];
		}

		if (this.m_depot_tile_to == -1) {
			local depot_tile_to = this.BuildRouteRailDepot(this.m_station_to, this.m_station_to_dir);
			if (depot_tile_to == null) {
				this.RemoveFailedRouteStation(this.m_station_from, this.m_station_from_dir, this.m_depot_tile_from);
				this.RemoveFailedRouteStation(this.m_station_to, this.m_station_to_dir);
				this.SetRouteFinished();
				return null;
			}
			this.m_depot_tile_to = depot_tile_to;
		}

		if (this.m_station_from != null && this.m_depot_tile_from != null && this.m_station_to != null && this.m_depot_tile_to != null) {
			local rail_array;
			if (this.m_pathfinder_profile == 1) rail_array = this.PathfindBuildDoubleRail(this.m_pathfinder_instance);
			if (this.m_pathfinder_profile == 0) rail_array = this.PathfindBuildSingleRail(this.m_pathfinder_instance);
			this.m_pathfinder_instance = rail_array[1];
			if (rail_array[0] == null) {
				if (this.m_pathfinder_instance != null) {
					return 0;
				}
				if (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0) {
					this.RemoveFailedRouteTracks();
				}
			} else if (this.m_pathfinder_profile == 0 && this.m_built_ways == 1) {
				return 0;
			}
		}

		if (this.m_built_tiles[0].len() == 0 && this.m_built_tiles[1].len() == 0) {
			this.RemoveFailedRouteStation(this.m_station_from, this.m_station_from_dir, this.m_depot_tile_from);
			this.RemoveFailedRouteStation(this.m_station_to, this.m_station_to_dir, this.m_depot_tile_to);
			this.SetRouteFinished();
			return null;
		}

		if (this.m_built_ways == 2 && this.m_num_signals == -1) {
			local signals_built = this.BuildSignals();
			if (signals_built == -1) {
				this.RemoveFailedRouteStation(this.m_station_from, this.m_station_from_dir, this.m_depot_tile_from);
				this.RemoveFailedRouteStation(this.m_station_to, this.m_station_to_dir, this.m_depot_tile_to);
				this.RemoveFailedRouteTracks();
				this.SetRouteFinished();
				return null;
			}
			this.m_num_signals = signals_built;
		}

		return RailRoute(this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile_from, this.m_depot_tile_to, this.m_bridge_tiles, this.m_cargo_class, this.m_sent_to_depot_rail_group, this.m_rail_type, this.m_station_from_dir, this.m_station_to_dir, this.m_num_signals);
	}

	function AreOtherRailwayStationsNearby(rail_station)
	{
		local is_friendly = AIController.GetSetting("is_friendly");
		local square_size = is_friendly ? this.m_coverage_radius * 2 : 2;

		local tile_list = AITileList();
		tile_list.AddRectangle(Utils.GetValidOffsetTile(rail_station.GetTopTile(), -1 * square_size, -1 * square_size), Utils.GetValidOffsetTile(rail_station.GetBottomTile(), square_size, square_size));

		foreach (tile, _ in tile_list) {
			if (AITile.IsStationTile(tile)) {
				if (AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					/* if another railway station of mine is nearby return true */
					if (AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN)) {
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

	function GetAdjacentNonRailwayStationID(rail_station_rectangle, spread_rectangle)
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
			if (AIStation.HasStationType(station_id, AIStation.STATION_TRAIN)) {
				tile_list[tile] = null;
				continue;
			}
			tile_list[tile] = station_id;
		}

		local station_list = AIList();
		station_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		foreach (tile, station_id in tile_list) {
			station_list[station_id] = rail_station_rectangle.DistanceManhattan(tile);
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

	function WorstStationOrientations(rail_station, rail_station_tiles, city_from, city_to)
	{
		local shortest_city_to_dist = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();

		for (local platform = 1; platform <= rail_station.m_num_plat; platform++) {
			local city_to_dist = AITown.GetDistanceManhattanToTile(city_to, rail_station.GetEntryTile(platform));
			if (city_to_dist < shortest_city_to_dist) {
				shortest_city_to_dist = city_to_dist;
			}
		}

		local best_tile = AIMap.TILE_INVALID;
		local shortest_city_from_dist = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();

		foreach (tile, _ in rail_station_tiles) {
			local city_from_dist = AITown.GetDistanceManhattanToTile(city_from, tile);
			if (city_from_dist < shortest_city_from_dist) {
				shortest_city_from_dist = city_from_dist;
				best_tile = tile;
			}
		}

		local town_from_tile = AITown.GetLocation(city_from);
		local diff_x = AIMap.GetTileX(town_from_tile) - AIMap.GetTileX(best_tile);
		local diff_y = AIMap.GetTileY(town_from_tile) - AIMap.GetTileY(best_tile);

		local worst_dirs = AIList();
		if (diff_x < 0) worst_dirs[RailStationDir.NE] = 0;
		if (diff_y < 0) worst_dirs[RailStationDir.NW] = 0;
		if (diff_x > 0) worst_dirs[RailStationDir.SW] = 0;
		if (diff_y > 0) worst_dirs[RailStationDir.SE] = 0;

		return [worst_dirs, shortest_city_from_dist, shortest_city_to_dist];
	}

	function BuildTownRailStation(city_from, city_to, best_routes_built, rail_type)
	{
		AIRail.SetCurrentRailType(rail_type);
		local pick_mode = AIController.GetSetting("pick_mode");
		local max_station_spread = AIGameSettings.GetValue("station_spread");
		local max_train_length = AIGameSettings.GetValue("max_train_length");
		local platform_length = min(RailRoute.MAX_PLATFORM_LENGTH, min(max_station_spread, max_train_length));
		local num_platforms = RailRoute.MAX_NUM_PLATFORMS;
		local distance_between_towns = AIMap.DistanceSquare(AITown.GetLocation(city_from), AITown.GetLocation(city_to));
		local town_rectangle = Utils.EstimateTownRectangle(city_from);
		town_rectangle = OrthogonalTileArea.CreateArea(town_rectangle[0], town_rectangle[1]);

		local rail_stations = AIPriorityQueue();
		foreach (dir in [RailStationDir.NE, RailStationDir.SW, RailStationDir.NW, RailStationDir.SE]) {
			local width = (dir == RailStationDir.NE || dir == RailStationDir.SW) ? platform_length : num_platforms;
			local height = (dir == RailStationDir.NE || dir == RailStationDir.SW) ? num_platforms : platform_length;

			/* build square around @city_from and find suitable tiles for railway station */
			local town_rectangle_expanded = clone town_rectangle;
			town_rectangle_expanded.Expand(width - 1, height - 1, false);
			town_rectangle_expanded.Expand(this.m_coverage_radius, this.m_coverage_radius);

			local tile_list = AITileList();
			tile_list.AddRectangle(town_rectangle_expanded.tile_top, town_rectangle_expanded.tile_bot);
			foreach (tile, _ in tile_list) {
				local rail_station = RailStation(tile, dir, num_platforms, platform_length);
				local rail_station_tiles = AITileList();
				rail_station_tiles.AddRectangle(rail_station.GetTopTile(), rail_station.GetBottomTile());

				local worst_dirs = this.WorstStationOrientations(rail_station, rail_station_tiles, city_from, city_to);
//				if (worst_dirs[0].HasItem(dir)){
//					continue;
//				}

//				local in_range = true;
//				foreach (station_tile, _ in rail_station_tiles) {
//					local city_from_dist = AITown.GetDistanceSquareToTile(city_from, station_tile);
//					local city_to_dist = AITown.GetDistanceSquareToTile(city_to, station_tile);
//					local farthest_town_id = city_from_dist < city_to_dist ? city_to : city_from;
//					if (AITown.GetDistanceSquareToTile(farthest_town_id, station_tile) >= distance_between_towns) {
//						in_range = false;
//						break;
///					} else {
///						AISign.BuildSign(station_tile, "" + dir);
//					}
//				}
//				if (!in_range) {
//					continue;
//				}

				local rectangle = rail_station.GetValidRectangle(4); // 4 tiles free
				if (rectangle == null) {
					continue;
				}

				if (!AITile.IsBuildableRectangle(rectangle[0], rectangle[1], rectangle[2])) {
					continue;
				}

				local exit_tile_1 = rail_station.GetExitTile(1);
				local exit_tile_2 = rail_station.GetExitTile(2);
				local depot_tile_1 = 2 * exit_tile_1 - exit_tile_2;
				local depot_tile_2 = 2 * exit_tile_2 - exit_tile_1;
				if (!AITile.IsBuildable(depot_tile_1) && !AITile.IsBuildable(depot_tile_2)) {
					continue;
				}

				local offset = exit_tile_1 - rail_station.GetEntryTile(1);
				local offset_2 = offset * 2;
				local offset_3 = offset * 3;
				local exit_turn_a_1 = depot_tile_1 + offset_2;
				local exit_turn_a_2 = depot_tile_1 + offset_3;
				local exit_turn_b_1 = depot_tile_2 + offset_3;
				local exit_turn_b_2 = depot_tile_2 + offset_2;
				local exit_front_a_2 = exit_tile_1 + offset_3;
				local exit_front_b_1 = exit_tile_2 + offset_3;
				if ((!AITile.IsBuildable(exit_turn_a_1) || !AITile.IsBuildable(exit_turn_a_2)) &&
						(!AITile.IsBuildable(exit_turn_b_1) || !AITile.IsBuildable(exit_turn_b_2)) &&
						(!AITile.IsBuildable(exit_turn_a_2) || !AITile.IsBuildable(exit_front_a_2)) &&
						(!AITile.IsBuildable(exit_front_b_1) || !AITile.IsBuildable(exit_turn_b_1))) {
					continue;
				}

				if (AITile.GetCargoAcceptance(tile, this.m_cargo_type, rail_station.m_width, rail_station.m_height, this.m_coverage_radius) < 8) {
					continue;
				}

				if (this.AreOtherRailwayStationsNearby(rail_station)) {
					continue;
				}

				local cargo_production = AITile.GetCargoProduction(tile, this.m_cargo_type, rail_station.m_width, rail_station.m_height, this.m_coverage_radius);
				if (pick_mode != 1 && !best_routes_built && cargo_production < 8) {
					continue;
				}

				/* store as negative to make priority queue prioritize highest values */
				rail_stations.Insert(rail_station, -((cargo_production << 26) | ((0x1FFF - worst_dirs[1]) << 13) | (0x1FFF - worst_dirs[2])));
			}
		}

		while (!rail_stations.IsEmpty()) {
			local rail_station = rail_stations.Pop();
			local top_tile = rail_station.GetTopTile();

			if (AITile.GetClosestTown(top_tile) != city_from) {
				continue;
			}

			local bot_tile = rail_station.GetBottomTile();

			/* get adjacent tiles */
			local rail_station_tiles = AITileList();
			rail_station_tiles.AddRectangle(top_tile, bot_tile);
			local adjacent_tile_list = AITileList();
			adjacent_tile_list.AddList(rail_station_tiles);

			foreach (tile in adjacent_tile_list) {
				local adjacent_tile_list2 = Utils.GetAdjacentTiles(tile);
				foreach (tile2 in adjacent_tile_list2) {
					adjacent_tile_list[tile2] = 0;
				}
			}
			adjacent_tile_list.RemoveRectangle(top_tile, bot_tile);

			/* avoid blocking other station exits */
			local blocking = false;
			foreach (adjacent_tile, _ in adjacent_tile_list) {
				if (!AITile.IsStationTile(adjacent_tile)) {
					continue;
				}
				if (!AITile.HasTransportType(adjacent_tile, AITile.TRANSPORT_ROAD)) {
					continue;
				}
				foreach (road_type, _ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD | AIRoad.ROADTRAMTYPES_TRAM)) {
					if (!AIRoad.HasRoadType(adjacent_tile, road_type)) {
						continue;
					}
					SetCurrentRoadType(road_type);
					if (!AIRoad.IsRoadStationTile(adjacent_tile)) {
						continue;
					}
					if (!rail_station_tiles.HasTile(AIRoad.GetRoadStationFrontTile(adjacent_tile))) {
						continue;
					}
					blocking = true;
					break;
				}
				if (blocking) {
					break;
				}
			}

			if (blocking) {
				continue;
			}

			local adjacent_station_id = AIStation.STATION_NEW;
			if (max_station_spread && AIGameSettings.GetValue("distant_join_stations")) {
				local remaining_x = max_station_spread - rail_station.m_width;
				local remaining_y = max_station_spread - rail_station.m_height;
				local rail_station_rectangle = OrthogonalTileArea(top_tile, rail_station.m_width, rail_station.m_height);
				local spread_rectangle = clone rail_station_rectangle;
				spread_rectangle.Expand(remaining_x, remaining_y);
				adjacent_station_id = this.GetAdjacentNonRailwayStationID(rail_station_rectangle, spread_rectangle);
			}

			local entry_tile_2 = rail_station.GetEntryTile(2);
			local exit_tile_2 = rail_station.GetExitTile(2);
			local exit_tile_1 = rail_station.GetExitTile(1);
			local entry_tile_1 = rail_station.GetEntryTile(1);
			local exit_tile_1_1 = 2 * exit_tile_1 - entry_tile_1;
			local exit_tile_2_1 = 2 * exit_tile_2 - entry_tile_2;

			local counter = 0;
			do {
				if (!TestBuildRailStation().TryBuild(top_tile, rail_station.GetTrackDirection(), rail_station.m_num_plat, rail_station.m_length, adjacent_station_id)) {
					++counter;
				} else {
//					AILog.Info("station built");
					break;
				}
				AIController.Sleep(1);
			} while (counter < 1);

			if (counter == 1) {
				continue;
			} else {
				/* Built rail station. Now build track infront of platform 1 */
				local counter = 0;
				do {
					if (!AIRoad.IsRoadTile(exit_tile_1) && !TestBuildRail().TryBuild(entry_tile_1, exit_tile_1, exit_tile_1_1)) {
						++counter;
					} else {
//						AILog.Info("built track infront of platform 1");
						break;
					}
					AIController.Sleep(1);
				} while (counter < 1);

				if (counter == 1) {
					local counter = 0;
					do {
						if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
							++counter;
						} else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
						continue;
					}
				} else {
					/* Built track in front of platform 1. Now build track in front of platform 2 */
					local counter = 0;
					do {
						if (!AIRoad.IsRoadTile(exit_tile_2) && !TestBuildRail().TryBuild(entry_tile_2, exit_tile_2, exit_tile_2_1)) {
							++counter;
						} else {
//							AILog.Info("built track infront of platform 2");
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						local counter = 0;
						do {
							if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, exit_tile_1_1)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, exit_tile_1_1));
						}

						local counter = 0;
						do {
							if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
						}
						continue;
					} else {
						/* Built track in front of platform 2. Now build track crossing from platform 1 to 2 */
						local counter = 0;
						do {
							if (!TestBuildRail().TryBuild(entry_tile_1, exit_tile_1, exit_tile_2_1)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							local counter = 0;
							do {
								if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, exit_tile_2_1)) {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);

							if (counter == 1) {
								::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, exit_tile_2_1));
							}

							local counter = 0;
							do {
								if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, exit_tile_1_1)) {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);

							if (counter == 1) {
								::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, exit_tile_1_1));
							}

							local counter = 0;
							do {
								if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);

							if (counter == 1) {
								::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
							}
							continue;
						} else {
							/* Built track crossing from platform 1 to 2. Now build track crossing from platform 2 to 1 */
							local counter = 0;
							do {
								if (!TestBuildRail().TryBuild(entry_tile_2, exit_tile_2, exit_tile_1_1)) {
									++counter;
								} else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);

							if (counter == 1) {
								local counter = 0;
								do {
									if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, exit_tile_2_1)) {
										++counter;
									} else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);

								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, exit_tile_2_1));
								}

								local counter = 0;
								do {
									if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, exit_tile_2_1)) {
										++counter;
									} else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);

								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, exit_tile_2_1));
								}
								local counter = 0;

								do {
									if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, exit_tile_1_1)) {
										++counter;
									} else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);
								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, exit_tile_1_1));
								}

								local counter = 0;
								do {
									if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
										++counter;
									} else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);

								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
								}
								continue;
							} else {
								AILog.Info("Railway station built in " + AITown.GetName(city_from) + " at tile " + top_tile + "!");
								return [top_tile, rail_station.m_dir];
							}
						}
					}
				}
			}
		}

		return null;
	}

	/* find rail way between this.m_station_from and this.m_station_to */
	function PathfindBuildSingleRail(pathfinder_instance, cost_so_far = 0)
	{
		if (this.m_station_from != this.m_station_to) {
			if (this.m_max_pathfinder_tries == -1) {
				this.m_max_pathfinder_tries = 600 * this.m_route_dist;
			}

			/* Print the names of the towns we'll try to connect. */
			AILog.Info("t:Connecting " + this.m_city_from_name + " (tile " + this.m_station_from + ") and " + AITown.GetName(this.m_city_to) + " (tile " + this.m_station_to + ") (iteration " + (this.m_pathfinder_tries + 1) + "/" + this.m_max_pathfinder_tries + ")");

			/* Tell OpenTTD we want to build this rail_type. */
			AIRail.SetCurrentRailType(this.m_rail_type);

			if (pathfinder_instance == null) {
				/* Create an instance of the pathfinder. */
				pathfinder_instance = SingleRail();

				AILog.Info("rail pathfinder: single rail");
/*defaults*/
/*10000000*/	pathfinder_instance.cost.max_cost;
/*100*/			pathfinder_instance.cost.tile;
/*70*/			pathfinder_instance.cost.diagonal_tile;
/*50*/			pathfinder_instance.cost.turn45 = 190;
/*300*/			pathfinder_instance.cost.turn90 = AIGameSettings.GetValue("forbid_90_deg") ? pathfinder_instance.cost.max_cost : pathfinder_instance.cost.turn90;
/*250*/			pathfinder_instance.cost.consecutive_turn = 460;
/*100*/			pathfinder_instance.cost.slope = AIGameSettings.GetValue("train_acceleration_model") ? AIGameSettings.GetValue("train_slope_steepness") * 20 : pathfinder_instance.cost.slope;
/*400*/			pathfinder_instance.cost.consecutive_slope;
/*150*/			pathfinder_instance.cost.bridge_per_tile = 225;
/*120*/			pathfinder_instance.cost.tunnel_per_tile;
/*20*/			pathfinder_instance.cost.coast = (AICompany.GetLoanAmount() == 0) ? pathfinder_instance.cost.coast : 5000;
/*900*/			pathfinder_instance.cost.level_crossing = pathfinder_instance.cost.max_cost;
/*6*/			pathfinder_instance.cost.max_bridge_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*6*/			pathfinder_instance.cost.max_tunnel_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
/*1*/			pathfinder_instance.cost.estimate_multiplier = 3;
/*0*/			pathfinder_instance.cost.search_range = max(this.m_route_dist / 15, 25);

				/* Give the source and goal tiles to the pathfinder. */
				local station_from = RailStation.CreateFromTile(this.m_station_from, this.m_station_from_dir);
				local station_to = RailStation.CreateFromTile(this.m_station_to, this.m_station_to_dir);
				local line_from_1 = station_from.GetPlatformLine(1);
				local line_to_2 = station_to.GetPlatformLine(2);

				local station_from_exit_1 = station_from.GetExitTile(line_from_1, 1);
				local station_to_exit_2 = station_to.GetExitTile(line_to_2, 1);

				/* SingleRail */
				if (this.m_built_ways == 0) {
					local line_from_2 = station_from.GetPlatformLine(2);
					local line_to_1 = station_to.GetPlatformLine(1);
					local station_from_entry_before_2 = station_from.GetEntryTile(line_from_2);
					local station_from_entry_2 = station_from.GetExitTile(line_from_2);
					local station_from_exit_2 = station_from.GetExitTile(line_from_2, 1);
					local station_to_entry_before_1 = station_to.GetEntryTile(line_to_1);
					local station_to_entry_1 = station_to.GetExitTile(line_to_1);
					local station_to_exit_1 = station_to.GetExitTile(line_to_1, 1);
					local ignore_tiles = [station_from_exit_1, station_to_exit_2];
					if (AIGameSettings.GetValue("forbid_90_deg")) {
						if (AIRail.GetRailDepotFrontTile(this.m_depot_tile_from) == station_from_entry_2) {
							station_from_entry_before_2 = this.m_depot_tile_from;
							ignore_tiles.push(2 * station_from_exit_2 - station_from_exit_1);
						} else {
							ignore_tiles.push(station_from.GetExitTile(line_from_1, 2));
							ignore_tiles.push(2 * station_from_exit_1 - station_from_exit_2);
						}
						if (AIRail.GetRailDepotFrontTile(this.m_depot_tile_to) == station_to_entry_1) {
							station_to_entry_before_1 = this.m_depot_tile_to;
							ignore_tiles.push(2 * station_to_exit_1 - station_to_exit_2);
						} else {
							ignore_tiles.push(station_to.GetExitTile(line_to_2, 2));
							ignore_tiles.push(2 * station_to_exit_2 - station_to_exit_1);
						}
					}
//					local ignore_tiles_text = "ignore_tiles = ";
//					foreach (tile in ignore_tiles) {
//						ignore_tiles_text += tile + "; ";
//					}
//					AILog.Info("station_from_exit_2 = " + station_from_exit_2 + "; station_from_entry_2 = " + station_from_entry_2 + "; station_from_entry_before_2 = " + station_from_entry_before_2);
//					AILog.Info("station_to_exit_1 = " + station_to_exit_1 + "; station_to_entry_1 = " + station_to_entry_1 + "; station_to_entry_before_1 = " + station_to_entry_before_1);
//					AILog.Info(ignore_tiles_text);
					pathfinder_instance.InitializePath(
						[[station_from_exit_2, station_from_entry_2, station_from_entry_before_2]],
						[[station_to_exit_1, station_to_entry_1, station_to_entry_before_1]],
						ignore_tiles
					);
				} else if (this.m_built_ways == 1) {
					local station_from_entry_before_1 = station_from.GetEntryTile(line_from_1);
					local station_from_entry_1 = station_from.GetExitTile(line_from_1);
					if (AIRail.GetRailDepotFrontTile(this.m_depot_tile_from) == station_from_entry_1) station_from_entry_before_1 = this.m_depot_tile_from;
					local station_to_entry_before_2 = station_to.GetEntryTile(line_to_2);
					local station_to_entry_2 = station_to.GetExitTile(line_to_2);
					if (AIRail.GetRailDepotFrontTile(this.m_depot_tile_to) == station_to_entry_2) station_to_entry_before_2 = this.m_depot_tile_to;
//					AILog.Info("station_to_exit_2 = " + station_to_exit_2 + "; station_to_entry_2 = " + station_to_entry_2 + "; station_to_entry_before_2 = " + station_to_entry_before_2);
//					AILog.Info("station_from_exit_1 = " + station_from_exit_1 + "; station_from_entry_1 = " + station_from_entry_1 + "; station_from_entry_before_1 = " + station_from_entry_before_1);
					pathfinder_instance.InitializePath(
						[[station_to_exit_2, station_to_entry_2, station_to_entry_before_2]],
						[[station_from_exit_1, station_from_entry_1, station_from_entry_before_1]]
					);
				}
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
//							AILog.Info("rail pathfinder: FindPath iterated: " + count);
//							local sign_list = AISignList();
//							foreach (sign, _ in sign_list) {
//								if (sign_list.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder_instance];
						}
					} else {
						/* Timed out */
						AILog.Error("rail pathfinder: FindPath return false (timed out)");
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					AILog.Error("rail pathfinder: FindPath return null (no path)");
					return [null, null];
				}
			} while (path == false);

//			if (this.m_pathfinder_tries != count) AILog.Info("rail pathfinder: FindPath iterated: " + count);
			AILog.Info("Rail path found! FindPath iterated: " + this.m_pathfinder_tries + ". Building track... ");
			AILog.Info("rail pathfinder: FindPath cost: " + path.GetCost());

			local segments = [];
			while (path != null) {
				segments.append(path.GetTile());
				path = path.GetParent();
			}
			segments.reverse();

			/* If a path was found, build a track over it. */
			local track_cost = cost_so_far;
			for (local id = 0; id < segments.len(); id++) {
				local cur = segments[id];
				local prev = id > 0 ? segments[id - 1] : null;
				local prevprev = prev && id - 1 > 0 ? segments[id - 2] : null;
				if (prev != null) {
					local distance = AIMap.DistanceManhattan(prev, cur);
					if (distance > 1) {
						if (AITunnel.GetOtherTunnelEnd(prev) == cur) {
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (!TestBuildTunnel().TryBuild(AIVehicle.VT_RAIL, prev)) {
									if (AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG") {
										if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && this.m_built_tiles[this.m_built_ways] != 0) {
											/* Remove everything and try again */
											AILog.Warning("Couldn't build rail tunnel at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
											this.RemoveFailedRouteTracks();
											return PathfindBuildSingleRail(null, track_cost);
										}
									}
									++counter;
								} else {
									track_cost += costs.GetCosts();
//									AILog.Warning("We built a rail tunnel at tiles " + prev + " and " + cur + ", ac: " + costs.GetCosts());
									this.m_built_tiles[this.m_built_ways].append(RailStruct.SetStruct(prev, RailStructType.TUNNEL, this.m_rail_type, cur));
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								AILog.Warning("Couldn't build rail tunnel at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString());
//								AIController.Break("");
								return [null, null];
							}
						} else {
							local bridge_length = distance + 1;
							local bridge_type_list = AIBridgeList_Length(bridge_length);
							foreach (bridge_type, _ in bridge_type_list) {
								bridge_type_list[bridge_type] = AIBridge.GetMaxSpeed(bridge_type);
							}
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (!TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, bridge_type_list.Begin(), prev, cur)) {
									if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
										bridge_type_list.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
										foreach (bridge_type, _ in bridge_type_list) {
											bridge_type_list[bridge_type] = AIBridge.GetPrice(bridge_type, bridge_length);
										}
										bridge_type_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
									} else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_BRIDGE_HEADS_NOT_ON_SAME_HEIGHT" || AIError.GetLastErrorString() == "ERR_TUNNEL_CANNOT_BUILD_ON_WATER") {
										if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && this.m_built_tiles[this.m_built_ways].len() != 0) {
											/* Remove everything and try again */
											AILog.Warning("Couldn't build rail bridge at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
											this.RemoveFailedRouteTracks(this.m_built_ways);
											return this.PathfindBuildSingleRail(null, track_cost);
										}
									}
									++counter;
								} else {
									track_cost += costs.GetCosts();
//									AILog.Warning("We built a rail bridge at tiles " + prev + " and " + cur + ", ac: " + costs.GetCosts());
									this.m_built_tiles[this.m_built_ways].append(RailStruct.SetStruct(prev, RailStructType.BRIDGE, this.m_rail_type, cur));
									this.m_bridge_tiles.append(prev < cur ? [prev, cur] : [cur, prev]);
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								AILog.Warning("Couldn't build rail bridge at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString());
//								AIController.Break("");
								return [null, null];
							}
						}
					} else if (prevprev != null && AIMap.DistanceManhattan(prevprev, prev) == 1) {
						if (!AIRoad.IsRoadTile(prev) || (AITestMode() && !AIRail.BuildRail(prevprev, prev, cur))) {
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (!TestBuildRail().TryBuild(prevprev, prev, cur)) {
									if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT") {
//										AILog.Warning("We found a rail track already built at tile " + prev + ", connecting " + prevprev + " to " + cur);
										break;
									} else if (AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_TUNNEL_CANNOT_BUILD_ON_WATER" || AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG") {
										if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && this.m_built_tiles[this.m_built_ways].len() != 0) {
											/* Remove everything and try again */
											AILog.Warning("Couldn't build rail track at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
											this.RemoveFailedRouteTracks(this.m_built_ways);
											return this.PathfindBuildSingleRail(null, track_cost);
										}
									}
									++counter;
								} else {
									track_cost += costs.GetCosts();
//									AILog.Warning("We built a rail track at tile " + prev + ", connecting " + prevprev + " to " + cur + ", ac: " + costs.GetCosts());
									this.m_built_tiles[this.m_built_ways].append(RailStruct.SetRail(prev, this.m_rail_type, prevprev, cur));
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								AILog.Warning("Couldn't build rail track at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString());
//								AIController.Break("");
								return [null, null];
							}
						} else if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && this.m_built_tiles[this.m_built_ways].len() != 0) {
							AILog.Warning("Won't build a rail crossing a road at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
							this.RemoveFailedRouteTracks(this.m_built_ways);
							return this.PathfindBuildSingleRail(null, track_cost);
						} else {
							AILog.Warning("Won't build a rail crossing a road at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString());
							return [null, null];
						}
					}
				}
			}

			AILog.Info("Track built! Actual cost for building track: " + track_cost);
		}

		this.m_built_ways++;
		return [this.m_built_tiles, null];
	}

	/* find rail way between this.m_station_from and this.m_station_to */
	function PathfindBuildDoubleRail(pathfinder_instance, cost_so_far = 0)
	{
		/* can store rail tiles into array */

		if (this.m_station_from != this.m_station_to) {
			if (this.m_max_pathfinder_tries == -1) {
				this.m_max_pathfinder_tries = 100 * this.m_route_dist;
			}

			/* Print the names of the towns we'll try to connect. */
			AILog.Info("t:Connecting " + this.m_city_from_name + " (tile " + this.m_station_from + ") and " + AITown.GetName(this.m_city_to) + " (tile " + this.m_station_to + ") (iteration " + (this.m_pathfinder_tries + 1) + "/" + this.m_max_pathfinder_tries + ")");

			/* Tell OpenTTD we want to build this rail_type. */
			AIRail.SetCurrentRailType(this.m_rail_type);

			if (pathfinder_instance == null) {
				/* Create an instance of the pathfinder. */
				pathfinder_instance = DoubleRail();

				AILog.Info("rail pathfinder: double rail");
/*defaults*/
/*10000000*/	pathfinder_instance.cost.max_cost;
/*100*/			pathfinder_instance.cost.tile;
/*70*/			pathfinder_instance.cost.diagonal_tile;
/*50*/			pathfinder_instance.cost.turn45 = 190;
/*300*/			pathfinder_instance.cost.turn90 = AIGameSettings.GetValue("forbid_90_deg") ? pathfinder_instance.cost.max_cost : pathfinder_instance.cost.turn90;
/*250*/			pathfinder_instance.cost.consecutive_turn = 460;
/*100*/			pathfinder_instance.cost.slope = AIGameSettings.GetValue("train_acceleration_model") ? AIGameSettings.GetValue("train_slope_steepness") * 20 : pathfinder_instance.cost.slope;
/*400*/			pathfinder_instance.cost.consecutive_slope;
/*150*/			pathfinder_instance.cost.bridge_per_tile = 225;
/*120*/			pathfinder_instance.cost.tunnel_per_tile;
/*20*/			pathfinder_instance.cost.coast = (AICompany.GetLoanAmount() == 0) ? pathfinder_instance.cost.coast : 5000;
/*900*/			pathfinder_instance.cost.level_crossing = pathfinder_instance.cost.max_cost;
/*6*/			pathfinder_instance.cost.max_bridge_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*6*/			pathfinder_instance.cost.max_tunnel_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
/*1*/			pathfinder_instance.cost.estimate_multiplier = 3;
/*0*/			pathfinder_instance.cost.search_range = max(this.m_route_dist / 15, 25);

				/* Give the source and goal tiles to the pathfinder. */
				local station_from = RailStation.CreateFromTile(this.m_station_from, this.m_station_from_dir);
				local station_to = RailStation.CreateFromTile(this.m_station_to, this.m_station_to_dir);
				local line_from_1 = station_from.GetPlatformLine(1);
				local line_to_2 = station_to.GetPlatformLine(2);
				local line_from_2 = station_from.GetPlatformLine(2);
				local line_to_1 = station_to.GetPlatformLine(1);

				local station_from_entry_1 = station_from.GetExitTile(line_from_1);
				local station_from_exit_1 = station_from.GetExitTile(line_from_1, 1);
				local station_to_entry_2 = station_to.GetExitTile(line_to_2);
				local station_to_exit_2 = station_to.GetExitTile(line_to_2, 1);
				local station_from_entry_2 = station_from.GetExitTile(line_from_2);
				local station_from_exit_2 = station_from.GetExitTile(line_from_2, 1);
				local station_to_entry_1 = station_to.GetExitTile(line_to_1);
				local station_to_exit_1 = station_to.GetExitTile(line_to_1, 1);
				local ignore_tiles = [];
//				if (AIRail.GetRailDepotFrontTile(this.m_depot_tile_from) == station_from_entry_2) {
					ignore_tiles.push(2 * station_from_exit_2 - station_from_exit_1);
//				} else {
					ignore_tiles.push(2 * station_from_exit_1 - station_from_exit_2);
//				}
//				if (AIRail.GetRailDepotFrontTile(this.m_depot_tile_to) == station_to_entry_1) {
					ignore_tiles.push(2 * station_to_exit_1 - station_to_exit_2);
//				} else {
					ignore_tiles.push(2 * station_to_exit_2 - station_to_exit_1);
//				}
//				local ignore_tiles_text = "ignore_tiles = ";
//				foreach (tile in ignore_tiles) {
//					ignore_tiles_text += tile + "; ";
//				}

				/* DoubleRail */
				AILog.Info("station_from_entry_1 = " + station_from_entry_1 + "; station_from_exit_1 = " + station_from_exit_1 + "; station_to_entry_2 = " + station_to_entry_2 + "; station_to_exit_2 = " + station_to_exit_2);
				AILog.Info("station_from_entry_2 = " + station_from_entry_2 + "; station_from_exit_2 = " + station_from_exit_2 + "; station_to_entry_1 = " + station_to_entry_1 + "; station_to_exit_1 = " + station_to_exit_1);
				AILog.Info(ignore_tiles_text);
				pathfinder_instance.InitializePath(
					[[station_from_entry_1, station_from_exit_1], [station_from_entry_2, station_from_exit_2]],
					[[station_to_exit_2, station_to_entry_2], [station_to_exit_1, station_to_entry_1]],
					ignore_tiles
				);
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
//							AILog.Info("rail pathfinder: FindPath iterated: " + count);
//							local sign_list = AISignList();
//							foreach (sign, _ in sign_list) {
//								if (sign_list.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder_instance];
						}
					} else {
						/* Timed out */
						AILog.Error("rail pathfinder: FindPath return false (timed out)");
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					AILog.Error("rail pathfinder: FindPath return null (no path)");
					return [null, null];
				}
			} while (path == false);

//			if (this.m_pathfinder_tries != count) AILog.Info("rail pathfinder: FindPath iterated: " + count);
			AILog.Info("Rail path found! FindPath iterated: " + this.m_pathfinder_tries + ". Building track... ");
			AILog.Info("rail pathfinder: FindPath cost: " + path.GetCost());

			local segments = [];
			while (path != null) {
				segments.append(path._segment);
				path = path.GetParent();
			}
			segments.reverse();

			/* If a path was found, build a track over it. */
			local track_cost = cost_so_far;
			local next = [null, null];
			local nextnext = [null, null];
			local scan_tile = [null, null];
			local last_tile = false;
			for (local id = 0; id <= segments.len(); id++) {
				last_tile = id == segments.len();
				local segment = last_tile ? segments[id - 1] : segments[id];
				foreach (j in [0, 1]) {
					for (local i = 0; i < segment.m_nodes[j].len(); i++) {
						scan_tile[j] = segment.m_nodes[j][i][!last_tile ? 3 : 0];
//						AILog.Info("id = " + id + "; line = " + (j + 1) + "; node = " + i + "; scan_tile = " + scan_tile[j] + "; next = " + next[j] + "; nextnext = " + nextnext[j]);
						if (nextnext[j] != null) {
							if (AIMap.DistanceManhattan(next[j], scan_tile[j]) > 1) {
								if (AITunnel.GetOtherTunnelEnd(next[j]) == scan_tile[j]) {
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildTunnel().TryBuild(AIVehicle.VT_RAIL, next[j])) {
											if (AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG") {
												if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
													AILog.Warning("Couldn't build rail tunnel at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
													/* Remove everything and try again */
													this.RemoveFailedRouteTracks();
													return this.PathfindBuildDoubleRail(null, track_cost);
												}
											}
											++counter;
										} else {
											track_cost += costs.GetCosts();
//											AILog.Warning("We built a rail tunnel at tiles " + next[j] + " and " + scan_tile[j] + ", ac: " + costs.GetCosts());
											this.m_built_tiles[j].append(RailStruct.SetStruct(next[j], RailStructType.TUNNEL, this.m_rail_type, scan_tile[j]));
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										AILog.Warning("Couldn't build rail tunnel at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString());
//										AIController.Break("");
										return [null, null];
									}
								} else {
									local bridge_length = AIMap.DistanceManhattan(scan_tile[j], next[j]) + 1;
									local bridge_type_list = AIBridgeList_Length(bridge_length);
									foreach (bridge_type, _ in bridge_type_list) {
										bridge_type_list[bridge_type] = AIBridge.GetMaxSpeed(bridge_type);
									}
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, bridge_type_list.Begin(), next[j], scan_tile[j])) {
											if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
												bridge_type_list.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
												foreach (bridge_type, _ in bridge_type_list) {
													bridge_type_list.SetValue(bridge_type, AIBridge.GetPrice(bridge_type, bridge_length));
												}
												bridge_type_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
											} else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_BRIDGE_HEADS_NOT_ON_SAME_HEIGHT" || AIError.GetLastErrorString() == "ERR_TUNNEL_CANNOT_BUILD_ON_WATER") {
												if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
													/* Remove everything and try again */
													AILog.Warning("Couldn't build rail bridge at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
													this.RemoveFailedRouteTracks();
													return this.PathfindBuildDoubleRail(null, track_cost);
												}
											}
											++counter;
										} else {
											track_cost += costs.GetCosts();
//											AILog.Warning("We built a rail bridge at tiles " + next[j] + " and " + scan_tile[j] + ", ac: " + costs.GetCosts());
											this.m_built_tiles[j].append(RailStruct.SetStruct(next[j], RailStructType.BRIDGE, this.m_rail_type, scan_tile[j]));
											this.m_bridge_tiles.append(next[j] < scan_tile[j] ? [next[j], scan_tile[j]] : [scan_tile[j], next[j]]);
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										AILog.Warning("Couldn't build rail bridge at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString());
//										AIController.Break("");
										return [null, null];
									}
								}
							} else if (AIMap.DistanceManhattan(nextnext[j], next[j]) == 1) {
								if (!AIRoad.IsRoadTile(next[j]) || (AITestMode() && !AIRail.BuildRail(nextnext[j], next[j], scan_tile[j]))) {
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildRail().TryBuild(nextnext[j], next[j], scan_tile[j])) {
											if (AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_TUNNEL_CANNOT_BUILD_ON_WATER" || AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG") {
												if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
													/* Remove everything and try again */
													AILog.Warning("Couldn't build rail track at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
													this.RemoveFailedRouteTracks();
													return this.PathfindBuildDoubleRail(null, track_cost);
												}
											}
											++counter;
										} else {
											track_cost += costs.GetCosts();
//											AILog.Warning("We built a rail track at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + ", ac: " + costs.GetCosts());
											this.m_built_tiles[j].append(RailStruct.SetRail(next[j], this.m_rail_type, nextnext[j], scan_tile[j]));
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										AILog.Warning("Couldn't build rail track at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString());
//										AIController.Break("");
										return [null, null];
									}
								} else if (this.m_pathfinder_tries < this.m_max_pathfinder_tries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
									AILog.Warning("Won't build a rail crossing a road at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
									this.RemoveFailedRouteTracks();
									return this.PathfindBuildDoubleRail(null, track_cost);
								} else {
									AILog.Warning("Won't build a rail crossing a road at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString());
									return [null, null];
								}
							}
						}
						nextnext[j] = next[j];
						next[j] = scan_tile[j];
					}
				}
			}

			AILog.Info("Track built! Actual cost for building track: " + track_cost);
		}

		this.m_built_ways += 2;
		return [this.m_built_tiles, null];
	}

	function BuildRailDepotOnTile(depot_tile, depot_front_tile, depot_rail_a, depot_rail_b, depot_rail_c)
	{
		local counter = 0;
		do {
			if (!TestBuildRailDepot().TryBuild(depot_tile, depot_front_tile)) {
				++counter;
			} else {
				break;
			}
			AIController.Sleep(1);
		} while (counter < 1);

		if (counter == 1) {
			return null;
		} else {
			local counter = 0;
			do {
				if (!TestBuildRail().TryBuild(depot_tile, depot_front_tile, depot_rail_a)) {
					++counter;
				} else {
					break;
				}
				AIController.Sleep(1);
			} while (counter < 1);

			if (counter == 1) {
				local counter = 0;
				do {
					if (!TestDemolishTile().TryDemolish(depot_tile)) {
						++counter;
					} else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 1);

				if (counter == 1) {
					::scheduled_removals_table.Train.append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
				}
				return null;
			} else {
				local counter = 0;
				do {
					if (!TestBuildRail().TryBuild(depot_tile, depot_front_tile, depot_rail_b)) {
						++counter;
					} else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 1);

				if (counter == 1) {
					local counter = 0;
					do {
						if (!TestRemoveRail().TryRemove(depot_tile, depot_front_tile, depot_rail_a)) {
							++counter;
						} else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						::scheduled_removals_table.Train.append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_a));
					}

					local counter = 0;
					do {
						if (!TestDemolishTile().TryDemolish(depot_tile)) {
							++counter;
						} else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						::scheduled_removals_table.Train.append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
					}
					return null;
				} else {
					local counter = 0;
					do {
						if (!TestBuildRail().TryBuild(depot_tile, depot_front_tile, depot_rail_c)) {
							++counter;
						} else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						local counter = 0;
						do {
							if (!TestRemoveRail().TryRemove(depot_tile, depot_front_tile, depot_rail_b)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_b));
						}

						local counter = 0;
						do {
							if (!TestRemoveRail().TryRemove(depot_tile, depot_front_tile, depot_rail_a)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetRail(depot_front_tile, this.m_rail_type, depot_tile, depot_rail_a));
						}

						local counter = 0;
						do {
							if (!TestDemolishTile().TryDemolish(depot_tile)) {
								++counter;
							} else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
						}
						return null;
					}
					return depot_tile;
				}
			}
		}
	}

	function BuildRouteRailDepot(station_tile, station_dir)
	{
		local depot_tile = null;

		AIRail.SetCurrentRailType(this.m_rail_type);
		local rail_station = RailStation.CreateFromTile(station_tile, station_dir);
		local line_1 = rail_station.GetPlatformLine(1);
		local line_2 = rail_station.GetPlatformLine(2);
		local exit_tile_1 = rail_station.GetExitTile(line_1);
		local exit_tile_2 = rail_station.GetExitTile(line_2);
		local entry_tile_1 = rail_station.GetEntryTile(line_1);

		/* first attempt, build next to line 1 (incoming) */
		local depot_tile_1 = 2 * exit_tile_1 - exit_tile_2;
		local exit_tile_1_1 = 2 * exit_tile_1 - entry_tile_1;

		if (AITestMode() && AIRail.BuildRail(depot_tile_1, exit_tile_1, entry_tile_1) && AIRail.BuildRail(depot_tile_1, exit_tile_1, exit_tile_1_1) &&
				AIRail.BuildRail(depot_tile_1, exit_tile_1, exit_tile_2) && AIRail.BuildRailDepot(depot_tile_1, exit_tile_1)) {
			depot_tile = this.BuildRailDepotOnTile(depot_tile_1, exit_tile_1, entry_tile_1, exit_tile_1_1, exit_tile_2);
		}
		if (depot_tile != null) {
			return depot_tile;
		}

		local entry_tile_2 = rail_station.GetEntryTile(line_2);

		/* second attempt, build next to line 2 (outgoing) */
		local depot_tile_2 = 2 * exit_tile_2 - exit_tile_1;
		local exit_tile_2_1 = 2 * exit_tile_2 - entry_tile_2;

		if (AITestMode() && AIRail.BuildRail(depot_tile_2, exit_tile_2, entry_tile_2) && AIRail.BuildRail(depot_tile_2, exit_tile_2, exit_tile_2_1) &&
				AIRail.BuildRail(depot_tile_2, exit_tile_2, exit_tile_1) && AIRail.BuildRailDepot(depot_tile_2, exit_tile_2)) {
			depot_tile = this.BuildRailDepotOnTile(depot_tile_2, exit_tile_2, entry_tile_2, exit_tile_2_1, exit_tile_1);
		}
		if (depot_tile != null) {
			return depot_tile;
		}

		/* no third attempt */
//		AILog.Warning("Couldn't build rail depot!");
		return depot_tile;
	}

	function NextTrack(current)
	{
		local front_tile = current[0];
		local prev_tile = current[1];
		local next_tile = AIMap.TILE_INVALID;
		if (AIRail.IsRailTile(front_tile)) {
			local offset = front_tile - prev_tile;
			local track = AIRail.GetRailTracks(front_tile);
			local bits = Utils.CountBits(track);
			if (bits >= 1 && bits <= 2) {
				switch (offset) {
					case 1: { // NE
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								next_tile = front_tile + 1;
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								next_tile = front_tile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								next_tile = front_tile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case -1: { // SW
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								next_tile = front_tile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								next_tile = front_tile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								next_tile = front_tile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case AIMap.GetMapSizeX(): { // NW
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								next_tile = front_tile + AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								next_tile = front_tile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								next_tile = front_tile + 1;
								break;
							}
						}
						break;
					}
					case -AIMap.GetMapSizeX(): { // SE
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								next_tile = front_tile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								next_tile = front_tile - 1;
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								next_tile = front_tile + 1;
								break;
							}
						}
						break;
					}
				}
			}
			if (next_tile != AIMap.TILE_INVALID) {
				return [next_tile, front_tile];
			}
		} else if (AIBridge.IsBridgeTile(front_tile)) {
			local offset = front_tile - prev_tile;
			local other_tile = AIBridge.GetOtherBridgeEnd(front_tile);
			if (((other_tile - front_tile) / AIMap.DistanceManhattan(other_tile, front_tile)) == offset) {
				next_tile = other_tile + offset;
			}
			if (next_tile != AIMap.TILE_INVALID) {
				return [next_tile, other_tile];
			}
		} else if (AITunnel.IsTunnelTile(front_tile)) {
			local offset = front_tile - prev_tile;
			local other_tile = AITunnel.GetOtherTunnelEnd(front_tile);
			if (((other_tile - front_tile) / AIMap.DistanceManhattan(other_tile, front_tile)) == offset) {
				next_tile = other_tile + offset;
			}
			if (next_tile != AIMap.TILE_INVALID) {
				return [next_tile, other_tile];
			}
		}
		return null;
	}

	function TrackSignalLength(current)
	{
		if (AIRail.IsRailTile(current[1])) {
			local track = AIRail.GetRailTracks(current[1]);
			switch (track) {
				case AIRail.RAILTRACK_NE_SW:
				case AIRail.RAILTRACK_NW_SE:
					return 2;
				case AIRail.RAILTRACK_NW_NE:
				case AIRail.RAILTRACK_NE_SE:
				case AIRail.RAILTRACK_NW_SW:
				case AIRail.RAILTRACK_SW_SE:
				case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE:
				case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW:
					return 1;
			}
		} else if (AIBridge.IsBridgeTile(current[1])) {
			return (AIMap.DistanceManhattan(current[1], AIBridge.GetOtherBridgeEnd(current[1])) + 1) * 2;
		} else if (AITunnel.IsTunnelTile(current[1])) {
			return (AIMap.DistanceManhattan(current[1], AITunnel.GetOtherTunnelEnd(current[1])) + 1) * 2;
		}
		throw "current[1] " + current[1] + " is neither a rail tile with at most two tracks, a bridge tile nor a tunnel in TrackSignalLength";
	}

	function BuildSignalsInLine(current, length)
	{
		local num_signals = 0;
		local signal_interval = null;
		local signal_cost = 0;
		local current_length = null;
		while (current != null) {
//			AILog.Info("current[0]: " + current[0] + "; current[1]: " + current[1]);
			if (signal_interval != null) {
				current_length = this.TrackSignalLength(current);
				signal_interval += current_length;
			}
			if (signal_interval == null || (signal_interval > length && (current_length != 2 || signal_interval - length != 1))) {
				local bits = Utils.CountBits(AIRail.GetRailTracks(current[1]));
				if (AIRail.IsRailTile(current[1]) && bits >= 1 && bits <= 2 && this.NextTrack(current) != null) {
					local counter = 0;
					do {
						local costs = AIAccounting();
						if (!TestBuildSignal().TryBuild(current[1], current[0], AIRail.SIGNALTYPE_PBS_ONEWAY)) {
							if (AIError.GetLastErrorString() == "ERR_PRECONDITION_FAILED" && AIRail.IsLevelCrossingTile(current[1])) {
								AILog.Warning("Couldn't build rail signal at level crossing tile " + current[1] + " towards " + current[0] + " - " + AIError.GetLastErrorString() + " - Skipping...");
								/* Skip to next */
								break;
							}
							++counter;
						} else {
							signal_cost += costs.GetCosts();
							num_signals++;
//							AILog.Warning("We built a rail signal at tile " + current[1] + " towards " + current[0] + ", ac: " + costs.GetCosts() + ", num_signals: " + num_signals + ", signal_interval: " + signal_interval + ", current_length: " + current_length);
							signal_interval = 0;
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);

					if (counter == 500) {
						AILog.Warning("Couldn't build rail signal at tile " + current[1] + " towards " + current[0] + " - " + AIError.GetLastErrorString());
						return [false, signal_cost];
					}
				}
			}
			current = this.NextTrack(current);
		}

		return [true, signal_cost, num_signals];
	}

	function BuildSignals()
	{
		local station_from = RailStation.CreateFromTile(this.m_station_from, this.m_station_from_dir);
		local station_to = RailStation.CreateFromTile(this.m_station_to, this.m_station_to_dir);
		local plats = RailStationPlatforms(station_from, station_to);
		local length = station_from.m_length * 2;

		local current = [station_to.GetExitTile(plats.m_to2, 1), station_to.GetExitTile(plats.m_to2)];
		local result = this.BuildSignalsInLine(current, length);
		if (!result[0]) {
			return -1;
		}

		local num_signals = result[2];
		local signal_cost = result[1];

		current = [station_from.GetExitTile(plats.m_from1, 1), station_from.GetExitTile(plats.m_from1)];
		result = this.BuildSignalsInLine(current, length);
		if (!result[0]) {
			return -1;
		}

		num_signals += result[2];
		signal_cost += result[1];

		AILog.Info("Signals built! Actual cost for building signals: " + signal_cost);
		this.m_built_ways++;
		return num_signals;
	}

	function SaveBuildManager()
	{
		return [this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile_from, this.m_depot_tile_to, this.m_bridge_tiles, this.m_cargo_class, this.m_rail_type, this.m_best_routes_built, this.m_station_from_dir, this.m_station_to_dir, this.m_built_tiles, this.m_pathfinder_profile, this.m_built_ways];
	}

	function LoadBuildManager(data)
	{
		this.m_city_from = data[0];
		this.m_city_to = data[1];
		this.m_station_from = data[2];
		this.m_station_to = data[3];
		this.m_depot_tile_from = data[4];
		this.m_depot_tile_to = data[5];
		this.m_bridge_tiles = data[6];
		this.m_cargo_class = data[7];
		this.m_rail_type = data[8];
		this.m_best_routes_built = data[9];
		this.m_station_from_dir = data[10];
		this.m_station_to_dir = data[11];
		this.m_built_tiles = data[12];
		this.m_pathfinder_profile = data[13];
		this.m_built_ways = data[14];

		if (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0) {
			/* incomplete route found most likely */
			this.RemoveFailedRouteTracks();
			this.m_built_ways = 0;
		}
	}
};
