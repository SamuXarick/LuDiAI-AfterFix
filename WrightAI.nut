//https://wiki.openttd.org/AI:WrightAI (from: https://bananas.openttd.org/en/ai/)
//modified by lukin_ and Samu


class WrightAI extends AIController {
	towns_used = null;
	triedTowns = null;
	distance_of_route = {};
	vehicle_to_depot = {};

	cargoId = null;
	cargoClass = null;
	
	days_interval = 10;
	
	big_engine_list = null;
	small_engine_list = null;
	helicopter_list = null;

	constructor(CargoClass) {
		this.towns_used = AIList();
		triedTowns = AIList();
		big_engine_list = AIList();
		small_engine_list = AIList();
		helicopter_list = AIList();

		cargoId = Utils.getCargoId(CargoClass);
		cargoClass = CargoClass
	}
};

function WrightAI::UpdateAircraftLists() {
	/* Create a list only with big planes */
	big_engine_list = AIEngineList(AIVehicle.VT_AIR);
	big_engine_list.Valuate(AIEngine.IsValidEngine);
	big_engine_list.KeepValue(1);
	big_engine_list.Valuate(AIEngine.IsBuildable);
	big_engine_list.KeepValue(1);
	big_engine_list.Valuate(AIEngine.CanRefitCargo, this.cargoId);
	big_engine_list.KeepValue(1);
	big_engine_list.Valuate(AIEngine.GetPlaneType);
	big_engine_list.KeepValue(AIAirport.PT_BIG_PLANE);
    big_engine_list.Valuate(AIEngine.GetPrice);
	big_engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
//	big_engine_list.Valuate(AIEngine.GetMaxSpeed);
//  if (big_engine_list.Count() > 0) AILog.Info("big_engine_list contains " + big_engine_list.Count() + " aircraft. Fastest model is " + AIEngine.GetName(big_engine_list.Begin()));

    /* Create a list only with small planes */
    small_engine_list = AIEngineList(AIVehicle.VT_AIR);
	small_engine_list.Valuate(AIEngine.IsValidEngine);
	small_engine_list.KeepValue(1);
	small_engine_list.Valuate(AIEngine.IsBuildable);
	small_engine_list.KeepValue(1);
	small_engine_list.Valuate(AIEngine.CanRefitCargo, this.cargoId);
	small_engine_list.KeepValue(1);
	small_engine_list.Valuate(AIEngine.GetPlaneType);
	small_engine_list.KeepValue(AIAirport.PT_SMALL_PLANE);
    small_engine_list.Valuate(AIEngine.GetPrice);
	small_engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
//	small_engine_list.Valuate(AIEngine.GetMaxSpeed);
//  if (small_engine_list.Count() > 0) AILog.Info("small_engine_list contains " + small_engine_list.Count() + " aircraft. Fastest model is " + AIEngine.GetName(small_engine_list.Begin()));
	
	/* Create a list only with helicopters */
	helicopter_list = AIEngineList(AIVehicle.VT_AIR);
	helicopter_list.Valuate(AIEngine.IsValidEngine);
	helicopter_list.KeepValue(1);
	helicopter_list.Valuate(AIEngine.IsBuildable);
	helicopter_list.KeepValue(1);
	helicopter_list.Valuate(AIEngine.CanRefitCargo, this.cargoId);
	helicopter_list.KeepValue(1);
	helicopter_list.Valuate(AIEngine.GetPlaneType);
	helicopter_list.KeepValue(AIAirport.PT_HELICOPTER);
    helicopter_list.Valuate(AIEngine.GetPrice);
	helicopter_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
//	helicopter_list.Valuate(AIEngine.GetMaxSpeed);
//  if (helicopter_list.Count() > 0) AILog.Info("helicopter_list contains " + helicopter_list.Count() + " aircraft. Fastest model is " + AIEngine.GetName(helicopter_list.Begin()));
}

/**
 * Build an airport route. Find 2 cities that are big enough and try to build airport in both cities.
 * Then we can build an aircraft and make some money.
 */
