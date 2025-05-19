require("RoadRouteManager.nut");
require("WaterRouteManager.nut");
require("AirRouteManager.nut");
require("RailRouteManager.nut");

require("RoadRoute.nut");
require("WaterRoute.nut");
require("AirRoute.nut");
require("RailRoute.nut");

require("RoadBuildManager.nut");
require("WaterBuildManager.nut");
require("AirBuildManager.nut");
require("RailBuildManager.nut");

require("TownManager.nut");
require("Utils.nut");
require("Caches.nut");

class LuDiAIAfterFix extends AIController
{
	static ROAD_DAYS_IN_TRANSIT = AIController.GetSetting("road_days_in_transit");
	static WATER_DAYS_IN_TRANSIT = AIController.GetSetting("water_days_in_transit");
	static RAIL_DAYS_IN_TRANSIT = AIController.GetSetting("rail_days_in_transit");

	static MAX_DISTANCE_INCREASE = 25;

	cargo_class_rotation = null;
	transport_mode_rotation = null;

	road_town_manager = null;
	road_route_manager = null;
	road_build_manager = null;

	water_town_manager = null;
	water_route_manager = null;
	water_build_manager = null;

	air_town_manager = null;
	air_route_manager = null;
	air_build_manager = null;

	rail_town_manager = null;
	rail_route_manager = null;
	rail_build_manager = null;

	is_loading = null;
	load_data = null;

	sleep_longer = null;

	constructor()
	{
		/* ::caches must exist before calling any RouteManager or SwapCargoClass */
		::caches <- Caches();

		this.road_town_manager = TownManager();
		this.water_town_manager = TownManager();
		this.air_town_manager = TownManager();
		this.rail_town_manager = TownManager();

		this.SwapCargoClass();

		this.road_route_manager = RoadRouteManager(this.road_town_manager);
		this.road_build_manager = RoadBuildManager();

		this.water_route_manager = WaterRouteManager(this.water_town_manager);
		this.water_build_manager = WaterBuildManager();

		this.air_route_manager = AirRouteManager(this.air_town_manager);
		this.air_build_manager = AirBuildManager();

		this.rail_route_manager = RailRouteManager(this.rail_town_manager);
		this.rail_build_manager = RailBuildManager();

		::scheduled_removals <- {
		    [AITile.TRANSPORT_RAIL] = [],
		    [AITile.TRANSPORT_ROAD] = {},
		    [AITile.TRANSPORT_WATER] = {},
		    [AITile.TRANSPORT_AIR] = {},
		};

		this.transport_mode_rotation = 1 << AITile.TRANSPORT_RAIL;

		this.is_loading = true;

		this.sleep_longer = {
			[AITile.TRANSPORT_RAIL] = true,
			[AITile.TRANSPORT_ROAD] = true,
			[AITile.TRANSPORT_WATER] = true,
			[AITile.TRANSPORT_AIR] = true,
		};
	}
};

