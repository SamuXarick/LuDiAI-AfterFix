require("RoadPathfinder.nut");

enum RoadTileType {
	ROAD,
	TUNNEL,
	BRIDGE
}

class RoadTile {
	m_tile = null;
	m_type = null;
	m_bridge_id = null;

	constructor(tile, type, bridgeId = -1) {
		m_tile = tile;
		m_type = type;
		m_bridge_id = bridgeId;
	}
}

class RoadBuildManager {

	m_cityFrom = -1;
	m_cityTo = -1;
	m_stationFrom = -1;
	m_stationTo = -1;
	m_depotTile = -1;
	m_bridgeTiles = [];
	m_cargoClass = -1;
	m_articulated = -1;
	m_pathfinder = null;
	m_pathfinderTries = 0;
	m_pathfinderProfile = -1;
	m_builtTiles = [];
	m_sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	function BuildTownRoadStation(town, cargoClass, stationTile, otherTown, articulated, best_routes_built);
	function PathfindBuildRoad(fromTile, toTile, silent_mode, pathfinder);
	function FindSuitableRoadDepotTile(tile);
	function BuildRouteRoadDepot(roadArray);
	function SaveBuildManager();
	function BuildRoadRoute(cityFrom, cityTo, cargoClass, articulated, sentToDepotRoadGroup, best_routes_built);

	function HasUnfinishedRoute() {
		return m_cityFrom != -1 && m_cityTo != -1 && m_cargoClass != -1;
	}

	function SetRouteFinished() {
		m_cityFrom = -1;
		m_cityTo = -1;
		m_stationFrom = -1;
		m_stationTo = -1;
		m_depotTile = -1;
		m_bridgeTiles = [];
		m_cargoClass = -1;
		m_articulated = -1;
		m_builtTiles = [];
		m_sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
		m_best_routes_built = null;
		m_pathfinderProfile = -1;
	}

	function BuildRoadRoute(cityFrom, cityTo, cargoClass, articulated, sentToDepotRoadGroup, best_routes_built) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_cargoClass = cargoClass;
		m_articulated = articulated;
		m_sentToDepotRoadGroup = sentToDepotRoadGroup;
		m_best_routes_built = best_routes_built;
		if (m_pathfinderProfile == -1) m_pathfinderProfile = AIController.GetSetting("pf_profile");