function WrightAI::BuildAirportRoute()
{
    /* Check if we can build more aircraft. */
    if (GetAircraftCount() >= AIGameSettings.GetValue("max_aircraft") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) return [0, null, null];
	
    /* Create a list of available airports */
    local airportTypes = AIList();
	airportTypes.AddItem(AIAirport.AT_INTERCON, AIAirport.GetPrice(AIAirport.AT_INTERCON));           // 7
	airportTypes.AddItem(AIAirport.AT_INTERNATIONAL, AIAirport.GetPrice(AIAirport.AT_INTERNATIONAL)); // 4
	airportTypes.AddItem(AIAirport.AT_METROPOLITAN, AIAirport.GetPrice(AIAirport.AT_METROPOLITAN));   // 3
	airportTypes.AddItem(AIAirport.AT_LARGE, AIAirport.GetPrice(AIAirport.AT_LARGE));                 // 1
	airportTypes.AddItem(AIAirport.AT_COMMUTER, AIAirport.GetPrice(AIAirport.AT_COMMUTER));           // 5
	airportTypes.AddItem(AIAirport.AT_SMALL, AIAirport.GetPrice(AIAirport.AT_SMALL));                 // 0
	airportTypes.AddItem(AIAirport.AT_HELISTATION, AIAirport.GetPrice(AIAirport.AT_HELISTATION));     // 8
	airportTypes.AddItem(AIAirport.AT_HELIDEPOT, AIAirport.GetPrice(AIAirport.AT_HELIDEPOT));         // 6
	airportTypes.AddItem(AIAirport.AT_HELIPORT, AIAirport.GetPrice(AIAirport.AT_HELIPORT));           // 2
	
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
//		    AILog.Info("Removing non-valid airport of type " + WrightAI.GetAirportTypeName(i));
		    airportTypes.RemoveItem(i);
		}
		/* Also filter out unavailable airports */
		if (!AIAirport.IsValidAirportType(i)) {
//		    AILog.Info("Removing non-valid airport of type " + WrightAI.GetAirportTypeName(i));
		    airportTypes.RemoveItem(i);
		}
//		/* Filter out heliports while helistations and helidepots aren't available, because it is required that one of the airports in a route to have a hangar */
//		if (i == AIAirport.AT_HELIPORT && !AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) && !AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
//		    airportTypes.RemoveItem(i);
//		}
	}
	/* No airports available. Abort */
	if (airportTypes.Count() == 0) return [0, null, null];
//	
//	AILog.Info("Available airport types:");
//	for (local a = airportTypes.Begin(); !airportTypes.IsEnd(); a = airportTypes.Next()) {
//	    AILog.Info(WrightAI.GetAirportTypeName(a) + " (monthly maintenance cost = " + AIAirport.GetMonthlyMaintenanceCost(a) + ")");
//	}
	
	local available_engines = false;
	local engine_costs = 0;
	WrightAI.UpdateAircraftLists();
	if (big_engine_list.Count() == 0) {
//	    airportTypes.RemoveItem(AIAirport.AT_INTERCON);
//		airportTypes.RemoveItem(AIAirport.AT_INTERNATIONAL);
//		airportTypes.RemoveItem(AIAirport.AT_METROPOLITAN);
//		airportTypes.RemoveItem(AIAirport.AT_LARGE);
	} else {
	    available_engines = true;
	    engine_costs = AIEngine.GetPrice(big_engine_list.Begin()) * 2;
	}

	if (small_engine_list.Count() == 0) {
//	    airportTypes.RemoveItem(AIAirport.AT_COMMUTER);
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
        town_list.Valuate(AITown.IsCity);
        town_list.KeepValue(1);
    }
	if (town_list.Count() - this.towns_used.Count() < 2) return [0, null, null];

	AILog.Info("Trying to build an airport route...");
	
	local tile_1 = this.FindSuitableAirportSpot(airportTypes, 0, false, false, false);
	
	local airport1_location = tile_1[0];
	local airport1_type = tile_1[1];
	local airport1_stationId = tile_1[5];
	
    if (airport1_location < 0) {
	    AILog.Error("Couldn't find a suitable town to build the first airport in");
	    return [-1, null, null];
	}
	
    if (airport1_type == AIAirport.AT_HELIPORT) {
	    airportTypes.RemoveItem(AIAirport.AT_HELIPORT);
		airportTypes.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	}
	
    local large_aircraft = tile_1[2];
    local small_aircraft = tile_1[3];
    local helicopter = tile_1[4];
	
	local tile_2 = this.FindSuitableAirportSpot(airportTypes, airport1_location, large_aircraft, small_aircraft, helicopter);
	
	local airport2_location = tile_2[0];
	local airport2_type = tile_2[1];
	local airport2_stationId = tile_2[5];
	
	if (airport2_location < 0) {
	    AILog.Error("Couldn't find a suitable town to build the second airport in");
		return [-1, null, null];
	}

	/* Build the airports for real */
	if (!(TestBuildAirport().TryBuild(airport1_location, airport1_type, airport1_stationId))) {
		AILog.Error("Although the testing told us we could build 2 airports, it still failed on the first airport at tile " + airport1_location + ".");
		return [-1, null, null];
	}

	if (!(TestBuildAirport().TryBuild(airport2_location, airport2_type, airport2_stationId))) {
		AILog.Error("Although the testing told us we could build 2 airports, it still failed on the second airport at tile " + airport2_location + ".");
		return [-1, null, null];
	}

	local ret = this.BuildAircraft(airport1_location, airport2_location, false, GetAircraftCount() == 0 ? true : false);
	if (ret < 0) {
		return [ret, null, null];
	}
	
	local airport1_town = AITile.GetClosestTown(airport1_location);
	local airport2_town = AITile.GetClosestTown(airport2_location);
	this.towns_used.AddItem(airport1_town, airport1_location);
	this.towns_used.AddItem(airport2_town, airport2_location);

