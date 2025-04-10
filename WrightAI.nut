class WrightAI
{
	function GetMaximumOrderDistance(engine_id)
	{
		local squared_dist = AIEngine.GetMaximumOrderDistance(engine_id);
		return squared_dist == 0 ? 0xFFFFFFFF : squared_dist;
	}

	function GetNumTerminals(aircraft_type, airport_type)
	{
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
				throw "Invalid airport_type in GetNumTerminals";
		}
	}

	function DistanceRealFake(t0, t1)
	{
		local t0x = AIMap.GetTileX(t0);
		local t0y = AIMap.GetTileY(t0);
		local t1x = AIMap.GetTileX(t1);
		local t1y = AIMap.GetTileY(t1);
		local dx = t0x > t1x ? t0x - t1x : t1x - t0x;
		local dy = t0y > t1y ? t0y - t1y : t1y - t0y;
		return dx > dy ? ((dx - dy) * 3 + dy * 4) / 3 : ((dy - dx) * 3 + dx * 4) / 3;
	}

	function GetEngineRealFakeDist(engine_id, days_in_transit)
	{
		/* Assuming going in axis, it is the same as distancemanhattan */
		local real_fake_dist = (AIEngine.GetMaxSpeed(engine_id) * 2 * 74 * days_in_transit / 256) / 16;
		return real_fake_dist;
	}

	function GetEngineBrokenRealFakeDist(engine_id, days_in_transit)
	{
		local speed_limit_broken = 320 / AIGameSettings.GetValue("plane_speed");
		local max_speed = AIEngine.GetMaxSpeed(engine_id);
		local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
		local broken_speed = breakdowns && max_speed < speed_limit_broken ? max_speed : speed_limit_broken;
		return (broken_speed * 2 * 74 * days_in_transit / 256) / 16;
	}

	function GetBestEngineIncome(engine_list, cargo, days_int, aircraft = true, location_from = null, type_from = null)
	{
		local best_income = null;
		local best_distance = 0;
		local best_engine = null;
		foreach (engine, _ in engine_list) {
			local optimized = GetEngineOptimalDaysInTransit(engine, cargo, days_int, aircraft, location_from, type_from);
			if (best_income == null || optimized[0] > best_income) {
				best_income = optimized[0];
				best_distance = optimized[1];
				best_engine = engine;
			}
		}
		return [best_engine, best_distance];
	}

	function GetEngineOptimalDaysInTransit(engine_id, cargo, days_int, aircraft, location_from = null, type_from = null)
	{
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		local distance_max_speed = aircraft ? GetEngineRealFakeDist(engine_id, 1000) : Utils.GetEngineTileDist(engine_id, 1000);
		local distance_broken_speed = aircraft ? GetEngineBrokenRealFakeDist(engine_id, 1000) : distance_max_speed;
		local running_cost = AIEngine.GetRunningCost(engine_id);
		local primary_capacity = ::caches.GetCapacity(engine_id, cargo);
		local secondary_capacity = (aircraft && AIController.GetSetting("select_town_cargo") == 2) ? ::caches.GetSecondaryCapacity(engine_id) : 0;

		local days_in_transit = 0;
		local best_income = -100000000;
		local best_distance = 0;
//		local min_distance = 0;
		local min_count = 1000;
		local max_count = 1;
		local best_count = 1;
		local multiplier = Utils.GetEngineReliabilityMultiplier(engine_id);
		local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
		local count_interval = GetEngineRealFakeDist(engine_id, days_int);
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
		local max_days = breakdowns ? 150 - 30 * breakdowns : 180;
		for (local days = days_int * 3; days <= max_days; days++) {
			if (aircraft && infrastructure && location_from != null && location_from > 0) {
				local fake_dist = distance_max_speed * days / 1000;
				max_count = (count_interval > 0 ? (fake_dist / count_interval) : max_count) + GetNumTerminals(aircraft_type, type_from) + GetNumTerminals(aircraft_type, type_from);
			}
			local income_primary = primary_capacity * AICargo.GetCargoIncome(cargo, distance_max_speed * days / 1000, days);
			local secondary_cargo = Utils.GetCargoType(AICargo.CC_MAIL);
			local is_valid_secondary_cargo = AICargo.IsValidCargo(secondary_cargo);
			local income_secondary = is_valid_secondary_cargo ? secondary_capacity * AICargo.GetCargoIncome(secondary_cargo, distance_max_speed * days / 1000, days) : 0;
			local income_max_speed = (income_primary + income_secondary - running_cost * days / 365 - infra_cost * 12 * days / 365 / max_count)/* * multiplier / 100*/;
			if (income_max_speed > 0 && max_count < min_count && max_count != 1) {
				min_count = max_count;
//			} else if (income_max_speed <= 0 && max_count <= min_count && max_count != 1) {
//				min_count = 1000;
			}
//			AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; days_in_transit = " + days + " ; distance = " + (distance_max_speed * days / 1000) + " ; income = " + income_max_speed + " ; " + (aircraft ? "fake_dist" : "tiledist") + " = " + (aircraft ? GetEngineRealFakeDist(engine_id, days) : Utils.GetEngineTileDist(engine_id, days)) + " ; max_count = " + max_count);
			if (breakdowns) {
				local income_primary_broken_speed = primary_capacity * AICargo.GetCargoIncome(cargo, distance_broken_speed * days / 1000, days);
				local income_secondary_broken_speed = is_valid_secondary_cargo ? secondary_capacity * AICargo.GetCargoIncome(secondary_cargo, distance_broken_speed * days / 1000, days) : 0;
				local income_broken_speed = (income_primary_broken_speed + income_secondary_broken_speed - running_cost * days / 365 - infra_cost * 12 * days / 365 / max_count);
				if (income_max_speed > 0 && income_broken_speed > 0 && income_max_speed > best_income) {
					best_income = income_max_speed;
					best_distance = distance_max_speed * days / 1000;
					days_in_transit = days;
					best_count = max_count;
//					if (min_distance == 0) min_distance = best_distance;
				}
			} else {
				if (income_max_speed > 0 && income_max_speed > best_income) {
					best_income = income_max_speed;
					best_distance = distance_max_speed * days / 1000;
					days_in_transit = days;
					best_count = max_count;
//					if (min_distance == 0) min_distance = best_distance;
				}
			}
		}
//		AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; max speed = " + AIEngine.GetMaxSpeed(engine_id) + " ; capacity = " + primary_capacity + "/" + secondary_capacity + " ; running cost = " + running_cost + " ; infra cost = " + infra_cost);
//		AILog.Info("days in transit = " + days_in_transit + " ; min/best distance = " + min_distance + "/" + best_distance + " ; best_income = " + best_income + " ; " + (aircraft ? "fake_dist" : "tiledist") + " = " + (aircraft ? GetEngineRealFakeDist(engine_id, days_in_transit) : Utils.GetEngineTileDist(engine_id, days_in_transit)) + " ; min/best count = " + min_count + "/" + best_count);

		return [best_income, best_distance, min_count];
	}

	function GetAdjacentNonAirportStationID(airport_rectangle, spread_rectangle)
	{
		local tile_list = AITileList();
		tile_list.AddRectangle(spread_rectangle.tile_top, spread_rectangle.tile_bot);
		foreach (tile, _ in tile_list) {
			if (!AITile.IsStationTile(tile)) {
				tile_list[tile] = null;
				continue;
			}
			if (AITile.GetOwner(tile) != ::caches.myCID) {
				tile_list[tile] = null;
				continue;
			}
			local station_id = AIStation.GetStationID(tile);
			if (AIStation.HasStationType(station_id, AIStation.STATION_AIRPORT)) {
				tile_list[tile] = null;
				continue;
			}
			tile_list[tile] = station_id;
		}

		local station_list = AIList();
		station_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);
		foreach (tile, station_id in tile_list) {
			station_list[station_id] = airport_rectangle.DistanceManhattan(tile);
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

	function GetAirportTypeName(airport_type)
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
};
