class WrightAI extends AIController {
	towns_used = null;
	triedTowns = null;
	triedTowns2 = null;
	best_air_routes_built = null;
	vehicle_to_depot = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];

	cargoId = null;
	cargoClass = null;

	days_interval = 10;
	buildTimer = 0;

	big_engine_list = null;
	small_engine_list = null;
	helicopter_list = null;

	from_location = null;
	from_type = null;
	from_stationId = null;
	small_aircraft_route = null;
	large_aircraft_route = null;
	helicopter_route = null;

	airportTypes = null;

	constructor(CargoClass, sentToDepotAirGroup) {
		this.towns_used = AIList();
		triedTowns = AIList();
		triedTowns2 = AIList();
		best_air_routes_built = false;
		big_engine_list = AIList();
		small_engine_list = AIList();
		helicopter_list = AIList();

		cargoId = Utils.getCargoId(CargoClass);
		cargoClass = CargoClass
		vehicle_to_depot = sentToDepotAirGroup;

		from_location = -1;
		from_type = AIAirport.AT_INVALID;
		from_stationId = -1;
		small_aircraft_route = -1;
		large_aircraft_route = -1;
		helicopter_route = -1;

		airportTypes = AIList();
	}
};

function WrightAI::UpdateAircraftLists() {
	big_engine_list.Clear();
	small_engine_list.Clear();
	helicopter_list.Clear();

	local all_engines = AIEngineList(AIVehicle.VT_AIR);
	for (local engine = all_engines.Begin(); !all_engines.IsEnd(); engine = all_engines.Next()) {
		if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, this.cargoId)) {
			local price = AIEngine.GetPrice(engine);
			switch (AIEngine.GetPlaneType(engine)) {
				case AIAirport.PT_BIG_PLANE:
					big_engine_list.AddItem(engine, price);
					break;
				case AIAirport.PT_SMALL_PLANE:
					small_engine_list.AddItem(engine, price);
					break;
				case AIAirport.PT_HELICOPTER:
					helicopter_list.AddItem(engine, price);
					break;
			}
		}
	}

	if (big_engine_list.Count() > 1) big_engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	if (small_engine_list.Count() > 1) small_engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	if (helicopter_list.Count() > 1) helicopter_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
}

/**
 * Build an airport route. Find 2 cities that are big enough and try to build airport in both cities.
 * Then we can build an aircraft and make some money.
 */
function WrightAI::BuildAirportRoute()
{
	/* Check if we can build more aircraft. */
	if (GetAircraftCount() >= AIGameSettings.GetValue("max_aircraft") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) return [0, null, null];

	if (this.from_location != -1) return BuildAirportRoutePart2();

	/* Create a list of available airports */
//	local airportTypes = AIList();
	airportTypes.AddItem(AIAirport.AT_INTERCON, AIAirport.GetPrice(AIAirport.AT_INTERCON));			  // 7
	airportTypes.AddItem(AIAirport.AT_INTERNATIONAL, AIAirport.GetPrice(AIAirport.AT_INTERNATIONAL)); // 4
	airportTypes.AddItem(AIAirport.AT_METROPOLITAN, AIAirport.GetPrice(AIAirport.AT_METROPOLITAN));	  // 3
	airportTypes.AddItem(AIAirport.AT_LARGE, AIAirport.GetPrice(AIAirport.AT_LARGE));				  // 1
	airportTypes.AddItem(AIAirport.AT_COMMUTER, AIAirport.GetPrice(AIAirport.AT_COMMUTER));			  // 5
	airportTypes.AddItem(AIAirport.AT_SMALL, AIAirport.GetPrice(AIAirport.AT_SMALL));				  // 0
	airportTypes.AddItem(AIAirport.AT_HELISTATION, AIAirport.GetPrice(AIAirport.AT_HELISTATION));	  // 8
	airportTypes.AddItem(AIAirport.AT_HELIDEPOT, AIAirport.GetPrice(AIAirport.AT_HELIDEPOT));		  // 6
	airportTypes.AddItem(AIAirport.AT_HELIPORT, AIAirport.GetPrice(AIAirport.AT_HELIPORT));			  // 2

	/* Filter out airports larger than the maximum value of a station size */
	local list = AIList();
	list.AddList(airportTypes);
	local station_spread = AIGameSettings.GetValue("station_spread");
	for (local i = list.Begin(); !list.IsEnd(); i = list.Next()) {
//		AILog.Info("i = " + i);
		local airport_x = AIAirport.GetAirportWidth(i);
//		AILog.Info("airport_x = " + airport_x);
		local airport_y = AIAirport.GetAirportHeight(i);
//		AILog.Info("airport_y = " + airport_y);
		if (airport_x > station_spread || airport_y > station_spread) {
//			AILog.Info("Removing non-valid airport of type " + WrightAI.GetAirportTypeName(i));
			airportTypes.RemoveItem(i);
		}
		/* Also filter out unavailable airports */
		if (!AIAirport.IsValidAirportType(i)) {
//			AILog.Info("Removing non-valid airport of type " + WrightAI.GetAirportTypeName(i));
			airportTypes.RemoveItem(i);
		}
//		/* Filter out heliports while helistations and helidepots aren't available, because it is required that one of the airports in a route to have a hangar */
//		if (i == AIAirport.AT_HELIPORT && !AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) && !AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
//			airportTypes.RemoveItem(i);
//		}
	}
	/* No airports available. Abort */
	if (airportTypes.Count() == 0) return [0, null, null];
//
//	AILog.Info("Available airport types:");
//	for (local a = airportTypes.Begin(); !airportTypes.IsEnd(); a = airportTypes.Next()) {
//		AILog.Info(WrightAI.GetAirportTypeName(a) + " (monthly maintenance cost = " + AIAirport.GetMonthlyMaintenanceCost(a) + ")");
//	}

	local available_engines = false;
	local engine_costs = 0;
	WrightAI.UpdateAircraftLists();
	if (big_engine_list.Count() == 0) {
//		airportTypes.RemoveItem(AIAirport.AT_INTERCON);
//		airportTypes.RemoveItem(AIAirport.AT_INTERNATIONAL);
//		airportTypes.RemoveItem(AIAirport.AT_METROPOLITAN);
//		airportTypes.RemoveItem(AIAirport.AT_LARGE);
	} else {
		available_engines = true;
		engine_costs = AIEngine.GetPrice(big_engine_list.Begin()) * 2;
	}

	if (small_engine_list.Count() == 0) {
//		airportTypes.RemoveItem(AIAirport.AT_COMMUTER);
//		airportTypes.RemoveItem(AIAirport.AT_SMALL);
	} else {
		available_engines = true;
		if (engine_costs < AIEngine.GetPrice(small_engine_list.Begin()) * 2) engine_costs = AIEngine.GetPrice(small_engine_list.Begin()) * 2;
	}

	if (helicopter_list.Count() == 0) {
		airportTypes.RemoveItem(AIAirport.AT_HELISTATION);
		airportTypes.RemoveItem(AIAirport.AT_HELIDEPOT);
		airportTypes.RemoveItem(AIAirport.AT_HELIPORT);
	} else {
		available_engines = true;
		if (engine_costs < AIEngine.GetPrice(helicopter_list.Begin()) * 2) engine_costs = AIEngine.GetPrice(helicopter_list.Begin()) * 2;
	}

	/* There are no engines available */
	if (!available_engines) return [0, null, null];

	/* Not enough money */
	local estimated_costs = airportTypes.GetValue(airportTypes.Begin()) + engine_costs;
	if (!Utils.HasMoney(estimated_costs + 25000)) return [0, null, null];

//	AILog.Info("airportTypes contains " + airportTypes.Count() + " type " + airportTypes.Begin());
	airportTypes.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

	/* Ensure there are at least 2 unused towns */
	local town_list = AITownList();
	if (AIController.GetSetting("cities_only")) {
		local removelist = AIList();
		for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
			if (!AITown.IsCity(town)) {
				removelist.AddItem(town, 0);
			}
		}
		town_list.RemoveList(removelist);
	}
	if (town_list.Count() - this.towns_used.Count() < 2) return [0, null, null];

	AILog.Info("Trying to build an airport route...");

	local tile_1 = this.FindSuitableAirportSpot(airportTypes, 0, false, false, false);

	this.from_location = tile_1[0];
	this.from_type = tile_1[1];
	this.from_stationId = tile_1[5];

	if (this.from_location < 0) {
		AILog.Error("Couldn't find a suitable town to build the first airport in");
		return [-1, null, null];
	}

	if (this.from_type == AIAirport.AT_HELIPORT) {
		airportTypes.RemoveItem(AIAirport.AT_HELIPORT);
		airportTypes.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	}

	this.large_aircraft_route = tile_1[2];
	this.small_aircraft_route = tile_1[3];
	this.helicopter_route = tile_1[4];

	return [null, null, null];
}

