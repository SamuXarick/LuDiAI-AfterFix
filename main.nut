require("RoadvehRouteManager.nut");
require("ShipRouteManager.nut");
require("AirRouteManager.nut");
require("TrainRouteManager.nut");

require("RoadvehRoute.nut");
require("ShipRoute.nut");
require("AirRoute.nut");
require("TrainRoute.nut");

require("RoadvehBuildManager.nut");
require("ShipBuildManager.nut");
require("AirBuildManager.nut");
require("TrainBuildManager.nut");

require("TownManager.nut");
require("Utils.nut");
require("Caches.nut");

class LuDiAIAfterFix extends AIController
{
	static ROAD_DAYS_IN_TRANSIT = AIController.GetSetting("road_days_in_transit");
	static WATER_DAYS_IN_TRANSIT = AIController.GetSetting("water_days_in_transit");
	static RAIL_DAYS_IN_TRANSIT = AIController.GetSetting("rail_days_in_transit");

	static MAX_DISTANCE_INCREASE = 25;

	bestRoutesBuilt = null;
	allRoutesBuilt = null;

	cargo_class_rotation = null;

	roadTownManager = null;
	road_route_manager = null;
	road_build_manager = null;

	shipTownManager = null;
	ship_route_manager = null;
	ship_build_manager = null;

	airTownManager = null;
	air_route_manager = null;
	air_build_manager = null;

	railTownManager = null;
	rail_route_manager = null;
	rail_build_manager = null;

	loading = null;
	loadData = null;

	buildTimerRoad = 0;
	buildTimerWater = 0;
	buildTimerAir = 0;
	buildTimerRail = 0;

	reservedMoney = 0;

	reservedMoneyRoad = 0;
	reservedMoneyWater = 0;
	reservedMoneyAir = 0;
	reservedMoneyRail = 0;

	constructor()
	{
		/* ::caches must exist before calling any RouteManager or SwapCargoClass */
		::caches <- Caches();

		roadTownManager = TownManager();
		shipTownManager = TownManager();
		airTownManager = TownManager();
		railTownManager = TownManager();

		this.SwapCargoClass();

		/**
		 * 'allRoutesBuilt' and 'bestRoutesBuilt' are bits:
		 * bit 0 - Road/Passengers, bit 1 - Road/Mail
		 * bit 2 - Water/Passengers, bit 3 - Water/Mail
		 * bit 4 - Air/Passengers, bit 5 - Air/Mail
		 * bit 6 - Rail/Passengers, bit 7 - Rail/Mail
		 */
		allRoutesBuilt = 0;
		bestRoutesBuilt = 0

		road_route_manager = RoadRouteManager();
		road_build_manager = RoadBuildManager();

		ship_route_manager = ShipRouteManager();
		ship_build_manager = ShipBuildManager();

		air_route_manager = AirRouteManager();
		air_build_manager = AirBuildManager();

		rail_route_manager = RailRouteManager();
		rail_build_manager = RailBuildManager();

		::scheduled_removals_table <- { Train = [], Road = {}, Ship = {}, Aircraft = {} };

		loading = true;
	}
};

