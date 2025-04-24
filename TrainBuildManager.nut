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

		local station_tiles = AITileList();
		station_tiles.AddRectangle(this.GetTopTile(), this.GetBottomTile());

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
		foreach (plat in [1, this.m_num_plat]) {
			local entry_tile = this.GetEntryTile(plat);
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

		local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN);
		station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
		local top_tile = station_tiles.Begin();
		station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_DESCENDING);
		local bot_tile = station_tiles.Begin();
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

			local counter = 0;
			do {
				if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
					++counter;
				}
				else {
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
				if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, 2 * exit_tile_1 - entry_tile_1)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track crossing from platform 2 to 1 at tile " + rail_station.GetExitTile(2));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, 2 * exit_tile_1 - entry_tile_1));
//				AILog.Error("Failed to remove rail track crossing from platform 2 to 1 at tile " + rail_station.GetExitTile(2));
			}
			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_2 - entry_tile_2)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track crossing from platform 1 to 2 at tile " + rail_station.GetExitTile(1));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
//				AILog.Error("Failed to remove rail track crossing from platform 1 to 2 at tile " + rail_station.GetExitTile(1));
			}
			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, 2 * exit_tile_2 - entry_tile_2)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track in front of platform 2 at tile " + rail_station.GetExitTile(2));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
//				AILog.Error("Failed to remove rail track in front of platform 2 at tile " + rail_station.GetExitTile(2));
			}
			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_1 - entry_tile_1)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track in front of platform 1 at tile " + rail_station.GetExitTile(1));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
//				AILog.Error("Failed to remove rail track in front of platform 1 at tile " + rail_station.GetExitTile(1));
			}
			if (depot_tile != null) {
				local depotFront = AIRail.GetRailDepotFrontTile(depot_tile);
				local depotRaila = abs(depot_tile - depotFront) == 1 ? depotFront - AIMap.GetMapSizeX() : depotFront - 1;
				local depotRailb = 2 * depotFront - depotRaila;
				local depotRailc = 2 * depotFront - depot_tile;
				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot_tile, depotFront, depotRaila)) {
						++counter;
					}
					else {
//						AILog.Warning("Removed rail track in front of depot towards the station at tile " + depotFront);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduled_removals_table.Train.append(RailStruct.SetRail(depotFront, this.m_rail_type, depot_tile, depotRaila));
//					AILog.Error("Failed to remove rail track in front of depot towards the station at tile " + depotFront);
				}
				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot_tile, depotFront, depotRailb)) {
						++counter;
					}
					else {
//						AILog.Warning("Removed rail track in front of depot towards the railroad at tile " + depotFront);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduled_removals_table.Train.append(RailStruct.SetRail(depotFront, this.m_rail_type, depot_tile, depotRailb));
//					AILog.Error("Failed to remove rail track in front of depot towards the railroad at tile " + depotFront);
				}
				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot_tile, depotFront, depotRailc)) {
						++counter;
					}
					else {
//						AILog.Warning("Removed rail track in front of depot accross the lines at tile " + depotFront);
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduled_removals_table.Train.append(RailStruct.SetRail(depotFront, this.m_rail_type, depot_tile, depotRailc));
//					AILog.Error("Failed to remove rail track in front of depot towards accross the lines at tile " + depotFront);
				}
				local counter = 0;
				do {
					if (!TestDemolishTile().TryDemolish(depot_tile)) {
						++counter;
					}
					else {
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
				local type = i.m_rail_type;
				AIRail.SetCurrentRailType(type);
				if (struct == RailStructType.RAIL) {
					if (AIRail.IsRailTile(tile)) {
						local tile_from = i.m_tile2;
						local tile_to = i.m_tile3;
						if (!TestRemoveRail().TryRemove(tile_from, tile, tile_to)) {
//							AILog.Info("Failed to remove rail at tile " + tile + ", connecting " + tile_from + " to " + tile_to + ".");
							::scheduled_removals_table.Train.append(RailStruct.SetRail(tile, type, tile_from, tile_to));
						}
//					} else {
//						AILog.Info("No rail tile found to remove at tile " + tile + ", connecting " + tile_from + " to " + tile_to + ".");
					}
				} else if (struct == RailStructType.BRIDGE) {
					local tile2 = i.m_tile2;
					if (AIBridge.IsBridgeTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) && AIBridge.GetOtherBridgeEnd(tile) == tile2) {
						if (!TestRemoveBridge().TryRemove(tile)) {
//							AILog.Info("Failed to demolish bridge at tiles " + tile + " and " + tile2 + ".");
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(tile, RailStructType.BRIDGE, type, tile2));
						}
//					} else {
//						AILog.Info("No bridge found to demolish at tiles " + tile + " and " + tile2 + ".");
					}
				} else if (struct == RailStructType.TUNNEL) {
					local tile2 = i.m_tile2;
					if (AITunnel.IsTunnelTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) && AITunnel.GetOtherTunnelEnd(tile) == tile2) {
						if (!TestRemoveTunnel().TryRemove(tile)) {
//							AILog.Info("Failed to demolish tunnel at tiles " + tile + " and " + tile2 + ".");
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(tile, RailStructType.TUNNEL, type, tile2));
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

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_RAIL);
		if (num_vehicles >= AIGameSettings.GetValue("max_trains") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_RAIL)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		if (this.m_station_from == -1) {
			local station_from = this.BuildTownRailStation(this.m_city_from, this.m_cargo_class, this.m_city_to, this.m_best_routes_built, this.m_rail_type);
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
			local station_to = this.BuildTownRailStation(this.m_city_to, this.m_cargo_class, this.m_city_from, this.m_best_routes_built, this.m_rail_type);
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
			local railArray;
			if (this.m_pathfinder_profile == 1) railArray = this.PathfindBuildDoubleRail(this.m_station_from, this.m_station_from_dir, this.m_depot_tile_from, this.m_station_to, this.m_station_to_dir, this.m_depot_tile_to, this.m_pathfinder_profile, false, this.m_pathfinder_instance, this.m_built_tiles);
			if (this.m_pathfinder_profile == 0) railArray = this.PathfindBuildSingleRail(this.m_station_from, this.m_station_from_dir, this.m_depot_tile_from, this.m_station_to, this.m_station_to_dir, this.m_depot_tile_to, this.m_pathfinder_profile, false, this.m_pathfinder_instance, this.m_built_tiles);
			this.m_pathfinder_instance = railArray[1];
			if (railArray[0] == null) {
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

		if (this.m_built_ways == 2) {
			local signals_built = this.BuildSignals(this.m_station_from, this.m_station_from_dir, this.m_station_to, this.m_station_to_dir);
			if (!signals_built) {
				this.RemoveFailedRouteStation(this.m_station_from, this.m_station_from_dir, this.m_depot_tile_from);
				this.RemoveFailedRouteStation(this.m_station_to, this.m_station_to_dir, this.m_depot_tile_to);
				this.RemoveFailedRouteTracks();
				this.SetRouteFinished();
				return null;
			}
		}

		this.m_built_tiles = [[], []];
		return RailRoute(this.m_city_from, this.m_city_to, this.m_station_from, this.m_station_to, this.m_depot_tile_from, this.m_depot_tile_to, this.m_bridge_tiles, this.m_cargo_class, this.m_sent_to_depot_rail_group, this.m_rail_type, this.m_station_from_dir, this.m_station_to_dir);
	}

	function AreOtherRailwayStationsNearby(rail_station)
	{
		local squareSize = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN) * 2;

		local square = AITileList();
		if (!AIController.GetSetting("is_friendly")) {
			squareSize = 2;
			/* don't care about enemy stations when is_friendly is off */
			square.AddRectangle(Utils.GetValidOffsetTile(rail_station.GetTopTile(), -1 * squareSize, -1 * squareSize), Utils.GetValidOffsetTile(rail_station.GetBottomTile(), squareSize, squareSize));

			/* if another railway station of mine is nearby return true */
			for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
				if (AITile.IsStationTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id && AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN)) {
					return true;
				}
			}
		} else {
			square.AddRectangle(Utils.GetValidOffsetTile(rail_station.GetTopTile(), -1 * squareSize, -1 * squareSize), Utils.GetValidOffsetTile(rail_station.GetBottomTile(), squareSize, squareSize));

			/* if any other station is nearby, except my own railway stations, return true */
			for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
				if (AITile.IsStationTile(tile)) {
					if (AITile.GetOwner(tile) != ::caches.m_my_company_id) {
						return true;
					} else {
						local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN);
						if (station_tiles.HasItem(tile)) {
							return true;
						}
					}
				}
			}
		}
	}

	function ExpandAdjacentRailwayStationRect(rail_station)
	{
		local spread_rad = AIGameSettings.GetValue("station_spread");

		local remaining_x = spread_rad - rail_station.m_width;
		local remaining_y = spread_rad - rail_station.m_height;

		local tile_top_x = AIMap.GetTileX(rail_station.GetTopTile());
		local tile_top_y = AIMap.GetTileY(rail_station.GetTopTile());
		local tile_bot_x = AIMap.GetTileX(rail_station.GetBottomTile());
		local tile_bot_y = AIMap.GetTileY(rail_station.GetBottomTile());

		for (local x = remaining_x; x > 0; x--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_top_x - 1, tile_top_y))) {
				tile_top_x = tile_top_x - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_bot_x + 1, tile_bot_y))) {
				tile_bot_x = tile_bot_x + 1;
			}
		}

		for (local y = remaining_y; y > 0; y--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_top_x, tile_top_y - 1))) {
				tile_top_y = tile_top_y - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(tile_bot_x, tile_bot_y + 1))) {
				tile_bot_y = tile_bot_y + 1;
			}
		}