function BuildAirportRoutePart2()
{
	local tile_2 = this.FindSuitableAirportSpot(this.airportTypes, this.from_location, this.large_aircraft_route, this.small_aircraft_route, this.helicopter_route);

	local airport2_location = tile_2[0];
	local airport2_type = tile_2[1];
	local airport2_stationId = tile_2[5];

	if (airport2_location == null) return [null, null, null];
	if (airport2_location < 0) {
		AILog.Error("Couldn't find a suitable town to build the second airport in");
		return [-1, null, null];
	}

	/* Build the airports for real */
	if (!(TestBuildAirport().TryBuild(this.from_location, this.from_type, this.from_stationId))) {
		AILog.Error("Although the testing told us we could build 2 airports, it still failed on the first airport at tile " + this.from_location + ".");
		return [-1, null, null];
	}

	if (!(TestBuildAirport().TryBuild(airport2_location, airport2_type, airport2_stationId))) {
		AILog.Error("Although the testing told us we could build 2 airports, it still failed on the second airport at tile " + airport2_location + ".");
		return [-1, null, null];
	}

	local station_Id1 = AIStation.GetStationID(this.from_location);
	local station_Id2 = AIStation.GetStationID(airport2_location);
	local ret = this.BuildAircraft(this.from_location, airport2_location, false, GetAircraftCount() == 0 ? true : false);
	if (ret == 0) {
		if (WrightAI.VehicleList_Station(station_Id1).Count() == 0) {
			return [ret, null, null];
		} else {
			ret = 1;
		}
	}

	local airport1_town = AITile.GetClosestTown(this.from_location);
	local airport2_town = AITile.GetClosestTown(airport2_location);
	this.towns_used.AddItem(airport1_town, this.from_location);
	this.towns_used.AddItem(airport2_town, airport2_location);

//	AILog.Warning("Done building aircraft route.");
	return [ret, station_Id1, station_Id2];
}

function WrightAI::GetBestAirportEngine(type, return_list = false, squared_dist = null) {
	WrightAI.UpdateAircraftLists();
	local engine_list = AIList();

	if (type == AIAirport.AT_INTERCON || type == AIAirport.AT_INTERNATIONAL || type == AIAirport.AT_METROPOLITAN || type == AIAirport.AT_LARGE) {
		engine_list.AddList(big_engine_list);
		engine_list.AddList(small_engine_list);
		engine_list.AddList(helicopter_list);
	}

	if (type == AIAirport.AT_SMALL || type == AIAirport.AT_COMMUTER) {
		engine_list.AddList(small_engine_list);
		engine_list.AddList(helicopter_list);
	}

	if (type == AIAirport.AT_HELISTATION || type == AIAirport.AT_HELIDEPOT || type == AIAirport.AT_HELIPORT) {
		engine_list.AddList(helicopter_list);
	}

	if (squared_dist != null) {
		local templist = AIList();
		for (local engine = engine_list.Begin(); !engine_list.IsEnd(); engine = engine_list.Next()) {
			local maximumorderdistance = WrightAI.GetMaximumOrderDistance(engine);
			if (maximumorderdistance >= squared_dist) {
				engine_list.SetValue(engine, maximumorderdistance);
			} else {
				templist.AddItem(engine, 0);
			}
		}
		engine_list.RemoveList(templist);
	}

	if (engine_list.Count() == 0) {
		return null;
	} else {
		if (return_list) {
			return engine_list;
		} else {
			return engine_list.Begin();
		}
	}
}

function WrightAI::GetBestRouteEngine(tile_1, tile_2) {
	local small_aircraft = AIAirport.GetAirportType(tile_1) == AIAirport.AT_SMALL || AIAirport.GetAirportType(tile_2) == AIAirport.AT_SMALL ||
		AIAirport.GetAirportType(tile_1) == AIAirport.AT_COMMUTER || AIAirport.GetAirportType(tile_2) == AIAirport.AT_COMMUTER;

	local helicopter = AIAirport.GetAirportType(tile_1) == AIAirport.AT_HELIPORT || AIAirport.GetAirportType(tile_2) == AIAirport.AT_HELIPORT ||
		AIAirport.GetAirportType(tile_1) == AIAirport.AT_HELIDEPOT || AIAirport.GetAirportType(tile_2) == AIAirport.AT_HELIDEPOT ||
		AIAirport.GetAirportType(tile_1) == AIAirport.AT_HELISTATION || AIAirport.GetAirportType(tile_2) == AIAirport.AT_HELISTATION;

	local dist = AIMap.DistanceSquare(tile_1, tile_2);
//	local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
	local fakedist = WrightAI.DistanceRealFake(tile_1, tile_2);

	local engine_list = AIEngineList(AIVehicle.VT_AIR);
	local removelist = AIList();
	for (local engine = engine_list.Begin(); !engine_list.IsEnd(); engine = engine_list.Next()) {
		if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, this.cargoId)) {
			if (small_aircraft && AIEngine.GetPlaneType(engine) == AIAirport.PT_BIG_PLANE) {
				removelist.AddItem(engine, 0);
				continue;
			}
			if (helicopter && AIEngine.GetPlaneType(engine) != AIAirport.PT_HELICOPTER) {
				removelist.AddItem(engine, 0);
				continue;
			}
			if (WrightAI.GetMaximumOrderDistance(engine) < dist) {
				removelist.AddItem(engine, 0);
				continue;
			}
			engine_list.SetValue(engine, WrightAI.GetEngineRouteIncome(engine, this.cargoId, fakedist));
		}
	}
	engine_list.RemoveList(removelist);

	if (engine_list.Count() == 0) {
		return null;
	} else {
		engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
		return engine_list.Begin();
	}
}

function WrightAI::GetMaximumOrderDistance(engineId) {
	local dist = AIEngine.GetMaximumOrderDistance(engineId);
	return dist == 0 ? 0xFFFFFFFF : dist;
}

function WrightAI::GetNumTerminals(aircraft_type, airport_type) {
	switch (airport_type) {
		case AIAirport.AT_INTERCON:
			return aircraft_type != AIAirport.PT_HELICOPTER ? 8 : 2;

		case AIAirport.AT_INTERNATIONAL:
			return aircraft_type != AIAirport.PT_HELICOPTER ? 6 : 2;

		case AIAirport.AT_METROPOLITAN:
			return 3;

		case AIAirport.AT_LARGE:
			return 3;

		case AIAirport.AT_COMMUTER:
			return aircraft_type != AIAirport.PT_HELICOPTER ? 3 : 2;

		case AIAirport.AT_SMALL:
			return 2;

		case AIAirport.AT_HELISTATION:
			return aircraft_type != AIAirport.PT_HELICOPTER ? 0 : 3;

		case AIAirport.AT_HELIDEPOT:
			return aircraft_type != AIAirport.PT_HELICOPTER ? 0 : 1;

		case AIAirport.AT_HELIPORT:
			return aircraft_type != AIAirport.PT_HELICOPTER ? 0 : 1;

		default:
			assert(false);
	}
}

function WrightAI::VehicleList_Station(stationId) {
	local vehicleList = AIVehicleList_Station(stationId);
	local returnlist = AIList();
	for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
		if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
			returnlist.AddItem(v, 0);
		}
	}
	return returnlist;
}

/**
 * Build an aircraft with orders from tile_1 to tile_2.
 * The best available aircraft of that time will be bought.
 */