		local num_vehicles = AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_ROAD);
		if (num_vehicles >= AIGameSettings.GetValue("max_roadveh") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD)) {
			/* Don't terminate the route, or it may leave already built stations behind. */
			return 0;
		}

		if (m_stationFrom == -1) {
			m_stationFrom = BuildTownRoadStation(m_cityFrom, m_cargoClass, null, m_cityTo, m_articulated, m_best_routes_built);
			if (m_stationFrom == null) {
				SetRouteFinished();
				return null;
			}
		}

		if (m_stationTo == -1) {
			m_stationTo = BuildTownRoadStation(m_cityTo, m_cargoClass, null, m_cityFrom, m_articulated, m_best_routes_built);
			if (m_stationTo == null) {
				if (m_stationFrom != null) {
//					local drivethrough = AIRoad.IsDriveThroughRoadStationTile(m_stationFrom);
					local counter = 0;
					do {
						if (!TestRemoveRoadStation().TryRemove(m_stationFrom)) {
							++counter;
						}
						else {
//							if (drivethrough) {
//								AILog.Warning("m_stationTo; Removed drive through station tile at " + m_stationFrom);
//							} else {
//								AILog.Warning("m_stationTo; Removed road station tile at " + m_stationFrom);
//							}
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);
					if (counter == 500) {
						::scheduledRemovalsTable.Road.rawset(m_stationFrom, 0);
//						if (drivethrough) {
//							AILog.Error("Failed to remove drive through station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
//						} else {
//							AILog.Error("Failed to remove road station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
//						}
					}
				}
				SetRouteFinished();
				return null;
			}
		}

		if (m_depotTile == -1) {
			local roadArray = PathfindBuildRoad(m_stationFrom, m_stationTo, false, m_pathfinder, m_builtTiles);
			m_pathfinder = roadArray[1];
			if (roadArray[0] == null && m_pathfinder != null) {
				return 0;
			}
			m_depotTile = BuildRouteRoadDepot(roadArray[0]);
		}

		if (m_depotTile == null) {
			if (m_stationFrom != null) {
//				local drivethrough = AIRoad.IsDriveThroughRoadStationTile(m_stationFrom);
				local counter = 0;
				do {
					if (!TestRemoveRoadStation().TryRemove(m_stationFrom)) {
						++counter;
					}
					else {
//						if (drivethrough) {
//							AILog.Warning("m_depotTile m_stationFrom; Removed drive through station tile at " + m_stationFrom);
//						} else {
//							AILog.Warning("m_depotTile m_stationFrom; Removed road station tile at " + m_stationFrom);
//						}
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Road.rawset(m_stationFrom, 0);
//					if (drivethrough) {
//						AILog.Error("Failed to remove drive through station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
//					} else {
//						AILog.Error("Failed to remove road station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
//					}
				}
			}

			if (m_stationTo != null) {
//				local drivethrough = AIRoad.IsDriveThroughRoadStationTile(m_stationTo);
				local counter = 0;
				do {
					if (!TestRemoveRoadStation().TryRemove(m_stationTo)) {
						++counter;
					}
					else {
//						if (drivethrough) {
//							AILog.Warning("m_depotTile m_stationTo; Removed drive through station tile at " + m_stationTo);
//						} else {
//							AILog.Warning("m_depotTile m_stationTo; Removed road station tile at " + m_stationTo);
//						}
						break;
					}
					AIController.Sleep(1);
				} while (counter < 500);
				if (counter == 500) {
					::scheduledRemovalsTable.Road.rawset(m_stationTo, 0);
//					if (drivethrough) {
//						AILog.Error("Failed to remove drive through station tile at " + m_stationTo + " - " + AIError.GetLastErrorString());
//					} else {
//						AILog.Error("Failed to remove road station tile at " + m_stationTo + " - " + AIError.GetLastErrorString());
//					}
				}
			}

			SetRouteFinished();
			return null;
		}

		m_builtTiles = [];
		return RoadRoute(m_cityFrom, m_cityTo, m_stationFrom, m_stationTo, m_depotTile, m_bridgeTiles, m_cargoClass, m_sentToDepotRoadGroup);
	}

	function BuildTownRoadStation(town, cargoClass, stationTile, otherTown, articulated, best_routes_built) {
		local stationId = (stationTile == null) ? AIStation.STATION_NEW : AIStation.GetStationID(stationTile);
		local vehicleType = (cargoClass == AICargo.CC_MAIL) ? AIRoad.ROADVEHTYPE_TRUCK : AIRoad.ROADVEHTYPE_BUS;
//		local max_spread = AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations");

		local cargoType = Utils.GetCargoType(cargoClass);
		local radius = cargoClass == AICargo.CC_PASSENGERS ? AIStation.GetCoverageRadius(AIStation.STATION_BUS_STOP) : AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);

		local tileList = AITileList();
		if (stationTile == null) {
			/* stationTile = AIStation.STATION_NEW; */
			/* build square around @town and find suitable tiles for truck stops */
			local rectangleCoordinates = Utils.EstimateTownRectangle(town);

			tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);

			local templist = AITileList();
			templist.AddList(tileList);
			for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
				if (!Utils.IsStationBuildableTile(tile)) {
					templist.RemoveTile(tile);
					continue;
				}

				if (AITile.GetCargoAcceptance(tile, cargoType, 1, 1, radius) < 8) {
					templist.RemoveTile(tile);
					continue;
				}

				if (Utils.AreOtherStationsNearby(tile, cargoClass, stationId)) {
					templist.RemoveTile(tile);
					continue;
				}
				local cargo_production = AITile.GetCargoProduction(tile, cargoType, 1, 1, radius);
				local pick_mode = AIController.GetSetting("pick_mode");
				if (pick_mode != 1 && !best_routes_built && cargo_production < 8) {
					templist.RemoveTile(tile);
					continue;
				} else {
					templist.SetValue(tile, cargo_production);
				}
//				templist.SetValue(tile, AITile.GetCargoProduction(tile, cargoType, 1, 1, radius));
			}
			tileList.Clear();
			tileList.AddList(templist);
			/* valuate and sort by the number of cargo tiles the station covers */
			tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // starts from corners if without sort
		}
		else {
			/* expanding existing station */
			if (!AIStation.IsValidStation(stationId)) {
				return null;
			}

			local squareSize = AIGameSettings.GetValue("station_spread") / 2;

			tileList.AddRectangle(Utils.GetValidOffsetTile(stationTile, -1 * squareSize, -1 * squareSize),
				Utils.GetValidOffsetTile(stationTile, squareSize, squareSize));

			local templist = AITileList();
			templist.AddList(tileList);
			for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
				if (!Utils.IsStationBuildableTile(tile)) {
					templist.RemoveTile(tile);
					continue;
				}

				if (Utils.AreOtherStationsNearby(tile, cargoClass, stationId)) {
					templist.RemoveTile(tile);
					continue;
				}

				local cargo_production = AITile.GetCargoProduction(tile, cargoType, 1, 1, radius);
				if (cargo_production == 0) {
					templist.RemoveTile(tile);
					continue;
				} else {
					templist.SetValue(tile, cargo_production);
				}
			}
			tileList.Clear();
			tileList.AddList(templist);

			tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		}

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (stationTile == null && AITile.GetClosestTown(tile) != town) continue;

			/* get adjacent tiles */
			local adjTileList = Utils.GetAdjacentTiles(tile);
			local adjRoadTiles = AITileList();
			for (local tile = adjTileList.Begin(); !adjTileList.IsEnd(); tile = adjTileList.Next()) {
				if (AIRoad.IsRoadTile(tile)) {
					adjRoadTiles.AddTile(tile);
				}
			}

			AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
			local adjRoadCount = adjRoadTiles.Count();
			local adjacentNonRoadStation = Utils.CheckAdjacentNonRoadStation(tile, stationId);

			switch (adjRoadCount) {
			/* case where station tile has no adjacent road tiles */
				case 0:
					if (stationTile != null) {
						continue;
					}

					if (articulated) {
						continue;
					}

					/* avoid blocking other station exits */
					local blocking = false;
					for (local adjTile = adjTileList.Begin(); !adjTileList.IsEnd(); adjTile = adjTileList.Next()) {
						if (AIRoad.IsRoadStationTile(adjTile) && AIRoad.GetRoadStationFrontTile(adjTile) == tile) {
							blocking = true;
							break;
						}
					}

					if (blocking) {
						continue;
					}

					local closestAdjTile = null;
					for (local adjTile = adjTileList.Begin(); !adjTileList.IsEnd(); adjTile = adjTileList.Next()) {
						if (!AITile.IsBuildable(adjTile) || AITile.HasTransportType(adjTile, AITile.TRANSPORT_WATER) && AICompany.GetLoanAmount() != 0) {
							continue;
						}

						if (closestAdjTile == null) {
							closestAdjTile = adjTile;
						}

						if (AITown.GetDistanceManhattanToTile(otherTown, adjTile) < AITown.GetDistanceManhattanToTile(otherTown, closestAdjTile)) {
							closestAdjTile = adjTile;
						}
					}

					if (closestAdjTile == null) {
						continue;
					}

					local counter = 0;
					do {
						if (!TestBuildRoadStation().TryBuild(tile, closestAdjTile, vehicleType, adjacentNonRoadStation)) {
//							if (AIError.GetLastErrorString() != "ERR_ALREADY_BUILT" && AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED") {
//								AILog.Warning("Couldn't build station! " + AIError.GetLastErrorString());
//							}
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);
					if (counter == 1) {
						continue;
					}

					AILog.Info("Station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
//					AISign.BuildSign(tile, "" + adjRoadCount);
					return tile;

					break;

				case 1:
					/* avoid blocking other station exits */
					local blocking = false;
					for (local adjTile = adjTileList.Begin(); !adjTileList.IsEnd(); adjTile = adjTileList.Next()) {
						if (AIRoad.IsRoadStationTile(adjTile) && AIRoad.GetRoadStationFrontTile(adjTile) == tile) {
							blocking = true;
							break;
						}
					}

					if (blocking) {
						continue;
					}

					local adjTile = adjRoadTiles.Begin();
					if (AIRoad.IsDriveThroughRoadStationTile(adjTile)) {
						continue;
					}

					local heighDifference = abs(AITile.GetMaxHeight(tile) - AITile.GetMaxHeight(adjTile));

					if (heighDifference != 0) {
						continue;
					}

					if (!articulated) {
						local counter = 0;
						do {
							/* Try to build a road station */
							if (!TestBuildRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentNonRoadStation)) {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);
						if (counter == 1) {
							/* Failed to build station, try the next location */
							continue;
						}
						else {
							/* With the road station built, try to connect it to the road */
							local counter = 0;
							do {
								if (!TestBuildRoad().TryBuild(tile, adjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < (stationTile == null ? 500 : 1));
							if (counter == (stationTile == null ? 500 : 1)) {
								/* Failed to connect road to the station. Try to remove the station we had built then */
								local counter = 0;
								do {
									if (!TestRemoveRoadStation().TryRemove(tile)) {
										++counter;
									}
									else {
//										AILog.Warning("case" + adjRoadCount + "; Removed road station tile at " + tile);
										break;
									}
									AIController.Sleep(1);
								} while (counter < (stationTile == null ? 500 : 1));
								if (counter == (stationTile == null ? 500 : 1)) {
									::scheduledRemovalsTable.Road.rawset(tile, 0);
//									AILog.Error("Failed to remove road station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									/* The station was successfully removed after failing to connect it to the road. Try it all over again in the next location */
									continue;
								}
							}
							else {
								/* The road was successfully connected to the station */
								AILog.Info("Station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
//								AISign.BuildSign(tile, "" + adjRoadCount);
								return tile;
							}
						}
					}
					else {
						if (AIRoad.IsRoadTile(tile)) {
							local counter = 0;
							do {
								/* Try to build a drivethrough road station */
								if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentNonRoadStation)) {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < 1);
							if (counter == 1) {
								/* Failed to build station, try the next location */
								continue;
							}
							else {
								/* With the road station built, try to connect it to the road */
								local counter = 0;
								do {
									if (!TestBuildRoad().TryBuild(tile, adjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
										++counter;
									}
									else {
										break;
									}
									AIController.Sleep(1);
								} while (counter < (stationTile == null ? 500 : 1));
								if (counter == (stationTile == null ? 500 : 1)) {
									/* Failed to connect road to the station. Try to remove the station we had built then */
									local counter = 0;
									do {
										if (!TestRemoveRoadStation().TryRemove(tile)) {
											++counter;
										}
										else {
//											AILog.Warning("case" + adjRoadCount + "; Removed drive through station tile at " + tile);
											break;
										}
										AIController.Sleep(1);
									} while (counter < (stationTile == null ? 500 : 1));
									if (counter == (stationTile == null ? 500 : 1)) {
										::scheduledRemovalsTable.Road.rawset(tile, 0);
//										AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
										continue;
									} else {
										/* The station was successfully removed after failing to connect it to the road. Try it all over again in the next location */
										continue;
									}
								}
								else {
									/* The road was successfully connected to the station */
									AILog.Info("Drivethrough station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
//									AISign.BuildSign(tile, "" + adjRoadCount);
									return tile;
								}
							}
						}
						else {
							continue;
						}
					}

					break;

				case 2:
					local adjTile = adjRoadTiles.Begin();
					local nextAdjTile = adjRoadTiles.Next();

					/* don't build drivethrough station next to regular station */
					adjTileList.RemoveItem(adjTile);
					adjTileList.RemoveItem(nextAdjTile);
					local blocking = false;
					for (local t = adjTileList.Begin(); !adjTileList.IsEnd(); t = adjTileList.Next()) {
						if (AIRoad.IsRoadStationTile(t) && AIRoad.GetRoadStationFrontTile(t) == tile ||
							AIRoad.IsRoadDepotTile(t) && AIRoad.GetRoadDepotFrontTile(t) == tile ||
							AIRoad.IsDriveThroughRoadStationTile(t) && (AIRoad.GetRoadStationFrontTile(t) != tile || AIRoad.GetDriveThroughBackTile(t) != tile)) {
							blocking = true;
							break;
						}
					}
					if (blocking) {
						continue;
					}

					/* check whether adjacent tiles are opposite */
					local opposite = false;
					if (AIMap.GetTileX(adjTile) == AIMap.GetTileX(nextAdjTile) || AIMap.GetTileY(adjTile) == AIMap.GetTileY(nextAdjTile)) {
							opposite = true;
					}

					if (AIRoad.IsRoadTile(tile)) {
						if (!opposite) {
							continue;
						}
					}

					if (opposite) {
						local has_road = AIRoad.IsRoadTile(tile);
						local heighDifference = abs(AITile.GetMaxHeight(nextAdjTile) - AITile.GetMaxHeight(adjTile));
						if (heighDifference != 0) {
							continue;
						}

						local counter = 0;
						do {
							if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentNonRoadStation)) {
//								if (AIError.GetLastErrorString() != "ERR_ALREADY_BUILT" && AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED" && AIError.GetLastErrorString() != "ERR_LOCAL_AUTHORITY_REFUSES") {
//									AILog.Warning("Couldn't build station! " + AIError.GetLastErrorString());
//								}
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1)
						} while (counter < 1);
						if (counter == 1) {
							continue;
						}
						else {
							local counter = 0;
							do {
								if (!TestBuildRoad().TryBuild(adjTile, nextAdjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < (stationTile == null ? 500 : 1));
							if (counter == (stationTile == null ? 500 : 1)) {
								local counter = 0;
								local removed = false;
								do {
									if (has_road) {
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
//										AILog.Warning("case" + adjRoadCount + "; Removed drive through station tile at " + tile);
										break;
									}
									AIController.Sleep(1);
								} while (counter < (stationTile == null ? 500 : 1));
								if (counter == (stationTile == null ? 500 : 1)) {
									::scheduledRemovalsTable.Road.rawset(tile, has_road ? 0 : 1);
//									AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									continue;
								}
							}
							else {
								AILog.Info("Drivethrough station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
//								AISign.BuildSign(tile, "" + adjRoadCount);
								return tile;
							}
						}
					}
					/* similar to case 1 if adjacent tiles are not opposite */
					else {
						if (articulated) {
							continue;
						}

						local heighDifference = abs(AITile.GetMaxHeight(tile) - AITile.GetMaxHeight(adjTile));
						if (heighDifference != 0) {
							heighDifference = abs(AITile.GetMaxHeight(tile) - AITile.GetMaxHeight(nextAdjTile));
							if (heighDifference != 0) {
								continue;
							} else {
								adjTile = nextAdjTile;
							}
						}

						local counter = 0;
						do {
							if (!TestBuildRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentNonRoadStation)) {
//								if (AIError.GetLastErrorString() != "ERR_ALREADY_BUILT" && AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED" && AIError.GetLastErrorString() != "ERR_LOCAL_AUTHORITY_REFUSES") {
//									AILog.Warning("Couldn't build station! " + AIError.GetLastErrorString());
//								}
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < 1);
						if (counter == 1) {
							continue;
						}
						else {
							local counter = 0;
							do {
								if (!TestBuildRoad().TryBuild(tile, adjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while (counter < (stationTile == null ? 500 : 1));
							if (counter == (stationTile == null ? 500 : 1)) {
								local counter = 0;
								do {
									if (!TestRemoveRoadStation().TryRemove(tile)) {
										++counter;
									}
									else {
//										AILog.Warning("case" + adjRoadCount + "; Removed road station tile at " + tile);
										break;
									}
									AIController.Sleep(1);
								} while (counter < (stationTile == null ? 500 : 1));
								if (counter == (stationTile == null ? 500 : 1)) {
									::scheduledRemovalsTable.Road.rawset(tile, 0);
//									AILog.Error("Failed to remove road station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									continue;
								}
							}
							else {
								AILog.Info("Station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
//								AISign.BuildSign(tile, "" + adjRoadCount);
								return tile;
							}
						}
					}

					break;

				case 3:
				case 4:
					/* similar to case 2 but always builds drivethrough station */

					if (AIRoad.IsRoadTile(tile)) {
						continue;
					}

					/* avoid blocking other station exits */
					local blocking = false;
					for (local adjTile = adjTileList.Begin(); !adjTileList.IsEnd(); adjTile = adjTileList.Next()) {
						if (AIRoad.IsRoadStationTile(adjTile) && AIRoad.GetRoadStationFrontTile(adjTile) == tile) {
							blocking = true;
							break;
						}
					}

					if (blocking) {
						continue;
					}

					/* check which adjacent tiles are opposite */
					local adjTile = Utils.GetOffsetTile(tile, -1, 0);
					local nextAdjTile = Utils.GetOffsetTile(tile, 1, 0);
					if (!(adjRoadTiles.HasItem(adjTile) && adjRoadTiles.HasItem(nextAdjTile))) {
						adjTile = Utils.GetOffsetTile(tile, 0, -1);
						nextAdjTile = Utils.GetOffsetTile(tile, 0, 1);
					}

					local heighDifference = abs(AITile.GetMaxHeight(nextAdjTile) - AITile.GetMaxHeight(adjTile));
					if (heighDifference != 0) {
						continue;
					}

					local counter = 0;
					do {
						if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentNonRoadStation)) {
//							if (AIError.GetLastErrorString() != "ERR_ALREADY_BUILT" && AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED" && AIError.GetLastErrorString() != "ERR_LOCAL_AUTHORITY_REFUSES") {
//								AILog.Warning("Couldn't build station! " + AIError.GetLastErrorString());
//							}
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 1);
					if (counter == 1) {
						continue;
					}
					else {
						local counter = 0;
						do {
							if (!TestBuildRoad().TryBuild(adjTile, nextAdjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while (counter < (stationTile == null ? 500 : 1));
						if (counter == (stationTile == null ? 500 : 1)) {
							local counter = 0;
							do {
								if (!TestDemolishTile().TryDemolish(tile)) {
									++counter;
								}
								else {
//									AILog.Warning("case" + adjRoadCount + "; Removed drive through station tile at " + tile);
									break;
								}
								AIController.Sleep(1);
							} while (counter < stationTile == null ? 500 : 1);
							if (counter == (stationTile == null ? 500 : 1)) {
								::scheduledRemovalsTable.Road.rawset(tile, 1);
//								AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
								continue;
							} else {
								continue;
							}
						}
						else {
							AILog.Info("Drivethrough station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
//							AISign.BuildSign(tile, "" + adjRoadCount);
							return tile;
						}
					}

					break;

				default:
					break;
			}
		}

		return null;
	}

	/* find road way between fromTile and toTile */
	function PathfindBuildRoad(fromTile, toTile, silent_mode = false, pathfinder = null, builtTiles = [], cost_so_far = 0) {
		/* can store road tiles into array */

		if (fromTile != toTile) {
			local route_dist = AIMap.DistanceManhattan(AITown.GetLocation(m_cityFrom), AITown.GetLocation(m_cityTo));
			assert(m_pathfinderProfile != -1);
			local max_pathfinderTries = route_dist;
			if (m_pathfinderProfile == 0) {
				max_pathfinderTries = 1250 * route_dist;
			} else if (m_pathfinderProfile == 1) {
				max_pathfinderTries = 500 * route_dist;
			} else {
				max_pathfinderTries = 5000 * route_dist / 15 + 5000 * route_dist % 15;
			}

			/* Print the names of the towns we'll try to connect. */
			if (!silent_mode) AILog.Info("r:Connecting " + AITown.GetName(m_cityFrom) + " (tile " + fromTile + ") and " + AITown.GetName(m_cityTo) + " (tile " + toTile + ") (iteration " + (m_pathfinderTries + 1) + "/" + max_pathfinderTries + ")");

			/* Tell OpenTTD we want to build normal road (no tram tracks). */
			AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

			if (pathfinder == null) {
				/* Create an instance of the pathfinder. */
				pathfinder = Road();

				switch(m_pathfinderProfile) {
					case 0:
						AILog.Info("road pathfinder: custom");
/*defaults*/
/*10000000*/			pathfinder.cost.max_cost;
/*100*/					pathfinder.cost.tile;
/*20*/					pathfinder.cost.no_existing_road = 40;
/*100*/					pathfinder.cost.turn;
/*200*/					pathfinder.cost.slope = AIGameSettings.GetValue("roadveh_acceleration_model") ? AIGameSettings.GetValue("roadveh_slope_steepness") * 20 : pathfinder.cost.slope;
/*150*/					pathfinder.cost.bridge_per_tile = 50;
/*120*/					pathfinder.cost.tunnel_per_tile = 60;
/*20*/					pathfinder.cost.coast = (AICompany.GetLoanAmount() == 0) ? pathfinder.cost.coast : 5000;
/*0*/					pathfinder.cost.drive_through = 800;
/*10*/					pathfinder.cost.max_bridge_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*20*/					pathfinder.cost.max_tunnel_length = (AICompany.GetLoanAmount() == 0) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
/*0*/					pathfinder.cost.search_range = min(route_dist / 5, 25);
						break;

					case 2:
						AILog.Info("road pathfinder: fastest");

						pathfinder.cost.max_cost;
						pathfinder.cost.tile;
						pathfinder.cost.no_existing_road = 10;
						pathfinder.cost.turn = 250;
						pathfinder.cost.slope = 50;
						pathfinder.cost.bridge_per_tile;
						pathfinder.cost.tunnel_per_tile;
						pathfinder.cost.coast = 5000;
						pathfinder.cost.drive_through;
						pathfinder.cost.max_bridge_length = 3;
						pathfinder.cost.max_tunnel_length = 0;
						pathfinder.cost.search_range = 3;
						break;

					case 1:
					default:
						AILog.Info("road pathfinder: default");

						pathfinder.cost.max_cost;
						pathfinder.cost.tile;
						pathfinder.cost.no_existing_road;
						pathfinder.cost.turn;
						pathfinder.cost.slope;
						pathfinder.cost.bridge_per_tile;
						pathfinder.cost.tunnel_per_tile;
						pathfinder.cost.coast;
						pathfinder.cost.drive_through;
						pathfinder.cost.max_bridge_length;
						pathfinder.cost.max_tunnel_length;
						pathfinder.cost.search_range;
						break;

				}
				/* Give the source and goal tiles to the pathfinder. */
				pathfinder.InitializePath(fromTile, toTile);
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
//							if (!silent_mode) AILog.Info("road pathfinder: FindPath iterated: " + count);
//							local signList = AISignList();
//							for (local sign = signList.Begin(); !signList.IsEnd(); sign = signList.Next()) {
//								if (signList.Count() < 64000) break;
//								if (AISign.GetName(sign) == "x") AISign.RemoveSign(sign);
//							}
							return [null, pathfinder];
						}
					} else {
						/* Timed out */
						if (!silent_mode) AILog.Error("road pathfinder: FindPath return false (timed out)");
						m_pathfinderTries = 0;
						return [null, null];
					}
				}

				if (path == null ) {
					/* No path was found. */
					if (!silent_mode) AILog.Error("road pathfinder: FindPath return null (no path)");
					m_pathfinderTries = 0;
					return [null, null];
				}
			} while (path == false);

//			if (!silent_mode && m_pathfinderTries != count) AILog.Info("road pathfinder: FindPath iterated: " + count);
			if (!silent_mode) AILog.Info("Road path found! FindPath iterated: " + m_pathfinderTries + ". Building road... ");
			if (!silent_mode) AILog.Info("road pathfinder: FindPath cost: " + path.GetCost());
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
//										if (!silent_mode) AILog.Warning("We found a road already built at tiles " + path.GetTile() + " and " + par.GetTile());
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" && AITunnel.IsTunnelTile(path.GetTile()) && AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
//										if (!silent_mode) AILog.Warning("We found a road tunnel already built at tiles " + path.GetTile() + " and " + par.GetTile());
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" && AIBridge.IsBridgeTile(path.GetTile()) && AIBridge.GetOtherBridgeEnd(path.GetTile()) == par.GetTile()) {
//										if (!silent_mode) AILog.Warning("We found a road bridge already built at tiles " + path.GetTile() + " and " + par.GetTile());
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
										if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
											if (!silent_mode) AILog.Warning("Couldn't build road at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
											return PathfindBuildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
										}
									}
									++counter;
								}
								else {
									road_cost += costs.GetCosts();
//									if (!silent_mode) AILog.Warning("We built a road at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
									break;
								}

								AIController.Sleep(1);
							} while (counter < 500);

							if (counter == 500) {
								if (!silent_mode) AILog.Warning("Couldn't build road at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
								m_pathfinderTries = 0;
								return [null, null];
							}

							/* add road piece into the road array */
							m_builtTiles.append(RoadTile(path.GetTile(), RoadTileType.ROAD));
						}
						else {
							if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
								if (!silent_mode) AILog.Warning("Won't build a road crossing a rail at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
								return PathfindBuildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
							}
							else {
								if (!silent_mode) AILog.Warning("Won't build a road crossing a rail at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
								m_pathfinderTries = 0;
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
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't demolish road at tile " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return PathfindBuildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										if (!silent_mode) AILog.Warning("We demolished a road at tile " + path.GetTile() + ". ec: 0, ac: " + costs.GetCosts());
										break;
									}

									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't demolish road at tile " + path.GetTile() + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}
							}
							if (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (!TestBuildTunnel().TryBuild(AIVehicle.VT_ROAD, path.GetTile())) {
										if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" && AITunnel.IsTunnelTile(path.GetTile()) && (AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) && last_node != null && AIRoad.AreRoadTilesConnected(path.GetTile(), last_node)) {
//											if (!silent_mode) AILog.Warning("We found a road tunnel already built at tiles " + path.GetTile() + " and " + par.GetTile());
											break;
										}
										else if (AIError.GetLastErrorString() == "ERR_ANOTHER_TUNNEL_IN_THE_WAY") {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build road tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return PathfindBuildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										if (!silent_mode) AILog.Warning("We built a road tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
										break;
									}

									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build road tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}

								m_builtTiles.append(RoadTile(path.GetTile(), RoadTileType.TUNNEL));

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
//											if (!silent_mode) AILog.Warning("We found a road bridge already built at tiles " + path.GetTile() + " and " + par.GetTile());
											m_bridgeTiles.append(path.GetTile() < par.GetTile() ? [path.GetTile(), par.GetTile()] : [par.GetTile(), path.GetTile()]);
											break;
										}
										else if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
											for (local bridge = bridge_list.Begin(); !bridge_list.IsEnd(); bridge = bridge_list.Next()) {
												bridge_list.SetValue(bridge, AIBridge.GetPrice(bridge, bridge_length));
											}
											bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
										}
										else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build road bridge at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return PathfindBuildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										if (!silent_mode) AILog.Warning("We built a road bridge at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
										m_bridgeTiles.append(path.GetTile() < par.GetTile() ? [path.GetTile(), par.GetTile()] : [par.GetTile(), path.GetTile()]);
										break;
									}

									AIController.Sleep(1);
								} while (counter < 500);

								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build road bridge at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}

								m_builtTiles.append(RoadTile(path.GetTile(), RoadTileType.BRIDGE, bridge_list.Begin()));
								m_builtTiles.append(RoadTile(par.GetTile(), RoadTileType.ROAD));
							}
						}
					}
				}
				last_node = path.GetTile();
				path = par;
			}
			if (!silent_mode) AILog.Info("Road built! Actual cost for building road: " + road_cost);
		}

		m_pathfinderTries = 0;
		return [builtTiles, null];
	}

	function FindSuitableRoadDepotTile(tile) {
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

	function BuildRoadDepotOnTile(t) {
		local square = AITileList();
		square.AddRectangle(Utils.GetValidOffsetTile(t, -1, -1), Utils.GetValidOffsetTile(t, 1, 1));

		local depotTile = FindSuitableRoadDepotTile(t);
		local depotFrontTile = t;

		if (depotTile != null) {
			local counter = 0;
			do {
				if (!TestBuildRoadDepot().TryBuild(depotTile, depotFrontTile)) {
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
					if (!TestBuildRoad().TryBuild(depotTile, depotFrontTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
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
						if (!TestRemoveRoadDepot().TryRemove(depotTile)) {
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while (counter < 500);

					if (counter == 500) {
						::scheduledRemovalsTable.Road.rawset(depotTile, 0);
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

	function BuildRouteRoadDepot(roadArray) {
		if (roadArray == null) {
			return null;
		}

		local depotTile = null;

		/* first attempt, build next to the road route */
		local arrayMiddleTile = roadArray[roadArray.len() / 2].m_tile;
		local roadTiles = AITileList();
		for (local index = 1; index < roadArray.len() - 1; ++index) {
			roadTiles.AddItem(roadArray[index].m_tile, AIMap.DistanceManhattan(roadArray[index].m_tile, arrayMiddleTile));
		}
		roadTiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		for (local tile = roadTiles.Begin(); !roadTiles.IsEnd(); tile = roadTiles.Next()) {
			depotTile = BuildRoadDepotOnTile(tile);
			if (depotTile != null) {
				return depotTile;
			}
		}

		local squareSize = AIGameSettings.GetValue("station_spread");

		/* second attempt, build closer to the destination */
		local tileList = AITileList();
		tileList.AddRectangle(Utils.GetValidOffsetTile(m_stationTo, -1 * squareSize, -1 * squareSize),
			Utils.GetValidOffsetTile(m_stationTo, squareSize, squareSize));

		local removelist = AITileList();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (!AIRoad.IsRoadTile(tile)) {
				removelist.AddTile(tile);
			} else {
				tileList.SetValue(tile, AIMap.DistanceManhattan(tile, m_stationTo));
			}
		}
		tileList.RemoveList(removelist);
		tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			depotTile = BuildRoadDepotOnTile(tile);
			if (depotTile != null) {
				return depotTile;
			}
		}

		/* third attempt, build closer to the source */
		tileList.Clear();

		tileList.AddRectangle(Utils.GetValidOffsetTile(m_stationFrom, -1 * squareSize, -1 * squareSize),
			Utils.GetValidOffsetTile(m_stationFrom, squareSize, squareSize));

		removelist.Clear();
		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (!AIRoad.IsRoadTile(tile)) {
				removelist.AddTile(tile);
			} else {
				tileList.SetValue(tile, AIMap.DistanceManhattan(tile, m_stationFrom));
			}
		}
		tileList.RemoveList(removelist);
		tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			depotTile = BuildRoadDepotOnTile(tile);
			if (depotTile != null) {
				return depotTile;
			}
		}

		AILog.Warning("Couldn't built road depot!");
		return depotTile;
	}

	function SaveBuildManager() {
		if (m_cityFrom == null) m_cityFrom = -1;
		if (m_cityTo == null) m_cityTo = -1;
		if (m_stationFrom == null) m_stationFrom = -1;
		if (m_stationTo == null) m_stationTo = -1;
		if (m_depotTile == null) m_depotTile = -1;
		if (m_articulated == null) m_articulated = -1;

		return [m_cityFrom, m_cityTo, m_stationFrom, m_stationTo, m_depotTile, m_bridgeTiles, m_cargoClass, m_articulated, m_best_routes_built, m_pathfinderProfile];
	}

	function LoadBuildManager(data) {
		m_cityFrom = data[0];
		m_cityTo = data[1];
		m_stationFrom = data[2];
		m_stationTo = data[3];
		m_depotTile = data[4];
		m_bridgeTiles = data[5];
		m_cargoClass = data[6];
		m_articulated = data[7];
		m_best_routes_built = data[8];
		m_pathfinderProfile = data[9];
	}
}