//		AILog.Info("spreadrectangle top = " + tile_top_x + "," + tile_top_y + " ; spreadrectangle bottom = " + tile_bot_x + "," + tile_bot_y);
		return [AIMap.GetTileIndex(tile_top_x, tile_top_y), AIMap.GetTileIndex(tile_bot_x, tile_bot_y)];
	}

	function TownRailwayStationRadRect(max_width, max_height, radius, town_id)
	{
		local town_rectangle = Utils.EstimateTownRectangle(town_id);

		local top_x = AIMap.GetTileX(town_rectangle[0]);
		local top_y = AIMap.GetTileY(town_rectangle[0]);
		local bot_x = AIMap.GetTileX(town_rectangle[1]);
		local bot_y = AIMap.GetTileY(town_rectangle[1]);
//		AILog.Info("top tile was " + top_x + "," + top_y + " bottom tile was " + bot_x + "," + bot_y + " ; town_id = " + AITown.GetName(town_id));

		for (local x = max_width; x > 1; x--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(top_x - 1, top_y))) {
				top_x = top_x - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(bot_x + 1, bot_y))) {
				bot_x = bot_x + 1;
			}
		}

		for (local y = max_height; y > 1; y--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(top_x, top_y - 1))) {
				top_y = top_y - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(bot_x, bot_y + 1))) {
				bot_y = bot_y + 1;
			}
		}

		for (local r = radius; r > 0; r--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(top_x - 1, top_y))) {
				top_x = top_x - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(top_x, top_y - 1))) {
				top_y = top_y - 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(bot_x + 1, bot_y))) {
				bot_x = bot_x + 1;
			}
			if (AIMap.IsValidTile(AIMap.GetTileIndex(bot_x, bot_y + 1))) {
				bot_y = bot_y + 1;
			}
		}
//		AILog.Info("top tile now " + top_x + "," + top_y + " bottom tile now " + bot_x + "," + bot_y + " ; town_id = " + AITown.GetName(town_id));
		return [AIMap.GetTileIndex(top_x, top_y), AIMap.GetTileIndex(bot_x, bot_y)];
	}

	function CheckAdjacentNonRailwayStation(rail_station)
	{
		if (!AIController.GetSetting("station_spread") || !AIGameSettings.GetValue("distant_join_stations")) {
			return AIStation.STATION_NEW;
		}

		local tileList = AITileList();
		local spreadrectangle = this.ExpandAdjacentRailwayStationRect(rail_station);
		tileList.AddRectangle(spreadrectangle[0], spreadrectangle[1]);

		local templist = AITileList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (Utils.IsTileMyStationWithoutRailwayStation(tile)) {
				tileList.SetValue(tile, AIStation.GetStationID(tile));
			} else {
				templist.AddTile(tile);
			}
		}
		tileList.RemoveList(templist);

		local station_list = AIList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tileList.Next()) {
			station_list.AddItem(tileList.GetValue(tile), AIMap.DistanceManhattan(tile, rail_station.GetTopTile()));
		}

		local spreadrectangle_top_x = AIMap.GetTileX(spreadrectangle[0]);
		local spreadrectangle_top_y = AIMap.GetTileY(spreadrectangle[0]);
		local spreadrectangle_bot_x = AIMap.GetTileX(spreadrectangle[1]);
		local spreadrectangle_bot_y = AIMap.GetTileY(spreadrectangle[1]);

		local list = AIList();
		list.AddList(station_list);
		for (local stationId = station_list.Begin(); !station_list.IsEnd(); stationId = station_list.Next()) {
			local station_tiles = AITileList_StationType(stationId, AIStation.STATION_ANY);
			local station_top_x = AIMap.GetTileX(AIBaseStation.GetLocation(stationId));
			local station_top_y = AIMap.GetTileY(AIBaseStation.GetLocation(stationId));
			local station_bot_x = station_top_x;
			local station_bot_y = station_top_y;
			for (local tile = station_tiles.Begin(); !station_tiles.IsEnd(); tile = station_tiles.Next()) {
				local tile_x = AIMap.GetTileX(tile);
				local tile_y = AIMap.GetTileY(tile);
				if (tile_x < station_top_x) {
					station_top_x = tile_x;
				}
				if (tile_x > station_bot_x) {
					station_bot_x = tile_x;
				}
				if (tile_y < station_top_y) {
					station_top_y = tile_y;
				}
				if (tile_y > station_bot_y) {
					station_bot_y = tile_y;
				}
			}

			if (spreadrectangle_top_x > station_top_x ||
				spreadrectangle_top_y > station_top_y ||
				spreadrectangle_bot_x < station_bot_x ||
				spreadrectangle_bot_y < station_bot_y) {
				list.RemoveItem(stationId);
			}
		}
		list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		local adjacentStation = AIStation.STATION_NEW;
		if (!list.IsEmpty()) {
			adjacentStation = list.Begin();
//			AILog.Info("adjacentStation = " + AIStation.GetName(adjacentStation) + " ; rail_station.GetTopTile() = " + AIMap.GetTileX(rail_station.GetTopTile()) + "," + AIMap.GetTileY(rail_station.GetTopTile()));
		}

		return adjacentStation;
	}

	function WorstStationOrientations(rail_station, station_tiles, town_id, otherTown)
	{
		local shortest_dist_other_town = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();

		for (local plat = 1; plat <= rail_station.m_num_plat; plat++) {
			local dist_other_town = AITown.GetDistanceManhattanToTile(otherTown, rail_station.GetEntryTile(plat));
			if (dist_other_town < shortest_dist_other_town) {
				shortest_dist_other_town = dist_other_town;
			}
		}

		local best_tile = AIMap.TILE_INVALID;
		local shortest_dist_town = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();

		foreach (tile, _ in station_tiles) {
			local dist_town = AITown.GetDistanceManhattanToTile(town_id, tile);
			if (dist_town < shortest_dist_town) {
				shortest_dist_town = dist_town;
				best_tile = tile;
			}
		}

		local worst_dirs = AIList();
		local diff_x = AIMap.GetTileX(AITown.GetLocation(town_id)) - AIMap.GetTileX(best_tile);
		local diff_y = AIMap.GetTileY(AITown.GetLocation(town_id)) - AIMap.GetTileY(best_tile);

		if (diff_x < 0) worst_dirs.AddItem(RailStationDir.NE, 0);
		if (diff_y < 0) worst_dirs.AddItem(RailStationDir.NW, 0);
		if (diff_x > 0) worst_dirs.AddItem(RailStationDir.SW, 0);
		if (diff_y > 0) worst_dirs.AddItem(RailStationDir.SE, 0);

		return [worst_dirs, shortest_dist_town, shortest_dist_other_town];
	}

	function BuildTownRailStation(town_id, cargo_class, otherTown, best_routes_built, rail_type)
	{
		AIRail.SetCurrentRailType(rail_type);
		local cargoType = Utils.GetCargoType(cargo_class);
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local pick_mode = AIController.GetSetting("pick_mode");
		local max_station_spread = AIGameSettings.GetValue("station_spread");
		local max_train_length = AIGameSettings.GetValue("max_train_length");
		local platform_length = min(RailRoute.MAX_PLATFORM_LENGTH, min(max_station_spread, max_train_length));
		local num_platforms = RailRoute.MAX_NUM_PLATFORMS;
		local distance_between_towns = AIMap.DistanceSquare(AITown.GetLocation(town_id), AITown.GetLocation(otherTown));

		local tileList = AITileList();
		/* build square around @town_id and find suitable tiles for railway station */
		local rectangleCoordinates = this.TownRailwayStationRadRect(max(platform_length, num_platforms), max(platform_length, num_platforms), radius, town_id);

		tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);
