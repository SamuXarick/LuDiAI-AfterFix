require("RoadPathfinder.nut");

enum RoadTileTypes {
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

class BuildManager {

	m_cityFrom = -1;
	m_cityTo = -1;
	m_stationFrom = -1;
	m_stationTo = -1;
	m_depotTile = -1;
	m_bridgeTiles = AIList();
	m_cargoClass = -1;
	m_articulated = -1;
	m_pathfinder = null;
	m_pathfinderTries = 0;
	m_builtTiles = [];
	m_sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];

	constructor() {

	}

	function buildTownStation(town, cargoClass, stationTile, otherTown, articulated);
	function estimateTownRectangle(town);
	function buildRoad(fromTile, toTile, silent_mode, pathfinder);
	function findRoadTileDepot(tile);
	function buildDepotOnRoad(roadArray);
	function saveBuildManager();
	function buildRoute(cityFrom, cityTo, cargoClass, articulated, sentToDepotRoadGroup);

	function hasUnfinishedRoute() {
		if(m_cityFrom != -1 && m_cityTo != -1 && m_cargoClass != -1) {
			return 1;
		}

		return 0;
	}

	function setRouteFinish() {
		m_cityFrom = -1;
		m_cityTo = -1;
		m_stationFrom = -1;
		m_stationTo = -1;
		m_depotTile = -1;
		m_bridgeTiles = AIList();
		m_cargoClass = -1;
		m_articulated = -1;
		m_builtTiles = [];
		m_sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	}

	function buildRoute(cityFrom, cityTo, cargoClass, articulated, sentToDepotRoadGroup) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_cargoClass = cargoClass;
		m_articulated = articulated;
		m_sentToDepotRoadGroup = sentToDepotRoadGroup;

