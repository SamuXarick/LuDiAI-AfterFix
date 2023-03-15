require("RailPathfinder.nut");

enum RailStationDir {
	NE,
	SW,
	NW,
	SE
}

class RailStation {
	m_tile = null;
	m_dir = null;
	m_num_plat = null;
	m_length = null;

	width = null;
	height = null;

	constructor(tile, dir, num_plat, length) {
		m_tile = tile;
		m_dir = dir;
		m_num_plat = num_plat;
		m_length = length;

		width = (m_dir == RailStationDir.NE || m_dir == RailStationDir.SW) ? m_length : m_num_plat;
		height = (m_dir == RailStationDir.NE || m_dir == RailStationDir.SW) ? m_num_plat : m_length;
	}

	function GetValidRectangle(extra_range) {
		if (extra_range == 0) return [GetTopTile(), width, height];

		local station_tiles = AITileList();
		station_tiles.AddRectangle(GetTopTile(), GetBottomTile());

		local offset_x;
		local offset_y;
		switch (m_dir) {
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

		local new_top_tile = GetTopTile();
		foreach (plat in [1, m_num_plat]) {
			local entry_tile = GetEntryTile(plat);
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

		local new_width = (m_dir == RailStationDir.NE || m_dir == RailStationDir.SW) ? m_length + extra_range : m_num_plat;
		local new_height = (m_dir == RailStationDir.NE || m_dir == RailStationDir.SW) ? m_num_plat : m_length + extra_range;
		return [new_top_tile, new_width, new_height];
	}

	function GetExitTile(platform, extra_range = 0) {
		switch (m_dir) {
			case RailStationDir.NE:
				return m_tile + AIMap.GetMapSizeX() * (platform - 1) - 1 - extra_range;

			case RailStationDir.SW:
				return m_tile + AIMap.GetMapSizeX() * (platform - 1) + m_length + extra_range;

			case RailStationDir.NW:
				return m_tile + (platform - 1) - AIMap.GetMapSizeX() - extra_range * AIMap.GetMapSizeX();

			case RailStationDir.SE:
				return m_tile + (platform - 1) + m_length * AIMap.GetMapSizeX() + extra_range * AIMap.GetMapSizeX();
		}
	}

	function GetEntryTile(platform) {
		switch (m_dir) {
			case RailStationDir.NE:
				return m_tile + AIMap.GetMapSizeX() * (platform - 1);

			case RailStationDir.SW:
				return m_tile + AIMap.GetMapSizeX() * (platform - 1) + m_length - 1;

			case RailStationDir.NW:
				return m_tile + (platform - 1);

			case RailStationDir.SE:
				return m_tile + (platform - 1) + (m_length - 1) * AIMap.GetMapSizeX();
		}
	}

	function GetTrackDirection() {
		switch (m_dir) {
			case RailStationDir.NE:
			case RailStationDir.SW:
				return AIRail.RAILTRACK_NE_SW;

			case RailStationDir.NW:
			case RailStationDir.SE:
				return AIRail.RAILTRACK_NW_SE;
		}
	}

	function GetTopTile() {
		return m_tile;
	}

	function GetBottomTile() {
		switch (m_dir) {
			case RailStationDir.NE:
			case RailStationDir.SW:
				return m_tile + AIMap.GetMapSizeX() * (m_num_plat - 1) + (m_length - 1);

			case RailStationDir.NW:
			case RailStationDir.SE:
				return m_tile + (m_num_plat - 1) + (m_length - 1) * AIMap.GetMapSizeX();
		}
	}

	function CreateFromTile(tile, dir = null) {
		assert(AIRail.IsRailStationTile(tile));
		if (dir != null) assert(dir == RailStationDir.NE || dir == RailStationDir.SW || dir = RailStationDir.NW || dir = RailStationDir.SE);

		local station_tiles = AITileList_StationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN);
		station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
		local top_tile = station_tiles.Begin();
		station_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_DESCENDING);
		local bot_tile = station_tiles.Begin();
		local railtrack = AIRail.GetRailStationDirection(top_tile);
		local length = railtrack == AIRail.RAILTRACK_NE_SW ? AIMap.GetTileX(bot_tile) - AIMap.GetTileX(top_tile) + 1 : AIMap.GetTileY(bot_tile) - AIMap.GetTileY(top_tile) + 1;
		local num_platforms = railtrack == AIRail.RAILTRACK_NE_SW ? AIMap.GetTileY(bot_tile) - AIMap.GetTileY(top_tile) + 1 : AIMap.GetTileX(bot_tile) - AIMap.GetTileX(top_tile) + 1;

		if (dir == null) {
			/* Try to guess direction based on the rail tracks at the exit */
			switch (railtrack) {
				case AIRail.RAILTRACK_NE_SW: {
					local exit_tile_NE_1 = top_tile - 1;
					local exit_tile_SW_1 = top_tile + length;
					if (AIRail.IsRailTile(exit_tile_NE_1) && AICompany.IsMine(AITile.GetOwner(exit_tile_NE_1))) {
						local tracks = AIRail.GetRailTracks(exit_tile_NE_1);
						if ((tracks & AIRail.RAILTRACK_NE_SW) != 0) {
							dir = RailStationDir.NE;
							break;
						}
					}
					if (AIRail.IsRailTile(exit_tile_SW_1) && AICompany.IsMine(AITile.GetOwner(exit_tile_SW_1))) {
						local tracks = AIRail.GetRailTracks(exit_tile_SW_1);
						if ((tracks & AIRail.RAILTRACK_NE_SW) != 0) {
							dir = RailStationDir.SW;
							break;
						}
					}
				}

				case AIRail.RAILTRACK_NW_SE: {
					local exit_tile_NW_1 = top_tile - AIMap.GetMapSizeX();
					local exit_tile_SE_1 = top_tile + length * AIMap.GetMapSizeX();
					if (AIRail.IsRailTile(exit_tile_NW_1) && AICompany.IsMine(AITile.GetOwner(exit_tile_NW_1))) {
						local tracks = AIRail.GetRailTracks(exit_tile_NW_1);
						if ((tracks & AIRail.RAILTRACK_NW_SE) != 0) {
							dir = RailStationDir.NW;
							break;
						}
					}
					if (AIRail.IsRailTile(exit_tile_SW_1) && AICompany.IsMine(AITile.GetOwner(exit_tile_SW_1))) {
						local tracks = AIRail.GetRailTracks(exit_tile_SW_1);
						if ((tracks & AIRail.RAILTRACK_NW_SE) != 0) {
							dir = RailStationDir.SE;
							break;
						}
					}
				}
			}
		}
		assert(dir != null); // Could not guess station direction
		return RailStation(top_tile, dir, num_platforms, length);
	}

	function GetPlatformLine(num) {
		assert(num == 1 || num == 2);

		switch (m_dir) {
			case RailStationDir.NE:
			case RailStationDir.SE:
				return num == 1 ? 1 : 2;

			case RailStationDir.NW:
			case RailStationDir.SW:
				return num == 1 ? 2 : 1;
		}
	}
}

enum RailStructType {
	RAIL,
	TUNNEL,
	BRIDGE,
	STATION,
	DEPOT,
}

class RailStruct {
	m_tile = null;
	m_struct = null;
	m_railtype = null;
	m_tile2 = null;
	m_tile3 = null;
	m_track = null;