//  AILog.Warning("Done building aicraft route.");
	return [ret, AIStation.GetStationID(airport1_location), AIStation.GetStationID(airport2_location)];
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
	    engine_list.Valuate(WrightAI.GetMaximumOrderDistance);
		engine_list.KeepAboveValue(squared_dist - 1);
	}
	if (engine_list.Count() == 0) {
	    return null;
	} else {
	    if (return_list) {
		    return engine_list;
		} else {
//		    engine_list.Valuate(AIEngine.GetMaxSpeed);
//          engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	        return engine_list.Begin();
		}
	}
}

function WrightAI::GetBestRouteEngine(tile_1, tile_2) {
    local engine_list = AIEngineList(AIVehicle.VT_AIR);
	engine_list.Valuate(AIEngine.IsValidEngine);
	engine_list.KeepValue(1);
	engine_list.Valuate(AIEngine.IsBuildable);
	engine_list.KeepValue(1);
	engine_list.Valuate(AIEngine.CanRefitCargo, this.cargoId);
	engine_list.KeepValue(1);
	
	local small_aircraft = AIAirport.GetAirportType(tile_1) == AIAirport.AT_SMALL || AIAirport.GetAirportType(tile_2) == AIAirport.AT_SMALL ||
						   AIAirport.GetAirportType(tile_1) == AIAirport.AT_COMMUTER || AIAirport.GetAirportType(tile_2) == AIAirport.AT_COMMUTER;
	if (small_aircraft) {
	    engine_list.Valuate(AIEngine.GetPlaneType);
	    engine_list.RemoveValue(AIAirport.PT_BIG_PLANE);
	}
	
	local helicopter = AIAirport.GetAirportType(tile_1) == AIAirport.AT_HELIPORT || AIAirport.GetAirportType(tile_2) == AIAirport.AT_HELIPORT ||
	                   AIAirport.GetAirportType(tile_1) == AIAirport.AT_HELIDEPOT || AIAirport.GetAirportType(tile_2) == AIAirport.AT_HELIDEPOT ||
					   AIAirport.GetAirportType(tile_1) == AIAirport.AT_HELISTATION || AIAirport.GetAirportType(tile_2) == AIAirport.AT_HELISTATION;
	if (helicopter) {
	    engine_list.Valuate(AIEngine.GetPlaneType);
		engine_list.KeepValue(AIAirport.PT_HELICOPTER);
	}
	
	local dist = AIMap.DistanceSquare(tile_1, tile_2);
	engine_list.Valuate(WrightAI.GetMaximumOrderDistance);
	engine_list.KeepAboveValue(dist - 1);
	
	if (AIGameSettings.GetValue("vehicle_breakdowns")) {
	    local reliability_list = AIList();
		reliability_list.AddList(engine_list);
	    reliability_list.Valuate(AIEngine.GetReliability);
	    reliability_list.KeepBelowValue(75);
	    if (reliability_list.Count() < engine_list.Count()) {
    	    engine_list.RemoveList(reliability_list);
    	}
	}
	
	local fakedist = WrightAI.DistanceRealFake(tile_1, tile_2);
	engine_list.Valuate(WrightAI.GetEngineRouteIncome, this.cargoId, fakedist);
	engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);