function WrightAI::BuildAircraft(tile_1, tile_2, silent_mode = false, build_multiple = false, skip_order = null)
{
	/* Check if we can build more aircraft. */
//	if (GetAircraftCount() >= AIGameSettings.GetValue("max_aircraft") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) return 0; // too slow
	if (AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) return 0;

	local station1 = AIStation.GetStationID(tile_1);
	local station2 = AIStation.GetStationID(tile_2);

	local vehicleList = WrightAI.VehicleList_Station(station1);

	/* Clone vehicle, share orders */
	local clone_vehicle_id = AIVehicle.VEHICLE_INVALID;
	local share_orders_vid = AIVehicle.VEHICLE_INVALID;

	local engine = this.GetBestRouteEngine(tile_1, tile_2);

	if (engine == null || !AIEngine.IsValidEngine(engine)) {
		if (!silent_mode) AILog.Error("Couldn't find a suitable engine");
		return 0;
	}

	for (local vehicle_id = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle_id = vehicleList.Next()) {
		if (AIVehicle.GetEngineType(vehicle_id) == engine) {
			clone_vehicle_id = vehicle_id;
		}
		if (AIGroup.IsValidGroup(AIVehicle.GetGroupID(vehicle_id)) && AIVehicle.GetGroupID(vehicle_id) != vehicle_to_depot[0] && AIVehicle.GetGroupID(vehicle_id) != vehicle_to_depot[1] && AIVehicle.GetGroupID(vehicle_id) != AIGroup.GROUP_DEFAULT) {
			share_orders_vid = vehicle_id;
		}
	}

	/* Build an aircraft */
	local airport1_type = AIAirport.GetAirportType(tile_1);
	local airport2_type = AIAirport.GetAirportType(tile_2);
	local hangar1 = airport1_type == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(tile_2) : AIAirport.GetHangarOfAirport(tile_1);
	local hangar2 = airport2_type == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(tile_1) : AIAirport.GetHangarOfAirport(tile_2);
	local cargowaiting1via2 = AICargo.GetDistributionType(this.cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, this.cargoId);
	local cargowaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, this.cargoId);
	local cargowaiting1 = cargowaiting1via2 + cargowaiting1any;
	local cargowaiting2via1 = AICargo.GetDistributionType(this.cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, this.cargoId);
	local cargowaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, this.cargoId);
	local cargowaiting2 = cargowaiting2via1 + cargowaiting2any;
	local best_hangar = cargowaiting1 >= cargowaiting2 ? skip_order == true ? hangar2 : hangar1 : skip_order == true ? hangar1 : hangar2;

	local new_vehicle = AIVehicle.VEHICLE_INVALID;
	if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
		new_vehicle = TestBuildAircraft().TryBuild(best_hangar, engine);
		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			if (!(TestRefitAircraft().TryRefit(new_vehicle, this.cargoId))) {
				if (!silent_mode) AILog.Error("Couldn't refit the aircraft");
				Utils.RepayLoan();
				return 0;
			}
		}
	} else {
		new_vehicle = TestCloneAircraft().TryClone(best_hangar, clone_vehicle_id, (AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id) ? true : false);
	}

	local order_1 = AIAirport.IsHangarTile(tile_1) ? AIMap.GetTileIndex(AIMap.GetTileX(tile_1), AIMap.GetTileY(tile_1) + 1) : tile_1;
	local order_2 = AIAirport.IsHangarTile(tile_2) ? AIMap.GetTileIndex(AIMap.GetTileX(tile_2), AIMap.GetTileY(tile_2) + 1) : tile_2;

	if (AIVehicle.IsValidVehicle(new_vehicle)) {
		local vehicle_ready_to_start = false;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
				if (AIOrder.AppendOrder(new_vehicle, order_1, AIOrder.OF_NONE) && AIOrder.AppendOrder(new_vehicle, order_2, AIOrder.OF_NONE)) {
					vehicle_ready_to_start = true;
				} else {
					if (!silent_mode) AILog.Error("Could not append orders");
					AIVehicle.SellVehicle(new_vehicle);
					Utils.RepayLoan();
					return 0;
				}
			} else {
				if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
					vehicle_ready_to_start = true;
				} else {
					if (!silent_mode) AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
					AIVehicle.SellVehicle(new_vehicle);
					Utils.RepayLoan();
					return 0;
				}
			}
		} else {
			if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
				vehicle_ready_to_start = true;
			} else {
				if (clone_vehicle_id != share_orders_vid) {
					if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						if (!silent_mode) AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						AIVehicle.SellVehicle(new_vehicle);
						Utils.RepayLoan();
						return 0;
					}
				}
				vehicle_ready_to_start = true;
			}
		}
		if (vehicle_ready_to_start) {
			/* Send him on his way */
			if (AIMap.DistanceSquare(best_hangar, tile_1) > AIMap.DistanceSquare(best_hangar, tile_2)) {
				AIOrder.SkipToOrder(new_vehicle, 1);
			}
			AIVehicle.StartStopVehicle(new_vehicle);

			local new_vehicle_group = AIVehicle.GetGroupID(new_vehicle);
			if (!AIGroup.IsValidGroup(new_vehicle_group) || new_vehicle_group == vehicle_to_depot[0] || new_vehicle_group == vehicle_to_depot[1] || new_vehicle_group == AIGroup.GROUP_DEFAULT) {
				AIGroup.MoveVehicle(AIGroup.GROUP_DEFAULT, new_vehicle);
				this.GroupVehicles(station1);
			}
		}
	} else {
		if (!silent_mode) AILog.Error("Couldn't build the aircraft");
		return 0;
	}

	local dist = WrightAI.DistanceRealFake(tile_1, tile_2);

	local route_list = WrightAI.VehicleList_Station(station1);
	local count = route_list.Count();
	for (local vehicle = route_list.Begin(); !route_list.IsEnd(); route_list.Next()) {
		if (AIVehicle.GetState(vehicle) == AIVehicle.VS_CRASHED) {
			count--;
		}
	}
	local count_interval = WrightAI.GetEngineRealFakeDist(engine, this.days_interval);
	local aircraft_type = AIEngine.GetPlaneType(AIVehicle.GetEngineType(new_vehicle));
	local max_count = (dist / count_interval) + GetNumTerminals(aircraft_type, airport1_type) + GetNumTerminals(aircraft_type, airport2_type);

	AILog.Info("Built " + AIEngine.GetName(engine) + " from " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(new_vehicle, skip_order == true ? 1 : 0))) + " to " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(new_vehicle, skip_order == true ? 0 : 1))) + " (" + count + "/" + max_count + " aircraft, " + AIMap.DistanceManhattan(tile_1, tile_2) + " manhattan tiles, " + dist + " realfake tiles, " + AIMap.DistanceSquare(tile_1, tile_2) + " squared tiles)");

	if (build_multiple == true && count < max_count) {
		if (skip_order == null) skip_order = false;
		return BuildAircraft(tile_1, tile_2, true, true, !skip_order);
	}
	if (build_multiple == false && count == 1 && AIAirport.GetNumHangars(tile_1) > 0 && AIAirport.GetNumHangars(tile_2) > 0) {
		return BuildAircraft(tile_1, tile_2, true, false, true);
	}
	return 1;
}

function WrightAI::GroupVehicles(stationId = null)
{
	local tempgroupList = AIGroupList();
	local groupList = AIList();
	for (local group = tempgroupList.Begin(); !tempgroupList.IsEnd(); group = tempgroupList.Next()) {
		if (AIGroup.GetVehicleType(group) == AIVehicle.VT_AIR) {
			groupList.AddItem(group, 0);
		}
	}

	if (AIGroup.IsValidGroup(vehicle_to_depot[0])) {
		groupList.RemoveItem(vehicle_to_depot[0]);
	}
	if (AIGroup.IsValidGroup(vehicle_to_depot[1])) {
		groupList.RemoveItem(vehicle_to_depot[1]);
	}

	for (local group = groupList.Begin(); !groupList.IsEnd(); group = groupList.Next()) {
		if (!AIVehicleList_Group(group).Count()) {
			AIGroup.DeleteGroup(group);
		}
	}

	local stationList = AIList();
	if (stationId != null) {
		stationList.AddItem(stationId, 0);
	} else {
		stationList = AIStationList(AIStation.STATION_AIRPORT);
	}

	for (local st = stationList.Begin(); !stationList.IsEnd(); st = stationList.Next()) {
		local vehicleList = WrightAI.VehicleList_Station(st);

		if (!vehicleList.Count()) {
			if (stationId != null) return AIGroup.GROUP_INVALID;
		} else {
			local route_group = AIGroup.GROUP_INVALID;

			for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
				if (AIVehicle.GetGroupID(v) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(v) != vehicle_to_depot[0] && AIVehicle.GetGroupID(v) != vehicle_to_depot[1]) {
					route_group = AIVehicle.GetGroupID(v);
					break;
				}
			}

			local create_group = false;
			if (!AIGroup.IsValidGroup(route_group)) {
				create_group = true;
			}

			for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
				if (AIVehicle.GetGroupID(v) != route_group && AIVehicle.GetGroupID(v) != vehicle_to_depot[0] && AIVehicle.GetGroupID(v) != vehicle_to_depot[1]) {
					if (create_group == true) {
						route_group = AIGroup.CreateGroup(AIVehicle.VT_AIR);
						if (AIGroup.IsValidGroup(route_group)) {
							local order1_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 0)));
							local order2_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 1)));
							local a1 = AIAirport.GetAirportType(order1_location);
							local a2 = AIAirport.GetAirportType(order2_location);
							local a = "L";
							if (a1 == AIAirport.AT_COMMUTER || a1 == AIAirport.AT_SMALL || a2 == AIAirport.AT_COMMUTER || a2 == AIAirport.AT_SMALL) {
								a = "S";
							}
							if (a1 == AIAirport.AT_HELISTATION || a1 == AIAirport.AT_HELIDEPOT || a1 == AIAirport.AT_HELIPORT || a2 == AIAirport.AT_HELISTATION || a2 == AIAirport.AT_HELIDEPOT || a2 == AIAirport.AT_HELIPORT) {
								a = "H";
							}
							local dist = WrightAI.DistanceRealFake(this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 0))), this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 1))));
							AIGroup.SetName(route_group, a + WrightAI.DistanceRealFake(order1_location, order2_location) + ": " + order1_location + " - " + order2_location);
							AILog.Info("Created " + AIGroup.GetName(route_group) + " for air route from " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 0))) + " to " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 1))));
							create_group = false;
						}
					}
					if (AIGroup.IsValidGroup(route_group)) {
						AIGroup.MoveVehicle(route_group, v);
					}
				}
			}

			if (stationId != null) return route_group;
		}
	}
}