//		AISign.BuildSign(rectangleCoordinates[0], AITown.GetName(town_id));
//		AISign.BuildSign(rectangleCoordinates[1], AITown.GetName(town_id));

		local stations = AIPriorityQueue();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			foreach (dir in [RailStationDir.NE, RailStationDir.SW, RailStationDir.NW, RailStationDir.SE]) {
				local rail_station = RailStation(tile, dir, num_platforms, platform_length);
				local station_tiles = AITileList();
				station_tiles.AddRectangle(rail_station.GetTopTile(), rail_station.GetBottomTile());

				local worst_dirs = this.WorstStationOrientations(rail_station, station_tiles, town_id, otherTown);
				if (worst_dirs[0].HasItem(dir)) continue;

				local in_range = true;
				foreach (station_tile, _ in station_tiles) {
					if (!tileList.HasItem(station_tile)) {
						in_range = false;
						break;
					}
					local dist_to_town = AITown.GetDistanceSquareToTile(town_id, station_tile);
					local dist_to_otherTown = AITown.GetDistanceSquareToTile(otherTown, station_tile);
					local farthest_town = dist_to_town < dist_to_otherTown ? otherTown : town_id;
					if (AITown.GetDistanceSquareToTile(farthest_town, station_tile) >= distance_between_towns) {
						in_range = false;
						break;
					}
//					else {
//						AISign.BuildSign(station_tile, "x");
//					}
				}
				if (!in_range) continue;

				local rectangle = rail_station.GetValidRectangle(4); // 4 tiles free
				if (rectangle == null) continue;

				if (AITile.IsBuildableRectangle(rectangle[0], rectangle[1], rectangle[2])) {
					local depot_tile_1 = rail_station.GetExitTile(1) + rail_station.GetExitTile(1) - rail_station.GetExitTile(2);
					local depot_tile_2 = rail_station.GetExitTile(2) + rail_station.GetExitTile(2) - rail_station.GetExitTile(1);
					if (!AITile.IsBuildable(depot_tile_1) && !AITile.IsBuildable(depot_tile_2)) continue;
					local exit_turn_a_1 = depot_tile_1 + (rail_station.GetExitTile(1) - rail_station.GetEntryTile(1)) * 2;
					local exit_turn_a_2 = depot_tile_1 + (rail_station.GetExitTile(1) - rail_station.GetEntryTile(1)) * 3;
					local exit_turn_b_1 = depot_tile_2 + (rail_station.GetExitTile(2) - rail_station.GetEntryTile(2)) * 3;
					local exit_turn_b_2 = depot_tile_2 + (rail_station.GetExitTile(2) - rail_station.GetEntryTile(2)) * 2;
					local exit_front_a_1 = exit_turn_a_2;
					local exit_front_a_2 = rail_station.GetExitTile(1) + (rail_station.GetExitTile(1) - rail_station.GetEntryTile(1)) * 3;
					local exit_front_b_1 = rail_station.GetExitTile(2) + (rail_station.GetExitTile(2) - rail_station.GetEntryTile(2)) * 3;
					local exit_front_b_2 = exit_turn_b_1;
					if (!(AITile.IsBuildable(exit_turn_a_1) && AITile.IsBuildable(exit_turn_a_2)) &&
							!(AITile.IsBuildable(exit_turn_b_1) && AITile.IsBuildable(exit_turn_b_2)) &&
							!(AITile.IsBuildable(exit_front_a_1) && AITile.IsBuildable(exit_front_a_2)) &&
							!(AITile.IsBuildable(exit_front_b_1) && AITile.IsBuildable(exit_front_b_2))) {
						continue;
					}

					if (AITile.GetCargoAcceptance(tile, cargoType, rail_station.m_width, rail_station.m_height, radius) >= 8) {
						if (!this.AreOtherRailwayStationsNearby(rail_station)) {
							local cargo_production = AITile.GetCargoProduction(tile, cargoType, rail_station.m_width, rail_station.m_height, radius);
							if (pick_mode == 1 || best_routes_built || cargo_production >= 8) {
								/* store as negative to make priority queue prioritize highest values */
								stations.Insert(rail_station, -((cargo_production << 26) | ((0x1FFF - worst_dirs[1]) << 13) | (0x1FFF - worst_dirs[2])));
							}
						}
					}
				}
			}
		}

		while (!stations.IsEmpty()) {
			local rail_station = stations.Pop();
			local top_tile = rail_station.GetTopTile();
			local bot_tile = rail_station.GetBottomTile();
			local entry_tile_2 = rail_station.GetEntryTile(2);
			local exit_tile_2 = rail_station.GetExitTile(2);
			local exit_tile_1 = rail_station.GetExitTile(1);
			local entry_tile_1 = rail_station.GetEntryTile(1);
			if (AITile.GetClosestTown(rail_station.GetTopTile()) != town_id) continue;

			/* get adjacent tiles */
			local station_tiles = AITileList();
			station_tiles.AddRectangle(top_tile, bot_tile);
			local adjTileList = AITileList();
			adjTileList.AddList(station_tiles);

			foreach (tile in adjTileList) {
				local adjTileList2 = Utils.GetAdjacentTiles(tile);
				foreach (tile2 in adjTileList2) {
					adjTileList.AddTile(tile2);
				}
			}
			adjTileList.RemoveRectangle(top_tile, bot_tile);

			local adjacentNonRailwayStation = this.CheckAdjacentNonRailwayStation(rail_station);

			/* avoid blocking other station exits */
			local blocking = false;
			foreach (adjTile in adjTileList) {
				if (AITile.IsStationTile(adjTile) && AITile.HasTransportType(adjTile, AITile.TRANSPORT_ROAD)) {
					foreach (roadtype, _ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD | AIRoad.ROADTRAMTYPES_TRAM)) {
						if (AIRoad.HasRoadType(adjTile, roadtype)) {
							SetCurrentRoadType(roadtype);
							if (AIRoad.IsRoadStationTile(adjTile) && rail_station.tiles.HasTile(AIRoad.GetRoadStationFrontTile(adjTile))) {
								blocking = true;
								break;
							}
						}
					}
					if (blocking) break;
				}
			}

			if (blocking) {
				continue;
			}

			local counter = 0;
			do {
				if (!TestBuildRailStation().TryBuild(top_tile, rail_station.GetTrackDirection(), rail_station.m_num_plat, rail_station.m_length, adjacentNonRailwayStation)) {
					++counter;
				}
				else {
//					AILog.Info("station built");
					break;
				}
				AIController.Sleep(1);
			} while (counter < 1);
			if (counter == 1) {
				continue;
			}
			else {
				/* Built rail station. Now build track infront of platform 1 */
				local counter = 0;
				do {
					if (!AIRoad.IsRoadTile(exit_tile_1) && !TestBuildRail().TryBuild(entry_tile_1, exit_tile_1, 2 * exit_tile_1 - entry_tile_1)) {
						++counter;
					}
					else {
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
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);
					if (counter == 1) {
						::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
						continue;
					}
				}
				else {
					/* Built track in front of platform 1. Now build track in front of platform 2 */
					local counter = 0;
					do {
						if (!AIRoad.IsRoadTile(rail_station.GetExitTile(2)) && !TestBuildRail().TryBuild(rail_station.GetEntryTile(2), rail_station.GetExitTile(2), rail_station.GetExitTile(2) - rail_station.GetEntryTile(2) + rail_station.GetExitTile(2))) {
							++counter;
						}
						else {
//							AILog.Info("built track infront of platform 2");
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);
					if (counter == 1) {
						local counter = 0;
						do {
							if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_1 - entry_tile_1)) {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);
						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
						}
						local counter = 0;
						do {
							if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);
						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
							continue;
						}
					}
					else {
						/* Built track in front of platform 2. Now build track crossing from platform 1 to 2 */
						local counter = 0;
						do {
							if (!TestBuildRail().TryBuild(entry_tile_1, exit_tile_1, 2 * exit_tile_2 - entry_tile_2)) {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);
						if (counter == 1) {
							local counter = 0;
							do {
								if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, 2 * exit_tile_2 - entry_tile_2)) {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);
							if (counter == 1) {
								::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
							}
							local counter = 0;
							do {
								if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_1 - entry_tile_1)) {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);
							if (counter == 1) {
								::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
							}
							local counter = 0;
							do {
								if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);
							if (counter == 1) {
								::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
								continue;
							}
						}
						else {
							/* Built track crossing from platform 1 to 2. Now build track crossing from platform 2 to 1 */
							local counter = 0;
							do {
								if (!TestBuildRail().TryBuild(entry_tile_2, exit_tile_2, 2 * exit_tile_1 - entry_tile_1)) {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);
							if (counter == 1) {
								local counter = 0;
								do {
									if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_2 - entry_tile_2)) {
										++counter;
									}
									else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);
								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
								}
								local counter = 0;
								do {
									if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, 2 * exit_tile_2 - entry_tile_2)) {
										++counter;
									}
									else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);
								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_2, this.m_rail_type, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
								}
								local counter = 0;
								do {
									if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_1 - entry_tile_1)) {
										++counter;
									}
									else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);
								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetRail(exit_tile_1, this.m_rail_type, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
								}
								local counter = 0;
								do {
									if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
										++counter;
									}
									else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < 1);
								if (counter == 1) {
									::scheduled_removals_table.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, this.m_rail_type, bot_tile));
									continue;
								}
							}
							else {
								AILog.Info("Railway station built in " + AITown.GetName(town_id) + " at tile " + top_tile + "!");
								return [top_tile, rail_station.m_dir];
							}
						}
					}
				}
			}
		}

		return null;
	}

	/* find rail way between tileFrom and tileTo */
	function PathfindBuildSingleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode = false, pathfinder = null, builtTiles = [[], []], cost_so_far = 0)
	{
		/* can store rail tiles into array */

		if (tileFrom != tileTo) {
			local route_dist = AIMap.DistanceManhattan(AITown.GetLocation(this.m_city_from), AITown.GetLocation(this.m_city_to));
			local max_pathfinderTries = 300 * route_dist;

			/* Print the names of the towns we'll try to connect. */
			if (!silent_mode) AILog.Info("t:Connecting " + AITown.GetName(this.m_city_from) + " (tile " + tileFrom + ") and " + AITown.GetName(this.m_city_to) + " (tile " + tileTo + ") (iteration " + (this.m_pathfinder_tries + 1) + "/" + max_pathfinderTries + ")");

			/* Tell OpenTTD we want to build this rail_type. */
			AIRail.SetCurrentRailType(this.m_rail_type);

			if (pathfinder == null) {
				/* Create an instance of the pathfinder. */
				pathfinder = SingleRail();

				AILog.Info("rail pathfinder: " + (pathfinderProfile == 0 ? "single rail" : "double rail"));
/*defaults*/
/*10000000*/	pathfinder.cost.max_cost;
/*100*/			pathfinder.cost.tile;
/*70*/			pathfinder.cost.diagonal_tile;
/*50*/			pathfinder.cost.turn45 = 190;
/*300*/			pathfinder.cost.turn90 = AIGameSettings.GetValue("forbid_90_deg") ? pathfinder.cost.max_cost : pathfinder.cost.turn90;
/*250*/			pathfinder.cost.consecutive_turn = 460;
/*100*/			pathfinder.cost.slope = AIGameSettings.GetValue("train_acceleration_model") ? AIGameSettings.GetValue("train_slope_steepness") * 20 : pathfinder.cost.slope;
/*400*/			pathfinder.cost.consecutive_slope;
/*150*/			pathfinder.cost.bridge_per_tile = 225;
/*120*/			pathfinder.cost.tunnel_per_tile;
/*20*/			pathfinder.cost.coast = (AICompany.GetLoanAmount() == 0) ? pathfinder.cost.coast : 5000;
/*900*/			pathfinder.cost.level_crossing = pathfinder.cost.max_cost;
/*6*/			pathfinder.cost.max_bridge_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*6*/			pathfinder.cost.max_tunnel_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
/*1*/			pathfinder.cost.estimate_multiplier = 3;
/*0*/			pathfinder.cost.search_range = max(route_dist / 15, 25);

				/* Give the source and goal tiles to the pathfinder. */
				local station_from = RailStation.CreateFromTile(tileFrom, station_from_dir);
				local station_to = RailStation.CreateFromTile(tileTo, station_to_dir);
				local plats = RailStationPlatforms(station_from, station_to);

				local stationFromExit1 = station_from.GetExitTile(plats.m_from1, 1);
				local stationToExit1 = station_to.GetExitTile(plats.m_to1, 1);

				/* SingleRail */
				if (this.m_built_ways == 0) {
					local stationFromEntryBefore2 = station_from.GetEntryTile(plats.m_from2);
					local stationFromEntry2 = station_from.GetExitTile(plats.m_from2);
					if (AIRail.GetRailDepotFrontTile(depot_tile_from) == stationFromEntry2) stationFromEntryBefore2 = depot_tile_from;
					local stationFromExit2 = station_from.GetExitTile(plats.m_from2, 1);
					local stationToEntryBefore2 = station_to.GetEntryTile(plats.m_to2);
					local stationToEntry2 = station_to.GetExitTile(plats.m_to2);
					if (AIRail.GetRailDepotFrontTile(depot_tile_to) == stationToEntry2) stationToEntryBefore2 = depot_tile_to;
					local stationToExit2 = station_to.GetExitTile(plats.m_to2, 1);
					local ignore_tiles = [stationFromExit1, stationToExit1];
					if (AIRail.GetRailDepotFrontTile(depot_tile_from) == stationFromEntry2) {
						ignore_tiles.push(stationFromExit2 - stationFromExit1 + stationFromExit2);
					} else {
						ignore_tiles.push(station_from.GetExitTile(plats.m_from1, 2));
						ignore_tiles.push(stationFromExit1 - stationFromExit2 + stationFromExit1);
					}
					if (AIRail.GetRailDepotFrontTile(depot_tile_to) == stationToEntry2) {
						ignore_tiles.push(stationToExit2 - stationToExit1 + stationToExit2);
					} else {
						ignore_tiles.push(station_to.GetExitTile(plats.m_to1, 2));
						ignore_tiles.push(stationToExit1 - stationToExit2 + stationToExit1);
					}
//					local ignore_tiles_text = "ignore_tiles = ";
//					foreach (tile in ignore_tiles) {
//						ignore_tiles_text += tile + "; ";
//					}
//					AILog.Info("stationFromExit2 = " + stationFromExit2 + "; stationFromEntry2 = " + stationFromEntry2 + "; stationFromEntryBefore2 = " + stationFromEntryBefore2);
//					AILog.Info("stationToExit2 = " + stationToExit2 + "; stationToEntry2 = " + stationToEntry2 + "; stationToEntryBefore2 = " + stationToEntryBefore2);
//					AILog.Info(ignore_tiles_text);
					pathfinder.InitializePath(
						[[stationFromExit2, stationFromEntry2, stationFromEntryBefore2]],
						[[stationToExit2, stationToEntry2, stationToEntryBefore2]],
						ignore_tiles
					);
				} else if (this.m_built_ways == 1) {
					local stationFromEntryBefore1 = station_from.GetEntryTile(plats.m_from1);
					local stationFromEntry1 = station_from.GetExitTile(plats.m_from1);
					if (AIRail.GetRailDepotFrontTile(depot_tile_from) == stationFromEntry1) stationFromEntryBefore1 = depot_tile_from;
					local stationToEntryBefore1 = station_to.GetEntryTile(plats.m_to1);
					local stationToEntry1 = station_to.GetExitTile(plats.m_to1);
					if (AIRail.GetRailDepotFrontTile(depot_tile_to) == stationToEntry1) stationToEntryBefore1 = depot_tile_to;
//					AILog.Info("stationToExit1 = " + stationToExit1 + "; stationToEntry1 = " + stationToEntry1 + "; stationToEntryBefore1 = " + stationToEntryBefore1);
//					AILog.Info("stationFromExit1 = " + stationFromExit1 + "; stationFromEntry1 = " + stationFromEntry1 + "; stationFromEntryBefore1 = " + stationFromEntryBefore1);
					pathfinder.InitializePath(
						[[stationToExit1, stationToEntry1, stationToEntryBefore1]],
						[[stationFromExit1, stationFromEntry1, stationFromEntryBefore1]]
					);
				}
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
//							if (!silent_mode) AILog.Info("rail pathfinder: FindPath iterated: " + count);
//							local sign_list = AISignList();
//							foreach (sign, _ in sign_list) {
//								if (sign_list.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder];
						}
					} else {
						/* Timed out */
						if (!silent_mode) AILog.Error("rail pathfinder: FindPath return false (timed out)");
						this.m_pathfinder_tries = 0;
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					if (!silent_mode) AILog.Error("rail pathfinder: FindPath return null (no path)");
					this.m_pathfinder_tries = 0;
					return [null, null];
				}
			} while (path == false);