function LuDiAIAfterFix::RemoveLeftovers()
{
	local cleared_list = AIList();
	local to_clear_list = AIList();
	if (::scheduled_removals[AITile.TRANSPORT_AIR].len() > 0) {
		foreach (tile, value in ::scheduled_removals[AITile.TRANSPORT_AIR]) {
			if (AIAirport.IsAirportTile(tile)) {
				if (TestRemoveAirport().TryRemove(tile)) {
					cleared_list[tile] = 0;
				}
			} else {
				/* there was nothing to remove */
				cleared_list[tile] = 0;
			}
		}

		foreach (tile, _ in cleared_list) {
			::scheduled_removals[AITile.TRANSPORT_AIR].rawdelete(tile);
		}
	}

	cleared_list.Clear();
	to_clear_list.Clear();
	if (::scheduled_removals[AITile.TRANSPORT_ROAD].len() > 0) {
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		foreach (tile, value in ::scheduled_removals[AITile.TRANSPORT_ROAD]) {
			if (value == 0) { // Remove without using demolish
				if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile)) {
					if (TestRemoveRoadStation().TryRemove(tile)) {
						cleared_list[tile] = 0;
					}
				} else if (AIRoad.IsRoadDepotTile(tile)) {
					if (TestRemoveRoadDepot().TryRemove(tile)) {
						cleared_list[tile] = 0;
					}
				} else {
					/* there was nothing to remove */
					cleared_list[tile] = 0;
				}
			/* Remove using demolish */
			} else if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile) || AIRoad.IsRoadDepotTile(tile)) {
				if (TestDemolishTile().TryDemolish(tile)) {
					cleared_list[tile] = 1;
				}
			} else {
				/* there was nothing to remove */
				cleared_list[tile] = 1;
			}
		}

		foreach (tile, _ in cleared_list) {
			::scheduled_removals[AITile.TRANSPORT_ROAD].rawdelete(tile);
		}
	}

	cleared_list.Clear();
	to_clear_list.Clear();
	if (::scheduled_removals[AITile.TRANSPORT_WATER].len() > 0) {
		foreach (tile, value in ::scheduled_removals[AITile.TRANSPORT_WATER]) {
			if (AIMarine.IsDockTile(tile)) {
				local slope = AITile.GetSlope(tile);
				if (slope == AITile.SLOPE_NE || slope == AITile.SLOPE_SE || slope == AITile.SLOPE_SW || slope == AITile.SLOPE_NW) {
					if (TestRemoveDock().TryRemove(tile)) {
						/* Check for canal and remove it */
						local offset = 0;
						if (slope == AITile.SLOPE_NE) offset = AIMap.GetTileIndex(1, 0);
						if (slope == AITile.SLOPE_SE) offset = AIMap.GetTileIndex(0, -1);
						if (slope == AITile.SLOPE_SW) offset = AIMap.GetTileIndex(-1, 0);
						if (slope == AITile.SLOPE_NW) offset = AIMap.GetTileIndex(0, 1);
						local tile2 = tile + offset;
						if (AIMarine.IsCanalTile(tile2)) {
							if (!TestRemoveCanal().TryRemove(tile2)) {
								to_clear_list[tile2] = 0;
							}
						}
						local tile3 = tile2 + offset;
						if (AIMarine.IsCanalTile(tile3) && !WaterBuildManager().RemovingCanalBlocksConnection(tile3)) {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								to_clear_list[tile3] = 0;
							}
						}
						cleared_list[tile] = 0;
					}
				} else {
					/* Not our dock, someone overbuilt it on top of a canal tile */
					cleared_list[tile] = 0;
				}
			} else if (AIMarine.IsCanalTile(tile) && !WaterBuildManager().RemovingCanalBlocksConnection(tile)) {
				if (TestRemoveCanal().TryRemove(tile)) {
					cleared_list[tile] = 0;
				}
			} else if (AIMarine.IsWaterDepotTile(tile)) {
				if (TestRemoveWaterDepot().TryRemove(tile)) {
					cleared_list[tile] = 0;
				}
			} else {
				/* there was nothing to remove */
				cleared_list[tile] = 0;
			}
		}

		foreach (tile, _ in cleared_list) {
			::scheduled_removals[AITile.TRANSPORT_WATER].rawdelete(tile);
		}
		foreach (tile, _ in to_clear_list) {
			::scheduled_removals[AITile.TRANSPORT_WATER].rawset(tile, 0);
		}
	}

	cleared_list.Clear();
	to_clear_list.Clear();
	if (::scheduled_removals[AITile.TRANSPORT_RAIL].len() > 0) {
		foreach (id, i in ::scheduled_removals[AITile.TRANSPORT_RAIL]) {
			local tile = i.m_tile;
			local struct = i.m_struct;
			local rail_type = i.m_rail_type;

			AIRail.SetCurrentRailType(rail_type);
			if (struct == RailStructType.STATION) {
				local tile2 = i.m_tile2;
				if (AIRail.IsRailStationTile(tile) && AIRail.IsRailStationTile(tile2) &&
						AITile.GetOwner(tile) == ::caches.m_my_company_id && AITile.GetOwner(tile2) == ::caches.m_my_company_id &&
						AIStation.GetStationID(tile) == AIStation.GetStationID(tile2)) {
					if (TestRemoveRailStationTileRectangle().TryRemove(tile, tile2, false)) {
						cleared_list[id] = 0;
					}
				} else {
					/* Does not match the criteria */
					cleared_list[id] = 0;
				}
			} else if (struct == RailStructType.DEPOT) {
				if (AIRail.IsRailDepotTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestDemolishTile().TryDemolish(tile)) {
						cleared_list[id] = 0;
					}
				} else {
					/* Does not match the criteria */
					cleared_list[id] = 0;
				}
			} else if (struct == RailStructType.BRIDGE) {
				local tile2 = i.m_tile2;
				if (AIBridge.IsBridgeTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) &&
						AIBridge.GetOtherBridgeEnd(tile) == tile2 && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveBridge().TryRemove(tile)) {
						cleared_list[id] = 0;
					}
				} else {
					/* Does not match the criteria */
					cleared_list[id] = 0;
				}
			} else if (struct == RailStructType.TUNNEL) {
				local tile2 = i.m_tile2;
				if (AITunnel.IsTunnelTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) &&
						AITunnel.GetOtherTunnelEnd(tile) == tile2 && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveTunnel().TryRemove(tile)) {
						cleared_list[id] = 0;
					}
				} else {
					/* Does not match the criteria */
					cleared_list[id] = 0;
				}
			} else if (struct == RailStructType.RAIL) {
				local tile_from = i.m_tile2;
				local tile_to = i.m_tile3;
				if (AIRail.IsRailTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveRail().TryRemove(tile_from, tile, tile_to)) {
						cleared_list[id] = 0;
					}
				} else {
					/* Does not match the criteria */
					cleared_list[id] = 0;
				}
			}
		}

		foreach (id, _ in cleared_list) {
			::scheduled_removals[AITile.TRANSPORT_RAIL].remove(id);
		}
	}
}