/**
 * Find a suitable spot for an airport, walking all towns hoping to find one.
 * When a town is used, it is marked as such and not re-used.
 */
function WrightAI::FindSuitableAirportSpot(airportTypes, airport1_tile, large_aircraft, small_aircraft, helicopter)
{
	local town_list = AITownList();

	/* Remove all the towns we already used */
	town_list.RemoveList(this.towns_used);

	/* Remove towns we have tried recently */
	town_list.RemoveList(this.triedTowns);

	local cities_only = AIController.GetSetting("cities_only");
	local pick_mode = AIController.GetSetting("pick_mode");
	local cargolimit = cargoClass == AICargo.CC_PASSENGERS ? 70 : 35;
	local removelist = AIList();
	for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
		if (cities_only && !AITown.IsCity(town)) {
			removelist.AddItem(town, 0);
			continue;
		}
		if (!best_air_routes_built && pick_mode != 1 && !Utils.IsTownGrowing(town, this.cargoId)) {
			removelist.AddItem(town, 0);
			continue;
		}
		local cargoproduction = (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, this.cargoId) : AITown.GetLastMonthProduction(town, this.cargoId));
		if (cargoproduction <= cargolimit) {
			removelist.AddItem(town, 0);
			continue;
		} else {
			town_list.SetValue(town, (pick_mode == 1 ? AIBase.Rand() : cargoproduction));
		}
	}
	town_list.RemoveList(removelist);
	town_list.Sort(AIList.SORT_BY_VALUE, false);

	if (town_list.Count() <= 1 && triedTowns.Count() > 0 && airport1_tile == 0) {
		this.triedTowns.Clear();
		if (pick_mode != 1 && !best_air_routes_built) {
			best_air_routes_built = true;
			AILog.Warning("Best air routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
		}
		return FindSuitableAirportSpot(airportTypes, airport1_tile, large_aircraft, small_aircraft, helicopter);
	}

	local large_engine_list = this.GetBestAirportEngine(AIAirport.AT_LARGE, true);
	local small_engine_list = this.GetBestAirportEngine(AIAirport.AT_SMALL, true);
	local heli_engine_list = this.GetBestAirportEngine(AIAirport.AT_HELIPORT, true);
	if (large_engine_list == null && small_engine_list == null && heli_engine_list == null) {
		return [-1, AIAirport.AT_INVALID, large_aircraft, small_aircraft, helicopter, -1];
	}

	local large_available = true;
	local large_fakedist;
	local large_max_dist;
	local large_min_dist;
	local large_closestTowns = AIList();

	local small_available = true;
	local small_fakedist;
	local small_max_dist;
	local small_min_dist;
	local small_closestTowns = AIList();

	local heli_available = true;
	local heli_fakedist;
	local heli_max_dist;
	local heli_min_dist;
	local heli_closestTowns = AIList();

	if (airport1_tile != 0) {
		local airport1_town = AITile.GetClosestTown(airport1_tile);
		local airport1_town_tile = AITown.GetLocation(airport1_town);
		if (pick_mode >= 2) {
			for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
				town_list.SetValue(town, WrightAI.GetTownDistanceRealFakeToTile(town, airport1_town_tile));
			}
			town_list.Sort(AIList.SORT_BY_VALUE, (pick_mode == 2 ? AIList.SORT_ASCENDING : AIList.SORT_DESCENDING));
		}

		if (!(large_aircraft && (AIAirport.IsValidAirportType(AIAirport.AT_INTERCON) || AIAirport.IsValidAirportType(AIAirport.AT_INTERNATIONAL) || AIAirport.IsValidAirportType(AIAirport.AT_METROPOLITAN) || AIAirport.IsValidAirportType(AIAirport.AT_LARGE)))) {
			large_available = false;
		}

		if (large_available) {
			if (large_engine_list == null) {
				large_available = false;
			}
		}

		local large_engine;
		if (large_available) {
			large_engine = WrightAI.GetBestEngineIncome(large_engine_list, this.cargoId, this.days_interval);
			if (large_engine[0] == null) {
				large_available = false;
			}
		}

		if (large_available) {
			large_fakedist = large_engine[1];

			/* Best engine is unprofitable enough */
			if (large_fakedist == 0) {
				large_available = false;
			}
		}

		if (large_available) {
			/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
			local large_max_order_dist = WrightAI.GetMaximumOrderDistance(large_engine[0]);
			large_max_dist = large_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : large_max_order_dist;
			local large_min_order_dist = (large_fakedist / 2) * (large_fakedist / 2);
			large_min_dist = large_min_order_dist > large_max_dist * 3 / 4 ? large_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : large_max_dist * 3 / 4 : large_min_order_dist;

			for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
				if (this.triedTowns2.HasItem(town)) continue;
				local dist = AITile.GetDistanceSquareToTile(AITown.GetLocation(town), airport1_tile);
				local fake = WrightAI.DistanceRealFake(AITown.GetLocation(town), airport1_tile);
				if (dist <= large_max_dist && dist >= large_min_dist && fake <= large_fakedist) {
					large_closestTowns.AddItem(town, (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, this.cargoId) : AITown.GetLastMonthProduction(town, this.cargoId)));
				}
			}
			local large_closest_count = large_closestTowns.Count();
			AILog.Info(large_closest_count + " possible destination" + (large_closest_count != 1 ? "s" : "") + " from " + AITown.GetName(airport1_town) + " for a large aeroplane route");
//			large_closestTowns.KeepTop(10);
		}

		if (!(small_aircraft && (AIAirport.IsValidAirportType(AIAirport.AT_COMMUTER) || AIAirport.IsValidAirportType(AIAirport.AT_SMALL)))) {
			small_available = false;
		}

		if (small_available) {
			if (small_engine_list == null) {
				small_available = false;
			}
		}

		local small_engine;
		if (small_available) {
			small_engine = WrightAI.GetBestEngineIncome(small_engine_list, this.cargoId, this.days_interval);
			if (small_engine[0] == null) {
				small_available = false;
			}
		}

		if (small_available) {
			small_fakedist = small_engine[1];

			/* Best engine is unprofitable enough */
			if (small_fakedist == 0) {
				small_available = false;
			}
		}

		if (small_available) {
			/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
			local small_max_order_dist = WrightAI.GetMaximumOrderDistance(small_engine[0]);
			small_max_dist = small_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : small_max_order_dist;
			local small_min_order_dist = (small_fakedist / 2) * (small_fakedist / 2);
			small_min_dist = small_min_order_dist > small_max_dist * 3 / 4 ? small_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : small_max_dist * 3 / 4 : small_min_order_dist;

			for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
				if (this.triedTowns2.HasItem(town)) continue;
				local dist = AITile.GetDistanceSquareToTile(AITown.GetLocation(town), airport1_tile);
				local fake = WrightAI.DistanceRealFake(AITown.GetLocation(town), airport1_tile);
				if (dist <= small_max_dist && dist >= small_min_dist && fake <= small_fakedist) {
					small_closestTowns.AddItem(town, (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, this.cargoId) : AITown.GetLastMonthProduction(town, this.cargoId)));
				}
			}
			local small_closest_count = small_closestTowns.Count();
			AILog.Info(small_closest_count + " possible destination" + (small_closest_count != 1 ? "s" : "") + " from " + AITown.GetName(airport1_town) + " for a small aeroplane route");
//			small_closestTowns.KeepTop(10);
		}

		if (!(helicopter && (AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) || AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT) || AIAirport.IsValidAirportType(AIAirport.AT_HELIPORT)))) {
			heli_available = false;
		}

		if (heli_available) {
			if (heli_engine_list == null) {
				heli_available = false;
			}
		}

		local heli_engine;
		if (heli_available) {
			heli_engine = WrightAI.GetBestEngineIncome(heli_engine_list, this.cargoId, this.days_interval);
			if (heli_engine[0] == null) {
				heli_available = false;
			}
		}

		if (heli_available) {
			heli_fakedist = heli_engine[1];

			/* Best engine is unprofitable enough */
			if (heli_fakedist == 0) {
				heli_available = false;
			}
		}

		if (heli_available) {
			/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
			local heli_max_order_dist = WrightAI.GetMaximumOrderDistance(heli_engine[0]);
			heli_max_dist = heli_max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : heli_max_order_dist;
			local heli_min_order_dist = (heli_fakedist / 2) * (heli_fakedist / 2);
			heli_min_dist = heli_min_order_dist > heli_max_dist * 3 / 4 ? heli_max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : heli_max_dist * 3 / 4 : heli_min_order_dist;

			for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
				if (this.triedTowns2.HasItem(town)) continue;
				local dist = AITile.GetDistanceSquareToTile(AITown.GetLocation(town), airport1_tile);
				local fake = WrightAI.DistanceRealFake(AITown.GetLocation(town), airport1_tile);
				if (dist <= heli_max_dist && dist >= heli_min_dist && fake <= heli_fakedist) {
					heli_closestTowns.AddItem(town, (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, this.cargoId) : AITown.GetLastMonthProduction(town, this.cargoId)));
				}
			}
			local heli_closest_count = heli_closestTowns.Count();
			AILog.Info(heli_closest_count + " possible destination" + (heli_closest_count != 1 ? "s" : "") + " from " + AITown.GetName(airport1_town) + " for a helicopter route");