function LuDiAIAfterFix::RemoveLeftovers()
{
	local clearedList = AIList();
	local toclearList = AIList();
	if (::scheduled_removals_table.Aircraft.len() > 0) {
		foreach (tile, value in ::scheduled_removals_table.Aircraft) {
			if (AIAirport.IsAirportTile(tile)) {
				if (TestRemoveAirport().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
				else {
					/* there was nothing to remove */
					clearedList.AddItem(tile, 0);
				}
			}
		}

		foreach (tile, _ in clearedList) {
			::scheduled_removals_table.Aircraft.rawdelete(tile);
		}
	}

	clearedList.Clear();
	toclearList.Clear();
	if (::scheduled_removals_table.Road.len() > 0) {
		AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
		foreach (tile, value in ::scheduled_removals_table.Road) {
			if (value == 0) { // Remove without using demolish
				if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile)) {
					if (TestRemoveRoadStation().TryRemove(tile)) {
						clearedList.AddItem(tile, 0);
					}
				}
				else if (AIRoad.IsRoadDepotTile(tile)) {
					if (TestRemoveRoadDepot().TryRemove(tile)) {
						clearedList.AddItem(tile, 0);
					}
				}
				else {
					/* there was nothing to remove */
					clearedList.AddItem(tile, 0);
				}
			}
			/* Remove using demolish */
			else if (AIRoad.IsRoadStationTile(tile) || AIRoad.IsDriveThroughRoadStationTile(tile) || AIRoad.IsRoadDepotTile(tile)) {
				if (TestDemolishTile().TryDemolish(tile)) {
					clearedList.AddItem(tile, 1);
				}
			}
			else {
				/* there was nothing to remove */
				clearedList.AddItem(tile, 1);
			}
		}

		foreach (tile, _ in clearedList) {
			::scheduled_removals_table.Road.rawdelete(tile);
		}
	}

	clearedList.Clear();
	toclearList.Clear();
	if (::scheduled_removals_table.Ship.len() > 0) {
		foreach (tile, value in ::scheduled_removals_table.Ship) {
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
								toclearList.AddItem(tile2, 0);
							}
						}
						local tile3 = tile2 + offset;
						if (AIMarine.IsCanalTile(tile3) && !ShipBuildManager().RemovingCanalBlocksConnection(tile3)) {
							if (!TestRemoveCanal().TryRemove(tile3)) {
								toclearList.AddItem(tile3, 0);
							}
						}
						clearedList.AddItem(tile, 0);
					}
				} else {
					/* Not our dock, someone overbuilt it on top of a canal tile */
					clearedList.AddItem(tile, 0);
				}
			}
			else if (AIMarine.IsCanalTile(tile) && !ShipBuildManager().RemovingCanalBlocksConnection(tile)) {
				if (TestRemoveCanal().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
			}
			else if (AIMarine.IsWaterDepotTile(tile)) {
				if (TestRemoveWaterDepot().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
			}
			else if (AIMarine.IsBuoyTile(tile)) {
				if (TestRemoveBuoy().TryRemove(tile)) {
					clearedList.AddItem(tile, 0);
				}
			}
			else {
				/* there was nothing to remove */
				clearedList.AddItem(tile, 0);
			}
		}

		foreach (tile, _ in clearedList) {
			::scheduled_removals_table.Ship.rawdelete(tile);
		}
		foreach (tile, _ in toclearList) {
			::scheduled_removals_table.Ship.rawset(tile, 0);
		}
	}

	clearedList.Clear();
	toclearList.Clear();
	if (::scheduled_removals_table.Train.len() > 0) {
		foreach (id, i in ::scheduled_removals_table.Train) {
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
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.DEPOT) {
				if (AIRail.IsRailDepotTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestDemolishTile().TryDemolish(tile)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.BRIDGE) {
				local tile2 = i.m_tile2;
				if (AIBridge.IsBridgeTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) &&
						AIBridge.GetOtherBridgeEnd(tile) == tile2 && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveBridge().TryRemove(tile)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.TUNNEL) {
				local tile2 = i.m_tile2;
				if (AITunnel.IsTunnelTile(tile) && AITile.HasTransportType(tile, AITile.TRANSPORT_RAIL) &&
						AITunnel.GetOtherTunnelEnd(tile) == tile2 && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveTunnel().TryRemove(tile)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
			else if (struct == RailStructType.RAIL) {
				local tile_from = i.m_tile2;
				local tile_to = i.m_tile3;
				if (AIRail.IsRailTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id) {
					if (TestRemoveRail().TryRemove(tile_from, tile, tile_to)) {
						clearedList.AddItem(id, 0);
					}
				} else {
					/* Does not match the criteria */
					clearedList.AddItem(id, 0);
				}
			}
		}
		foreach (id, _ in clearedList) {
			::scheduled_removals_table.Train.remove(id);
		}
	}
}

function LuDiAIAfterFix::PerformSingleTownAction(town_id, town_action)
{
	if (!AITown.IsActionAvailable(town_id, town_action)) {
		return false;
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

	if (AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
		return false;
	}

	if (!TestPerformTownAction().TryPerform(town_id, town_action)) {
		return false;
	}

	return true;
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

function LuDiAIAfterFix::PerformTownActions()
{
	if (!AIController.GetSetting("fund_buildings") && !AIController.GetSetting("build_statues") && !AIController.GetSetting("advertise")) {
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

			if (!AIController.GetSetting("fund_buildings")) {
				continue;
			}

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

	if (AICompany.GetBankBalance(::caches.m_my_company_id) <= cost) {
		return;
	}

	if (!TestFoundTown().TryFound(town_tile, AITown.TOWN_SIZE_MEDIUM, true, AITown.ROAD_LAYOUT_3x3, null)) {
		return;
	}
	AILog.Warning("Founded town " + AITown.GetName(AITile.GetTownAuthority(town_tile)) + ".");

	if (allRoutesBuilt == 0) {
		return;
	}

	allRoutesBuilt = 0;
//	roadTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	roadTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	roadTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	roadTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//	shipTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	shipTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	shipTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	shipTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//	airTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	airTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	airTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	airTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
//	railTownManager.m_near_city_pair_array[AICargo.CC_PASSENGERS].clear();
//	railTownManager.m_near_city_pair_array[AICargo.CC_MAIL].clear();
	railTownManager.m_used_cities_list[AICargo.CC_PASSENGERS].Clear();
	railTownManager.m_used_cities_list[AICargo.CC_MAIL].Clear();
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

function LuDiAIAfterFix::Save()
{
	local ops = AIController.GetOpsTillSuspend();
	if (loading) {
		if (loadData != null) return loadData;
		AILog.Error("WARNING! AI didn't finish loading previously saved data. It will be saving partial data!")
	}

	local table = {};
	table.rawset("road_town_manager", roadTownManager.SaveTownManager());
	table.rawset("road_route_manager", road_route_manager.SaveRouteManager());
	table.rawset("road_build_manager", road_build_manager.SaveBuildManager());

	table.rawset("ship_town_manager", shipTownManager.SaveTownManager());
	table.rawset("ship_route_manager", ship_route_manager.SaveRouteManager());
	table.rawset("ship_build_manager", ship_build_manager.SaveBuildManager());

	table.rawset("air_town_manager", airTownManager.SaveTownManager());
	table.rawset("air_route_manager", air_route_manager.SaveRouteManager());
	table.rawset("air_build_manager", air_build_manager.SaveBuildManager());

	table.rawset("rail_town_manager", railTownManager.SaveTownManager());
	table.rawset("rail_route_manager", rail_route_manager.SaveRouteManager());
	table.rawset("rail_build_manager", rail_build_manager.SaveBuildManager());

	table.rawset("scheduled_removals_table", ::scheduled_removals_table);

	table.rawset("best_routes_built", bestRoutesBuilt);
	table.rawset("all_routes_built", allRoutesBuilt);

	table.rawset("reserved_money", reservedMoney);
	table.rawset("reserved_money_road", reservedMoneyRoad);
	table.rawset("reserved_money_water", reservedMoneyWater);
	table.rawset("reserved_money_air", reservedMoneyAir);
	table.rawset("reserved_money_rail", reservedMoneyRail);

	table.rawset("cargo_class_rotation", this.cargo_class_rotation);

	table.rawset("caches", ::caches.SaveCaches());

	AILog.Info("Saved! Used ops: " + (ops - AIController.GetOpsTillSuspend()));
	return table;
}

function LuDiAIAfterFix::Load(version, data)
{
	loading = true;
	loadData = [version, data];
	AILog.Warning("Loading data from version " + version + "...");
}

function LuDiAIAfterFix::Start()
{
	if (AICompany.GetAutoRenewStatus(::caches.m_my_company_id)) AICompany.SetAutoRenewStatus(false);

	if (loading) {
		if (loadData != null) {
			if (loadData[1].rawin("road_town_manager")) {
				roadTownManager.LoadTownManager(loadData[1].rawget("road_town_manager"));
			}

			if (loadData[1].rawin("road_route_manager")) {
				road_route_manager.LoadRouteManager(loadData[1].rawget("road_route_manager"));
			}

			if (loadData[1].rawin("road_build_manager")) {
				road_build_manager.LoadBuildManager(loadData[1].rawget("road_build_manager"));
			}

			if (loadData[1].rawin("ship_town_manager")) {
				shipTownManager.LoadTownManager(loadData[1].rawget("ship_town_manager"));
			}

			if (loadData[1].rawin("ship_route_manager")) {
				ship_route_manager.LoadRouteManager(loadData[1].rawget("ship_route_manager"));
			}

			if (loadData[1].rawin("ship_build_manager")) {
				ship_build_manager.LoadBuildManager(loadData[1].rawget("ship_build_manager"));
			}

			if (loadData[1].rawin("air_town_manager")) {
				airTownManager.LoadTownManager(loadData[1].rawget("air_town_manager"));
			}

			if (loadData[1].rawin("air_route_manager")) {
				air_route_manager.LoadRouteManager(loadData[1].rawget("air_route_manager"));
			}

			if (loadData[1].rawin("air_build_manager")) {
				air_build_manager.LoadBuildManager(loadData[1].rawget("air_build_manager"));
			}

			if (loadData[1].rawin("rail_town_manager")) {
				railTownManager.LoadTownManager(loadData[1].rawget("rail_town_manager"));
			}

			if (loadData[1].rawin("rail_route_manager")) {
				rail_route_manager.LoadRouteManager(loadData[1].rawget("rail_route_manager"));
			}

			if (loadData[1].rawin("rail_build_manager")) {
				rail_build_manager.LoadBuildManager(loadData[1].rawget("rail_build_manager"));
			}

			if (loadData[1].rawin("scheduled_removals_table")) {
				::scheduled_removals_table = loadData[1].rawget("scheduled_removals_table");
			}

			if (loadData[1].rawin("best_routes_built")) {
				bestRoutesBuilt = loadData[1].rawget("best_routes_built");
			}

			if (loadData[1].rawin("all_routes_built")) {
				allRoutesBuilt = loadData[1].rawget("all_routes_built");
			}

			if (loadData[1].rawin("reserved_money")) {
				reservedMoney = loadData[1].rawget("reserved_money");
			}

			if (loadData[1].rawin("reserved_money_road")) {
				reservedMoneyRoad = loadData[1].rawget("reserved_money_road");
			}

			if (loadData[1].rawin("reserved_money_water")) {
				reservedMoneyWater = loadData[1].rawget("reserved_money_water");
			}

			if (loadData[1].rawin("reserved_money_air")) {
				reservedMoneyAir = loadData[1].rawget("reserved_money_air");
			}

			if (loadData[1].rawin("reserved_money_rail")) {
				reservedMoneyRail = loadData[1].rawget("reserved_money_rail");
			}

			if (loadData[1].rawin("cargo_class_rotation")) {
				this.cargo_class_rotation = loadData[1].rawget("cargo_class_rotation");
			}

			if (loadData[1].rawin("caches")) {
				::caches.LoadCaches(loadData[1].rawget("caches"));
			}

			CheckForUnfinishedRoadRoute();
			CheckForUnfinishedWaterRoute();
			CheckForUnfinishedRailRoute();

			AILog.Warning("Game loaded.");
			loadData = null;
		} else {
			/* Name company */
			this.NameCompany();
		}
		loading = false;
	}

	while (AIController.Sleep(1)) {
//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RepayLoan");
		Utils.RepayLoan();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RepayLoan " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . RemoveLeftovers");
		RemoveLeftovers();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("RemoveLeftovers " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageRoadvehRoutes");
		road_route_manager.ManageRoadvehRoutes(roadTownManager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageRoadvehRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildRoadRoute");
		BuildRoadRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildRoadRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageAircraftRoutes");
		air_route_manager.ManageAircraftRoutes(airTownManager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageAircraftRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildAirRoute");
		BuildAirRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildAirRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageShipRoutes");
		ship_route_manager.ManageShipRoutes(shipTownManager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageShipRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildWaterRoute");
		BuildWaterRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildWaterRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . ManageTrainRoutes");
		rail_route_manager.ManageTrainRoutes(railTownManager);
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("ManageTrainRoutes " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildRailRoute");
		BuildRailRoute();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildRailRoute " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . PerformTownActions");
		this.PerformTownActions();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("PerformTownActions " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . FoundTown");
		FoundTown();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("FoundTown " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
//		AILog.Info("main loop . BuildHQ");
		BuildHQ();
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("BuildHQ " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}
}

require("RoadvehMain.nut");
require("ShipMain.nut");
require("AirMain.nut");
require("TrainMain.nut");