	constructor(tile, struct, railtype = -1, tile2 = -1, tile3 = -1, track = -1) {
		m_tile = tile;
		m_struct = struct;
		m_railtype = railtype;
		m_tile2 = tile2;
		m_tile3 = tile3;
		m_track = track;
	}

	function SetRail(tile, railtype, tile2, tile3) {
		return {
			m_tile = tile,
			m_struct = RailStructType.RAIL,
			m_railtype = railtype,
			m_tile2 = tile2,
			m_tile3 = tile3,
		};
	}

	function SetStruct(tile, struct, railtype, tile2 = -1) {
		assert(struct != RailStructType.RAIL);
		if (struct != RailStructType.DEPOT) assert(tile2 != -1);
		return {
			m_tile = tile,
			m_struct = struct,
			m_railtype = railtype,
			m_tile2 = tile2,
		};
	}
}

class RailBuildManager {

	m_cityFrom = -1;
	m_cityTo = -1;
	m_stationFrom = -1;
	m_stationTo = -1;
	m_depotFrom = -1;
	m_depotTo = -1;
	m_bridgeTiles = [];
	m_cargoClass = -1;
	m_pathfinder = null;
	m_pathfinderTries = 0;
	m_builtTiles = [];
	m_sentToDepotRailGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;
	m_railtype = AIRail.RAILTYPE_INVALID;
	m_stationFromDir = -1;
	m_stationToDir = -1;

	function buildTrainStation(town, cargoClass, otherTown, best_routes_built, railtype);
	function buildRail(fromTile, toTile, silent_mode, pathfinder);
	function findRailTileDepot(tile);
	function buildDepot(station, stationDir);
	function saveBuildManager();
	function buildRailRoute(cityFrom, cityTo, cargoClass, sentToDepotRailGroup, best_routes_built, railtype);

	function hasUnfinishedRoute() {
		if (m_cityFrom != -1 && m_cityTo != -1 && m_cargoClass != -1) {
			return 1;
		}

		return 0;
	}

	function setRouteFinish() {
		m_cityFrom = -1;
		m_cityTo = -1;
		m_stationFrom = -1;
		m_stationTo = -1;
		m_depotFrom = -1;
		m_depotTo = -1;
		m_bridgeTiles = [];
		m_cargoClass = -1;
		m_builtTiles = [];
		m_sentToDepotRailGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
		m_best_routes_built = null;
		m_railtype = AIRail.RAILTYPE_INVALID;
		m_stationFromDir = -1;
		m_stationToDir = -1;
	}

	function RemoveFailedRouteStation(stationTile, stationDir, depot = null) {
		if (stationTile != null) {
			local station = RailStation.CreateFromTile(stationTile, stationDir);
			local top_tile = station.GetTopTile();
			local bot_tile = station.GetBottomTile();
			local entry_tile_2 = station.GetEntryTile(2);
			local exit_tile_2 = station.GetExitTile(2);
			local exit_tile_1 = station.GetExitTile(1);
			local entry_tile_1 = station.GetEntryTile(1);

			local counter = 0;
			do {
				if (!TestRemoveRailStationTileRectangle().TryRemove(top_tile, bot_tile, false)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed railway station tile at " + stationTile);
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, m_railtype, bot_tile));
//				AILog.Error("Failed to remove railway station tile at " + stationTile + " - " + AIError.GetLastErrorString());
			}
			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, 2 * exit_tile_1 - entry_tile_1)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track crossing from platform 2 to 1 at tile " + station.GetExitTile(2));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, m_railtype, entry_tile_2, 2 * exit_tile_1 - entry_tile_1));
//				AILog.Error("Failed to remove rail track crossing from platform 2 to 1 at tile " + station.GetExitTile(2));
			}
			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_2 - entry_tile_2)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track crossing from platform 1 to 2 at tile " + station.GetExitTile(1));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, m_railtype, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
//				AILog.Error("Failed to remove rail track crossing from platform 1 to 2 at tile " + station.GetExitTile(1));
			}
			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_2, exit_tile_2, 2 * exit_tile_2 - entry_tile_2)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track in front of platform 2 at tile " + station.GetExitTile(2));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, m_railtype, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
//				AILog.Error("Failed to remove rail track in front of platform 2 at tile " + station.GetExitTile(2));
			}
			local counter = 0;
			do {
				if (!TestRemoveRail().TryRemove(entry_tile_1, exit_tile_1, 2 * exit_tile_1 - entry_tile_1)) {
					++counter;
				}
				else {
//					AILog.Warning("Removed rail track in front of platform 1 at tile " + station.GetExitTile(1));
					break;
				}
				AIController.Sleep(1);
			} while (counter < 500);
			if (counter == 500) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, m_railtype, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
//				AILog.Error("Failed to remove rail track in front of platform 1 at tile " + station.GetExitTile(1));
			}
			if (depot != null) {
				local depotFront = AIRail.GetRailDepotFrontTile(depot);
				local depotRaila = abs(depot - depotFront) == 1 ? depotFront - AIMap.GetMapSizeX() : depotFront - 1;;
				local depotRailb = 2 * depotFront - depotRaila;
				local depotRailc = 2 * depotFront - depot;
				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot, depotFront, depotRaila)) {
						++counter;
					}
					else {
//						AILog.Warning("Removed rail track in front of depot towards the station at tile " + depotFront);
						break;
					}
					AIController.Sleep(1);
				} while(counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, m_railtype, depot, depotRaila));
//					AILog.Error("Failed to remove rail track in front of depot towards the station at tile " + depotFront);
				}
				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot, depotFront, depotRailb)) {
						++counter;
					}
					else {
//						AILog.Warning("Removed rail track in front of depot towards the railroad at tile " + depotFront);
						break;
					}
					AIController.Sleep(1);
				} while(counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, m_railtype, depot, depotRailb));
//					AILog.Error("Failed to remove rail track in front of depot towards the railroad at tile " + depotFront);
				}
				local counter = 0;
				do {
					if (!TestRemoveRail().TryRemove(depot, depotFront, depotRailc)) {
						++counter;
					}
					else {
//						AILog.Warning("Removed rail track in front of depot accross the lines at tile " + depotFront);
						break;
					}
					AIController.Sleep(1);
				} while(counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, m_railtype, depot, depotRailc));
//					AILog.Error("Failed to remove rail track in front of depot towards accross the lines at tile " + depotFront);
				}
				local counter = 0;
				do {
					if (!TestDemolishTile().TryDemolish(depot)) {
						++counter;
					}
					else {
//						AILog.Warning("Removed rail depot at tile " + depot);
						break;
					}
					AIController.Sleep(1);
				} while(counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depot, RailStructType.DEPOT, m_railtype));