//			heli_closestTowns.KeepTop(10);
		}

		if (!large_available && !small_available && !heli_available) {
			return [-1, AIAirport.AT_INVALID, large_aircraft, small_aircraft, helicopter, -1];
		}
	}

	local cur_date = AIDate.GetCurrentDate();

	/* Now find a suitable town */
	for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
		local town_tile = AITown.GetLocation(town);
		if (airport1_tile != 0 && !large_closestTowns.HasItem(town) && !small_closestTowns.HasItem(town) && !heli_closestTowns.HasItem(town)) continue;

		for (local a = airportTypes.Begin(); !airportTypes.IsEnd(); a = airportTypes.Next()) {
			local airport_x = AIAirport.GetAirportWidth(a);
			local airport_y = AIAirport.GetAirportHeight(a);
			local airport_rad = AIAirport.GetAirportCoverageRadius(a);
			if (!AIAirport.IsValidAirportType(a)) continue;

			if (large_aircraft && a != AIAirport.AT_INTERCON && a != AIAirport.AT_INTERNATIONAL && a != AIAirport.AT_METROPOLITAN && a != AIAirport.AT_LARGE) {
				continue;
			}
			if (small_aircraft && a != AIAirport.AT_INTERCON && a != AIAirport.AT_INTERNATIONAL && a != AIAirport.AT_METROPOLITAN && a != AIAirport.AT_LARGE && a != AIAirport.AT_SMALL && a != AIAirport.AT_COMMUTER) {
				continue;
			}
			if (helicopter && a != AIAirport.AT_HELISTATION && a != AIAirport.AT_HELIDEPOT && a != AIAirport.AT_HELIPORT) {
				if (AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) || AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
					continue;
				}
			}

			local fakedist;
			local max_dist;
			local min_dist;
			if (airport1_tile != 0) {
				local closestTowns = AIList();
				if (a == AIAirport.AT_INTERCON || a == AIAirport.AT_INTERNATIONAL || a == AIAirport.AT_METROPOLITAN || a == AIAirport.AT_LARGE) {
					if (large_aircraft) {
						if (large_available) {
							closestTowns.AddList(large_closestTowns);
							fakedist = large_fakedist;
							max_dist = large_max_dist;
							min_dist = large_min_dist;
						} else {
							continue;
						}
					}
					if (small_aircraft) {
						if (small_available) {
							closestTowns.AddList(small_closestTowns);
							fakedist = small_fakedist;
							max_dist = small_max_dist;
							min_dist = small_min_dist;
						} else {
							continue;
						}
					}
					if (helicopter) {
						if (heli_available) {
							closestTowns.AddList(heli_closestTowns);
							fakedist = heli_fakedist;
							max_dist = heli_max_dist;
							min_dist = heli_min_dist;
						} else {
							continue;
						}
					}
				} else if (a == AIAirport.AT_COMMUTER || a == AIAirport.AT_SMALL) {
					if (large_aircraft || small_aircraft) {
						if (small_available) {
							closestTowns.AddList(small_closestTowns);
							fakedist = small_fakedist;
							max_dist = small_max_dist;
							min_dist = small_min_dist;
						} else {
							continue;
						}
					}
					if (helicopter) {
						if (heli_available) {
							closestTowns.AddList(heli_closestTowns);
							fakedist = heli_fakedist;
							max_dist = heli_max_dist;
							min_dist = heli_min_dist;
						} else {
							continue;
						}
					}
				} else {
					if (heli_available) {
						closestTowns.AddList(heli_closestTowns);
						fakedist = heli_fakedist;
						max_dist = heli_max_dist;
						min_dist = heli_min_dist;
					} else {
						continue;
					}
				}

				if (!closestTowns.HasItem(town)) continue;
			}

			AILog.Info("Checking " + AITown.GetName(town) + " for an airport of type " + WrightAI.GetAirportTypeName(a));

			local rectangleCoordinates = this.TownAirportRadRect(a, town);
			local tileList = AITileList();
			tileList.AddRectangle(rectangleCoordinates[0], rectangleCoordinates[1]);

			local tempList = AITileList();
			tempList.AddList(tileList);
			for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
				if (airport1_tile != 0) {
					/* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
					local distance_square = AITile.GetDistanceSquareToTile(tile, airport1_tile);
					if (!(distance_square > min_dist)) {
						tempList.RemoveItem(tile);
						continue;
					}
					if (!(distance_square < max_dist)) {
						tempList.RemoveItem(tile);
						continue;
					}
					if (!(WrightAI.DistanceRealFake(tile, airport1_tile) < fakedist)) {
						tempList.RemoveItem(tile);
						continue;
					}
				}

				if (!(AITile.IsBuildableRectangle(tile, airport_x, airport_y))) {
					tempList.RemoveItem(tile);
					continue;
				}

				/* Sort on acceptance, remove places that don't have acceptance */
				if (AITile.GetCargoAcceptance(tile, this.cargoId, airport_x, airport_y, airport_rad) < 10) {
					tempList.RemoveItem(tile);
					continue;
				}
				if (AIController.GetSetting("select_town_cargo") == 2) {
					if (AITile.GetCargoAcceptance(tile, Utils.getCargoId(AICargo.CC_MAIL), airport_x, airport_y, airport_rad) < 10) {
						tempList.RemoveItem(tile);
						continue;
					}
				}

				local cargo_production = AITile.GetCargoProduction(tile, this.cargoId, airport_x, airport_y, airport_rad);
				if (pick_mode != 1 && !best_air_routes_built && cargo_production < 18) {
					tempList.RemoveItem(tile);
					continue;
				} else {
					tempList.SetValue(tile, cargo_production);
				}
			}
			tileList.Clear();
			tileList.AddList(tempList);

			/* Couldn't find a suitable place for this town, skip to the next */
			if (tileList.Count() == 0) continue;
			tileList.Sort(AIList.SORT_BY_VALUE, false);

			/* Walk all the tiles and see if we can build the airport at all */
			local good_tile = 0;
			for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
				local noise = AIAirport.GetNoiseLevelIncrease(tile, a);
				local allowed_noise = AITown.GetAllowedNoise(AIAirport.GetNearestTown(tile, a));
				if (noise > allowed_noise) continue;
//				AISign.BuildSign(tile, ("" + noise + " <= " + allowed_noise + ""));

				local adjacentStationId = checkAdjacentStation(tile, a);
				local nearest_town;
				if (adjacentStationId == AIStation.STATION_NEW) {
					nearest_town = AITile.GetClosestTown(tile);
					if (nearest_town != town) continue;
				} else {
					nearest_town = AIStation.GetNearestTown(adjacentStationId);
					if (nearest_town != town) {
						adjacentStationId = AIStation.STATION_NEW;
						nearest_town = AITile.GetClosestTown(tile);
						if (nearest_town != town) continue;
					}
				}

				if (AITestMode() && !AIAirport.BuildAirport(tile, a, adjacentStationId)) continue;
				good_tile = tile;

				/* Don't build airport if there is any competitor station in the vicinity, or an airport of mine */
				local airportcoverage = this.TownAirportRadRect(a, tile, false);
				local tileList2 = AITileList();
				tileList2.AddRectangle(airportcoverage[0], airportcoverage[1]);
				tileList2.RemoveRectangle(tile, AIMap.GetTileIndex(AIMap.GetTileX(tile + airport_x - 1), AIMap.GetTileY(tile + airport_y - 1)));
				local nearby_station = false;
				for (local t = tileList2.Begin(); !tileList2.IsEnd(); t = tileList2.Next()) {
					if (AITile.IsStationTile(t) && (AIAirport.IsAirportTile(t) || AITile.GetOwner(t) != Utils.MyCID() && AIController.GetSetting("is_friendly"))) {
						nearby_station = true;
						break;
					}
				}
				if (nearby_station) continue;

				/* Mark the town as tried, so we don't use it again */
				assert(!towns_used.HasItem(nearest_town) && !triedTowns.HasItem(nearest_town) && nearest_town == town);
				if (airport1_tile == 0) {
					this.triedTowns.AddItem(nearest_town, good_tile);
				} else {
					this.triedTowns2.AddItem(nearest_town, good_tile);
				}

				if (airport1_tile == 0) {
					if (a == AIAirport.AT_INTERCON || a == AIAirport.AT_INTERNATIONAL || a == AIAirport.AT_METROPOLITAN || a == AIAirport.AT_LARGE) {
						large_aircraft = true;
					}
					if (a == AIAirport.AT_COMMUTER || a == AIAirport.AT_SMALL) {
						small_aircraft = true;
					}
					if (a == AIAirport.AT_HELISTATION || a == AIAirport.AT_HELIDEPOT || a == AIAirport.AT_HELIPORT) {
						helicopter = true;
					}
				}

				return [good_tile, a, large_aircraft, small_aircraft, helicopter, adjacentStationId];
			}
		}

		/* All airport types were tried on this town and no suitable location was found */
		assert(!triedTowns.HasItem(town));
		if (airport1_tile == 0) {
			assert(!triedTowns.HasItem(town));
			this.triedTowns.AddItem(town, town_tile);
		} else {
			assert(!triedTowns2.HasItem(town));
			this.triedTowns2.AddItem(town, town_tile);
		}
		if (AIDate.GetCurrentDate() - cur_date > 2) {
			if (airport1_tile == 0) {
				return [-1, AIAirport.AT_INVALID, large_aircraft, small_aircraft, helicopter, -1];
			} else {
				return [null, AIAirport.AT_INVALID, large_aircraft, small_aircraft, helicopter, -1];
			}
		}
	}

	/* We haven't found a suitable location for any airport type in any town */
	return [-1, AIAirport.AT_INVALID, large_aircraft, small_aircraft, helicopter, -1];
}