function LuDiAIAfterFix::SwapCargoClass()
{
	switch (AIController.GetSetting("select_town_cargo")) {
		case 0: { // Passengers
			this.cargo_class_rotation = AICargo.CC_PASSENGERS;
			return this.cargo_class_rotation;
		}
		case 1: { // Mail
			if (AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) {
				this.cargo_class_rotation = AICargo.CC_MAIL;
			} else {
				this.cargo_class_rotation = AICargo.CC_PASSENGERS;
			}
			return this.cargo_class_rotation;
		}
		case 2: { // Passengers and Mail
			if (this.cargo_class_rotation == AICargo.CC_PASSENGERS) {
				if (AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) {
					this.cargo_class_rotation = AICargo.CC_MAIL;
				} else {
					this.cargo_class_rotation = AICargo.CC_PASSENGERS;
				}
			} else if (this.cargo_class_rotation == AICargo.CC_MAIL) {
				this.cargo_class_rotation = AICargo.CC_PASSENGERS;
			} else if (this.cargo_class_rotation == null) {
				if (AIBase.Chance(1, 2)) {
					if (AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) {
						this.cargo_class_rotation = AICargo.CC_MAIL;
					} else {
						this.cargo_class_rotation = AICargo.CC_PASSENGERS;
					}
				} else {
					this.cargo_class_rotation = AICargo.CC_PASSENGERS;
				}
			}
			return this.cargo_class_rotation;
		}
	}
}

function LuDiAIAfterFix::PerformSingleTownAction(town_id, town_action)
{
	if (!AITown.IsActionAvailable(town_id, town_action)) {
		if (town_action == AITown.TOWN_ACTION_BUY_RIGHTS) {
			local bribe_company = AITown.GetExclusiveRightsCompany(town_id);
			if (bribe_company != AICompany.COMPANY_INVALID && bribe_company != ::caches.m_my_company_id) {
				if (AIController.GetSetting("bribe_authority")) {
					if (this.PerformSingleTownAction(town_id, AITown.TOWN_ACTION_BRIBE)) {
						AILog.Warning("Bribed the local authority of " + AITown.GetName(town_id) + ".");
					} else {
						return false;
					}
				}
			}
		} else {
			return false;
		}
	}

	if (AICompany.GetLoanAmount() != 0) {
		return false;
	}

	if (town_action == AITown.TOWN_ACTION_FUND_BUILDINGS) {
		if (AITown.GetFundBuildingsDuration(town_id) != 0) {
			return false;
		}
	}

	local cost = TestPerformTownAction().TestCost(town_id, town_action);
	if (cost == 0) {
		return false;
	}

	if (AICompany.GetBankBalance(::caches.m_my_company_id) <= (cost + ::caches.m_reserved_money)) {
		return false;
	}

	if (!TestPerformTownAction().TryPerform(town_id, town_action)) {
		return false;
	}

	return true;
}