//					AILog.Error("Failed to remove rail depot at tile " + depot);
				}
			}
		}
	}

	function RemoveFailedRouteTracks() {
		while (m_builtTiles.len() != 0) {
			local i = m_builtTiles.pop();
			local tile = i.m_tile;
			local struct = i.m_struct;
			local type = i.m_railtype;
			AIRail.SetCurrentRailType(type);
			if (struct == RailStructType.RAIL) {
				if (AIRail.IsRailTile(tile)) {
					local tile_from = i.m_tile2;
					local tile_to = i.m_tile3;
					if (!TestRemoveRail().TryRemove(tile_from, tile, tile_to)) {
//						AILog.Info("Failed to remove rail at tile " + tile + ", connecting " + tile_from + " to " + tile_to + ".");
						::scheduledRemovalsTable.Train.append(RailStruct.SetRail(tile_from, type, tile, tile_to));
					}
				} else {
//					AILog.Info("No rail tile found to remove at tile " + tile + ", connecting " + tile_from + " to " + tile_to + ".");
				}
			} else if (struct == RailStructType.BRIDGE) {
				local tile2 = i.m_tile2;
				if (AIBridge.IsBridgeTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) && AIBridge.GetOtherBridgeEnd(tile) == tile2) {
					if (!TestDemolishTile().TryDemolish(tile)) {
//						AILog.Info("Failed to demolish bridge at tiles " + tile + " and " + tile2 + ".");
						::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(tile, RailStructType.BRIDGE, type, tile2));
					}
				} else {
//					AILog.Info("No bridge found to demolish at tiles " + tile + " and " + tile2 + ".");
				}
			} else if (struct == RailStructType.TUNNEL) {
				local tile2 = i.m_tile2;
				if (AITunnel.IsTunnelTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) && AITunnel.GetOtherTunnelEnd(tile) == tile2) {
					if (!TestDemolishTile().TryDemolish(tile)) {
//						AILog.Info("Failed to demolish tunnel at tiles " + tile + " and " + tile2 + ".");
						::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(tile, RailStructType.TUNNEL, type, tile2));
					}
				} else {
//					AILog.Info("No tunnel found to demolish at tiles " + tile + " and " + tile2 + ".");
				}
			}
		}
	}

	function buildRailRoute(cityFrom, cityTo, cargoClass, sentToDepotRailGroup, best_routes_built, railtype) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_cargoClass = cargoClass;
		m_sentToDepotRailGroup = sentToDepotRailGroup;
		m_best_routes_built = best_routes_built;
		m_railtype = railtype;

		local list = AIVehicleList();
		local num_vehicles = 0;
		for (local v = list.Begin(); !list.IsEnd(); v = list.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_RAIL) {
				num_vehicles++;
			}
		}
		if (num_vehicles >= AIGameSettings.GetValue("max_trains") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_RAIL)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		if (m_stationFrom == -1) {
			local stationFrom = buildTrainStation(m_cityFrom, m_cargoClass, m_cityTo, m_best_routes_built, m_railtype);
			if (stationFrom == null) {
				setRouteFinish();
				return null;
			}
			m_stationFrom = stationFrom[0];
			m_stationFromDir = stationFrom[1];
		}

		if (m_depotFrom == -1) {
			local depotFrom = buildDepot(m_stationFrom, m_stationFromDir);
			if (depotFrom == null) {
				RemoveFailedRouteStation(m_stationFrom, m_stationFromDir);
				setRouteFinish();
				return null;
			}
			m_depotFrom = depotFrom;
		}

		if (m_stationTo == -1) {
			local stationTo = buildTrainStation(m_cityTo, m_cargoClass, m_cityFrom, m_best_routes_built, m_railtype);
			if (stationTo == null) {
				RemoveFailedRouteStation(m_stationFrom, m_stationFromDir, m_depotFrom);
				setRouteFinish();
				return null;
			}
			m_stationTo = stationTo[0];
			m_stationToDir = stationTo[1];
		}

		if (m_depotTo == -1) {
			local depotTo = buildDepot(m_stationTo, m_stationToDir);
			if (depotTo == null) {
				RemoveFailedRouteStation(m_stationFrom, m_stationFromDir, m_depotFrom);
				RemoveFailedRouteStation(m_stationTo, m_stationToDir);
				setRouteFinish();
				return null;
			}
			m_depotTo = depotTo;
		}

		if (m_stationFrom != null && m_depotFrom != null && m_stationTo != null && m_depotTo != null) {
			local railArray = buildRail(m_stationFrom, m_stationFromDir, m_stationTo, m_stationToDir, false, m_pathfinder, m_builtTiles);
			m_pathfinder = railArray[1];
			if (railArray[0] == null && m_pathfinder != null) {
				return 0;
			}
			if (railArray[0] == null && m_builtTiles.len() != 0) {
				RemoveFailedRouteTracks();
			}
		}

		if (m_builtTiles.len() == 0) {
			RemoveFailedRouteStation(m_stationFrom, m_stationFromDir, m_depotFrom);
			RemoveFailedRouteStation(m_stationTo, m_stationToDir, m_depotTo);
			setRouteFinish();
			return null;
		}
		m_builtTiles = [];
		AILog.Info(typeof(m_pathfinder));
		return RailRoute(m_cityFrom, m_cityTo, m_stationFrom, m_stationTo, m_depotFrom, m_depotTo, m_bridgeTiles, m_cargoClass, m_sentToDepotRailGroup, m_railtype, m_stationFromDir, m_stationToDir);
	}

	function AreOtherRailwayStationsNearby(station) {
		local squareSize = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN) * 2;

		local square = AITileList();
		if (!AIController.GetSetting("is_friendly")) {
			squareSize = 2;
			//don't care about enemy stations when is_friendly is off
			square.AddRectangle(Utils.getValidOffsetTile(station.GetTopTile(), (-1) * squareSize, (-1) * squareSize),
					Utils.getValidOffsetTile(station.GetBottomTile(), squareSize, squareSize));

			//if another railway station of mine is nearby return true
			for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
				if (AITile.IsStationTile(tile) && AITile.GetOwner(tile) == Utils.MyCID() && AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN)) {
					return true;
				}
			}
		} else {
			square.AddRectangle(Utils.getValidOffsetTile(station.GetTopTile(), (-1) * squareSize, (-1) * squareSize),
					Utils.getValidOffsetTile(station.GetBottomTile(), squareSize, squareSize));

			//if any other station is nearby, except my own railway stations, return true
			for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
				if (AITile.IsStationTile(tile)) {
					if (AITile.GetOwner(tile) != Utils.MyCID()) {
						return true;
					} else {
						local stationTiles = AITileList_StationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN);
						if (stationTiles.HasItem(tile)) {
							return true;
						}
					}
				}
			}
		}
	}

	function expandAdjacentRailwayStationRect(station) {
		local spread_rad = AIGameSettings.GetValue("station_spread");

		local remaining_x = spread_rad - station.width;
		local remaining_y = spread_rad - station.height;

		local tile_top_x = AIMap.GetTileX(station.GetTopTile());
		local tile_top_y = AIMap.GetTileY(station.GetTopTile());
		local tile_bot_x = AIMap.GetTileX(station.GetBottomTile());
		local tile_bot_y = AIMap.GetTileY(station.GetBottomTile());

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

	function TownRailwayStationRadRect(max_width, max_height, radius, town) {
		local town_rectangle = Utils.estimateTownRectangle(town);

		local top_x = AIMap.GetTileX(town_rectangle[0]);
		local top_y = AIMap.GetTileY(town_rectangle[0]);
		local bot_x = AIMap.GetTileX(town_rectangle[1]);
		local bot_y = AIMap.GetTileY(town_rectangle[1]);
//		AILog.Info("top tile was " + top_x + "," + top_y + " bottom tile was " + bot_x + "," + bot_y + " ; town = " + AITown.GetName(town));

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
//		AILog.Info("top tile now " + top_x + "," + top_y + " bottom tile now " + bot_x + "," + bot_y + " ; town = " + AITown.GetName(town));
		return [AIMap.GetTileIndex(top_x, top_y), AIMap.GetTileIndex(bot_x, bot_y)];
	}

	function checkAdjacentNonRailwayStation(station) {
		if (!AIController.GetSetting("station_spread") || !AIGameSettings.GetValue("distant_join_stations")) {
			return AIStation.STATION_NEW;
		}

		local tileList = AITileList();
		local spreadrectangle = expandAdjacentRailwayStationRect(station);
		tileList.AddRectangle(spreadrectangle[0], spreadrectangle[1]);

		local templist = AITileList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (Utils.isTileMyStationWithoutRailwayStation(tile)) {
				tileList.SetValue(tile, AIStation.GetStationID(tile));
			} else {
				templist.AddTile(tile);
			}
		}
		tileList.RemoveList(templist);

		local stationList = AIList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tileList.Next()) {
			stationList.AddItem(tileList.GetValue(tile), AITile.GetDistanceManhattanToTile(tile, station.GetTopTile()));
		}

		local spreadrectangle_top_x = AIMap.GetTileX(spreadrectangle[0]);
		local spreadrectangle_top_y = AIMap.GetTileY(spreadrectangle[0]);
		local spreadrectangle_bot_x = AIMap.GetTileX(spreadrectangle[1]);
		local spreadrectangle_bot_y = AIMap.GetTileY(spreadrectangle[1]);

		local list = AIList();
		list.AddList(stationList);
		for (local stationId = stationList.Begin(); !stationList.IsEnd(); stationId = stationList.Next()) {
			local stationTiles = AITileList_StationType(stationId, AIStation.STATION_ANY);
			local station_top_x = AIMap.GetTileX(AIBaseStation.GetLocation(stationId));
			local station_top_y = AIMap.GetTileY(AIBaseStation.GetLocation(stationId));
			local station_bot_x = station_top_x;
			local station_bot_y = station_top_y;
			for (local tile = stationTiles.Begin(); !stationTiles.IsEnd(); tile = stationTiles.Next()) {
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
		list.Sort(AIList.SORT_BY_VALUE, true);

		local adjacentStation = AIStation.STATION_NEW;
		if (list.Count()) {
			adjacentStation = list.Begin();
//			AILog.Info("adjacentStation = " + AIStation.GetName(adjacentStation) + " ; station.GetTopTile() = " + AIMap.GetTileX(station.GetTopTile()) + "," + AIMap.GetTileY(station.GetTopTile()));
		}

		return adjacentStation;
	}

	function WorstStationOrientations(station, station_tiles, town, otherTown) {
		local shortest_dist_other_town = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();

		for (local plat = 1; plat <= station.m_num_plat; plat++) {
			local dist_other_town = AITown.GetDistanceManhattanToTile(otherTown, station.GetEntryTile(plat));
			if (dist_other_town < shortest_dist_other_town) {
				shortest_dist_other_town = dist_other_town;
			}
		}

		local best_tile = AIMap.TILE_INVALID;
		local shortest_dist_town = AIMap.GetMapSizeX() + AIMap.GetMapSizeY();

		foreach (tile, _ in station_tiles) {
			local dist_town = AITown.GetDistanceManhattanToTile(town, tile);
			if (dist_town < shortest_dist_town) {
				shortest_dist_town = dist_town;
				best_tile = tile;
			}
		}

		local worst_dirs = AIList();
		local diff_x = AIMap.GetTileX(AITown.GetLocation(town)) - AIMap.GetTileX(best_tile);
		local diff_y = AIMap.GetTileY(AITown.GetLocation(town)) - AIMap.GetTileY(best_tile);

		if (diff_x < 0) worst_dirs.AddItem(RailStationDir.NE, 0);
		if (diff_y < 0) worst_dirs.AddItem(RailStationDir.NW, 0);
		if (diff_x > 0) worst_dirs.AddItem(RailStationDir.SW, 0);
		if (diff_y > 0) worst_dirs.AddItem(RailStationDir.SE, 0);

		return [worst_dirs, shortest_dist_town, shortest_dist_other_town];
	}

	function buildTrainStation(town, cargoClass, otherTown, best_routes_built, railtype) {
		AIRail.SetCurrentRailType(railtype);
		local cargoType = Utils.getCargoId(cargoClass);
		local radius = AIStation.GetCoverageRadius(AIStation.STATION_TRAIN);
		local pick_mode = AIController.GetSetting("pick_mode");
		local max_station_spread = AIGameSettings.GetValue("station_spread");
		local max_train_length = AIGameSettings.GetValue("max_train_length");
		local platform_length = min(RailRoute.MAX_PLATFORM_LENGTH, min(max_station_spread, max_train_length));
		local num_platforms = RailRoute.MAX_NUM_PLATFORMS;
		local distance_between_towns = AIMap.DistanceSquare(AITown.GetLocation(town), AITown.GetLocation(otherTown));

		local tileList = AITileList();
		/* build square around @town and find suitable tiles for railway station */
		local rectangleCoordinates = TownRailwayStationRadRect(max(platform_length, num_platforms), max(platform_length, num_platforms), radius, town);

		tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);
//		AISign.BuildSign(rectangleCoordinates[0], AITown.GetName(town));
//		AISign.BuildSign(rectangleCoordinates[1], AITown.GetName(town));

		local stations = AIPriorityQueue();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			foreach (dir in [RailStationDir.NE, RailStationDir.SW, RailStationDir.NW, RailStationDir.SE]) {
				local station = RailStation(tile, dir, num_platforms, platform_length);
				local station_tiles = AITileList();
				station_tiles.AddRectangle(station.GetTopTile(), station.GetBottomTile());

				local worst_dirs = WorstStationOrientations(station, station_tiles, town, otherTown);
				if (worst_dirs[0].HasItem(dir)) continue;

				local in_range = true;
				foreach (station_tile, _ in station_tiles) {
					if (!tileList.HasItem(station_tile)) {
						in_range = false;
						break;
					}
					local dist_to_town = AITown.GetDistanceSquareToTile(town, station_tile);
					local dist_to_otherTown = AITown.GetDistanceSquareToTile(otherTown, station_tile);
					local farthest_town = dist_to_town < dist_to_otherTown ? otherTown : town;
					if (AITown.GetDistanceSquareToTile(farthest_town, station_tile) >= distance_between_towns) {
						in_range = false;
						break;
					}
//					else {
//						AISign.BuildSign(station_tile, "x");
//					}
				}
				if (!in_range) continue;

				local rectangle = station.GetValidRectangle(4); // 4 tiles free
				if (rectangle == null) continue;

				if (AITile.IsBuildableRectangle(rectangle[0], rectangle[1], rectangle[2])) {
					local depot_tile_1 = station.GetExitTile(1) + station.GetExitTile(1) - station.GetExitTile(2);
					local depot_tile_2 = station.GetExitTile(2) + station.GetExitTile(2) - station.GetExitTile(1);
					if (!AITile.IsBuildable(depot_tile_1) && !AITile.IsBuildable(depot_tile_2)) continue;
					local exit_turn_a_1 = depot_tile_1 + (station.GetExitTile(1) - station.GetEntryTile(1)) * 2;
					local exit_turn_a_2 = depot_tile_1 + (station.GetExitTile(1) - station.GetEntryTile(1)) * 3;
					local exit_turn_b_1 = depot_tile_2 + (station.GetExitTile(2) - station.GetEntryTile(2)) * 3;
					local exit_turn_b_2 = depot_tile_2 + (station.GetExitTile(2) - station.GetEntryTile(2)) * 2;
					local exit_front_a_1 = exit_turn_a_2;
					local exit_front_a_2 = station.GetExitTile(1) + (station.GetExitTile(1) - station.GetEntryTile(1)) * 3;
					local exit_front_b_1 = station.GetExitTile(2) + (station.GetExitTile(2) - station.GetEntryTile(2)) * 3;
					local exit_front_b_2 = exit_turn_b_1;
					if (!(AITile.IsBuildable(exit_turn_a_1) && AITile.IsBuildable(exit_turn_a_2)) &&
							!(AITile.IsBuildable(exit_turn_b_1) && AITile.IsBuildable(exit_turn_b_2)) &&
							!(AITile.IsBuildable(exit_front_a_1) && AITile.IsBuildable(exit_front_a_2)) &&
							!(AITile.IsBuildable(exit_front_b_1) && AITile.IsBuildable(exit_front_b_2))) {
						continue;
					}

					if (AITile.GetCargoAcceptance(tile, cargoType, station.width, station.height, radius) >= 8) {
						if (!AreOtherRailwayStationsNearby(station)) {
							local cargo_production = AITile.GetCargoProduction(tile, cargoType, station.width, station.height, radius);
							if (pick_mode == 1 || best_routes_built || cargo_production >= 8) {
								stations.Insert(station, -((cargo_production << 28) | ((0x2000 - worst_dirs[1]) << 14) | (0x2000 - worst_dirs[2]))); // store as negative to make priority queue prioritize highest values
							}
						}
					}
				}
			}
		}

		while (!stations.IsEmpty()) {
			local station = stations.Pop();
			local top_tile = station.GetTopTile();
			local bot_tile = station.GetBottomTile();
			local entry_tile_2 = station.GetEntryTile(2);
			local exit_tile_2 = station.GetExitTile(2);
			local exit_tile_1 = station.GetExitTile(1);
			local entry_tile_1 = station.GetEntryTile(1);
			if (AITile.GetClosestTown(station.GetTopTile()) != town) continue;

			/* get adjacent tiles */
			local station_tiles = AITileList();
			station_tiles.AddRectangle(top_tile, bot_tile);
			local adjTileList = AITileList();
			adjTileList.AddList(station_tiles);

			foreach (tile in adjTileList) {
				local adjTileList2 = Utils.getAdjacentTiles(tile);
				foreach (tile2 in adjTileList2) {
					adjTileList.AddTile(tile2);
				}
			}
			adjTileList.RemoveRectangle(top_tile, bot_tile);

			local adjacentNonRailwayStation = checkAdjacentNonRailwayStation(station);

			/* avoid blocking other station exits */
			local blocking = false;
			foreach (adjTile in adjTileList) {
				if (AITile.IsStationTile(adjTile) && AITile.HasTransportType(adjTile, AITile.TRANSPORT_ROAD)) {
					foreach (roadtype, _ in AIRoadTypeList(AIRoad.ROADTRAMTYPES_ROAD | AIRoad.ROADTRAMTYPES_TRAM)) {
						if (AIRoad.HasRoadType(adjTile, roadtype)) {
							SetCurrentRoadType(roadtype);
							if (AIRoad.IsRoadStationTile(adjTile) && station.tiles.HasTile(AIRoad.GetRoadStationFrontTile(adjTile))) {
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
				if (!TestBuildRailStation().TryBuild(top_tile, station.GetTrackDirection(), station.m_num_plat, station.m_length, adjacentNonRailwayStation)) {
					++counter;
				}
				else {
//					AILog.Info("station built");
					break;
				}
				AIController.Sleep(1);
			} while(counter < 1);
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
				} while(counter < 1);
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
						::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, m_railtype, bot_tile));
						continue;
					}
				}
				else {
					/* Built track in front of platform 1. Now build track in front of platform 2 */
					local counter = 0;
					do {
						if (!AIRoad.IsRoadTile(station.GetExitTile(2)) && !TestBuildRail().TryBuild(station.GetEntryTile(2), station.GetExitTile(2), station.GetExitTile(2) - station.GetEntryTile(2) + station.GetExitTile(2))) {
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
							::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, m_railtype, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
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
							::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, m_railtype, bot_tile));
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
								::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, m_railtype, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
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
								::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, m_railtype, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
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
								::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, m_railtype, bot_tile));
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
									::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, m_railtype, entry_tile_1, 2 * exit_tile_2 - entry_tile_2));
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
									::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_2, m_railtype, entry_tile_2, 2 * exit_tile_2 - entry_tile_2));
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
									::scheduledRemovalsTable.Train.append(RailStruct.SetRail(exit_tile_1, m_railtype, entry_tile_1, 2 * exit_tile_1 - entry_tile_1));
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
									::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(top_tile, RailStructType.STATION, m_railtype, bot_tile));
									continue;
								}
							}
							else {
								AILog.Info("Railway station built in " + AITown.GetName(town) + " at tile " + top_tile + "!");
								return [top_tile, station.m_dir];
							}
						}
					}
				}
			}
		}

		return null;
	}

	// find rail way between fromTile and toTile
	function buildRail(fromTile, fromTileDir, toTile, toTileDir, silent_mode = false, pathfinder = null, builtTiles = [], cost_so_far = 0) {
		//can store rail tiles into array

		if (fromTile != toTile) {
			local route_dist = AIMap.DistanceManhattan(AITown.GetLocation(m_cityFrom), AITown.GetLocation(m_cityTo));
			local profile = AIController.GetSetting("rail_pf_profile");
			local max_pathfinderTries = route_dist;
			if (profile == 0) {
				max_pathfinderTries = 1250 * route_dist;
			} else if (profile == 1) {
				max_pathfinderTries = 1000 * route_dist;
			} else {
				max_pathfinderTries = 5000 * route_dist / 5 + 5000 * route_dist % 5;
			}

			//* Print the names of the towns we'll try to connect. */
			if (!silent_mode) AILog.Info("t:Connecting " + AITown.GetName(m_cityFrom) + " (tile " + fromTile + ") and " + AITown.GetName(m_cityTo) + " (tile " + toTile + ") (iteration " + (m_pathfinderTries + 1) + "/" + max_pathfinderTries + ")");

			// Tell OpenTTD we want to build this railtype. */
			AIRail.SetCurrentRailType(m_railtype);

			if (pathfinder == null) {
				// Create an instance of the pathfinder. */
				pathfinder = Rail();

				switch(profile) {
					case 0:
						AILog.Info("rail pathfinder: custom");
/*defaults*/
/*10000000*/			pathfinder.cost.max_cost;
/*100*/					pathfinder.cost.tile;
/*70*/					pathfinder.cost.diagonal_tile;
/*50*/					pathfinder.cost.turn45;
/*300*/					pathfinder.cost.turn90 = pathfinder.cost.max_cost;
/*250*/					pathfinder.cost.consecutive_turn = pathfinder.cost.max_cost;
/*100*/					pathfinder.cost.slope = AIGameSettings.GetValue("train_acceleration_model") ? AIGameSettings.GetValue("train_slope_steepness") * 20 : pathfinder.cost.slope;
/*400*/					pathfinder.cost.consecutive_slope = pathfinder.cost.max_cost/*4 * pathfinder.cost.slope*/;
/*150*/					pathfinder.cost.bridge_per_tile = 50;
/*120*/					pathfinder.cost.tunnel_per_tile = 60;
/*20*/					pathfinder.cost.coast = (AICompany.GetLoanAmount() == 0) ? pathfinder.cost.coast : 5000;
/*900*/					pathfinder.cost.level_crossing = pathfinder.cost.max_cost;
/*6*/					pathfinder.cost.max_bridge_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*6*/					pathfinder.cost.max_tunnel_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
/*1*/					pathfinder.cost.estimate_multiplier = 1.0 + route_dist / 2000.0;
/*0*/					pathfinder.cost.search_range = max(route_dist / 15, 25);
						break;

					case 2:
						AILog.Info("rail pathfinder: fastest");

						pathfinder.cost.max_cost;
						pathfinder.cost.tile;
						pathfinder.cost.diagonal_tile;
						pathfinder.cost.turn45 = 250;
						pathfinder.cost.turn90 = pathfinder.cost.max_cost;
						pathfinder.cost.consecutive_turn = 5000;
						pathfinder.cost.slope = 50;
						pathfinder.cost.consecutive_slope = 5000;
						pathfinder.cost.bridge_per_tile;
						pathfinder.cost.tunnel_per_tile;
						pathfinder.cost.coast = 5000;
						pathfinder.cost.level_crossing = pathfinder.cost.max_cost;
						pathfinder.cost.max_bridge_length;
						pathfinder.cost.max_tunnel_length;
						pathfinder.cost.estimate_multiplier = 2;
						pathfinder.cost.search_range = max(route_dist / 30, 7);
						break;

					case 1:
					default:
						AILog.Info("rail pathfinder: default");

						pathfinder.cost.max_cost;
						pathfinder.cost.tile;
						pathfinder.cost.diagonal_tile;
						pathfinder.cost.turn45;
						pathfinder.cost.turn90;
						pathfinder.cost.consecutive_turn;
						pathfinder.cost.slope;
						pathfinder.cost.consecutive_slope
						pathfinder.cost.bridge_per_tile;
						pathfinder.cost.tunnel_per_tile;
						pathfinder.cost.coast;
						pathfinder.cost.level_crossing
						pathfinder.cost.max_bridge_length;
						pathfinder.cost.max_tunnel_length;
						pathfinder.cost.estimate_multiplier;
						pathfinder.cost.search_range;
						break;

				}
				// Give the source and goal tiles to the pathfinder. */
				local stationFrom = RailStation.CreateFromTile(fromTile, fromTileDir);
				local stationTo = RailStation.CreateFromTile(toTile, toTileDir);

				local stationFromPlat1;
				local stationToPlat1;
				local stationFromPlat2;
				local stationToPlat2;
				switch (fromTileDir) {
					case RailStationDir.NE:
						switch (toTileDir) {
							case RailStationDir.NE:
								stationFromPlat1 = 1;
								stationToPlat1 = 2;
								stationFromPlat2 = 2;
								stationToPlat2 = 1;
								break;

							case RailStationDir.NW:
								stationFromPlat1 = 1;
								stationToPlat1 = 1;
								stationFromPlat2 = 2;
								stationToPlat2 = 2;
								break;

							case RailStationDir.SE:
								stationFromPlat1 = 1;
								stationToPlat1 = 2;
								stationFromPlat2 = 2;
								stationToPlat2 = 1;
								break;

							case RailStationDir.SW:
								stationFromPlat1 = 1;
								stationToPlat1 = 1;
								stationFromPlat2 = 2;
								stationToPlat2 = 2;
								break;
						}
						break;

					case RailStationDir.NW:
						switch (toTileDir) {
							case RailStationDir.NE:
								stationFromPlat1 = 2;
								stationToPlat1 = 2;
								stationFromPlat2 = 1;
								stationToPlat2 = 1;
								break;

							case RailStationDir.NW:
								stationFromPlat1 = 2;
								stationToPlat1 = 1;
								stationFromPlat2 = 1;
								stationToPlat2 = 2;
								break;

							case RailStationDir.SE:
								stationFromPlat1 = 2;
								stationToPlat1 = 2;
								stationFromPlat2 = 1;
								stationToPlat2 = 1;
								break;

							case RailStationDir.SW:
								stationFromPlat1 = 2;
								stationToPlat1 = 1;
								stationFromPlat2 = 1;
								stationToPlat2 = 2;
								break;
						}
						break;

					case RailStationDir.SE:
						switch (toTileDir) {
							case RailStationDir.NE:
								stationFromPlat1 = 1;
								stationToPlat1 = 2;
								stationFromPlat2 = 2;
								stationToPlat2 = 1;
								break;

							case RailStationDir.NW:
								stationFromPlat1 = 1;
								stationToPlat1 = 1;
								stationFromPlat2 = 2;
								stationToPlat2 = 2;
								break;

							case RailStationDir.SE:
								stationFromPlat1 = 1;
								stationToPlat1 = 2;
								stationFromPlat2 = 2;
								stationToPlat2 = 1;
								break;

							case RailStationDir.SW:
								stationFromPlat1 = 1;
								stationToPlat1 = 1;
								stationFromPlat2 = 2;
								stationToPlat2 = 2;
								break;
						}
						break;

					case RailStationDir.SW:
						switch (toTileDir) {
							case RailStationDir.NE:
								stationFromPlat1 = 2;
								stationToPlat1 = 2;
								stationFromPlat2 = 1;
								stationToPlat2 = 1;
								break;

							case RailStationDir.NW:
								stationFromPlat1 = 2;
								stationToPlat1 = 1;
								stationFromPlat2 = 1;
								stationToPlat2 = 2;
								break;

							case RailStationDir.SE:
								stationFromPlat1 = 2;
								stationToPlat1 = 2;
								stationFromPlat2 = 1;
								stationToPlat2 = 1;
								break;

							case RailStationDir.SW:
								stationFromPlat1 = 2;
								stationToPlat1 = 1;
								stationFromPlat2 = 1;
								stationToPlat2 = 2;
								break;
						}
						break;
				}

				local stationFromEntry1 = stationFrom.GetExitTile(stationFromPlat1);
				local stationFromExit1 = stationFrom.GetExitTile(stationFromPlat1) - stationFrom.GetEntryTile(stationFromPlat1) + stationFrom.GetExitTile(stationFromPlat1);
				local stationToEntry1 = stationTo.GetExitTile(stationToPlat1);
				local stationToExit1 = stationTo.GetExitTile(stationToPlat1) - stationTo.GetEntryTile(stationToPlat1) + stationTo.GetExitTile(stationToPlat1);
				local stationFromEntry2 = stationFrom.GetExitTile(stationFromPlat2);
				local stationFromExit2 = stationFrom.GetExitTile(stationFromPlat2) - stationFrom.GetEntryTile(stationFromPlat2) + stationFrom.GetExitTile(stationFromPlat2);
				local stationToEntry2 = stationTo.GetExitTile(stationToPlat2);
				local stationToExit2 = stationTo.GetExitTile(stationToPlat2) - stationTo.GetEntryTile(stationToPlat2) + stationTo.GetExitTile(stationToPlat2);
				local ignoreTileFrom1 = stationFromExit1 - stationFromExit2 + stationFromExit1;
				local ignoreTileFrom2 = stationFromExit2 - stationFromExit1 + stationFromExit2;
				local ignoreTileTo1 = stationToExit1 - stationToExit2 + stationToExit1;
				local ignoreTileTo2 = stationToExit2 - stationToExit1 + stationToExit2;
				AILog.Info("stationFromEntry1 = " + stationFromEntry1 + "; stationFromExit1 = " + stationFromExit1 + "; stationToEntry1 = " + stationToEntry1 + "; stationToExit1 = " + stationToExit1);
				AILog.Info("stationFromEntry2 = " + stationFromEntry2 + "; stationFromExit2 = " + stationFromExit2 + "; stationToEntry2 = " + stationToEntry2 + "; stationToExit2 = " + stationToExit2);
				AILog.Info("ignoreTileFrom1 = " + ignoreTileFrom1 + "; ignoreTileFrom2 = " + ignoreTileFrom2 + "; ignoreTileTo1 = " + ignoreTileTo1 + "; ignoreTileTo2 = " + ignoreTileTo2);
				pathfinder.InitializePath(
					[[stationFromEntry1, stationFromExit1], [stationFromEntry2, stationFromExit2]],
					[[stationToExit1, stationToEntry1], [stationToExit2, stationToEntry2]],
					[ignoreTileFrom1, ignoreTileFrom2, ignoreTileTo1, ignoreTileTo2]);
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
//							if (!silent_mode) AILog.Info("rail pathfinder: FindPath iterated: " + count);
							local signList = AISignList();
							for (local sign = signList.Begin(); !signList.IsEnd(); sign = signList.Next()) {
								if (signList.Count() < 64000) break;
								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
							}
							return [null, pathfinder];
						}
					} else {
						// Timed out
						if (!silent_mode) AILog.Error("rail pathfinder: FindPath return false (timed out)");
						m_pathfinderTries = 0;
						return [null, null];
					}
				}

				if (path == null ) {
					// No path was found. */
					if (!silent_mode) AILog.Error("rail pathfinder: FindPath return null (no path)");
					m_pathfinderTries = 0;
					return [null, null];
				}
			} while(path == false);