function WrightAI::GetAircraftCount()
{
	local list = AIVehicleList();
	local count = 0;
	for (local vehicle = list.Begin(); !list.IsEnd(); vehicle = list.Next()) {
		if (AIVehicle.GetVehicleType(vehicle) == AIVehicle.VT_AIR) {
			count++;
		}
	}
	return count;
}

function WrightAI::ManageAirRoutes()
{
//	local start_tick = AIController.GetTick();

	this.GroupVehicles();

	local list = AIList();
	local vehiclelist = AIVehicleList();
	for (local vehicle = vehiclelist.Begin(); !vehiclelist.IsEnd(); vehicle = vehiclelist.Next()) {
		if (AIVehicle.GetVehicleType(vehicle) == AIVehicle.VT_AIR) {
			list.AddItem(vehicle, AIVehicle.GetProfitLastYear(vehicle));
		}
	}

	for (local vehicle = list.Begin(); !list.IsEnd(); vehicle = list.Next()) {
		/* Profit last year bad? Let's sell the vehicle */
		local profit = list.GetValue(vehicle);
		if (profit < 0 && AIVehicle.GetAge(vehicle) >= 730) {
			/* Send the vehicle to depot if we didn't do so yet */
			if (AIVehicle.GetGroupID(vehicle) != vehicle_to_depot[0] && AIVehicle.GetGroupID(vehicle) != vehicle_to_depot[1] && AIVehicle.GetState(vehicle) != AIVehicle.VS_CRASHED) {
				local airport1_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(vehicle, 0)) != 0;
				local airport2_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(vehicle, 1)) != 0;
				if (!(airport1_hangars && airport2_hangars)) {
					if (airport1_hangars) {
						AIOrder.SkipToOrder(vehicle, 0);
					} else {
						AIOrder.SkipToOrder(vehicle, 1);
					}
				}
				if (AIVehicle.SendVehicleToDepot(vehicle)) {
					AILog.Info("Sending " + AIVehicle.GetName(vehicle) + " to hangar as profit last year was: " + profit);
					if (!AIGroup.MoveVehicle(vehicle_to_depot[0], vehicle)) {
						AILog.Error("Failed to move vehicle " + AIVehicle.GetName(vehicle) + " to group " + wrightAI.vehicle_to_depot[0]);
					}
				}
			}
		} else {
			/* Aircraft too old? Sell it. */
			if (AIVehicle.GetAgeLeft(vehicle) <= 365) {
				/* Send the vehicle to depot if we didn't do so yet */
				if (AIVehicle.GetGroupID(vehicle) != vehicle_to_depot[0] && AIVehicle.GetGroupID(vehicle) != vehicle_to_depot[1] && AIVehicle.GetState(vehicle) != AIVehicle.VS_CRASHED) {
					local airport1_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(vehicle, 0)) != 0;
					local airport2_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(vehicle, 1)) != 0;
					if (!(airport1_hangars && airport2_hangars)) {
						if (airport1_hangars) {
							AIOrder.SkipToOrder(vehicle, 0);
						} else {
							AIOrder.SkipToOrder(vehicle, 1);
						}
					}
					if (AIVehicle.SendVehicleToDepot(vehicle)) {
						AILog.Info("Sending " + AIVehicle.GetName(vehicle) + " to hangar to be sold, due to its old age.");
						if (!AIGroup.MoveVehicle(vehicle_to_depot[1], vehicle)) {
							AILog.Error("Failed to move vehicle " + AIVehicle.GetName(vehicle) + " to group " + wrightAI.vehicle_to_depot[1]);
						}
					}
				}
			} else if (AIVehicle.GetGroupID(vehicle) != vehicle_to_depot[0] && AIVehicle.GetGroupID(vehicle) != vehicle_to_depot[1] && AIVehicle.GetState(vehicle) != AIVehicle.VS_CRASHED) {
				local renew_aircraft = true;
				local order1_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0)));
				local order2_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 1)));
				local veh_name = AIVehicle.GetName(vehicle);

				local list2 = WrightAI.VehicleList_Station(AIStation.GetStationID(order1_location));

				/* Don't renew aircraft if there are no engines available */
				local best_engine = this.GetBestRouteEngine(order1_location, order2_location);
				if (best_engine == null || AIVehicle.GetEngineType(vehicle) == best_engine) {
					renew_aircraft = false;
				}

				if (renew_aircraft) {
					local airport1_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(vehicle, 0)) != 0;
					local airport2_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(vehicle, 1)) != 0;
					if (!(airport1_hangars && airport2_hangars)) {
						if (airport1_hangars) {
							AIOrder.SkipToOrder(vehicle, 0);
						} else {
							AIOrder.SkipToOrder(vehicle, 1);
						}
					}
					if (AIVehicle.SendVehicleToDepot(vehicle)) {
						AILog.Info("Sending " + AIVehicle.GetName(vehicle) + " to hangar to replace engine.");
						if (!AIGroup.MoveVehicle(vehicle_to_depot[1], vehicle)) {
							AILog.Error("Failed to move vehicle " + AIVehicle.GetName(vehicle) + " to group " + wrightAI.vehicle_to_depot[1]);
						}
					}
				}
			}
		}
	}

	for (local vehicle = list.Begin(); !list.IsEnd(); vehicle = list.Next()) {
		if (AIVehicle.IsStoppedInDepot(vehicle)) {
			/* Sell it once it really is in the depot */
			if (AIVehicle.GetGroupID(vehicle) == vehicle_to_depot[0]) {
				AILog.Info("Selling " + AIVehicle.GetName(vehicle) + " as it finally is in a hangar. (From " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0))) + " to " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 1))) + ")");
				local list2 = WrightAI.VehicleList_Station(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0)));
				/* Last vehicle on this route? */
				if (list2.Count() == 1) {
					if (AIVehicle.GetProfitLastYear(vehicle) < 10000 && AIVehicle.GetProfitThisYear(vehicle) < 10000) {
						AILog.Warning("Last aircraft of this route!");
					}
				}
				if (AIVehicle.SellVehicle(vehicle)) {
					Utils.RepayLoan();
				}
			}

			if (AIVehicle.GetGroupID(vehicle) == vehicle_to_depot[1]) {
				local renew_aircraft = true;
				local order1_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0)));
				local order2_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 1)));
				local veh_name = AIVehicle.GetName(vehicle);

				local list2 = WrightAI.VehicleList_Station(AIStation.GetStationID(order1_location));

				/* Don't renew aircraft if there are no engines available */
				local best_engine = this.GetBestRouteEngine(order1_location, order2_location);
				if (best_engine == null) {
					renew_aircraft = false;
				}

				if (renew_aircraft) {
					/* Don't add a vehicle to prevent airport overcapacity */
					local count_interval = WrightAI.GetEngineRealFakeDist(best_engine, this.days_interval);
					local dist = WrightAI.DistanceRealFake(order1_location, order2_location);
					local airport1_type = AIAirport.GetAirportType(order1_location);
					local airport2_type = AIAirport.GetAirportType(order2_location);
					local aircraft_type = AIEngine.GetPlaneType(best_engine);
					local max_count = (dist / count_interval) + GetNumTerminals(aircraft_type, airport1_type) + GetNumTerminals(aircraft_type, airport2_type);
					if (list2.Count() - 1 >= max_count) {
						renew_aircraft = false;
					}
				}

				if (AIVehicle.SellVehicle(vehicle)) {
					Utils.RepayLoan();
					AILog.Info("Selling " + veh_name + " as it finally is in a hangar. (From " + AIStation.GetName(AIStation.GetStationID(order1_location)) + " to " + AIStation.GetName(AIStation.GetStationID(order2_location)) + ")");
					if (!renew_aircraft || !BuildAircraft(order1_location, order2_location, true, null)) {
						/* Last vehicle on this route? */
						if (list2.Count() == 0) {
							AILog.Warning("Last aircraft of this route!");
						}
					}
				}
			}
		}
	}

	list = AIStationList(AIStation.STATION_AIRPORT);