function LuDiAIAfterFix::PerformTownActions()
{
	if (!AIController.GetSetting("fund_buildings") && !AIController.GetSetting("build_statues") && !AIController.GetSetting("advertise") && !AIController.GetSetting("exclusive_rights") && !AIController.GetSetting("bribe_authority")) {
		return;
	}

	local cargo_class = this.SwapCargoClass();
	local cargo_type = Utils.GetCargoType(cargo_class);

	local station_list = AIStationList(AIStation.STATION_ANY);
	local station_towns = AIList();
	local town_list = AIList();
	local statue_count = 0;
	foreach (station_id, _ in station_list) {
		if (!AIStation.HasCargoRating(station_id, cargo_type)) {
			continue;
		}

		local nearest_town = AIStation.GetNearestTown(station_id);
		if (!town_list.HasItem(nearest_town)) {
			town_list[nearest_town] = 0;
			if (AITown.HasStatue(nearest_town)) {
				statue_count++;
			}
		}

		if (AIStation.GetCargoRating(station_id, cargo_type) >= 50) {
			continue;
		}

		if (AIStation.GetCargoWaiting(station_id, cargo_type) > 100) {
			continue;
		}

		if (!station_towns.HasItem(nearest_town)) {
			station_towns[nearest_town] = station_id;
			continue;
		}

		local nearest_town_dist_to_existing_station = AITown.GetDistanceManhattanToTile(nearest_town, AIBaseStation.GetLocation(station_towns[nearest_town]));
		local nearest_town_dist_to_checking_station = AITown.GetDistanceManhattanToTile(nearest_town, AIBaseStation.GetLocation(station_id));
//		local nearest_town_name = AITown.GetName(nearest_town);
//		local existing_station_name = AIBaseStation.GetName(station_towns[nearest_town]);
//		local checking_station_name = AIBaseStation.GetName(station_id);
//		AILog.Info(nearest_town_name + " to existing station " + existing_station_name + " (" + nearest_town_dist_to_existing_station + " manhattan tiles)");
//		AILog.Info(nearest_town_name + " to checking station " + checking_station_name + " (" + nearest_town_dist_to_checking_station + " manhattan tiles)");
		if (nearest_town_dist_to_existing_station >= nearest_town_dist_to_checking_station) {
			continue;
		}

		station_towns[nearest_town] = station_id;
	}

	local town_count = town_list.Count();
	if (AIController.GetSetting("build_statues") && statue_count < town_count) {
		foreach (town_id, _ in town_list) {
			if (!this.PerformSingleTownAction(town_id, AITown.TOWN_ACTION_BUILD_STATUE)) {
				continue;
			}

			statue_count++;
			AILog.Warning("Built a statue in " + AITown.GetName(town_id) + " (" + statue_count + "/" + town_count + " " + AICargo.GetCargoLabel(cargo_type) + ")");
		}
	} else {
		foreach (town_id, _ in station_towns) {
			if (AIController.GetSetting("advertise")) {
				local station_location = AIBaseStation.GetLocation(station_towns.GetValue(town_id));
				local distance = AITown.GetDistanceManhattanToTile(town_id, station_location);
				if (distance <= 10) {
					if (this.PerformSingleTownAction(town_id, AITown.TOWN_ACTION_ADVERTISE_SMALL)) {
						AILog.Warning("Initiated a small advertising campaign in " + AITown.GetName(town_id) + ".");
					}
				} else if (distance <= 15) {
					if (this.PerformSingleTownAction(town_id, AITown.TOWN_ACTION_ADVERTISE_MEDIUM)) {
						AILog.Warning("Initiated a medium advertising campaign in " + AITown.GetName(town_id) + ".");
					}
				} else if (distance <= 20) {
					if (this.PerformSingleTownAction(town_id, AITown.TOWN_ACTION_ADVERTISE_LARGE)) {
						AILog.Warning("Initiated a large advertising campaign in " + AITown.GetName(town_id) + ".");
					}
				}
			}

			if (AIController.GetSetting("exclusive_rights")) {
				if (!this.PerformSingleTownAction(town_id, AITown.TOWN_ACTION_BUY_RIGHTS)) {
					continue;
				}
				AILog.Warning("Bought exclusive transport rights in " + AITown.GetName(town_id) + ".");
			}

			if (AIController.GetSetting("fund_buildings")) {
				if (TownManager.GetLastMonthProductionDiffRate(town_id, cargo_type) > TownManager.CARGO_TYPE_LIMIT[cargo_class]) {
					continue;
				}

				if (!this.PerformSingleTownAction(town_id, AITown.TOWN_ACTION_FUND_BUILDINGS)) {
					continue;
				}
				AILog.Warning("Funded the construction of new buildings in " + AITown.GetName(town_id) + ".");
			}
		}
	}
}