//			if (!silent_mode && m_pathfinderTries != count) AILog.Info("rail pathfinder: FindPath iterated: " + count);
			if (!silent_mode) AILog.Info("Rail path found! FindPath iterated: " + m_pathfinderTries + ". Building track... ");
			if (!silent_mode) AILog.Info("rail pathfinder: FindPath cost: " + path.GetCost());
			local track_cost = cost_so_far;
			// If a path was found, build a track over it. */

			local scan_path = path;
			local prev = [null, null];
			local prevprev = [null, null];
			local scan_tile = [null, null];
			local last_tile = false;
			while (scan_path != null) {
				foreach (j in [0, 1]) {
					for (local i = scan_path._segment.m_nodes[j].len() - 1; i >= 0; i--) {
						scan_tile[j] = scan_path._segment.m_nodes[j][i][last_tile ? 3 : 0];
						if (prevprev[j] != null) {
							if (AIMap.DistanceManhattan(prev[j], scan_tile[j]) > 1) {
								if (AITunnel.GetOtherTunnelEnd(prev[j]) == scan_tile[j]) {
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildTunnel().TryBuild(AIVehicle.VT_RAIL, prev[j])) {
											++counter;
										}
										else {
											track_cost += costs.GetCosts();
//											if (!silent_mode) AILog.Warning("We built a rail tunnel at tiles " + prev[j] + " and " + scan_tile[j] + ", ac: " + costs.GetCosts());
											m_builtTiles.append(RailStruct.SetStruct(prev[j], RailStructType.TUNNEL, m_railtype, scan_tile[j]));
											break;
										}
										AIController.Sleep(1);
									} while(counter < 500);

									if (counter == 500) {
										if (!silent_mode) AILog.Warning("Couldn't build rail tunnel at tiles " + prev[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString());
										m_pathfinderTries = 0;
										return [null, null];
									}
								} else {
									local bridge_list = AIBridgeList_Length(AIMap.DistanceManhattan(scan_tile[j], prev[j]) + 1);
									for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
										bridge_list.SetValue(bridge, AIBridge.GetMaxSpeed(bridge));
									}
									bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildBridge().TryBuild(AIVehicle.VT_RAIL, bridge_list.Begin(), prev[j], scan_tile[j])) {
											if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
												for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
													bridge_list.SetValue(bridge, AIBridge.GetPrice(bridge, bridge_length));
												}
												bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
											}
											++counter;
										}
										else {
											track_cost += costs.GetCosts();
//											if (!silent_mode) AILog.Warning("We built a rail bridge at tiles " + prev[j] + " and " + scan_tile[j] + ", ac: " + costs.GetCosts());
											m_builtTiles.append(RailStruct.SetStruct(prev[j], RailStructType.BRIDGE, m_railtype, scan_tile[j]));
											m_bridgeTiles.append(prev[j] < scan_tile[j] ? [prev[j], scan_tile[j]] : [scan_tile[j], prev[j]]);
											break;
										}
										AIController.Sleep(1);
									} while(counter < 500);

									if (counter == 500) {
										if (!silent_mode) AILog.Warning("Couldn't build rail bridge at tiles " + prev[j] + " and " + scan_tile[j] + " - " + AIError.GetLastErrorString());
										m_pathfinderTries = 0;
										return [null, null];
									}
								}
							} else if (AIMap.DistanceManhattan(prevprev[j], prev[j]) == 1) {
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (!TestBuildRail().TryBuild(prevprev[j], prev[j], scan_tile[j])) {
										++counter;
									}
									else {
										track_cost += costs.GetCosts();
//										if (!silent_mode) AILog.Warning("We built a rail track at tile " + prev[j] + ", connecting " + prevprev[j] + " to " + scan_tile[j] + ", ac: " + costs.GetCosts());
										m_builtTiles.append(RailStruct.SetRail(prev[j], m_railtype, prevprev[j], scan_tile[j]));
										break;
									}
									AIController.Sleep(1);
								} while(counter < 500);

								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build rail track at tile " + prev[j] + ", connecting " + prevprev[j] + " to " + scan_tile[j] + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}
								if (j == 0) {
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildSignal().TryBuild(prev[j], prevprev[j], AIRail.SIGNALTYPE_PBS_ONEWAY)) {
											++counter;
										}
										else {
											track_cost += costs.GetCosts();
//											if (!silent_mode) AILog.Warning("We built a rail signal at tile " + prev[j] + " towards " + prevprev[j] + ", ac: " + costs.GetCosts());
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										if (!silent_mode) AILog.Warning("Couldn't build rail signal at tile " + prev[j] + " towards " + prevprev[j] + " - " + AIError.GetLastErrorString());
										m_pathfinderTries = 0;
										return [null, null];
									}
								}
								if (j == 1) {
									local counter = 0;
									do {
										local costs = AIAccounting();
										if (!TestBuildSignal().TryBuild(prev[j], scan_tile[j], AIRail.SIGNALTYPE_PBS_ONEWAY)) {
											++counter;
										}
										else {
											track_cost += costs.GetCosts();
//											if (!silent_mode) AILog.Warning("We built a rail signal at tile " + prev[j] + " towards " + scan_tile[j] + ", ac: " + costs.GetCosts());
											break;
										}
										AIController.Sleep(1);
									} while (counter < 500);

									if (counter == 500) {
										if (!silent_mode) AILog.Warning("Couldn't build rail signal at tile " + prev[j] + " towards " + scan_tile[j] + " - " + AIError.GetLastErrorString());
										m_pathfinderTries = 0;
										return [null, null];
									}
								}
							}
						}
						prevprev[j] = prev[j];
						prev[j] = scan_tile[j];
					}
				}
				if (last_tile == false && scan_path.GetParent() == null) {
					last_tile = true;
				} else {
					scan_path = scan_path.GetParent();
				}
			}

			if (!silent_mode) AILog.Info("Track built! Actual cost for building track: " + track_cost);
		}