//	local air_routes = list.Count() / 2 + list.Count() % 2;
	for (local station = list.Begin(); !list.IsEnd(); station = list.Next()) {
//		AILog.Info("Airport " + AIBaseStation.GetName(station));
		local list2 = WrightAI.VehicleList_Station(station);
		/* No vehicles going to this station, abort and sell */
		local count = list2.Count();
		if (count == 0) {
			this.SellAirport(station);
			continue;
		}

		/* Find the first vehicle that is going to this station */
		local v = list2.Begin();
		local order1_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 0)));
		local order2_location = this.GetAirportTile(AIStation.GetStationID(AIOrder.GetOrderDestination(v, 1)));

		/* Don't try to add planes if there are no engines available */
		local best_engine = this.GetBestRouteEngine(order1_location, order2_location);
		if (best_engine == null) continue;

		/* Don't add a vehicle to prevent airport overcapacity */
		local count_interval = WrightAI.GetEngineRealFakeDist(best_engine, this.days_interval);
		local dist = WrightAI.DistanceRealFake(order1_location, order2_location);
		local airport1_type = AIAirport.GetAirportType(order1_location);
		local airport2_type = AIAirport.GetAirportType(order2_location);
		local aircraft_type = AIEngine.GetPlaneType(best_engine);
		local max_count = (dist / count_interval) + GetNumTerminals(aircraft_type, airport1_type) + GetNumTerminals(aircraft_type, airport2_type);
		if (count >= max_count) continue;

		local best_route_profit = null;
		for (v = list2.Begin(); !list2.IsEnd(); v = list2.Next()) {
			local profit = AIVehicle.GetProfitLastYear(v) + AIVehicle.GetProfitThisYear(v);
			if (best_route_profit == null || profit > best_route_profit) {
				best_route_profit = profit;
			}
		}
		/* This route doesn't seem to be profitable. Stop adding more aircraft */
		if (best_route_profit != null && best_route_profit < 10000) continue;

		/* Do not build a new vehicle once one of the airports becomes unavailable (small airport) */
		if (!AIAirport.IsValidAirportType(airport1_type) || !AIAirport.IsValidAirportType(airport2_type)) continue;

		/* Do not build a new vehicle anymore once helidepots become available for routes where one of the airports isn't dedicated for helicopters */
		if (AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) || AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
			if (airport1_type == AIAirport.AT_HELIPORT && airport2_type != AIAirport.AT_HELISTATION && airport2_type != AIAirport.AT_HELIDEPOT ||
					airport2_type == AIAirport.AT_HELIPORT && airport1_type != AIAirport.AT_HELISTATION && airport1_type != AIAirport.AT_HELIDEPOT) {
				continue;
			}
		}

		local interval_threshold = true;
		for (v = list2.Begin(); !list2.IsEnd(); v = list2.Next()) {
			if (AIVehicle.GetAge(v) < count_interval) {
				interval_threshold = false;
				break;
			}
		}
		/* Do not build a new vehicle if we bought a new one in the last 'count_interval' days */
		if (!interval_threshold) continue;

		/* Don't add aircraft if the cargo waiting would not fill it */
		local engine_capacity = AIEngine.GetCapacity(best_engine);
		local other_station = AIStation.GetStationID(order1_location) == station ? AIStation.GetStationID(order2_location) : AIStation.GetStationID(order1_location);
		local cargo_waiting_via_other_station = AICargo.GetDistributionType(this.cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station, other_station, this.cargoId);
		local cargo_waiting_via_any_station = AIStation.GetCargoWaitingVia(station, AIStation.STATION_INVALID, this.cargoId);
		local cargo_waiting = cargo_waiting_via_other_station + cargo_waiting_via_any_station;
//		AILog.Info(AIBaseStation.GetName(station) + ": cargo waiting = " + AIStation.GetCargoWaiting(station, this.cargoId) + " ; cargo waiting via " + AIBaseStation.GetName(other_station) + " = " + cargo_waiting_via_other_station + " ; cargo waiting via any station = " + cargo_waiting_via_any_station + " (total = " + cargo_waiting + ")");
		if (cargo_waiting < engine_capacity) continue;
		local number_to_add = 1 + cargo_waiting / engine_capacity;

		/* Try to add this number of aircraft at once */
		for (local n = 1; n <= number_to_add && count + n <= max_count; n++) {
			this.BuildAircraft(order1_location, order2_location, true);
		}
	}

//	if (air_routes) {
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + air_routes + " air route" + (air_routes != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
//	}
}

function WrightAI::GetAirportTile(stationId) {
	local airport_tiles = AITileList_StationType(stationId, AIStation.STATION_AIRPORT);
	airport_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
	return airport_tiles.Begin();
}

/**
  * Sells the airport from stationId
  * Removes town from towns_used list too
  */
function WrightAI::SellAirport(stationId) {
	/* Remove the empty group */
	this.GroupVehicles(stationId);
	local airport_location = this.GetAirportTile(stationId);
	local airport_name = AIBaseStation.GetName(stationId);

	/* Remove the airport */
	if (TestRemoveAirport().TryRemove(airport_location)) {
		AILog.Warning("Removed " + airport_name + " at tile " + airport_location + " as no aircraft was serving it.");
		/* Free the town_used entry */
		this.towns_used.RemoveValue(airport_location);
	}
}

function WrightAI::BuildAirRoute() {
	local start_date = AIDate.GetCurrentDate();
	local route = this.BuildAirportRoute();
	buildTimer += AIDate.GetCurrentDate() - start_date;
	if (route[0] == null) return;
	if (route[0] > 0) {
		AILog.Warning("Built air route between " + AIBaseStation.GetName(route[1]) + " and " + AIBaseStation.GetName(route[2]) + " in " + buildTimer + " day" + (buildTimer != 1 ? "s" : "") + ".");
	} else {
		if (route[0] < 0) {
			AILog.Error(buildTimer + " day" + (buildTimer != 1 ? "s" : "") + " wasted!");
		}
	}
	this.from_location = -1;
	this.from_type = AIAirport.AT_INVALID;
	this.from_stationId = -1;
	this.small_aircraft_route = -1;
	this.large_aircraft_route = -1;
	this.helicopter_route = -1;
	this.airportTypes.Clear();
	this.triedTowns2.Clear();
	buildTimer = 0;
}

function WrightAI::DistanceRealFake(t0, t1)
{
	local t0x = AIMap.GetTileX(t0);
	local t0y = AIMap.GetTileY(t0);
	local t1x = AIMap.GetTileX(t1);
	local t1y = AIMap.GetTileY(t1);
	local dx = t0x > t1x ? t0x - t1x : t1x - t0x;
	local dy = t0y > t1y ? t0y - t1y : t1y - t0y;
	return dx > dy ? ((dx - dy) * 3 + dy * 4) / 3 : ((dy - dx) * 3 + dx * 4) / 3;
}

function WrightAI::GetTownDistanceRealFakeToTile(town, tile)
{
	return WrightAI.DistanceRealFake(AITown.GetLocation(town), tile);
}

function WrightAI::GetEngineRealFakeDist(engine_id, days_in_transit)
{
	/* Assuming going in axis, it is the same as distancemanhattan */
	local realfakedist = (AIEngine.GetMaxSpeed(engine_id) * 2 * 74 * days_in_transit / 256) / 16;
	return realfakedist;
}

function WrightAI::GetEngineBrokenRealFakeDist(engine_id, days_in_transit)
{
	local speed_limit_broken = 320 / AIGameSettings.GetValue("plane_speed");
	local max_speed = AIEngine.GetMaxSpeed(engine_id);
	local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
	local broken_speed = breakdowns && max_speed < speed_limit_broken ? max_speed : speed_limit_broken;
	return (broken_speed * 2 * 74 * days_in_transit / 256) / 16;
}

function WrightAI::GetEngineDaysInTransit(engine_id, fakedist)
{
	local days_in_transit = (fakedist * 256 * 16) / (2 * 74 * AIEngine.GetMaxSpeed(engine_id));
	return days_in_transit;
}

function WrightAI::GetBestEngineIncome(engine_list, cargo, days_int, aircraft = true) {
	local best_income = null;
	local best_distance = 0;
	local best_engine = null;
	for (local engine = engine_list.Begin(); !engine_list.IsEnd(); engine = engine_list.Next()) {
		local optimized = WrightAI.GetEngineOptimalDaysInTransit(engine, cargo, days_int, aircraft);
		if (best_income == null || optimized[0] > best_income) {
			best_income = optimized[0];
			best_distance = optimized[1];
			best_engine = engine;
		}
	}
	return [best_engine, best_distance];
}