function LuDiAIAfterFix::BuildHQ()
{
	if (!AIController.GetSetting("build_hq")) {
		return;
	}

	if (AIMap.IsValidTile(AICompany.GetCompanyHQ(::caches.m_my_company_id))) {
		return;
	}

	local tileN = AIBase.RandRange(AIMap.GetMapSize());
	if (!AITile.IsBuildableRectangle(tileN, 2, 2)) {
		return;
	}

	local headquarters_rectangle = OrthogonalTileArea(tileN, 2, 2);
	local tile_list = AITileList();
	tile_list.AddRectangle(headquarters_rectangle.tile_top, headquarters_rectangle.tile_bot);

	local clear_costs = AIAccounting();
	local max_clear_costs = AITile.GetBuildCost(AITile.BT_CLEAR_ROUGH) * 4;
	foreach (tile, _ in tile_list) {
		if (AITile.GetSlope(tile) != AITile.SLOPE_FLAT) {
			return;
		}
		if (!(AITestMode() && AITile.DemolishTile(tile))) {
			return;
		}
		if (clear_costs.GetCosts() > max_clear_costs) {
			return;
		}
	}

	if (!TestBuildHQ().TryBuild(tileN)) {
		return;
	}
	AILog.Warning("Built company HQ near " + AITown.GetName(AITile.GetClosestTown(tileN)) + ".");
}

function LuDiAIAfterFix::FoundTown()
{
	if (!AIController.GetSetting("found_towns")) {
		return;
	}

	if (AICompany.GetLoanAmount() != 0) {
		return;
	}

	local town_tile = AIBase.RandRange(AIMap.GetMapSize());
	if (!AITile.IsBuildable(town_tile)) {
		return;
	}

	if (AITile.GetSlope(town_tile) != AITile.SLOPE_FLAT) {
		return;
	}

	local cost = TestFoundTown().TestCost(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null);
	if (cost == 0) {
		return;
	}

	if (AICompany.GetBankBalance(::caches.m_my_company_id) <= (cost + ::caches.m_reserved_money)) {
		return;
	}

	if (!TestFoundTown().TryFound(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null)) {
		return;
	}
	AILog.Warning("Founded town " + AITown.GetName(AITile.GetTownAuthority(town_tile)) + ".");

	local any_all_built = false;
	foreach (cargo_class in [this.rail_route_manager.m_routes_built.all, this.road_route_manager.m_routes_built.all, this.water_route_manager.m_routes_built.all, this.air_route_manager.m_routes_built.all]) {
		if (Utils.ListHasValue(cargo_class, true)) {
			any_all_built = true;
			break;
		}
	}
	if (!any_all_built) {
		return;
	}

	foreach (cargo_class in [this.rail_route_manager.m_routes_built.all, this.road_route_manager.m_routes_built.all, this.water_route_manager.m_routes_built.all, this.air_route_manager.m_routes_built.all]) {
		foreach (cargo_class in ::caches.m_cargo_classes) {
			cargo_class = false;
		}
	}
//	this.road_town_manager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	this.road_town_manager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	this.road_town_manager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	this.road_town_manager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//	this.water_town_manager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	this.water_town_manager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	this.water_town_manager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	this.water_town_manager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//	this.air_town_manager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	this.air_town_manager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	this.air_town_manager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	this.air_town_manager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//	this.rail_town_manager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	this.rail_town_manager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	this.rail_town_manager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	this.rail_town_manager.m_used_cities_list[AICargo.CC_MAIL].Clear();
	AILog.Warning("Not all routes have been used at this time.");
}

