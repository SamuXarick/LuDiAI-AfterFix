class WrightAI {
};

function WrightAI::GetMaximumOrderDistance(engineId) {
	local squaredist = AIEngine.GetMaximumOrderDistance(engineId);
	return squaredist == 0 ? 0xFFFFFFFF : squaredist;
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

function WrightAI::GetBestEngineIncome(engine_list, cargo, days_int, aircraft = true, location_from = null, type_from = null) {
	local best_income = null;
	local best_distance = 0;
	local best_engine = null;
	for (local engine = engine_list.Begin(); !engine_list.IsEnd(); engine = engine_list.Next()) {
		local optimized = WrightAI.GetEngineOptimalDaysInTransit(engine, cargo, days_int, aircraft, location_from, type_from);
		if (best_income == null || optimized[0] > best_income) {
			best_income = optimized[0];
			best_distance = optimized[1];
			best_engine = engine;
		}
	}
	return [best_engine, best_distance];
}

function WrightAI::GetEngineOptimalDaysInTransit(engine_id, cargo, days_int, aircraft, location_from = null, type_from = null)
{
	local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
	local distance_max_speed = aircraft ? WrightAI.GetEngineRealFakeDist(engine_id, 1000) : Utils.GetEngineTileDist(engine_id, 1000);
	local distance_broken_speed = aircraft ? WrightAI.GetEngineBrokenRealFakeDist(engine_id, 1000) : distance_max_speed;
	local running_cost = AIEngine.GetRunningCost(engine_id);
	local primary_capacity = Utils.GetCapacity(engine_id, cargo);
	local secondary_capacity = (aircraft && AIController.GetSetting("select_town_cargo") == 2) ? Utils.GetSecondaryCapacity(engine_id) : 0;
	local reliability = AIEngine.GetReliability(engine_id);

	local days_in_transit = 0;
	local best_income = -100000000;
	local best_distance = 0;
//	local min_distance = 0;
	local min_count = 1000;
	local max_count = 1;
	local best_count = 1;
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
	local count_interval = WrightAI.GetEngineRealFakeDist(engine_id, days_int);
	local infra_cost = 0;
	if (aircraft && infrastructure && location_from != null && location_from > 0) {
		infra_cost = AIAirport.GetMonthlyMaintenanceCost(type_from);
		if (type_from == AIAirport.AT_HELIDEPOT || type_from == AIAirport.AT_HELISTATION) {
			local heliport = AIAirport.GetMonthlyMaintenanceCost(AIAirport.AT_HELIPORT);
			if (!AIAirport.IsValidAirportType(AIAirport.AT_HELIPORT) || infra_cost < heliport) {
				infra_cost += infra_cost;
			} else {
				infra_cost += heliport;
			}
		}
	}
	local aircraft_type = AIEngine.GetPlaneType(engine_id);
	for (local days = days_int * 3; days <= (breakdowns ? 150 - 30 * breakdowns : 180); days++) {
		if (aircraft && infrastructure && location_from != null && location_from > 0) {
			local fakedist = distance_max_speed * days / 1000;
			max_count = (count_interval > 0 ? (fakedist / count_interval) : max_count) + WrightAI.GetNumTerminals(aircraft_type, type_from) + WrightAI.GetNumTerminals(aircraft_type, type_from);
		}
		local income_max_speed = (primary_capacity * AICargo.GetCargoIncome(cargo, distance_max_speed * days / 1000, days) + secondary_capacity * AICargo.GetCargoIncome(Utils.getCargoId(AICargo.CC_MAIL), distance_max_speed * days / 1000, days) - running_cost * days / 365 - infra_cost * 12 * days / 365 / max_count)/* * multiplier / 100*/;
		if (income_max_speed > 0 && max_count < min_count && max_count != 1) {
			min_count = max_count;
		} else if (income_max_speed <= 0 && max_count <= min_count && max_count != 1) {
//			min_count = 1000;
		}
//		AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; days_in_transit = " + days + " ; distance = " + (distance_max_speed * days / 1000) + " ; income = " + income_max_speed + " ; " + (aircraft ? "fakedist" : "tiledist") + " = " + (aircraft ? WrightAI.GetEngineRealFakeDist(engine_id, days) : Utils.GetEngineTileDist(engine_id, days)) + " ; max_count = " + max_count);
		if (breakdowns) {
			local income_broken_speed = (primary_capacity * AICargo.GetCargoIncome(cargo, distance_broken_speed * days / 1000, days) + secondary_capacity * AICargo.GetCargoIncome(Utils.getCargoId(AICargo.CC_MAIL), distance_broken_speed * days / 1000, days) - running_cost * days / 365 - infra_cost * 12 * days / 365 / max_count);
			if (income_max_speed > 0 && income_broken_speed > 0 && income_max_speed > best_income) {
				best_income = income_max_speed;
				best_distance = distance_max_speed * days / 1000;
				days_in_transit = days;
				best_count = max_count;
//				if (min_distance == 0) min_distance = best_distance;
			}
		} else {
			if (income_max_speed > 0 && income_max_speed > best_income) {
				best_income = income_max_speed;
				best_distance = distance_max_speed * days / 1000;
				days_in_transit = days;
				best_count = max_count;
//				if (min_distance == 0) min_distance = best_distance;
			}
		}
	}
//	AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; max speed = " + AIEngine.GetMaxSpeed(engine_id) + " ; capacity = " + primary_capacity + "/" + secondary_capacity + " ; running cost = " + running_cost + " ; infra cost = " + infra_cost);
//	AILog.Info("days in transit = " + days_in_transit + " ; min/best distance = " + min_distance + "/" + best_distance + " ; best_income = " + best_income + " ; " + (aircraft ? "fakedist" : "tiledist") + " = " + (aircraft ? WrightAI.GetEngineRealFakeDist(engine_id, days_in_transit) : Utils.GetEngineTileDist(engine_id, days_in_transit)) + " ; min/best count = " + min_count + "/" + best_count);

	return [best_income, best_distance, min_count];
}

function WrightAI::GetEngineRouteIncome(engine_id, cargo, fakedist, primary_capacity = 0, secondary_capacity = 0) {
	local running_cost = AIEngine.GetRunningCost(engine_id);
	primary_capacity = primary_capacity == 0 ? Utils.GetCapacity(engine_id, cargo) : primary_capacity;
	secondary_capacity = AIController.GetSetting("select_town_cargo") != 2 ? 0 : secondary_capacity == 0 ? Utils.GetSecondaryCapacity(engine_id) : secondary_capacity;
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
	local income = (primary_capacity * AICargo.GetCargoIncome(cargo, fakedist, days_in_transit) + secondary_capacity * AICargo.GetCargoIncome(Utils.getCargoId(AICargo.CC_MAIL), fakedist, days_in_transit) - running_cost * days_in_transit / 365) * multiplier;
//	AILog.Info("Engine = " + AIEngine.GetName(engine_id) + "; income = " + income);
	return income;
}

function WrightAI::checkAdjacentNonAirport(airportTile, airport_type) {
	if (!AIController.GetSetting("station_spread") || !AIGameSettings.GetValue("distant_join_stations")) {
		return AIStation.STATION_NEW;
	}

	local tileList = AITileList();
	local spreadrectangle = WrightAI.expandAdjacentAirportRect(airportTile, airport_type);
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

function WrightAI::expandAdjacentAirportRect(airportTile, airport_type) {
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
		local town_rectangle = Utils.estimateTownRectangle(index);

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

function WrightAI::GetMinAirportDistToTile(airport_tile, airport_type, town_tile)
{
	local airport_x = AIAirport.GetAirportWidth(airport_type);
	local airport_y = AIAirport.GetAirportHeight(airport_type);

	local top_x = AIMap.GetTileX(airport_tile);
	local top_y = AIMap.GetTileY(airport_tile);
	local bot_x = top_x + airport_x - 1;
	local bot_y = top_y + airport_y - 1;

	local tileList = AITileList();
	tileList.AddTile(AIMap.GetTileIndex(top_x, top_y));
	tileList.AddTile(AIMap.GetTileIndex(top_x, bot_y));
	tileList.AddTile(AIMap.GetTileIndex(bot_x, top_y));
	tileList.AddTile(AIMap.GetTileIndex(bot_x, bot_y));

	local min_dist = 0x1FFF;
	for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
		local dist = AIMap.DistanceManhattan(tile, town_tile);
		if (dist < min_dist) {
			min_dist = dist;
		}
	}

	return min_dist;
}