//			if (!silent_mode && this.m_pathfinder_tries != count) AILog.Info("rail pathfinder: FindPath iterated: " + count);
			if (!silent_mode) AILog.Info("Rail path found! FindPath iterated: " + this.m_pathfinder_tries + ". Building track... ");
			if (!silent_mode) AILog.Info("rail pathfinder: FindPath cost: " + path.GetCost());

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
										if (this.m_pathfinder_tries < max_pathfinderTries && this.m_built_tiles[this.m_built_ways] != 0) {
											/* Remove everything and try again */
											if (!silent_mode) AILog.Warning("Couldn't build rail tunnel at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
											this.RemoveFailedRouteTracks();
											return PathfindBuildSingleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
										}
									}
									++counter;
								}
								else {
									track_cost += costs.GetCosts();
//									if (!silent_mode) AILog.Warning("We built a rail tunnel at tiles " + prev + " and " + cur + ", ac: " + costs.GetCosts());
									this.m_built_tiles[this.m_built_ways].append(RailStruct.SetStruct(prev, RailStructType.TUNNEL, this.m_rail_type, cur));
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								if (!silent_mode) AILog.Warning("Couldn't build rail tunnel at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString());
//								AIController.Break("");
								this.m_pathfinder_tries = 0;
								return [null, null];
							}
						}
						else {
							local bridge_length = distance + 1;
							local bridge_list = AIBridgeList_Length(bridge_length);
							for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
								bridge_list.SetValue(bridge, AIBridge.GetMaxSpeed(bridge));
							}
							bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (!TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, bridge_list.Begin(), prev, cur)) {
									if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
										for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
											bridge_list.SetValue(bridge, AIBridge.GetPrice(bridge, bridge_length));
										}
										bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
									}
									else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_BRIDGE_HEADS_NOT_ON_SAME_HEIGHT" || AIError.GetLastErrorString() == "ERR_TUNNEL_CANNOT_BUILD_ON_WATER") {
										if (this.m_pathfinder_tries < max_pathfinderTries && this.m_built_tiles[this.m_built_ways].len() != 0) {
											/* Remove everything and try again */
											if (!silent_mode) AILog.Warning("Couldn't build rail bridge at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
											this.RemoveFailedRouteTracks(this.m_built_ways);
											return this.PathfindBuildSingleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
										}
									}
									++counter;
								}
								else {
									track_cost += costs.GetCosts();
//									if (!silent_mode) AILog.Warning("We built a rail bridge at tiles " + prev + " and " + cur + ", ac: " + costs.GetCosts());
									this.m_built_tiles[this.m_built_ways].append(RailStruct.SetStruct(prev, RailStructType.BRIDGE, this.m_rail_type, cur));
									this.m_bridge_tiles.append(prev < cur ? [prev, cur] : [cur, prev]);
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								if (!silent_mode) AILog.Warning("Couldn't build rail bridge at tiles " + prev + " and " + cur + " - " + AIError.GetLastErrorString());
//								AIController.Break("");
								this.m_pathfinder_tries = 0;
								return [null, null];
							}
						}
					}
					else if (prevprev != null && AIMap.DistanceManhattan(prevprev, prev) == 1) {
						if (!AIRoad.IsRoadTile(prev) || (AITestMode() && !AIRail.BuildRail(prevprev, prev, cur))) {
							local counter = 0;
							do {
								local costs = AIAccounting();
								if (!TestBuildRail().TryBuild(prevprev, prev, cur)) {
									if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT") {
//										if (!silent_mode) AILog.Warning("We found a rail track already built at tile " + prev + ", connecting " + prevprev + " to " + cur);
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_TUNNEL_CANNOT_BUILD_ON_WATER" || AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG") {
										if (this.m_pathfinder_tries < max_pathfinderTries && this.m_built_tiles[this.m_built_ways].len() != 0) {
											/* Remove everything and try again */
											if (!silent_mode) AILog.Warning("Couldn't build rail track at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
											this.RemoveFailedRouteTracks(this.m_built_ways);
											return this.PathfindBuildSingleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
										}
									}
									++counter;
								}
								else {
									track_cost += costs.GetCosts();
//									if (!silent_mode) AILog.Warning("We built a rail track at tile " + prev + ", connecting " + prevprev + " to " + cur + ", ac: " + costs.GetCosts());
									this.m_built_tiles[this.m_built_ways].append(RailStruct.SetRail(prev, this.m_rail_type, prevprev, cur));
									break;
								}
								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								if (!silent_mode) AILog.Warning("Couldn't build rail track at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString());
//								AIController.Break("");
								this.m_pathfinder_tries = 0;
								return [null, null];
							}
						}
						else if (this.m_pathfinder_tries < max_pathfinderTries && this.m_built_tiles[this.m_built_ways].len() != 0) {
							if (!silent_mode) AILog.Warning("Won't build a rail crossing a road at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString() + " - Retrying...");
							this.RemoveFailedRouteTracks(this.m_built_ways);
							return this.PathfindBuildSingleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
						}
						else {
							if (!silent_mode) AILog.Warning("Won't build a rail crossing a road at tile " + prev + ", connecting " + prevprev + " to " + cur + " - " + AIError.GetLastErrorString());
							this.m_pathfinder_tries = 0;
							return [null, null];
						}
					}
				}
			}

			if (!silent_mode) AILog.Info("Track built! Actual cost for building track: " + track_cost);
		}

		this.m_pathfinder_tries = 0;
		this.m_built_ways++;
		return [builtTiles, null];
	}

	/* find rail way between tileFrom and tileTo */
	function PathfindBuildDoubleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode = false, pathfinder = null, builtTiles = [[], []], cost_so_far = 0)
	{
		/* can store rail tiles into array */

		if (tileFrom != tileTo) {
			local route_dist = AIMap.DistanceManhattan(AITown.GetLocation(this.m_city_from), AITown.GetLocation(this.m_city_to));
			local max_pathfinderTries = 100 * route_dist;

			/* Print the names of the towns we'll try to connect. */
			if (!silent_mode) AILog.Info("t:Connecting " + AITown.GetName(this.m_city_from) + " (tile " + tileFrom + ") and " + AITown.GetName(this.m_city_to) + " (tile " + tileTo + ") (iteration " + (this.m_pathfinder_tries + 1) + "/" + max_pathfinderTries + ")");

			/* Tell OpenTTD we want to build this rail_type. */
			AIRail.SetCurrentRailType(this.m_rail_type);

			if (pathfinder == null) {
				/* Create an instance of the pathfinder. */
				pathfinder = DoubleRail();

				AILog.Info("rail pathfinder: " + (pathfinderProfile == 0 ? "single rail" : "double rail"));
/*defaults*/
/*10000000*/	pathfinder.cost.max_cost;
/*100*/			pathfinder.cost.tile;
/*70*/			pathfinder.cost.diagonal_tile;
/*50*/			pathfinder.cost.turn45 = 190;
/*300*/			pathfinder.cost.turn90 = AIGameSettings.GetValue("forbid_90_deg") ? pathfinder.cost.max_cost : pathfinder.cost.turn90;
/*250*/			pathfinder.cost.consecutive_turn = 460;
/*100*/			pathfinder.cost.slope = AIGameSettings.GetValue("train_acceleration_model") ? AIGameSettings.GetValue("train_slope_steepness") * 20 : pathfinder.cost.slope;
/*400*/			pathfinder.cost.consecutive_slope;
/*150*/			pathfinder.cost.bridge_per_tile = 225;
/*120*/			pathfinder.cost.tunnel_per_tile;
/*20*/			pathfinder.cost.coast = (AICompany.GetLoanAmount() == 0) ? pathfinder.cost.coast : 5000;
/*900*/			pathfinder.cost.level_crossing = pathfinder.cost.max_cost;
/*6*/			pathfinder.cost.max_bridge_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*6*/			pathfinder.cost.max_tunnel_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
/*1*/			pathfinder.cost.estimate_multiplier = 3;
/*0*/			pathfinder.cost.search_range = max(route_dist / 15, 25);

				/* Give the source and goal tiles to the pathfinder. */
				local station_from = RailStation.CreateFromTile(tileFrom, station_from_dir);
				local station_to = RailStation.CreateFromTile(tileTo, station_to_dir);
				local plats = RailStationPlatforms(station_from, station_to);

				local stationFromEntry1 = station_from.GetExitTile(plats.m_from1);
				local stationFromExit1 = station_from.GetExitTile(plats.m_from1, 1);
				local stationToEntry1 = station_to.GetExitTile(plats.m_to1);
				local stationToExit1 = station_to.GetExitTile(plats.m_to1, 1);
				local stationFromEntry2 = station_from.GetExitTile(plats.m_from2);
				local stationFromExit2 = station_from.GetExitTile(plats.m_from2, 1);
				local stationToEntry2 = station_to.GetExitTile(plats.m_to2);
				local stationToExit2 = station_to.GetExitTile(plats.m_to2, 1);
				local ignore_tiles = [];
//				if (AIRail.GetRailDepotFrontTile(depot_tile_from) == stationFromEntry2) {
					ignore_tiles.push(stationFromExit2 - stationFromExit1 + stationFromExit2);
//				} else {
					ignore_tiles.push(stationFromExit1 - stationFromExit2 + stationFromExit1);
//				}
//				if (AIRail.GetRailDepotFrontTile(depot_tile_to) == stationToEntry2) {
					ignore_tiles.push(stationToExit2 - stationToExit1 + stationToExit2);
//				} else {
					ignore_tiles.push(stationToExit1 - stationToExit2 + stationToExit1);
//				}
//				local ignore_tiles_text = "ignore_tiles = ";
//				foreach (tile in ignore_tiles) {
//					ignore_tiles_text += tile + "; ";
//				}

				/* DoubleRail */
//				AILog.Info("stationFromEntry1 = " + stationFromEntry1 + "; stationFromExit1 = " + stationFromExit1 + "; stationToEntry1 = " + stationToEntry1 + "; stationToExit1 = " + stationToExit1);
//				AILog.Info("stationFromEntry2 = " + stationFromEntry2 + "; stationFromExit2 = " + stationFromExit2 + "; stationToEntry2 = " + stationToEntry2 + "; stationToExit2 = " + stationToExit2);
//				AILog.Info(ignore_tiles_text);
				pathfinder.InitializePath(
					[[stationFromEntry1, stationFromExit1], [stationFromEntry2, stationFromExit2]],
					[[stationToExit1, stationToEntry1], [stationToExit2, stationToEntry2]],
					ignore_tiles
				);
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
//							if (!silent_mode) AILog.Info("rail pathfinder: FindPath iterated: " + count);
//							local sign_list = AISignList();
//							foreach (sign, _ in sign_list) {
//								if (sign_list.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder];
						}
					} else {
						/* Timed out */
						if (!silent_mode) AILog.Error("rail pathfinder: FindPath return false (timed out)");
						this.m_pathfinder_tries = 0;
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					if (!silent_mode) AILog.Error("rail pathfinder: FindPath return null (no path)");
					this.m_pathfinder_tries = 0;
					return [null, null];
				}
			} while (path == false);