function LuDiAIAfterFix::NameCompany()
{
	/* Name company */
	local cargo_string = "";
	switch (AIController.GetSetting("select_town_cargo")) {
		case 0: {
			cargo_string += " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_PASSENGERS));
			break;
		}
		case 1: {
			local mail_cargo_type = Utils.GetCargoType(AICargo.CC_MAIL);
			if (AICargo.IsValidCargo(mail_cargo_type)) {
				cargo_string += " " + AICargo.GetCargoLabel(mail_cargo_type);
			} else {
				cargo_string += " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_PASSENGERS));
			}
			break;
		}
		case 2: {
			local mail_cargo_type = Utils.GetCargoType(AICargo.CC_MAIL);
			if (!AICargo.IsValidCargo(mail_cargo_type)) {
				cargo_string += " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_PASSENGERS));
			}
			break;
		}
	}

	if (!AICompany.SetName("LuDiAI AfterFix" + cargo_string)) {
		local i = 2;
		while (!AICompany.SetName("LuDiAI AfterFix" + cargo_string + " #" + i)) {
			++i;
		}
	}
}

function LuDiAIAfterFix::ToggleTransportMode(transport_mode)
{
	this.transport_mode_rotation = this.transport_mode_rotation ^ (1 << transport_mode);
}

function LuDiAIAfterFix::IsTransportModeInRotation(transport_mode)
{
	return (this.transport_mode_rotation & (1 << transport_mode)) != 0;
}

function LuDiAIAfterFix::Save()
{
	local ops = AIController.GetOpsTillSuspend();
	if (this.is_loading) {
		if (this.load_data != null) return this.load_data;
		AILog.Error("WARNING! AI didn't finish loading previously saved data. It will be saving partial data!")
	}

	local table = {};
	table.rawset("caches", ::caches.SaveCaches());

	table.rawset("road_town_manager", this.road_town_manager.SaveTownManager());
	table.rawset("road_route_manager", this.road_route_manager.SaveRouteManager());
	table.rawset("road_build_manager", this.road_build_manager.SaveBuildManager());

	table.rawset("this.water_town_manager", this.water_town_manager.SaveTownManager());
	table.rawset("water_route_manager", this.water_route_manager.SaveRouteManager());
	table.rawset("water_build_manager", this.water_build_manager.SaveBuildManager());

	table.rawset("air_town_manager", this.air_town_manager.SaveTownManager());
	table.rawset("air_route_manager", this.air_route_manager.SaveRouteManager());
	table.rawset("air_build_manager", this.air_build_manager.SaveBuildManager());

	table.rawset("rail_town_manager", this.rail_town_manager.SaveTownManager());
	table.rawset("rail_route_manager", this.rail_route_manager.SaveRouteManager());
	table.rawset("rail_build_manager", this.rail_build_manager.SaveBuildManager());

	table.rawset("scheduled_removals", ::scheduled_removals);

	table.rawset("cargo_class_rotation", this.cargo_class_rotation);
	table.rawset("transport_mode_rotation", this.transport_mode_rotation);

	AILog.Info("Saved! Used ops: " + (ops - AIController.GetOpsTillSuspend()));
	return table;
}

function LuDiAIAfterFix::Load(version, data)
{
	this.is_loading = true;
	this.load_data = [version, data];
	AILog.Warning("Loading data from version " + version + "...");
}