//	engine_list.Valuate(AIEngine.GetMaxSpeed);
//  engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
 
	if (engine_list.Count() == 0) {
	    return null;
	} else {
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

/**
 * Build an aircraft with orders from tile_1 to tile_2.
 * The best available aircraft of that time will be bought.
 */
function WrightAI::BuildAircraft(tile_1, tile_2, silent_mode = false, build_multiple = false)
{
    /* Check if we can build more aircraft. */
    if (GetAircraftCount() >= AIGameSettings.GetValue("max_aircraft") || AIGameSettings.IsDisabledVehicleType(AIVehicle.VT_AIR)) return -1;

	local engine = this.GetBestRouteEngine(tile_1, tile_2);

	if (engine == null || !AIEngine.IsValidEngine(engine)) {
		if (!silent_mode) AILog.Error("Couldn't find a suitable engine");
		return -1;
	}

	/* Build an aircraft */
	local airport1_type = AIAirport.GetAirportType(tile_1);
	local airport2_type = AIAirport.GetAirportType(tile_2);
	local hangar1 = airport1_type == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(tile_2) : AIAirport.GetHangarOfAirport(tile_1);
	local hangar2 = airport2_type == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(tile_1) : AIAirport.GetHangarOfAirport(tile_2);
	local station1 = AIStation.GetStationID(tile_1);
	local station2 = AIStation.GetStationID(tile_2);
	local cargowaiting1via2 = AICargo.GetDistributionType(this.cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, this.cargoId);
	local cargowaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, this.cargoId);
	local cargowaiting1 = cargowaiting1via2 + cargowaiting1any;
	local cargowaiting2via1 = AICargo.GetDistributionType(this.cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, this.cargoId);
	local cargowaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, this.cargoId);
	local cargowaiting2 = cargowaiting2via1 + cargowaiting2any;
	local best_hangar = cargowaiting1 > cargowaiting2 ? hangar1 : hangar2;

	local vehicle = TestBuildAircraft().TryBuild(best_hangar, engine);
	if (vehicle == null) {
	    if (!silent_mode) AILog.Error("Couldn't build the aircraft");
		return -1;
	}

	local order_1 = AIAirport.IsHangarTile(tile_1) ? AIMap.GetTileIndex(AIMap.GetTileX(tile_1), AIMap.GetTileY(tile_1) + 1) : tile_1;
	local order_2 = AIAirport.IsHangarTile(tile_2) ? AIMap.GetTileIndex(AIMap.GetTileX(tile_2), AIMap.GetTileY(tile_2) + 1) : tile_2;
	if (AIMap.DistanceSquare(best_hangar, tile_1) < AIMap.DistanceSquare(best_hangar, tile_2)) {
	    if (!AIOrder.AppendOrder(vehicle, order_1, AIOrder.OF_NONE)) {
		    if (!silent_mode) AILog.Error("Could not append first order");
			AIVehicle.SellVehicle(vehicle);
			Utils.RepayLoan();
			return -1;
		}
	    if (!AIOrder.AppendOrder(vehicle, order_2, AIOrder.OF_NONE)) {
		    if (!silent_mode) AILog.Error("Could not append second order");
			AIVehicle.SellVehicle(vehicle);
			Utils.RepayLoan();
			return -1;
		}
    } else {
	    if (!AIOrder.AppendOrder(vehicle, order_2, AIOrder.OF_NONE)) {
		    if (!silent_mode) AILog.Error("Could not append first order");
			AIVehicle.SellVehicle(vehicle);
			Utils.RepayLoan();
			return -1;
		}
	    if (!AIOrder.AppendOrder(vehicle, order_1, AIOrder.OF_NONE)) {
		    if (!silent_mode) AILog.Error("Could not append second order");
			AIVehicle.SellVehicle(vehicle);
			Utils.RepayLoan();
			return -1;
		}
	}

    if (!(TestRefitAircraft().TryRefit(vehicle, this.cargoId))) {
	    if (!silent_mode) AILog.Error("Couldn't refit the aircraft");
		return -1;
	}
	
	/* Send him on his way */
	AIVehicle.StartStopVehicle(vehicle);
	
	this.distance_of_route.rawset(vehicle, AIMap.DistanceSquare(tile_1, tile_2));
	vehicle_to_depot.rawdelete(vehicle);
	local dist = WrightAI.DistanceRealFake(tile_1, tile_2);
	
	local route_list = AIVehicleList_Station(AIStation.GetStationID(tile_1));
	route_list.Valuate(AIVehicle.GetVehicleType);
	route_list.KeepValue(AIVehicle.VT_AIR);
	route_list.Valuate(AIVehicle.GetState);
	route_list.RemoveValue(AIVehicle.VS_CRASHED);
	local count = route_list.Count();
	local count_interval = WrightAI.GetEngineRealFakeDist(engine, this.days_interval);
	local aircraft_type = AIEngine.GetPlaneType(AIVehicle.GetEngineType(vehicle));
	local max_count = (dist / count_interval) + GetNumTerminals(aircraft_type, airport1_type) + GetNumTerminals(aircraft_type, airport2_type);

	AILog.Info("Built " + AIEngine.GetName(engine) + " from " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 0))) + " to " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(vehicle, 1))) + " (" + count + "/" + max_count + " aircraft, " + AIMap.DistanceManhattan(tile_1, tile_2) + " manhattan tiles, " + dist + " realfake tiles, " + distance_of_route.rawget(vehicle) + " squared tiles)");

	if (build_multiple && count < max_count) BuildAircraft(tile_2, tile_1, true, true);
	if (!build_multiple && count == 1 && AIAirport.GetNumHangars(tile_1) > 0 && AIAirport.GetNumHangars(tile_2) > 0) BuildAircraft(tile_2, tile_1, true, false);
	return 1;
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
	
	if (AIController.GetSetting("cities_only")) {
        town_list.Valuate(AITown.IsCity);
        town_list.KeepValue(1);
    }

    town_list.Valuate(AITown.GetLastMonthProduction, this.cargoId);
    town_list.KeepAboveValue(cargoClass == AICargo.CC_PASSENGERS ? 70 : 35);
	
	local pick_mode = AIController.GetSetting("pick_mode");
	if (pick_mode == 1) {
	    town_list.Valuate(AIBase.RandItem);
	} else {
	    town_list.Sort(AIList.SORT_BY_VALUE, false);
	}
	
	if (town_list.Count() <= 1 && triedTowns.Count() > 0) {
        this.triedTowns.Clear();
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
	
	if (airport1_tile == 0) {
//	    /* Keep the best 10, if we can't find a station in there, just leave it anyway */
//      town_list.KeepTop(10);
	} else {
		local airport1_town = AITile.GetClosestTown(airport1_tile);
		local airport1_town_tile = AITown.GetLocation(airport1_town);
		if (pick_mode >= 2) {
			town_list.Valuate(WrightAI.GetTownDistanceRealFakeToTile, airport1_town_tile);
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
		        local dist = AITile.GetDistanceSquareToTile(AITown.GetLocation(town), airport1_tile);
			    local fake = WrightAI.DistanceRealFake(AITown.GetLocation(town), airport1_tile);
			    if (dist <= large_max_dist && dist >= large_min_dist && fake <= large_fakedist) {
					large_closestTowns.AddItem(town, AITown.GetLastMonthProduction(town, this.cargoId));
			    }
		    }
		    local large_closest_count = large_closestTowns.Count();
		    AILog.Info(large_closest_count + " possible destination" + (large_closest_count != 1 ? "s" : "") + " from " + AITown.GetName(airport1_town) + " for a large aeroplane route");
//		    large_closestTowns.KeepTop(10);
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
		        local dist = AITile.GetDistanceSquareToTile(AITown.GetLocation(town), airport1_tile);
			    local fake = WrightAI.DistanceRealFake(AITown.GetLocation(town), airport1_tile);
			    if (dist <= small_max_dist && dist >= small_min_dist && fake <= small_fakedist) {
			        small_closestTowns.AddItem(town, AITown.GetLastMonthProduction(town, this.cargoId));
			    }
		    }
		    local small_closest_count = small_closestTowns.Count();
		    AILog.Info(small_closest_count + " possible destination" + (small_closest_count != 1 ? "s" : "") + " from " + AITown.GetName(airport1_town) + " for a small aeroplane route");
//		    small_closestTowns.KeepTop(10);
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
		        local dist = AITile.GetDistanceSquareToTile(AITown.GetLocation(town), airport1_tile);
			    local fake = WrightAI.DistanceRealFake(AITown.GetLocation(town), airport1_tile);
			    if (dist <= heli_max_dist && dist >= heli_min_dist && fake <= heli_fakedist) {
    			    heli_closestTowns.AddItem(town, AITown.GetLastMonthProduction(town, this.cargoId));
	    		}
		    }
		    local heli_closest_count = heli_closestTowns.Count();
		    AILog.Info(heli_closest_count + " possible destination" + (heli_closest_count != 1 ? "s" : "") + " from " + AITown.GetName(airport1_town) + " for a helicopter route");