//			if (!silent_mode && this.m_pathfinder_tries != count) AILog.Info("rail pathfinder: FindPath iterated: " + count);
			if (!silent_mode) AILog.Info("Rail path found! FindPath iterated: " + this.m_pathfinder_tries + ". Building track... ");
			if (!silent_mode) AILog.Info("rail pathfinder: FindPath cost: " + path.GetCost());

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
												if (this.m_pathfinder_tries < max_pathfinderTries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
													if (!silent_mode) AILog.Warning("Couldn't build rail tunnel at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
													/* Remove everything and try again */
													this.RemoveFailedRouteTracks();
													return this.PathfindBuildDoubleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
												}
											}
											++counter;
										}
										else {
											track_cost += costs.GetCosts();
//											if (!silent_mode) AILog.Warning("We built a rail tunnel at tiles " + next[j] + " and " + scan_tile[j] + ", ac: " + costs.GetCosts());
											this.m_built_tiles[j].append(RailStruct.SetStruct(next[j], RailStructType.TUNNEL, this.m_rail_type, scan_tile[j]));
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										if (!silent_mode) AILog.Warning("Couldn't build rail tunnel at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString());
//										AIController.Break("");
										this.m_pathfinder_tries = 0;
										return [null, null];
									}
								} else {
									local bridge_length = AIMap.DistanceManhattan(scan_tile[j], next[j]) + 1;
									local bridge_list = AIBridgeList_Length(bridge_length);
									for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
										bridge_list.SetValue(bridge, AIBridge.GetMaxSpeed(bridge));
									}
									bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, bridge_list.Begin(), next[j], scan_tile[j])) {
											if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
												for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
													bridge_list.SetValue(bridge, AIBridge.GetPrice(bridge, bridge_length));
												}
												bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
											}
											else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY" || AIError.GetLastErrorString() == "ERR_BRIDGE_HEADS_NOT_ON_SAME_HEIGHT" || AIError.GetLastErrorString() == "ERR_TUNNEL_CANNOT_BUILD_ON_WATER") {
												if (this.m_pathfinder_tries < max_pathfinderTries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
													/* Remove everything and try again */
													if (!silent_mode) AILog.Warning("Couldn't build rail bridge at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
													this.RemoveFailedRouteTracks();
													return this.PathfindBuildDoubleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
												}
											}
											++counter;
										}
										else {
											track_cost += costs.GetCosts();
//											if (!silent_mode) AILog.Warning("We built a rail bridge at tiles " + next[j] + " and " + scan_tile[j] + ", ac: " + costs.GetCosts());
											this.m_built_tiles[j].append(RailStruct.SetStruct(next[j], RailStructType.BRIDGE, this.m_rail_type, scan_tile[j]));
											this.m_bridge_tiles.append(next[j] < scan_tile[j] ? [next[j], scan_tile[j]] : [scan_tile[j], next[j]]);
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										if (!silent_mode) AILog.Warning("Couldn't build rail bridge at tiles " + next[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString());
//										AIController.Break("");
										this.m_pathfinder_tries = 0;
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
												if (this.m_pathfinder_tries < max_pathfinderTries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
													/* Remove everything and try again */
													if (!silent_mode) AILog.Warning("Couldn't build rail track at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
													this.RemoveFailedRouteTracks();
													return this.PathfindBuildDoubleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
												}
											}
											++counter;
										}
										else {
											track_cost += costs.GetCosts();
//											if (!silent_mode) AILog.Warning("We built a rail track at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + ", ac: " + costs.GetCosts());
											this.m_built_tiles[j].append(RailStruct.SetRail(next[j], this.m_rail_type, nextnext[j], scan_tile[j]));
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										if (!silent_mode) AILog.Warning("Couldn't build rail track at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString());
//										AIController.Break("");
										this.m_pathfinder_tries = 0;
										return [null, null];
									}
								}
								else if (this.m_pathfinder_tries < max_pathfinderTries && (this.m_built_tiles[0].len() != 0 || this.m_built_tiles[1].len() != 0)) {
									if (!silent_mode) AILog.Warning("Won't build a rail crossing a road at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString() + " - Retrying...");
									this.RemoveFailedRouteTracks();
									return this.PathfindBuildDoubleRail(tileFrom, station_from_dir, depot_tile_from, tileTo, station_to_dir, depot_tile_to, pathfinderProfile, silent_mode, null, this.m_built_tiles, track_cost);
								}
								else {
									if (!silent_mode) AILog.Warning("Won't build a rail crossing a road at tile " + next[j] + ", connecting " + nextnext[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString());
									this.m_pathfinder_tries = 0;
									return [null, null];
								}
							}
						}
						nextnext[j] = next[j];
						next[j] = scan_tile[j];
					}
				}
			}

			if (!silent_mode) AILog.Info("Track built! Actual cost for building track: " + track_cost);
		}

		this.m_pathfinder_tries = 0;
		this.m_built_ways += 2;
		return [builtTiles, null];
	}


	function BuildRailDepotOnTile(depot_tile, depotFront, depotRaila, depotRailb, depotRailc)
	{
		local counter = 0;
		do {
			if (!TestBuildRailDepot().TryBuild(depot_tile, depotFront)) {
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
				if (!TestBuildRail().TryBuild(depot_tile, depotFront, depotRaila)) {
					++counter;
				}
				else {
					break;
				}
				AIController.Sleep(1);
			} while (counter < 1);

			if (counter == 1) {
				local counter = 0;
				do {
					if (!TestDemolishTile().TryDemolish(depot_tile)) {
						++counter;
					}
					else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 1);

				if (counter == 1) {
					::scheduled_removals_table.Train.append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
					return null;
				}
				else {
					return null;
				}
			}
			else {
				local counter = 0;
				do {
					if (!TestBuildRail().TryBuild(depot_tile, depotFront, depotRailb)) {
						++counter;
					}
					else {
						break;
					}
					AIController.Sleep(1);
				} while (counter < 1);

				if (counter == 1) {
					local counter = 0;
					do {
						if (!TestRemoveRail().TryRemove(depot_tile, depotFront, depotRaila)) {
							++counter;;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						::scheduled_removals_table.Train.append(RailStruct.SetRail(depotFront, this.m_rail_type, depot_tile, depotRaila));
					}
					local counter = 0;
					do {
						if (!TestDemolishTile().TryDemolish(depot_tile)) {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						::scheduled_removals_table.Train.append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
						return null;
					}
					else {
						return null;
					}
				}
				else {
					local counter = 0;
					do {
						if (!TestBuildRail().TryBuild(depot_tile, depotFront, depotRailc)) {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						local counter = 0;
						do {
							if (!TestRemoveRail().TryRemove(depot_tile, depotFront, depotRailb)) {
								++counter;;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetRail(depotFront, this.m_rail_type, depot_tile, depotRailb));
						}
						local counter = 0;
						do {
							if (!TestRemoveRail().TryRemove(depot_tile, depotFront, depotRaila)) {
								++counter;;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetRail(depotFront, this.m_rail_type, depot_tile, depotRaila));
						}
						local counter = 0;
						do {
							if (!TestDemolishTile().TryDemolish(depot_tile)) {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduled_removals_table.Train.append(RailStruct.SetStruct(depot_tile, RailStructType.DEPOT, this.m_rail_type));
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
	}

	function BuildRouteRailDepot(station_tile, station_dir)
	{
		local depot_tile = null;

		AIRail.SetCurrentRailType(this.m_rail_type);
		local rail_station = RailStation.CreateFromTile(station_tile, station_dir);

		/* first attempt, build next to line 2 */
		local depotTile2 = rail_station.GetExitTile(2) - rail_station.GetExitTile(1) + rail_station.GetExitTile(2);
		local depotFront2 = rail_station.GetExitTile(2);
		local depotRail2a = rail_station.GetEntryTile(2);
		local depotRail2b = rail_station.GetExitTile(2) - rail_station.GetEntryTile(2) + rail_station.GetExitTile(2);
		local depotRail2c = rail_station.GetExitTile(1);

		if (AITestMode() && AIRail.BuildRail(depotTile2, depotFront2, depotRail2a) && AIRail.BuildRail(depotTile2, depotFront2, depotRail2b) &&
				AIRail.BuildRail(depotTile2, depotFront2, depotRail2c) && AIRail.BuildRailDepot(depotTile2, depotFront2)) {
			depot_tile = this.BuildRailDepotOnTile(depotTile2, depotFront2, depotRail2a, depotRail2b, depotRail2c);
		}
		if (depot_tile != null) {
			return depot_tile;
		}

		/* second attempt, build next to line 1 */
		local depotTile1 = rail_station.GetExitTile(1) - rail_station.GetExitTile(2) + rail_station.GetExitTile(1);
		local depotFront1 = rail_station.GetExitTile(1);
		local depotRail1a = rail_station.GetEntryTile(1);
		local depotRail1b = rail_station.GetExitTile(1) - rail_station.GetEntryTile(1) + rail_station.GetExitTile(1);
		local depotRail1c = rail_station.GetExitTile(1);

		if (AITestMode() && AIRail.BuildRail(depotTile1, depotFront1, depotRail1a) && AIRail.BuildRail(depotTile1, depotFront1, depotRail1b) &&
				AIRail.BuildRail(depotTile1, depotFront1, depotRail1c) && AIRail.BuildRailDepot(depotTile1, depotFront1)) {
			depot_tile = this.BuildRailDepotOnTile(depotTile1, depotFront1, depotRail1a, depotRail1b, depotRail1c);
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
		local frontTile = current[0];
		local prevTile = current[1];
		local nextTile = AIMap.TILE_INVALID;
		if (AIRail.IsRailTile(frontTile)) {
			local dir = frontTile - prevTile;
			local track = AIRail.GetRailTracks(frontTile);
			local bits = Utils.CountBits(track);
			if (bits >= 1 && bits <= 2) {
				switch (dir) {
					case 1: { // NE
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								nextTile = frontTile + 1;
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								nextTile = frontTile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								nextTile = frontTile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case -1: { // SW
						switch (track) {
							case AIRail.RAILTRACK_NE_SW: {
								nextTile = frontTile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								nextTile = frontTile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								nextTile = frontTile + AIMap.GetMapSizeX();
								break;
							}
						}
						break;
					}
					case AIMap.GetMapSizeX(): { // NW
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								nextTile = frontTile + AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NW_NE:
							case AIRail.RAILTRACK_NW_NE | AIRail.RAILTRACK_SW_SE: {
								nextTile = frontTile - 1;
								break;
							}
							case AIRail.RAILTRACK_NW_SW:
							case AIRail.RAILTRACK_NW_SW | AIRail.RAILTRACK_NE_SE: {
								nextTile = frontTile + 1;
								break;
							}
						}
						break;
					}
					case -AIMap.GetMapSizeX(): { // SE
						switch (track) {
							case AIRail.RAILTRACK_NW_SE: {
								nextTile = frontTile - AIMap.GetMapSizeX();
								break;
							}
							case AIRail.RAILTRACK_NE_SE:
							case AIRail.RAILTRACK_NE_SE | AIRail.RAILTRACK_NW_SW: {
								nextTile = frontTile - 1;
								break;
							}
							case AIRail.RAILTRACK_SW_SE:
							case AIRail.RAILTRACK_SW_SE | AIRail.RAILTRACK_NW_NE: {
								nextTile = frontTile + 1;
								break;
							}
						}
						break;
					}
				}
			}
			if (nextTile != AIMap.TILE_INVALID) {
				return [nextTile, frontTile];
			}
		} else if (AIBridge.IsBridgeTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AIBridge.GetOtherBridgeEnd(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				return [nextTile, otherTile];
			}
		} else if (AITunnel.IsTunnelTile(frontTile)) {
			local dir = frontTile - prevTile;
			local otherTile = AITunnel.GetOtherTunnelEnd(frontTile);
			if (((otherTile - frontTile) / AIMap.DistanceManhattan(otherTile, frontTile)) == dir) {
				nextTile = otherTile + dir;
			}
			if (nextTile != AIMap.TILE_INVALID) {
				return [nextTile, otherTile];
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
		throw "current[1] " + current[1] + "is neither a rail tile, a bridge tile nor a tunnel in TrackSignalLength";
	}

	function BuildSignalsInLine(current, length)
	{
		local i = 0;
		local signal_interval = null;
		local signal_cost = 0;
		while (current != null) {
//			AILog.Info("current[0]: " + current[0] + "; current[1]: " + current[1]);
			if (signal_interval != null) {
				signal_interval += this.TrackSignalLength(current);
			}
			if (signal_interval == null || signal_interval > length) {
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
						}
						else {
							signal_cost += costs.GetCosts();
							signal_interval = 0;
							i++;
//							AILog.Warning("We built a rail signal at tile " + current[1] + " towards " + current[0] + ", ac: " + costs.GetCosts() + ", i: " + i);
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

		return [true, signal_cost];
	}

	function BuildSignals(tileFrom, station_from_dir, tileTo, station_to_dir)
	{
		local station_from = RailStation.CreateFromTile(tileFrom, station_from_dir);
		local station_to = RailStation.CreateFromTile(tileTo, station_to_dir);
		local plats = RailStationPlatforms(station_from, station_to);
		local length = station_from.m_length * 2;

		local current = [station_to.GetExitTile(plats.m_to2, 1), station_to.GetExitTile(plats.m_to2)];
		local result = this.BuildSignalsInLine(current, length);
		if (!result[0]) return false;
		local signal_cost = result[1];
		current = [station_from.GetExitTile(plats.m_from1, 1), station_from.GetExitTile(plats.m_from1)];
		result = this.BuildSignalsInLine(current, length);
		if (!result[0]) return false;
		signal_cost += result[1];

		AILog.Info("Signals built! Actual cost for building signals: " + signal_cost);
		this.m_built_ways++;
		return true;
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