function WrightAI::GetEngineOptimalDaysInTransit(engine_id, cargo, days_int, aircraft)
{
	local distance_max_speed = aircraft ? WrightAI.GetEngineRealFakeDist(engine_id, 1000) : Utils.GetEngineTileDist(engine_id, 1000);
	local distance_broken_speed = aircraft ? WrightAI.GetEngineBrokenRealFakeDist(engine_id, 1000) : distance_max_speed;
	local running_cost = AIEngine.GetRunningCost(engine_id);
	local capacity = AIEngine.GetCapacity(engine_id);
	local reliability = AIEngine.GetReliability(engine_id);

	local days_in_transit = 0;
	local best_income = -100000000;
	local best_distance = 0;
	local multiplier = reliability;
	local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
	switch (breakdowns) {
		case 0:
			multiplier = 100;
			break;
		case 1:
			multiplier = reliability + (100 - reliability) / 2;
			break;
		case 2:
		default:
			multiplier = reliability;
			break;
	}
	for (local days = days_int * 3; days <= (breakdowns ? 130 / breakdowns : 185); days++) {
		local income_max_speed = (capacity * AICargo.GetCargoIncome(cargo, distance_max_speed * days / 1000, days) - running_cost * days / 365) * multiplier;
//		AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; days_in_transit = " + days + " ; distance = " + (distance_max_speed * days / 1000) + " ; income = " + income_max_speed + " ; " + (aircraft ? "fakedist" : "tiledist") + " = " + (aircraft ? GetEngineRealFakeDist(engine_id, days) : Utils.GetEngineTileDist(engine_id, days)));
		if (breakdowns) {
			local income_broken_speed = (capacity * AICargo.GetCargoIncome(cargo, distance_broken_speed * days / 1000, days) - running_cost * days / 365) * 100;
			if (income_max_speed > 0 && income_broken_speed > 0 && income_max_speed > best_income) {
				best_income = income_max_speed;
				best_distance = distance_max_speed * days / 1000;
				days_in_transit = days;
			}
		} else {
			if (income_max_speed > 0 && income_max_speed > best_income) {
				best_income = income_max_speed;
				best_distance = distance_max_speed * days / 1000;
				days_in_transit = days;
			}
		}
	}
//	AILog.Info("days_in_transit = " + days_in_transit + " ; best_distance = " + best_distance + " ; best_income = " + best_income + " ; " + (aircraft ? "fakedist" : "tiledist") + " = " + (aircraft ? GetEngineRealFakeDist(engine_id, days_in_transit) : Utils.GetEngineTileDist(engine_id, days_in_transit)));
//	AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; max speed = " + AIEngine.GetMaxSpeed(engine_id) + " ; capacity = " + capacity + " ; running cost = " + running_cost);
	return [best_income, best_distance];
}

function WrightAI::GetEngineRouteIncome(engine_id, cargo, fakedist) {
	local running_cost = AIEngine.GetRunningCost(engine_id);
	local capacity = AIEngine.GetCapacity(engine_id);
	local days_in_transit = WrightAI.GetEngineDaysInTransit(engine_id, fakedist);
	local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
	local reliability = AIEngine.GetReliability(engine_id);
	local multiplier = reliability;
	switch (breakdowns) {
		case 0:
			multiplier = 100;
			break;
		case 1:
			multiplier = reliability + (100 - reliability) / 2;
			break;
		case 2:
		default:
			multiplier = reliability;
			break;
	}
	local income = (capacity * AICargo.GetCargoIncome(cargo, fakedist, days_in_transit) - running_cost * days_in_transit / 365) * multiplier;
	return income;
}

function WrightAI::checkAdjacentStation(airportTile, airport_type) {
	if (!AIController.GetSetting("station_spread") || !AIGameSettings.GetValue("distant_join_stations")) {
		return AIStation.STATION_NEW;
	}

	local tileList = AITileList();
	local spreadrectangle = expandAdjacentStationRect(airportTile, airport_type);
	tileList.AddRectangle(spreadrectangle[0], spreadrectangle[1]);

	local templist = AITileList();
	for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
		if (Utils.isTileMyStationWithoutAirport(tile)) {
			tileList.SetValue(tile, AIStation.GetStationID(tile));
		} else {
			templist.AddTile(tile);
		}
	}
	tileList.RemoveList(templist);

	local stationList = AIList();
	for (local tile = tileList.Begin(); !tileList.IsEnd(); tileList.Next()) {
		stationList.AddItem(tileList.GetValue(tile), AITile.GetDistanceManhattanToTile(tile, airportTile));
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
//		AILog.Info("adjacentStation = " + AIStation.GetName(adjacentStation) + " ; airportTile = " + AIMap.GetTileX(airportTile) + "," + AIMap.GetTileY(airportTile));
	}

	return adjacentStation;
}

function WrightAI::expandAdjacentStationRect(airportTile, airport_type) {
	local spread_rad = AIGameSettings.GetValue("station_spread");
	local airport_x = AIAirport.GetAirportWidth(airport_type);
	local airport_y = AIAirport.GetAirportHeight(airport_type);

	local remaining_x = spread_rad - airport_x;
	local remaining_y = spread_rad - airport_y;

	local tile_top_x = AIMap.GetTileX(airportTile);
	local tile_top_y = AIMap.GetTileY(airportTile);
	local tile_bot_x = tile_top_x + airport_x - 1;
	local tile_bot_y = tile_top_y + airport_y - 1;

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

//	AILog.Info("spreadrectangle top = " + tile_top_x + "," + tile_top_y + " ; spreadrectangle bottom = " + tile_bot_x + "," + tile_bot_y);
	return [AIMap.GetTileIndex(tile_top_x, tile_top_y), AIMap.GetTileIndex(tile_bot_x, tile_bot_y)];
}

function WrightAI::TownAirportRadRect(airport_type, index, town = true) {
	local airport_x = AIAirport.GetAirportWidth(airport_type);
	local airport_y = AIAirport.GetAirportHeight(airport_type);
	local airport_rad = AIAirport.GetAirportCoverageRadius(airport_type);

	local top_x;
	local top_y;
	local bot_x;
	local bot_y;
	if (town) {
		local town_rectangle = BuildManager.estimateTownRectangle(index);

		top_x = AIMap.GetTileX(town_rectangle[0]);
		top_y = AIMap.GetTileY(town_rectangle[0]);
		bot_x = AIMap.GetTileX(town_rectangle[1]);
		bot_y = AIMap.GetTileY(town_rectangle[1]);
	} else {
		top_x = AIMap.GetTileX(index);
		top_y = AIMap.GetTileY(index);
		bot_x = top_x + airport_x - 1;
		bot_y = top_y + airport_y - 1;
	}
//	AILog.Info("top tile was " + top_x + "," + top_y + " bottom tile was " + bot_x + "," + bot_y + " ; town = " + town);

	for (local x = airport_x; x > 1; x--) {
		if (AIMap.IsValidTile(AIMap.GetTileIndex(top_x - 1, top_y))) {
			top_x = top_x - 1;
		}
	}

	for (local y = airport_y; y > 1; y--) {
		if (AIMap.IsValidTile(AIMap.GetTileIndex(top_x, top_y - 1))) {
			top_y = top_y - 1;
		}
	}

	for (local r = airport_rad; r > 0; r--) {
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
//	AILog.Info("top tile now " + top_x + "," + top_y + " bottom tile now " + bot_x + "," + bot_y + " ; town = " + town);
	return [AIMap.GetTileIndex(top_x, top_y), AIMap.GetTileIndex(bot_x, bot_y)];
}

function WrightAI::GetAirportTypeName(airport_type)
{
	if (airport_type == AIAirport.AT_INTERCON) return "Intercontinental";
	if (airport_type == AIAirport.AT_INTERNATIONAL) return "International";
	if (airport_type == AIAirport.AT_METROPOLITAN) return "Metropolitan";
	if (airport_type == AIAirport.AT_LARGE) return "City";
	if (airport_type == AIAirport.AT_COMMUTER) return "Commuter";
	if (airport_type == AIAirport.AT_SMALL) return "Small";
	if (airport_type == AIAirport.AT_HELISTATION) return "Helistation";
	if (airport_type == AIAirport.AT_HELIDEPOT) return "Helidepot";
	if (airport_type == AIAirport.AT_HELIPORT) return "Heliport";
	return "Invalid";
}

function WrightAI::save() {
	local array = [];

	array.append(cargoId);

	array.append(vehicle_to_depot);

	local usedTownsTable = {};
	for (local town = this.towns_used.Begin(), i = 0; !this.towns_used.IsEnd(); town = this.towns_used.Next(), ++i) {
		usedTownsTable.rawset(i, [town, towns_used.GetValue(town)]);
	}

	array.append(usedTownsTable);
	array.append(cargoClass);
	array.append(best_air_routes_built);

	return array;
}

function WrightAI::load(data) {
	if (towns_used == null) {
		usedTownsTable = AIList();
	}

	cargoId = data[0];

	vehicle_to_depot = data[1];
	local table = data[2];
	cargoClass = data[3];
	best_air_routes_built = data[4];
//	AILog.Info("best_air_routes_built = " + best_air_routes_built);

	local i = 0;
	while(table.rawin(i)) {
		local town = table.rawget(i);
		towns_used.AddItem(town[0], town[1]);

		++i;
	}

	AILog.Info("Loaded " + towns_used.Count() + " towns used.");
}