//		if (!silent_mode) AILog.Info("Track built!");
		m_pathfinderTries = 0;
		return [builtTiles, null];
	}

	function buildDepotOnTile(depotTile, depotFront, depotRaila, depotRailb, depotRailc) {
		local counter = 0;
		do {
			if (!TestBuildRailDepot().TryBuild(depotTile, depotFront)) {
				++counter;
			}
			else {
				break;
			}
			AIController.Sleep(1);
		} while(counter < 1);

		if (counter == 1) {
			return null;
		}
		else {
			local counter = 0;
			do {
				if(!TestBuildRail().TryBuild(depotTile, depotFront, depotRaila)) {
					++counter;
				}
				else {
					break;
				}
				AIController.Sleep(1);
			} while(counter < 1);

			if (counter == 1) {
				local counter = 0;
				do {
					if (!TestDemolishTile().TryDemolish(depotTile)) {
						++counter;
					}
					else {
						break;
					}
					AIController.Sleep(1);
				} while(counter < 1);

				if (counter == 1) {
					::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depotTile, RailStructType.DEPOT, m_railtype));
					return null;
				}
				else {
					return null;
				}
			}
			else {
				local counter = 0;
				do {
					if(!TestBuildRail().TryBuild(depotTile, depotFront, depotRailb)) {
						++counter;
					}
					else {
						break;
					}
					AIController.Sleep(1);
				} while(counter < 1);

				if (counter == 1) {
					local counter = 0;
					do {
						if (!TestRemoveRail().TryRemove(depotTile, depotFront, depotRaila)) {
							++counter;;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while(counter < 1);

					if (counter == 1) {
						::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, m_railtype, depotTile, depotRaila));
					}
					local counter = 0;
					do {
						if (!TestDemolishTile().TryDemolish(depotTile)) {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);

					if (counter == 1) {
						::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depotTile, RailStructType.DEPOT, m_railtype));
						return null;
					}
					else {
						return null;
					}
				}
				else {
					local counter = 0;
					do {
						if (!TestBuildRail().TryBuild(depotTile, depotFront, depotRailc)) {
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
							if (!TestRemoveRail().TryRemove(depotTile, depotFront, depotRailb)) {
								++counter;;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while(counter < 1);

						if (counter == 1) {
							::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, m_railtype, depotTile, depotRailb));
						}
						local counter = 0;
						do {
							if (!TestRemoveRail().TryRemove(depotTile, depotFront, depotRaila)) {
								++counter;;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while(counter < 1);

						if (counter == 1) {
							::scheduledRemovalsTable.Train.append(RailStruct.SetRail(depotFront, m_railtype, depotTile, depotRaila));
						}
						local counter = 0;
						do {
							if (!TestDemolishTile().TryDemolish(depotTile)) {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);

						if (counter == 1) {
							::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depotTile, RailStructType.DEPOT, m_railtype));
							return null;
						}
						else {
							return null;
						}
					}
					else {
						return depotTile;
					}
				}
			}
		}
	}

	function buildDepot(stationTile, stationDir) {
		local depotTile = null;

		AIRail.SetCurrentRailType(m_railtype);
		local station = RailStation.CreateFromTile(stationTile, stationDir);
		local stationFromPlat2 = station.GetPlatformLine(2);

		/* first attempt, build next to line 2 */
		local depotTile2 = station.GetExitTile(2) - station.GetExitTile(1) + station.GetExitTile(2);
		local depotFront2 = station.GetExitTile(2);
		local depotRail2a = station.GetEntryTile(2);
		local depotRail2b = station.GetExitTile(2) - station.GetEntryTile(2) + station.GetExitTile(2);
		local depotRail2c = station.GetExitTile(1);

		if (AITestMode() && AIRail.BuildRail(depotTile2, depotFront2, depotRail2a) && AIRail.BuildRail(depotTile2, depotFront2, depotRail2b) &&
				AIRail.BuildRail(depotTile2, depotFront2, depotRail2c) && AIRail.BuildRailDepot(depotTile2, depotFront2)) {
			depotTile = buildDepotOnTile(depotTile2, depotFront2, depotRail2a, depotRail2b, depotRail2c);
		}
		if (depotTile != null) {
			return depotTile;
		}

		/* second attempt, build next to line 1 */
		local depotTile1 = station.GetExitTile(1) - station.GetExitTile(2) + station.GetExitTile(1);
		local depotFront1 = station.GetExitTile(1);
		local depotRail1a = station.GetEntryTile(1);
		local depotRail1b = station.GetExitTile(1) - station.GetEntryTile(1) + station.GetExitTile(1);
		local depotRail1c = station.GetExitTile(1);

		if (AITestMode() && AIRail.BuildRail(depotTile1, depotFront1, depotRail1a) && AIRail.BuildRail(depotTile1, depotFront1, depotRail1b) &&
				AIRail.BuildRail(depotTile1, depotFront1, depotRail1c) && AIRail.BuildRailDepot(depotTile1, depotFront1)) {
			depotTile = buildDepotOnTile(depotTile1, depotFront1, depotRail1a, depotRail1b, depotRail1c);
		}
		if (depotTile != null) {
			return depotTile;
		}

		/* no third attempt */
//		AILog.Warning("Couldn't build rail depot!");
		return depotTile;
	}

	function saveBuildManager() {
		if (m_cityFrom == null) m_cityFrom = -1;
		if (m_cityTo == null) m_cityTo = -1;
		if (m_stationFrom == null) m_stationFrom = -1;
		if (m_stationTo == null) m_stationTo = -1;
		if (m_depotFrom == null) m_depotFrom = -1;
		if (m_depotTo == null) m_depotTo = -1;

		return [m_cityFrom, m_cityTo, m_stationFrom, m_stationTo, m_depotFrom, m_depotTo, m_bridgeTiles, m_cargoClass, m_railtype, m_best_routes_built, m_stationFromDir, m_stationToDir, m_builtTiles];
	}

	function loadBuildManager(data) {
		m_cityFrom = data[0];
		m_cityTo = data[1];
		m_stationFrom = data[2];
		m_stationTo = data[3];
		m_depotFrom = data[4];
		m_depotTo = data[5];
		m_bridgeTiles = data[6];
		m_cargoClass = data[7];
		m_railtype = data[8];
		m_best_routes_built = data[9];
		m_stationFromDir = data[10];
		m_stationToDir = data[11];
		m_builtTiles = data[12];

		if (m_builtTiles.len() != 0) {
			/* incomplete route found most likely */
			RemoveFailedRouteTracks();
		}
	}
}