		local list = AIVehicleList();
		list.Valuate(AIVehicle.GetVehicleType);
		list.KeepValue(AIVehicle.VT_ROAD);
		if (list.Count() >= AIGameSettings.GetValue("max_roadveh") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_ROAD)) {
			setRouteFinish();
			return null;
		}

		if (m_stationFrom == -1) {
			m_stationFrom = buildTownStation(m_cityFrom, m_cargoClass, null, m_cityTo, m_articulated);
			if (m_stationFrom == null) {
				setRouteFinish();
				return null;
			}
		}

		if (m_stationTo == -1) {
			m_stationTo = buildTownStation(m_cityTo, cargoClass, null, m_cityFrom, m_articulated);
			if (m_stationTo == null) {
				if (m_stationFrom != null) {
					local drivethrough = AIRoad.IsDriveThroughRoadStationTile(m_stationFrom);
					local counter = 0;
					do {
						if (!TestRemoveRoadStation().TryRemove(m_stationFrom)) {
							++counter;
						}
						else {
							if (drivethrough) {
//								AILog.Warning("m_stationTo; Removed drive through station tile at " + m_stationFrom);
							} else {
//								AILog.Warning("m_stationTo; Removed road station tile at " + m_stationFrom);
							}
							break;
						}
						AIController.Sleep(1);
					} while(counter < 500);
					if (counter == 500) {
						LuDiAIAfterFix().scheduledRemovals.AddItem(m_stationFrom, 0);
						if (drivethrough) {
//							AILog.Error("Failed to remove drive through station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
						} else {
//							AILog.Error("Failed to remove road station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
						}
					}
				}
				setRouteFinish();
				return null;
			}
		}

		if (m_depotTile == -1) {
			local roadArray = buildRoad(m_stationFrom, m_stationTo, false, m_pathfinder, m_builtTiles);
			m_pathfinder = roadArray[1];
			if (roadArray[0] == null && m_pathfinder != null) {
				return 0;
			}
			m_depotTile = buildDepotOnRoad(roadArray[0]);
		}

		if ((m_depotTile == null)) {
			if (m_stationFrom != null) {
				local drivethrough = AIRoad.IsDriveThroughRoadStationTile(m_stationFrom);
				local counter = 0;
				do {
					if (!TestRemoveRoadStation().TryRemove(m_stationFrom)) {
						++counter;
					}
					else {
						if (drivethrough) {
//							AILog.Warning("m_depotTile m_stationFrom; Removed drive through station tile at " + m_stationFrom);
						} else {
//							AILog.Warning("m_depotTile m_stationFrom; Removed road station tile at " + m_stationFrom);
						}
						break;
					}
					AIController.Sleep(1);
				} while(counter < 500);
				if (counter == 500) {
					LuDiAIAfterFix().scheduledRemovals.AddItem(m_stationFrom, 0);
					if (drivethrough) {
//						AILog.Error("Failed to remove drive through station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
					} else {
//						AILog.Error("Failed to remove road station tile at " + m_stationFrom + " - " + AIError.GetLastErrorString());
					}
				}
			}

			if (m_stationTo != null) {
				local drivethrough = AIRoad.IsDriveThroughRoadStationTile(m_stationTo);
				local counter = 0;
				do {
					if (!TestRemoveRoadStation().TryRemove(m_stationTo)) {
						++counter;
					}
					else {
						if (drivethrough) {
//							AILog.Warning("m_depotTile m_stationTo; Removed drive through station tile at " + m_stationTo);
						} else {
//							AILog.Warning("m_depotTile m_stationTo; Removed road station tile at " + m_stationTo);
						}
						break;
					}
					AIController.Sleep(1);
				} while(counter < 500);
				if (counter == 500) {
					LuDiAIAfterFix().scheduledRemovals.AddItem(m_stationTo, 0);
					if (drivethrough) {
//						AILog.Error("Failed to remove drive through station tile at " + m_stationTo + " - " + AIError.GetLastErrorString());
					} else {
//						AILog.Error("Failed to remove road station tile at " + m_stationTo + " - " + AIError.GetLastErrorString());
					}
				}
			}

			setRouteFinish();
			return null;
		}

		m_builtTiles = [];
		return Route(m_cityFrom, m_cityTo, m_stationFrom, m_stationTo, m_depotTile, m_bridgeTiles, m_cargoClass, m_sentToDepotRoadGroup);
	}

	function buildTownStation(town, cargoClass, stationTile, otherTown, articulated) {
		local stationId = (stationTile == null) ?  AIStation.STATION_NEW : AIStation.GetStationID(stationTile);
		local vehicleType = (cargoClass == AICargo.CC_MAIL) ? AIRoad.ROADVEHTYPE_TRUCK : AIRoad.ROADVEHTYPE_BUS;
//		local max_spread = AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations");

		local cargoType = Utils.getCargoId(cargoClass);
		local radius = cargoClass == AICargo.CC_PASSENGERS ? AIStation.GetCoverageRadius(AIStation.STATION_BUS_STOP) : AIStation.GetCoverageRadius(AIStation.STATION_TRUCK_STOP);

		local tileList = AITileList();
		if(stationTile == null) {
			//stationTile = AIStation.STATION_NEW;
			//build square around @town and find suitable tiles for truck stops
			local rectangleCoordinates = estimateTownRectangle(town);

			tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);

			tileList.Valuate(Utils.IsStationBuildableTile);
			tileList.RemoveValue(0);

			//valuate and sort by the number of cargo tiles the station covers
			tileList.Valuate(AITile.GetCargoAcceptance, cargoType, 1, 1, radius);
			tileList.RemoveBelowValue(8);

			tileList.Valuate(AITile.GetCargoProduction, cargoType, 1, 1, radius);
			tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); //starts from corners if without sort

			for(local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
				if (Utils.AreOtherStationsNearby(tile, cargoClass, stationId)) {
					tileList.RemoveTile(tile);
				}
			}
		}
		else {
			//expanding existing station
			if(!AIStation.IsValidStation(stationId)) {
				return null;
			}

			local squareSize = AIGameSettings.GetValue("station_spread") / 2;

			tileList.AddRectangle(Utils.getValidOffsetTile(stationTile, -1 * squareSize, -1 * squareSize),
				Utils.getValidOffsetTile(stationTile, squareSize, squareSize));

			tileList.Valuate(Utils.IsStationBuildableTile);
			tileList.RemoveValue(0);

			tileList.Valuate(AITile.GetCargoProduction, cargoType, 1, 1, radius);
			tileList.RemoveValue(0);
			tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

			for(local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
				if (Utils.AreOtherStationsNearby(tile, cargoClass, stationId)) {
					tileList.RemoveTile(tile);
				}
			}
		}

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			if (stationTile == null && AITile.GetClosestTown(tile) != town) continue;

			//get adjacent tiles
			local adjTileList = Utils.getAdjacentTiles(tile);
			local adjRoadTiles = AITileList();
			adjRoadTiles.AddList(adjTileList);
			adjRoadTiles.Valuate(AIRoad.IsRoadTile);
			adjRoadTiles.KeepValue(1);

			AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
			local adjRoadCount = adjRoadTiles.Count();
			local adjacentAirport = Utils.checkAdjacentAirport(tile, cargoClass, stationId);

			switch (adjRoadCount) {
			//case where station tile has no adjacent road tiles
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
						if (!AITile.IsBuildable(adjTile) || AITile.HasTransportType(adjTile, AITile.TRANSPORT_WATER) && !Utils.HasMoney(AICompany.GetMaxLoanAmount() * 2)) {
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
						if (!TestBuildRoadStation().TryBuild(tile, closestAdjTile, vehicleType, adjacentAirport)) {
							//if((AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") && (AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED")) {
								//AILog.Warning("Couldnt build station! " + AIError.GetLastErrorString());
							//}
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while(counter < 1);
					if(counter == 1) {
						continue;
					}

					AILog.Info("Station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
					//AISign.BuildSign(tile, "" + adjRoadCount);
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

					if(heighDifference != 0) {
						continue;
					}

					if (!articulated) {
						local counter = 0;
						do {
							/* Try to build a road station */
							if (!TestBuildRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentAirport)) {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while(counter < 1);
						if (counter == 1) {
							/* Failed to build station, try the next location */
							continue;
						}
						else {
							/* With the road station built, try to connect it to the road */
							local counter = 0;
							do {
								if(!TestBuildRoad().TryBuild(tile, adjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while(counter < (stationTile == null ? 500 : 1));
							if(counter == (stationTile == null ? 500 : 1)) {
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
									LuDiAIAfterFix().scheduledRemovals.AddItem(tile, 0);
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
								//AISign.BuildSign(tile, "" + adjRoadCount);
								return tile;
							}
						}
					}
					else {
						if (AIRoad.IsRoadTile(tile)) {
							local counter = 0;
							do {
								/* Try to build a drivethrough road station */
								if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentAirport)) {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while(counter < 1);
							if (counter == 1) {
								/* Failed to build station, try the next location */
								continue;
							}
							else {
								/* With the road station built, try to connect it to the road */
								local counter = 0;
								do {
									if(!TestBuildRoad().TryBuild(tile, adjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
										++counter;
									}
									else {
										break;
									}
									AIController.Sleep(1);
								} while(counter < (stationTile == null ? 500 : 1));
								if(counter == (stationTile == null ? 500 : 1)) {
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
										LuDiAIAfterFix().scheduledRemovals.AddItem(tile, 0);
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
									//AISign.BuildSign(tile, "" + adjRoadCount);
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

					//dont build drivethrough station next to regular station
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

					//check whether adjacent tiles are opposite
					local opposite = false;
					if((AIMap.GetTileX(adjTile) == AIMap.GetTileX(nextAdjTile))
						|| (AIMap.GetTileY(adjTile) == AIMap.GetTileY(nextAdjTile))) {
							opposite = true;
					}

					if(AIRoad.IsRoadTile(tile)) {
						if(!opposite) {
							continue;
						}
					}

					if(opposite) {
						local has_road = AIRoad.IsRoadTile(tile);
						local heighDifference = abs(AITile.GetMaxHeight(nextAdjTile) - AITile.GetMaxHeight(adjTile));
						if (heighDifference != 0) {
							continue;
						}

						local counter = 0;
						do {
							if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentAirport)) {
								if((AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") && (AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED")) {
									if(AIError.GetLastErrorString() != "ERR_LOCAL_AUTHORITY_REFUSES") {
										//AILog.Warning("Couldnt build station! " + AIError.GetLastErrorString());
									}
								}
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1)
						} while(counter < 1);
						if (counter == 1) {
							continue;
						}
						else {
							local counter = 0;
							do {
								if(!TestBuildRoad().TryBuild(adjTile, nextAdjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while(counter < (stationTile == null ? 500 : 1));
							if(counter == (stationTile == null ? 500 : 1)) {
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
								} while(counter < (stationTile == null ? 500 : 1));
								if (counter == (stationTile == null ? 500 : 1)) {
									LuDiAIAfterFix().scheduledRemovals.AddItem(tile, has_road ? 0 : 1);
//									AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									continue;
								}
							}
							else {
								AILog.Info("Drivethrough station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
								//AISign.BuildSign(tile, "" + adjRoadCount);
								return tile;
							}
						}
					}
					//similar to case 1 if adjacent tiles are not opposite
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
							if (!TestBuildRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentAirport)) {
								if((AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") && (AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED")) {
									if(AIError.GetLastErrorString() != "ERR_LOCAL_AUTHORITY_REFUSES") {
										//AILog.Warning("Couldnt build station! " + AIError.GetLastErrorString());
									}
								}
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while(counter < 1);
						if (counter == 1) {
							continue;
						}
						else {
							local counter = 0;
							do {
								if(!TestBuildRoad().TryBuild(tile, adjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
									++counter;
								}
								else {
									break;
								}
								AIController.Sleep(1);
							} while(counter < (stationTile == null ? 500 : 1));
							if(counter == (stationTile == null ? 500 : 1)) {
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
								} while(counter < (stationTile == null ? 500 : 1));
								if (counter == (stationTile == null ? 500 : 1)) {
									LuDiAIAfterFix().scheduledRemovals.AddItem(tile, 0);
//									AILog.Error("Failed to remove road station tile at " + tile + " - " + AIError.GetLastErrorString());
									continue;
								} else {
									continue;
								}
							}
							else {
								AILog.Info("Station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
								//AISign.BuildSign(tile, "" + adjRoadCount);
								return tile;
							}
						}
					}

					break;

				case 3:
				case 4:
					//similar to case 2 but always builds drivethrough station

					if(AIRoad.IsRoadTile(tile)) {
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

					//check which adjacent tiles are opposite
					local adjTile = Utils.getOffsetTile(tile, -1, 0);
					local nextAdjTile = Utils.getOffsetTile(tile, 1, 0);
					if (!(adjRoadTiles.HasItem(adjTile) && adjRoadTiles.HasItem(nextAdjTile))) {
						adjTile = Utils.getOffsetTile(tile, 0, -1);
						nextAdjTile = Utils.getOffsetTile(tile, 0, 1);
					}

					local heighDifference = abs(AITile.GetMaxHeight(nextAdjTile) - AITile.GetMaxHeight(adjTile));
					if(heighDifference != 0) {
						continue;
					}

					local counter = 0;
					do {
						if (!TestBuildDriveThroughRoadStation().TryBuild(tile, adjTile, vehicleType, adjacentAirport)) {
							if((AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") && (AIError.GetLastErrorString() != "ERR_PRECONDITION_FAILED")) {
								if(AIError.GetLastErrorString() != "ERR_LOCAL_AUTHORITY_REFUSES") {
									//AILog.Warning("Couldnt build station! " + AIError.GetLastErrorString());
								}
							}
							++counter;
						}
						else {
							break;
						}
						AIController.Sleep(1);
					} while(counter < 1);
					if (counter == 1) {
						continue;
					}
					else {
						local counter = 0;
						do {
							if(!TestBuildRoad().TryBuild(adjTile, nextAdjTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
								++counter;
							}
							else {
								break;
							}
							AIController.Sleep(1);
						} while(counter < (stationTile == null ? 500 : 1));
						if(counter == (stationTile == null ? 500 : 1)) {
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
								LuDiAIAfterFix().scheduledRemovals.AddItem(tile, 1);
//								AILog.Error("Failed to remove drive through station tile at " + tile + " - " + AIError.GetLastErrorString());
								continue;
							} else {
								continue;
							}
						}
						else {
							AILog.Info("Drivethrough station built in " + AITown.GetName(town) + " at tile " + tile + "! case" + adjRoadCount);
							//AISign.BuildSign(tile, "" + adjRoadCount);
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

	function estimateTownRectangle(town) {
		local townId = town;
		local townLocation = AITown.GetLocation(town);
		local rectangleIncreaseKoeficient = 1;

		local topCornerTile = AITown.GetLocation(town);
		local bottomCornerTile = AITown.GetLocation(town);

		local isMaxExpanded = false;
		while(!isMaxExpanded) {
			local maxExpandedCounter = 0;
			for (local i = 0; i < 4; ++i) {
				switch(i) {
					case 0:
						local offsetTile = Utils.getOffsetTile(topCornerTile, (-1) * rectangleIncreaseKoeficient, 0);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
							continue;
						}

						if (AITown.IsWithinTownInfluence(town, offsetTile)) {
							topCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
							continue;
						}
						break;

					case 1:
						local offsetTile = Utils.getOffsetTile(bottomCornerTile, 0, rectangleIncreaseKoeficient);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
							continue;
						}

						if (AITown.IsWithinTownInfluence(town, offsetTile)) {
							bottomCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
							continue;
						}
						break;

					case 2:
						local offsetTile = Utils.getOffsetTile(bottomCornerTile, rectangleIncreaseKoeficient, 0);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
							continue;
						}

						if (AITown.IsWithinTownInfluence(town, offsetTile)) {
							bottomCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
							continue;
						}
						break;

					case 3:
						local offsetTile = Utils.getOffsetTile(topCornerTile, 0, (-1) * rectangleIncreaseKoeficient);

						if (offsetTile == AIMap.TILE_INVALID) {
							++maxExpandedCounter;
						}

						if (AITown.IsWithinTownInfluence(town, offsetTile)) {
							topCornerTile = offsetTile;
						}
						else {
							++maxExpandedCounter;
						}
						break;

					default:
						break;
				}
			}

			if (maxExpandedCounter == 4) {
				isMaxExpanded = true;
			}
		}

		return [topCornerTile, bottomCornerTile];
	}

	//find road way between fromTile and toTile
	function buildRoad(fromTile, toTile, silent_mode = false, pathfinder = null, builtTiles = [], cost_so_far = 0) {
		//can store road tiles into array

		if (fromTile != toTile) {
			++m_pathfinderTries;
			local route_dist = AIMap.DistanceManhattan(AITown.GetLocation(m_cityFrom), AITown.GetLocation(m_cityTo));
			local profile = AIController.GetSetting("pf_profile");
			local max_pathfinderTries = route_dist;
			if (profile == 0) {
				max_pathfinderTries = 1 + route_dist / 4;
			} else if (profile == 1) {
				max_pathfinderTries = 1 + route_dist / 10;
			} else {
				max_pathfinderTries = 1 + route_dist / 31;
			}

			//* Print the names of the towns we'll try to connect. */
			if (!silent_mode) AILog.Info("Connecting " + AITown.GetName(m_cityFrom) + " (tile " + fromTile + ") and " + AITown.GetName(m_cityTo) + " (tile " + toTile + ") (attempt " + m_pathfinderTries + "/" + max_pathfinderTries + ")");

			// Tell OpenTTD we want to build normal road (no tram tracks). */
			AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);

			if (pathfinder == null) {
				// Create an instance of the pathfinder. */
				pathfinder = Road();

				switch(profile) {
					case 0:
						AILog.Info("pathfinder: custom");
/*defaults*/
/*10000000*/			pathfinder.cost.max_cost;
/*100*/					pathfinder.cost.tile;
/*20*/					pathfinder.cost.no_existing_road = 40;
/*100*/					pathfinder.cost.turn;
/*200*/					pathfinder.cost.slope = AIGameSettings.GetValue("roadveh_acceleration_model") ? AIGameSettings.GetValue("roadveh_slope_steepness") * 10 : pathfinder.cost.slope;
/*150*/					pathfinder.cost.bridge_per_tile = 50;
/*120*/					pathfinder.cost.tunnel_per_tile = 60;
/*20*/					pathfinder.cost.coast = Utils.HasMoney(AICompany.GetMaxLoanAmount() * 2) ? pathfinder.cost.coast : 5000;
/*0*/					pathfinder.cost.drive_through = 800;
/*10*/					pathfinder.cost.max_bridge_length = Utils.HasMoney(AICompany.GetMaxLoanAmount() * 2) ? AIGameSettings.GetValue("max_bridge_length") + 2 : 13;
/*20*/					pathfinder.cost.max_tunnel_length = Utils.HasMoney(AICompany.GetMaxLoanAmount() * 2) ? AIGameSettings.GetValue("max_tunnel_length") + 2 : 11;
						break;

					case 2:
						AILog.Info("pathfinder: fastest");

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
						break;

					case 1:
					default:
						AILog.Info("pathfinder: default");

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
						break;

				}
				// Give the source and goal tiles to the pathfinder. */
				pathfinder.InitializePath(fromTile, toTile);
			}

			local cur_tick = AIController.GetTick();
			local path = pathfinder.FindPath(5000);
			AILog.Info("pathfinder: FindPath ticks = " + (AIController.GetTick() - cur_tick));

			if (path == false) {
				if (m_pathfinderTries < max_pathfinderTries) {
					return [null, pathfinder];
				} else {
					// Timed out
					if (!silent_mode) AILog.Error("pathfinder: FindPath return false (timed out)");
					m_pathfinderTries = 0;
					return [null, null];
				}
			}

			if (path == null ) {
				// No path was found. */
				if (!silent_mode) AILog.Error("pathfinder: FindPath return null (no path)");
				m_pathfinderTries = 0;
				return [null, null];
			}

			if (!silent_mode) AILog.Info("Path found! Building road... ");
			AILog.Info("pathfinder: FindPath cost: " + path.GetCost());
			local road_cost = cost_so_far;
			// If a path was found, build a road over it. */
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
									if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT") {
//										if (!silent_mode) AILog.Warning("We found a road already built at tiles " + path.GetTile() + " and " + par.GetTile());
										break;
									}
									else if (AIError.GetLastErrorString() == "ERR_LAND_SLOPED_WRONG" || AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
										if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
											if (!silent_mode) AILog.Warning("Couldn't build road at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
											return buildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
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
							} while(counter < 500);

							if (counter == 500) {
								if (!silent_mode) AILog.Warning("Couldn't build road at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
								m_pathfinderTries = 0;
								return [null, null];
							}

							//add road piece into the road array
							m_builtTiles.append(RoadTile(path.GetTile(), RoadTileTypes.ROAD));
						}
						else {
							if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
								if (!silent_mode) AILog.Warning("Won't build a road crossing a rail at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
								return buildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
							}
							else {
								if (!silent_mode) AILog.Warning("Won't build a road crossing a rail at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
								m_pathfinderTries = 0;
								return [null, null];
							}
						}
					}
					else {
						// Build a bridge or tunnel. */
						if (!AIBridge.IsBridgeTile(path.GetTile()) || !AITunnel.IsTunnelTile(path.GetTile())) {
							// If it was a road tile, demolish it first. Do this to work around expended roadbits. */
							if (AIRoad.IsRoadTile(path.GetTile()) && !AIRoad.IsDriveThroughRoadStationTile(path.GetTile()) && AITunnel.GetOtherTunnelEnd(path.GetTile()) == par.GetTile()) {
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (!TestDemolishTile().TryDemolish(path.GetTile())) {
										if (AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't demolish road at tile " + path.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return buildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
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
								} while(counter < 500);

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
//											if (!silent_mode) AILog.Warning("We found a tunnel already built at tiles " + path.GetTile() + " and " + par.GetTile());
											break;
										}
										else if (AIError.GetLastErrorString() == "ERR_ANOTHER_TUNNEL_IN_THE_WAY") {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return buildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										if (!silent_mode) AILog.Warning("We built a tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
										break;
									}

									AIController.Sleep(1);
								} while(counter < 500);

								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build tunnel at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}

								m_builtTiles.append(RoadTile(path.GetTile(), RoadTileTypes.TUNNEL));

							}
							else {
								local bridge_length = AIMap.DistanceManhattan(path.GetTile(), par.GetTile()) + 1;
								local bridge_list = AIBridgeList_Length(bridge_length);
								bridge_list.Valuate(AIBridge.GetMaxSpeed);
								bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
								local counter = 0;
								do {
									local costs = AIAccounting();
									if (!TestBuildBridge().TryBuild(AIVehicle.VT_ROAD, bridge_list.Begin(), path.GetTile(), par.GetTile())) {
										if (AIError.GetLastErrorString() == "ERR_ALREADY_BUILT" || AIBridge.IsBridgeTile(path.GetTile()) && (AIBridge.GetOtherBridgeEnd(path.GetTile()) == par.GetTile()) && last_node != null && AIRoad.AreRoadTilesConnected(path.GetTile(), last_node)) {
//											if (!silent_mode) AILog.Warning("We found a bridge already built at tiles " + path.GetTile() + " and " + par.GetTile());
											m_bridgeTiles.AddItem(path.GetTile() < par.GetTile() ? path.GetTile() : par.GetTile(), path.GetTile() < par.GetTile() ? par.GetTile() : path.GetTile());
											break;
										}
										else if (AIError.GetLastErrorString() == "ERR_NOT_ENOUGH_CASH") {
											bridge_list.Valuate(AIBridge.GetPrice, bridge_length);
											bridge_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
										}
										else if (AIError.GetLastErrorString() == "ERR_AREA_NOT_CLEAR" || AIError.GetLastErrorString() == "ERR_OWNED_BY_ANOTHER_COMPANY") {
											if (m_pathfinderTries < max_pathfinderTries && last_node != null) {
												if (!silent_mode) AILog.Warning("Couldn't build bridge at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString() + " - Retrying...");
												return buildRoad(fromTile, last_node, silent_mode, null, m_builtTiles, road_cost);
											}
										}
										++counter;
									}
									else {
										road_cost += costs.GetCosts();
//										if (!silent_mode) AILog.Warning("We built a bridge at tiles " + path.GetTile() + " and " + par.GetTile() + ". ec: " + (path.GetCost() - par.GetCost()) + ", ac: " + costs.GetCosts());
										m_bridgeTiles.AddItem(path.GetTile() < par.GetTile() ? path.GetTile() : par.GetTile(), path.GetTile() < par.GetTile() ? par.GetTile() : path.GetTile());
										break;
									}

									AIController.Sleep(1);
								} while(counter < 500);

								if (counter == 500) {
									if (!silent_mode) AILog.Warning("Couldn't build bridge at tiles " + path.GetTile() + " and " + par.GetTile() + " - " + AIError.GetLastErrorString());
									m_pathfinderTries = 0;
									return [null, null];
								}

								m_builtTiles.append(RoadTile(path.GetTile(), RoadTileTypes.BRIDGE, bridge_list.Begin()));
								m_builtTiles.append(RoadTile(par.GetTile(), RoadTileTypes.ROAD));
							}
						}
					}
				}
				last_node = path.GetTile();
				path = par;
			}
			if (!silent_mode) AILog.Info("Road built! Actual cost for building road: " + road_cost);
		}

//		if (!silent_mode) AILog.Info("Road built!");
		m_pathfinderTries = 0;
		return [builtTiles, null];
	}

	function findRoadTileDepot(tile) {
		if(!AIRoad.IsRoadTile(tile)) {
			return null;
		}

		local depotTile = null;

		local adjacentTiles = Utils.getAdjacentTiles(tile);
		adjacentTiles.Valuate(AIRoad.IsRoadTile);
		adjacentTiles.RemoveValue(1);

		local roadTiles = Utils.getAdjacentTiles(tile);
		roadTiles.Valuate(AIRoad.IsRoadTile);
		roadTiles.KeepValue(1);

		local roadTile = null;
		for (roadTile = roadTiles.Begin(); !roadTiles.IsEnd(); roadTile = roadTiles.Next()) {
			if (AIRoad.AreRoadTilesConnected(roadTile, tile)) {
				break;
			}
		}
		assert(roadTile != null);

		for (local adjacentTile = adjacentTiles.Begin(); !adjacentTiles.IsEnd(); adjacentTile = adjacentTiles.Next()) {
			if (AIRoad.AreRoadTilesConnected(tile, adjacentTile) || AITile.IsBuildable(adjacentTile) && (AITile.GetSlope(adjacentTile) == AITile.SLOPE_FLAT || !AITile.IsCoastTile(adjacentTile) || !AITile.HasTransportType(adjacentTile, AITile.TRANSPORT_WATER) || Utils.HasMoney(AICompany.GetMaxLoanAmount() * 2)) && AIRoad.CanBuildConnectedRoadPartsHere(tile, roadTile, adjacentTile)) {
				depotTile = adjacentTile;
				break;
			}
		}

		return depotTile;
	}

	function buildDepotOnTile(t) {
		local square = AITileList();
		local squareSize = 1;
		square.AddRectangle(Utils.getValidOffsetTile(t, (-1) * squareSize, (-1) * squareSize),
			Utils.getValidOffsetTile(t, squareSize, squareSize));

		local depotTile = findRoadTileDepot(t);
		local depotFrontTile = t;

		if(depotTile != null) {
			local counter = 0;
			do {
				if (!TestBuildRoadDepot().TryBuild(depotTile, depotFrontTile)) {
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
					if(!TestBuildRoad().TryBuild(depotTile, depotFrontTile) && AIError.GetLastErrorString() != "ERR_ALREADY_BUILT") {
						++counter;
					}
					else {
						break;
					}
					AIController.Sleep(1);
				} while(counter < 500);

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
					} while(counter < 500);

					if (counter == 500) {
						LuDiAIAfterFix().scheduledRemovals.AddItem(depotTile, 0);
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

	function buildDepotOnRoad(roadArray) {
		if(roadArray == null) {
			return null;
		}

		local depotTile = null;

		//first attempt, build next to the road route
		local arrayMiddleTile = roadArray[roadArray.len() / 2].m_tile;
		local roadTiles = AITileList();
		for (local index = 1; index < roadArray.len() - 1; ++index) {
			roadTiles.AddItem(roadArray[index].m_tile, AIMap.DistanceManhattan(roadArray[index].m_tile, arrayMiddleTile));
		}
		roadTiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		for (local tile = roadTiles.Begin(); !roadTiles.IsEnd(); tile = roadTiles.Next()) {
			depotTile = buildDepotOnTile(tile);
			if (depotTile != null) {
				return depotTile;
			}
		}

		local squareSize = AIGameSettings.GetValue("station_spread");

		//second attempt, build closer to the destination
		local tileList = AITileList();

		tileList.AddRectangle(Utils.getValidOffsetTile(m_stationTo, -1 * squareSize, -1 * squareSize),
			Utils.getValidOffsetTile(m_stationTo, squareSize, squareSize));

		tileList.Valuate(AIRoad.IsRoadTile);
		tileList.KeepValue(1);
		tileList.Valuate(AIMap.DistanceManhattan, m_stationTo);
		tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			depotTile = buildDepotOnTile(tile);
			if (depotTile != null) {
				return depotTile;
			}
		}

		//third attempt, build closer to the source
		tileList.Clear();

		tileList.AddRectangle(Utils.getValidOffsetTile(m_stationFrom, -1 * squareSize, -1 * squareSize),
			Utils.getValidOffsetTile(m_stationFrom, squareSize, squareSize));

		tileList.Valuate(AIRoad.IsRoadTile);
		tileList.KeepValue(1);
		tileList.Valuate(AIMap.DistanceManhattan, m_stationFrom);
		tileList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

		for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
			depotTile = buildDepotOnTile(tile);
			if (depotTile != null) {
				return depotTile;
			}
		}

		AILog.Warning("Couldn't built road depot!");
		return depotTile;
	}

	function saveBuildManager() {
		local route = [];

		if(m_cityFrom == null) {
			m_cityFrom = -1;
		}

		if(m_cityTo == null) {
			m_cityTo = -1;
		}

		if(m_stationFrom == null) {
			m_stationFrom = -1;
		}

		if(m_stationTo == null) {
			m_stationTo = -1;
		}

		if(m_depotTile == null) {
			m_depotTile = -1;
		}

		local bridgeTilesTable = {};
		for (local bridge = m_bridgeTiles.Begin(), i = 0; !m_bridgeTiles.IsEnd(); bridge = m_bridgeTiles.Next(), ++i) {
			bridgeTilesTable.rawset(i, [bridge, m_bridgeTiles.GetValue(bridge)]);
		}

		if(m_articulated == null) {
			m_articulated = -1;
		}

		route.append(m_cityFrom);
		route.append(m_cityTo);
		route.append(m_stationFrom);
		route.append(m_stationTo);
		route.append(m_depotTile);
		route.append(bridgeTilesTable);
		route.append(m_cargoClass);
		route.append(m_articulated);

		return route;
	}

	function loadBuildManager(data) {
		m_cityFrom = data[0];
		m_cityTo = data[1];
		m_stationFrom = data[2];
		m_stationTo = data[3];
		m_depotTile = data[4];

//		local m_bridgeTiles = AIList();
		local bridgeTable = data[5];
		local i = 0;
		while(bridgeTable.rawin(i)) {
			local tile = bridgeTable.rawget(i);
			m_bridgeTiles.AddItem(tile[0], tile[1]);
			++i;
		}

		m_cargoClass = data[6];
		m_articulated = data[7];

		return;
	}
}