function LuDiAIAfterFix::Start()
{
	if (AICompany.GetAutoRenewStatus(::caches.m_my_company_id)) AICompany.SetAutoRenewStatus(false);
	if (AICompany.GetAutoRenewMonths(::caches.m_my_company_id) != -12) AICompany.SetAutoRenewMonths(-12);
	if (AICompany.GetAutoRenewMoney(::caches.m_my_company_id) != 0) AICompany.SetAutoRenewMoney(0);

	if (this.is_loading) {
		if (this.load_data != null) {
			if (this.load_data[1].rawin("caches")) {
				::caches.LoadCaches(this.load_data[1].rawget("caches"));
			}

			if (this.load_data[1].rawin("road_town_manager")) {
				this.road_town_manager.LoadTownManager(this.load_data[1].rawget("road_town_manager"));
			}

			if (this.load_data[1].rawin("road_route_manager")) {
				this.road_route_manager.LoadRouteManager(this.load_data[1].rawget("road_route_manager"));
			}

			if (this.load_data[1].rawin("road_build_manager")) {
				this.road_build_manager.LoadBuildManager(this.load_data[1].rawget("road_build_manager"));
			}

			if (this.load_data[1].rawin("water_town_manager")) {
				this.water_town_manager.LoadTownManager(this.load_data[1].rawget("water_town_manager"));
			}

			if (this.load_data[1].rawin("water_route_manager")) {
				this.water_route_manager.LoadRouteManager(this.load_data[1].rawget("water_route_manager"));
			}

			if (this.load_data[1].rawin("water_build_manager")) {
				this.water_build_manager.LoadBuildManager(this.load_data[1].rawget("water_build_manager"));
			}

			if (this.load_data[1].rawin("air_town_manager")) {
				this.air_town_manager.LoadTownManager(this.load_data[1].rawget("air_town_manager"));
			}

			if (this.load_data[1].rawin("air_route_manager")) {
				this.air_route_manager.LoadRouteManager(this.load_data[1].rawget("air_route_manager"));
			}

			if (this.load_data[1].rawin("air_build_manager")) {
				this.air_build_manager.LoadBuildManager(this.load_data[1].rawget("air_build_manager"));
			}

			if (this.load_data[1].rawin("rail_town_manager")) {
				this.rail_town_manager.LoadTownManager(this.load_data[1].rawget("rail_town_manager"));
			}

			if (this.load_data[1].rawin("rail_route_manager")) {
				this.rail_route_manager.LoadRouteManager(this.load_data[1].rawget("rail_route_manager"));
			}

			if (this.load_data[1].rawin("rail_build_manager")) {
				this.rail_build_manager.LoadBuildManager(this.load_data[1].rawget("rail_build_manager"));
			}

			if (this.load_data[1].rawin("scheduled_removals")) {
				::scheduled_removals = this.load_data[1].rawget("scheduled_removals");
			}

			if (this.load_data[1].rawin("cargo_class_rotation")) {
				this.cargo_class_rotation = this.load_data[1].rawget("cargo_class_rotation");
			}

			if (this.load_data[1].rawin("transport_mode_rotation")) {
				this.transport_mode_rotation = this.load_data[1].rawget("transport_mode_rotation");
			}

			this.CheckForUnfinishedRoadRoute();
			this.CheckForUnfinishedWaterRoute();
			this.CheckForUnfinishedRailRoute();

			AILog.Warning("Game loaded.");
			this.load_data = null;
		} else {
			/* Name company */
			this.NameCompany();
		}
		this.is_loading = false;
	}

	do {
//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RepayLoan");
		Utils.RepayLoan();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RepayLoan " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RemoveLeftovers");
		this.RemoveLeftovers();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RemoveLeftovers " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageRoadvehRoutes");
		this.road_route_manager.ManageRoadvehRoutes(this.road_town_manager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageRoadvehRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildRoadRoute");
		if (this.IsTransportModeInRotation(AITile.TRANSPORT_ROAD)) {
			local built_road_route = this.BuildRoadRoute();
			switch (typeof(built_road_route)) {
				case "integer": {
					this.sleep_longer[AITile.TRANSPORT_ROAD] = (built_road_route & 1) == 0;
					if ((built_road_route & 2) != 0) {
						if (!this.IsTransportModeInRotation(AITile.TRANSPORT_AIR)) {
							this.ToggleTransportMode(AITile.TRANSPORT_AIR);
						}
					}
					break;
				}
				case "bool": {
					this.sleep_longer[AITile.TRANSPORT_ROAD] = built_road_route;
					this.ToggleTransportMode(AITile.TRANSPORT_ROAD);
					if (!this.IsTransportModeInRotation(AITile.TRANSPORT_AIR)) {
						this.ToggleTransportMode(AITile.TRANSPORT_AIR);
					}
					break;
				}
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildRoadRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageAircraftRoutes");
		this.air_route_manager.ManageAircraftRoutes(this.air_town_manager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageAircraftRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildAirRoute");
		if (this.IsTransportModeInRotation(AITile.TRANSPORT_AIR)) {
			local built_air_route = this.BuildAirRoute();
			switch (typeof(built_air_route)) {
				case "integer": {
					this.sleep_longer[AITile.TRANSPORT_AIR] = (built_air_route & 1) == 0;
					if ((built_air_route & 2) != 0) {
						if (!this.IsTransportModeInRotation(AITile.TRANSPORT_WATER)) {
							this.ToggleTransportMode(AITile.TRANSPORT_WATER);
						}
					}
					break;
				}
				case "bool": {
					this.sleep_longer[AITile.TRANSPORT_AIR] = built_air_route;
					this.ToggleTransportMode(AITile.TRANSPORT_AIR);
					if (!this.IsTransportModeInRotation(AITile.TRANSPORT_WATER)) {
						this.ToggleTransportMode(AITile.TRANSPORT_WATER);
					}
					break;
				}
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildAirRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageShipRoutes");
		this.water_route_manager.ManageShipRoutes(this.water_town_manager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageShipRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildWaterRoute");
		if (this.IsTransportModeInRotation(AITile.TRANSPORT_WATER)) {
			local built_water_route = this.BuildWaterRoute();
			switch (typeof(built_water_route)) {
				case "integer": {
					this.sleep_longer[AITile.TRANSPORT_WATER] = (built_water_route & 1) == 0;
					if ((built_water_route & 2) != 0) {
						if (!this.IsTransportModeInRotation(AITile.TRANSPORT_RAIL)) {
							this.ToggleTransportMode(AITile.TRANSPORT_RAIL);
						}
					}
					break;
				}
				case "bool": {
					this.sleep_longer[AITile.TRANSPORT_WATER] = built_water_route;
					this.ToggleTransportMode(AITile.TRANSPORT_WATER);
					if (!this.IsTransportModeInRotation(AITile.TRANSPORT_RAIL)) {
						this.ToggleTransportMode(AITile.TRANSPORT_RAIL);
					}
					break;
				}
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildWaterRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageTrainRoutes");
		this.rail_route_manager.ManageTrainRoutes(this.rail_town_manager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageTrainRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildRailRoute");
		if (this.IsTransportModeInRotation(AITile.TRANSPORT_RAIL)) {
			local built_rail_route = this.BuildRailRoute();
			switch (typeof(built_rail_route)) {
				case "integer": {
					this.sleep_longer[AITile.TRANSPORT_RAIL] = (built_rail_route & 1) == 0;
					if ((built_rail_route & 2) != 0) {
						if (!this.IsTransportModeInRotation(AITile.TRANSPORT_ROAD)) {
							this.ToggleTransportMode(AITile.TRANSPORT_ROAD);
						}
					}
					break;
				}
				case "bool": {
					this.sleep_longer[AITile.TRANSPORT_RAIL] = built_rail_route;
					this.ToggleTransportMode(AITile.TRANSPORT_RAIL);
					if (!this.IsTransportModeInRotation(AITile.TRANSPORT_ROAD)) {
						this.ToggleTransportMode(AITile.TRANSPORT_ROAD);
					}
					break;
				}
			}
		}
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildRailRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . PerformTownActions");
		this.PerformTownActions();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("PerformTownActions " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . FoundTown");
		this.FoundTown();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("FoundTown " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildHQ");
		this.BuildHQ();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildHQ " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		AILog.Info("::caches.m_reserved_money: " + ::caches.m_reserved_money);
//		AILog.Info("this.road_route_manager.m_reserved_money: " + this.road_route_manager.m_reserved_money);
//		AILog.Info("this.water_route_manager.m_reserved_money: " + this.water_route_manager.m_reserved_money);
//		AILog.Info("this.air_route_manager.m_reserved_money: " + this.air_route_manager.m_reserved_money);
//		AILog.Info("this.rail_route_manager.m_reserved_money: " + this.rail_route_manager.m_reserved_money);
//		AILog.Info("this.transport_mode_rotation: " + this.transport_mode_rotation);
	} while (AIController.Sleep(Utils.ListHasValue(this.sleep_longer, false) ? 1 : 74));
}

require("RoadMain.nut");
require("WaterMain.nut");
require("AirMain.nut");
require("RailMain.nut");