//		    heli_closestTowns.KeepTop(10);
        }
		
		if (!large_available && !small_available && !heli_available) {
		    return [-1, AIAirport.AT_INVALID, large_aircraft, small_aircraft, helicopter, -1];
		}
			
//		town_list.Clear();
//		if (large_available) town_list.AddList(large_closestTowns);
//		if (small_available) town_list.AddList(small_closestTowns);
//		if (heli_available) town_list.AddList(heli_closestTowns);
	}

    /* Now find a suitable town */
    for (local town = town_list.Begin(); !town_list.IsEnd(); town = town_list.Next()) {
	    /* Don't make this a CPU hog */
//	   	AIController.Sleep(1);
	    local town_tile = AITown.GetLocation(town);
		if (airport1_tile != 0 && !large_closestTowns.HasItem(town) && !small_closestTowns.HasItem(town) && !heli_closestTowns.HasItem(town)) continue;
		
//	    AILog.Info("Checking town " + AITown.GetName(town));
		
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

			if (airport1_tile != 0) {
		        /* If we have the tile of the first airport, we don't want the second airport to be as close or as further */
		    	tileList.Valuate(AITile.GetDistanceSquareToTile, airport1_tile);
			    tileList.KeepBetweenValue(min_dist, max_dist);
				tileList.Valuate(WrightAI.DistanceRealFake, airport1_tile);
				tileList.KeepBelowValue(fakedist);
			    if (tileList.Count() == 0) continue;
		    }

		    tileList.Valuate(AITile.IsBuildableRectangle, airport_x, airport_y);
		    tileList.KeepValue(1)
		    if (tileList.Count() == 0) continue;

		    /* Sort on acceptance, remove places that don't have acceptance */
		    tileList.Valuate(AITile.GetCargoAcceptance, this.cargoId, airport_x, airport_y, airport_rad);
		    tileList.RemoveBelowValue(10);
		    if (tileList.Count() == 0) continue;
		
		    tileList.Valuate(AITile.GetCargoProduction, this.cargoId, airport_x, airport_y, airport_rad);
		    tileList.RemoveBelowValue(18);
 			/* Couldn't find a suitable place for this town, skip to the next */
		    if (tileList.Count() == 0) continue;
		    tileList.Sort(AIList.SORT_BY_VALUE, false);
		
		    /* Walk all the tiles and see if we can build the airport at all */
		    local good_tile = 0;
		    for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
		        local noise = AIAirport.GetNoiseLevelIncrease(tile, a);
			    local allowed_noise = AITown.GetAllowedNoise(AIAirport.GetNearestTown(tile, a));
			    if (noise > allowed_noise) continue;
//			    AISign.BuildSign(tile, ("" + noise + " <= " + allowed_noise + ""));

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
				
			    AIController.Sleep(1);
			    if (AITestMode() && !AIAirport.BuildAirport(tile, a, adjacentStationId)) continue;
				good_tile = tile;
				
				/* Don't build airport if there is any competitor station in the vicinity, or an airport of mine */
				local airportcoverage = this.TownAirportRadRect(a, tile, false);
				local tileList2 = AITileList();
				tileList2.AddRectangle(airportcoverage[0], airportcoverage[1]);
				tileList2.RemoveRectangle(tile, AIMap.GetTileIndex(AIMap.GetTileX(tile + airport_x - 1), AIMap.GetTileY(tile + airport_y - 1)));
				local nearby_station = false;
				for (local t = tileList2.Begin(); !tileList2.IsEnd(); t = tileList2.Next()) {
					if (AITile.IsStationTile(t) && (AIAirport.IsAirportTile(t) || AITile.GetOwner(t) != AICompany.ResolveCompanyID(AICompany.COMPANY_SELF) && AIController.GetSetting("is_friendly"))) {
					    nearby_station = true;
						break;
					}
				}
				if (nearby_station) continue;

				/* Mark the town as tried, so we don't use it again */
				assert(!towns_used.HasItem(nearest_town) && !triedTowns.HasItem(nearest_town) && nearest_town == town);
				this.triedTowns.AddItem(nearest_town, good_tile);

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
		this.triedTowns.AddItem(town, town_tile);
	}
	
	/* We haven't found a suitable location for any airport type in any town */
	return [-1, AIAirport.AT_INVALID, large_aircraft, small_aircraft, helicopter, -1];
}

function WrightAI::GetAircraftCount()
{
    local list = AIVehicleList();
	list.Valuate(AIVehicle.GetVehicleType);
	list.KeepValue(AIVehicle.VT_AIR);
	return list.Count();
}

function WrightAI::ManageAirRoutes()
{
	local start_tick = AIController.GetTick();
	
	local list = AIVehicleList();
	list.Valuate(AIVehicle.GetVehicleType);
	list.KeepValue(AIVehicle.VT_AIR);
	list.Valuate(AIVehicle.GetAge);
	/* Give the plane at least 2 years to make a difference */
	list.KeepAboveValue(365 * 2);
	list.Valuate(AIVehicle.GetProfitLastYear);
	for (local i = list.Begin(); !list.IsEnd(); i = list.Next()) {
		local profit = list.GetValue(i);
		/* Profit last year bad? Let's sell the vehicle */
		if (profit < 0) {
			/* Send the vehicle to depot if we didn't do so yet */
			if (!vehicle_to_depot.rawin(i) || vehicle_to_depot.rawget(i) != true) {
			    local airport1_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(i, 0)) != 0;
				local airport2_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(i, 1)) != 0;
				if (!(airport1_hangars && airport2_hangars)) {
				    if (airport1_hangars) {
					    AIOrder.SkipToOrder(i, 0);
					} else {
					    AIOrder.SkipToOrder(i, 1);
					}
				}
				if (AIVehicle.SendVehicleToDepot(i)) {
				    AILog.Info("Sending " + AIVehicle.GetName(i) + " to hangar as profit last year was: " + profit);
				    vehicle_to_depot.rawset(i, true);
				}
			}
		}
		
		/* Aircraft too old? Sell it. */
		if (AIVehicle.GetAgeLeft(i) < 365) {
		    /* Send the vehicle to depot if we didn't do so yet */
			if (!vehicle_to_depot.rawin(i) || vehicle_to_depot.rawget(i) != true) {
			    local airport1_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(i, 0)) != 0;
				local airport2_hangars = AIAirport.GetNumHangars(AIOrder.GetOrderDestination(i, 1)) != 0;
				if (!(airport1_hangars && airport2_hangars)) {
				    if (airport1_hangars) {
					    AIOrder.SkipToOrder(i, 0);
					} else {
					    AIOrder.SkipToOrder(i, 1);
					}
				}
				if (AIVehicle.SendVehicleToDepot(i)) {
				    AILog.Info("Sending " + AIVehicle.GetName(i) + " to hangar to be sold, due to its old age.");
				    vehicle_to_depot.rawset(i, true);
				}
			}
		}

		/* Sell it once it really is in the depot */
		if (vehicle_to_depot.rawin(i) && vehicle_to_depot.rawget(i) == true && AIVehicle.IsStoppedInDepot(i)) {
		    AILog.Info("Selling " + AIVehicle.GetName(i) + " as it finally is in a hangar. (From " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(i, 0))) + " to " + AIStation.GetName(AIStation.GetStationID(AIOrder.GetOrderDestination(i, 1))) + ")");
			local list2 = AIVehicleList_Station(AIStation.GetStationID(AIOrder.GetOrderDestination(i, 0)));
			list2.Valuate(AIVehicle.GetVehicleType);
		    list2.KeepValue(AIVehicle.VT_AIR);
			/* Last vehicle on this route? */
			if (list2.Count() == 1) {
			    if (AIVehicle.GetProfitLastYear(i) < 10000 && AIVehicle.GetProfitThisYear(i) < 10000) {
				    AILog.Warning("Last aircraft of this route!");
				}
			}
			if (AIVehicle.SellVehicle(i)) {
			    Utils.RepayLoan();
				vehicle_to_depot.rawdelete(i);
			}
		}
	}

	list = AIStationList(AIStation.STATION_AIRPORT);
	local air_routes = list.Count() / 2 + list.Count() % 2;
	list.Valuate(AIStation.GetCargoWaiting, this.cargoId);
	list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	for (local i = list.Begin(); !list.IsEnd(); i = list.Next()) {
		local list2 = AIVehicleList_Station(i);
		list2.Valuate(AIVehicle.GetVehicleType);
		list2.KeepValue(AIVehicle.VT_AIR);
		/* No vehicles going to this station, abort and sell */
		local count = list2.Count();
		if (count == 0) {
		    this.SellAirport(i);
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
//		    if (AIVehicle.GetAge(v) > 365 * 2) {
			    local profit = AIVehicle.GetProfitLastYear(v) + AIVehicle.GetProfitThisYear(v);
				if (best_route_profit == null || profit > best_route_profit) {
				    best_route_profit = profit;
				}
//			}
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
		list2.Valuate(AIVehicle.GetAge);
		list2.KeepBelowValue(count_interval);
		/* Do not build a new vehicle if we bought a new one in the last 'count_interval' days */
		if (list2.Count() != 0) continue;
		
		/* Don't add aircraft if the cargo waiting would not fill it */
		local engine_capacity = AIEngine.GetCapacity(best_engine);
		local other_station = AIStation.GetStationID(order1_location) == i ? AIStation.GetStationID(order2_location) : AIStation.GetStationID(order1_location);
		local cargo_waiting_via_other_station = AICargo.GetDistributionType(this.cargoId) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(i, other_station, this.cargoId);
		local cargo_waiting_via_any_station = AIStation.GetCargoWaitingVia(i, AIStation.STATION_INVALID, this.cargoId);
		local cargo_waiting = cargo_waiting_via_other_station + cargo_waiting_via_any_station;
//		AILog.Info(AIBaseStation.GetName(i) + ": cargo waiting = " + AIStation.GetCargoWaiting(i, this.cargoId) + " ; cargo waiting via " + AIBaseStation.GetName(other_station) + " = " + cargo_waiting_via_other_station + " ; cargo waiting via any station = " + cargo_waiting_via_any_station + " (total = " + cargo_waiting + ")");
		if (cargo_waiting < engine_capacity) continue;
		local number_to_add = 1 + cargo_waiting / engine_capacity;

		/* Try to add this number of aircraft at once */
        for (local n = 1; n <= number_to_add && count + n <= max_count; n++) {
		    this.BuildAircraft(order1_location, order2_location, true);
		}
	}
	
	if (air_routes) {
		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + air_routes + " air route" + (air_routes != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}
}

function WrightAI::GetAirportTile(stationId){
    local airport_tiles = AITileList_StationType(stationId, AIStation.STATION_AIRPORT);
	airport_tiles.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
	return airport_tiles.Begin();
}

/**
  * Sells the airport from stationId
  * Removes town from towns_used list too
  */
function WrightAI::SellAirport(stationId) {
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
//  Utils.RepayLoan();
//	this.UpdateAircraftLists();
//	this.ManageAirRoutes();
	
	local current_date = AIDate.GetCurrentDate();
	local route = this.BuildAirportRoute();
	local days = AIDate.GetCurrentDate() - current_date;
	if (route[0] > 0) {
	    AILog.Warning("Built air route between " + AIBaseStation.GetName(route[1]) + " and " + AIBaseStation.GetName(route[2]) + " in " + days + " day" + (days != 1 ? "s" : "") + ".");
	} else {
	    if (route[0] < 0) {
		    AILog.Error(days + " day" + (days != 1 ? "s" : "") + " wasted!");
		}
	}
//	Utils.RepayLoan();
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
	if (AIGameSettings.GetValue("vehicle_breakdowns")) {
	    local reliability_list = AIList();
		reliability_list.AddList(engine_list);
	    reliability_list.Valuate(AIEngine.GetReliability);
	    reliability_list.KeepBelowValue(75);
	    if (reliability_list.Count() < engine_list.Count()) {
    	    engine_list.RemoveList(reliability_list);
    	}
	}
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
	
	local days_in_transit = 0;
	local best_income = -100000000;
	local best_distance = 0;
	local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
    for (local days = days_int * 3; days <= (breakdowns ? 130 / breakdowns : 185); days++) {
        local income_max_speed = capacity * AICargo.GetCargoIncome(cargo, distance_max_speed * days / 1000, days) - running_cost * days / 365;
//		AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; days_in_transit = " + days + " ; distance = " + (distance_max_speed * days / 1000) + " ; income = " + income_max_speed + " ; " + (aircraft ? "fakedist" : "tiledist") + " = " + (aircraft ? GetEngineRealFakeDist(engine_id, days) : Utils.GetEngineTileDist(engine_id, days)));
		if (breakdowns) {
		    local income_broken_speed = capacity * AICargo.GetCargoIncome(cargo, distance_broken_speed * days / 1000, days) - running_cost * days / 365;
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
	local income = capacity * AICargo.GetCargoIncome(cargo, fakedist, days_in_transit) - running_cost * days_in_transit / 365;
	return income;
}

function WrightAI::checkAdjacentStation(airportTile, airport_type) {
    if (!AIController.GetSetting("station_spread")) {
	    return AIStation.STATION_NEW;
	}

	local tileList = AITileList();
	local spreadrectangle = expandAdjacentStationRect(airportTile, airport_type);
	tileList.AddRectangle(spreadrectangle[0], spreadrectangle[1]);

	tileList.Valuate(Utils.isTileMyStationWithoutAirport);
	tileList.KeepValue(1);
	tileList.Valuate(AIStation.GetStationID);

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

	array.append(distance_of_route);
	array.append(vehicle_to_depot);

	local usedTownsTable = {};
	for (local town = this.towns_used.Begin(), i = 0; !this.towns_used.IsEnd(); town = this.towns_used.Next(), ++i) {
	    usedTownsTable.rawset(i, [town, towns_used.GetValue(town)]);
	}

	array.append(usedTownsTable);
    array.append(cargoClass);

	return array;
}

function WrightAI::load(data) {
	if (towns_used == null) {
		usedTownsTable = AIList();
	}

	cargoId = data[0];

	distance_of_route = data[1];
	vehicle_to_depot = data[2];

	local table = data[3];

	local i = 0;
	while(table.rawin(i)) {
		local town = table.rawget(i);
		towns_used.AddItem(town[0], town[1]);

		++i;
	}
	cargoClass = data[4];
	AILog.Info("Loaded " + towns_used.Count() + " towns used.");
}
