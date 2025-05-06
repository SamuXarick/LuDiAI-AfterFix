class OrthogonalTileArea
{
	tile_top = null; ///< The base tile of the area
	tile_bot = null; ///< The last tile of the area
	w = null; ///< The width of the area
	h = null; ///< The height of the area
	sx = null; ///< The x coordinate of base tile
	sy = null; ///< the y coordinate of base tile
	ex = null; ///< The x coordinate of last tile
	ey = null; ///< The y coordinate of last tile

	constructor(top, width, height)
	{
		assert(AIMap.IsValidTile(top));
		assert(width > 0);
		assert(height > 0);

		this.sx = AIMap.GetTileX(top);
		this.sy = AIMap.GetTileY(top);
		this.ex = this.sx + width - 1;
		this.ey = this.sy + height - 1;

		this.tile_top = top;
		this.tile_bot = AIMap.GetTileIndex(this.ex, this.ey);
		assert(AIMap.IsValidTile(this.tile_bot));
		this.w = this.ex - this.sx + 1;
		this.h = this.ey - this.sy + 1;
	}

	function CreateArea(start, end)
	{
		assert(AIMap.IsValidTile(start));
		assert(AIMap.IsValidTile(end));

		local sx = AIMap.GetTileX(start);
		local sy = AIMap.GetTileY(start);
		local ex = AIMap.GetTileX(end);
		local ey = AIMap.GetTileY(end);

		if (sx > ex) { local temp = sx; sx = ex; ex = temp; }
		if (sy > ey) { local temp = sy; sy = ey; ey = temp; }

		local top = AIMap.GetTileIndex(sx, sy);
		local width = ex - sx + 1;
		local height = ey - sy + 1;

//		AILog.Info("CreateArea, top:" + top + ", width: " + width + ", height: " + height + ", start: " + start + ", end: " + end + ", sx: " + sx + ", sy: " + sy + ", ex: " + ex + ", ey: " + ey);
//		area.PrintValues();
		return OrthogonalTileArea(top, width, height);
	}

	function Expand(rad_x, rad_y, bot = true)
	{
		assert(rad_x >= 0);
		assert(rad_y >= 0);

		local borders = AIGameSettings.GetValue("freeform_edges");
		local x = this.sx;
		local y = this.sy;

		this.sx = max(x - rad_x, borders);
		this.sy = max(y - rad_y, borders);
		if (bot) {
			this.ex = min(x + this.w + rad_x, AIMap.GetMapSizeX() - borders) - 1;
			this.ey = min(y + this.h + rad_y, AIMap.GetMapSizeY() - borders) - 1;
		}

		this.tile_top = AIMap.GetTileIndex(this.sx, this.sy);
		this.tile_bot = AIMap.GetTileIndex(this.ex, this.ey);
		this.w = this.ex - this.sx + 1;
		this.h = this.ey - this.sy + 1;

		return this;
	}

//	function Intersects(ta)
//	{
//		return ta.sx <= this.ex && ta.ex >= this.sx && ta.sy <= this.ey && ta.ey >= this.sy;
//	}

	function Contains(tile)
	{
		assert(AIMap.IsValidTile(tile));

		local x = AIMap.GetTileX(tile);
		local y = AIMap.GetTileY(tile);

		return x <= this.ex && x >= this.sx && y <= this.ey && y >= this.sy;
	}

	function DistanceManhattan(tile)
	{
		assert(AIMap.IsValidTile(tile));

		local x = AIMap.GetTileX(tile);
		local y = AIMap.GetTileY(tile);

		local dx = x < this.sx ? this.sx - x : (x > this.ex ? x - this.ex : 0);
		local dy = y < this.sy ? this.sy - y : (y > this.ey ? y - this.ey : 0);

		return dx + dy;
	}

//	function IsEqual(ta)
//	{
//		return ta.tile_top == this.tile_top && ta.tile_bot == this.tile_bot && ta.w == this.w && ta.h == this.h && ta.sx == this.sx && ta.sy == this.sy && ta.ex == this.ex && ta.ey == this.ey;
//	}

	function PrintValues()
	{
		AILog.Info("tile_top: " + this.tile_top + ", tile_bot: " + this.tile_bot + ", w: " + this.w + ", h: " + this.h + ", sx: " + this.sx + ", sy: " + this.sy + ", ex: " + this.ex + ", ey: " + this.ey);
	}
};

class Utils
{
	function ListHasValue(list, value)
	{
		local list_type = typeof(list);
		assert(list_type == "table" || list_type == "array" || (list_type == "instance" && (list_type instanceof AIList || list_type instanceof AITileList)));

		switch (list_type) {
			case "instance":
				if (typeof(value) == "bool") value = value.tointeger();
				assert(typeof(value) == "integer");
			case "array":
			case "table":
			case "instance":
				foreach (_, val in list) {
					if (val == value) return true;
				}
		}
		return false;
	}

//	function HasBit(x, y)
//	{
//		assert(typeof(x) == "integer");
//		assert(typeof(y) == "integer");
//
//		assert(y >= 0);
//		assert(y < 64);
//
//		return (x & (1 << y)) != 0;
//	}

//	function FindLastBit(value)
//	{
//		assert(typeof(value) == "integer");
//
//		local pos = 0;
//		while (value != 0) {
//			pos++;
//			value = value >> 1;
//		}
//		return pos;
//	}

//	function SB(x, s, n, d)
//	{
//		assert(typeof(x) == "integer");
//		assert(typeof(s) == "integer");
//		assert(typeof(n) == "integer");
//		assert(typeof(d) == "integer");
//
//		assert(s >= 0);
//		assert(s < 64);
//		assert(n > 0);
//		assert(n <= 64);
//		assert(s + n <= 64);
//		assert(Utils.FindLastBit(d) < n);
//
//		x = x & ~(((1 << n) - 1) << s);
//		return x | (d << s);
//	}

//	function AssignBit(x, y, value)
//	{
//		assert(typeof(value) == "bool");
//
//		return Utils.SB(x, y, 1, value.tointeger());
//	}

	function CountBits(value)
	{
		assert(typeof(value) == "integer");

		local num;
		for (num = 0; value != 0; num++) {
			value = value & (value - 1);
		}
		return num;
	}

	function Clamp(a, min, max)
	{
		assert(min <= max);
		if (a <= min) return min;
		if (a >= max) return max;
		return a;
	}

	function ConvertKmhishSpeedToDisplaySpeed(speed)
	{
		local velocity = AIGameSettings.GetValue("units_velocity");
		local unit_str = " km-ish/h";
		local converted_speed = speed;

		if (velocity == 0) { // Imperial
			unit_str = " mph";
			converted_speed = ((speed * 10 * 1) >> 0) / 16;
		} else if (velocity == 1) { // Metric
			unit_str = " km/h";
			converted_speed = ((speed * 10 * 103) >> 6) / 16;
		} else if (velocity == 2) { // SI
			unit_str = " m/s";
			converted_speed = ((speed * 10 * 1831) >> 12) / 16;
		}

		return converted_speed + unit_str;
	}

	function GetValidOffsetTile(tile, offset_x, offset_y)
	{
		local freeform = AIGameSettings.GetValue("freeform_edges");

		offset_x += AIMap.GetTileX(tile);
		offset_y += AIMap.GetTileY(tile);

		offset_x = Utils.Clamp(offset_x, freeform, AIMap.GetMapSizeX() - 2);
		offset_y = Utils.Clamp(offset_y, freeform, AIMap.GetMapSizeY() - 2);

		return AIMap.GetTileIndex(offset_x, offset_y);
	}

	/**
	 * GetOffsetTile
	 * @param tile - The starting tile.
	 * @param offset_x - The x-axis offset.
	 * @param offset_y - The y-axis offset.
	 * @return - The offset tile.
	 */
	function GetOffsetTile(tile, offset_x, offset_y)
	{
		local freeform = AIMap.IsValidTile(0) ? 0 : 1;

		offset_x += AIMap.GetTileX(tile);
		if (offset_x < freeform || offset_x > AIMap.GetMapSizeX() - 2) {
			return AIMap.TILE_INVALID;
		}

		offset_y += AIMap.GetTileY(tile);
		if (offset_y < freeform || offset_y > AIMap.GetMapSizeY() - 2) {
			return AIMap.TILE_INVALID;
		}

		return AIMap.GetTileIndex(offset_x, offset_y);
	}

	/**
	 * GetAdjacentTiles
	 * @param tile - The starting tile.
	 * @return - The AITileList of adjacent tiles.
	 */
	function GetAdjacentTiles(tile)
	{
		local adjacent_tiles = AITileList();

		foreach (offset in [AIMap.GetTileIndex(0, -1), 1, AIMap.GetTileIndex(0, 1), -1]) {
			local offset_tile = tile + offset;
			if (AIMap.IsValidTile(offset_tile)) {
				adjacent_tiles[offset_tile] = 0;
			}
		}

		return adjacent_tiles;
	}

	/**
	 * GetCargoType - Returns either mail cargo_type, or passenger cargo_type.
	 * @param cargo_class - either AICargo.CC_MAIL, or AICargo.CC_PASSENGERS
	 * @return - Cargo list.
	 */
	function GetCargoType(cargo_class)
	{
		local cargo_type = 0xFF;
		foreach (cargo_type2, _ in ::caches.m_cargo_type_list) {
			if (AICargo.HasCargoClass(cargo_type2, cargo_class)) {
				cargo_type = cargo_type2;
				break;
			}
		}
//		assert(AICargo.IsValidCargo(cargo_type));

		/* both AICargo.CC_MAIL and AICargo.CC_PASSENGERS should return the first available cargo_type */
		return cargo_type;
	}

	/**
	 * Distance a vehicle engine runs when moving at its maximum speed for the given time
	 */
	function GetEngineTileDist(engine_id, days_in_transit)
	{
		/* Assuming going in axis, it is the same as distancemanhattan */
		switch (AIEngine.GetVehicleType(engine_id)) {
			case AIVehicle.VT_ROAD: {
				/* ((max_speed * 2 * 74 * days_in_transit * 3) / 4) / (192 * 16) */
				return AIEngine.GetMaxSpeed(engine_id) * days_in_transit * 37 / 1024;
			}
			case AIVehicle.VT_WATER:
			case AIVehicle.VT_AIR:
			case AIVehicle.VT_RAIL: {
				/* (max_speed * 2 * 74 * days_in_transit) / (256 * 16) */
				return AIEngine.GetMaxSpeed(engine_id) * days_in_transit * 37 / 1024;
			}
			default: {
				assert(!AIEngine.IsValidEngine(engine_id) || !AIEngine.IsBuildable(engine_id));
				return 0;
			}
		}
	}

	function GetEngineBrokenRealFakeDist(engine_id, days_in_transit)
	{
		/* For aircraft only */
		if (AIEngine.GetVehicleType(engine_id) != AIVehicle.VT_AIR) {
			assert(!AIEngine.IsValidEngine(engine_id) || !AIEngine.IsBuildable(engine_id));
			return 0;
		}

		local speed_limit_broken = 320 / AIGameSettings.GetValue("plane_speed");
		local max_speed = AIEngine.GetMaxSpeed(engine_id);
		local breakdowns = AIGameSettings.GetValue("vehicle_breakdowns");
		local broken_speed = breakdowns && max_speed < speed_limit_broken ? max_speed : speed_limit_broken;
		return (broken_speed * 2 * 74 * days_in_transit / 256) / 16;
	}

	function GetEngineReliabilityMultiplier(engine_id)
	{
		local reliability = AIEngine.GetReliability(engine_id);
		switch (AIGameSettings.GetValue("vehicle_breakdowns")) {
			case 0:
				return 100;
			case 1:
				return reliability + (100 - reliability) / 2;
			case 2:
			default:
				return reliability;
		}
	}

	function GetMaximumOrderDistance(engine_id)
	{
		local dist = AIEngine.GetMaximumOrderDistance(engine_id);
		return dist == 0 ? 0xFFFFFFFF : dist;
	}

	function DistanceRealFake(t0, t1)
	{
		/* This type of distance is for aircraft only */
		local t0x = AIMap.GetTileX(t0);
		local t0y = AIMap.GetTileY(t0);
		local t1x = AIMap.GetTileX(t1);
		local t1y = AIMap.GetTileY(t1);
		local dx = t0x > t1x ? t0x - t1x : t1x - t0x;
		local dy = t0y > t1y ? t0y - t1y : t1y - t0y;
		return dx > dy ? ((dx - dy) * 3 + dy * 4) / 3 : ((dy - dx) * 3 + dx * 4) / 3;
	}

	function GetBestEngineIncome(engine_list, cargo_type, days_int, aircraft = true, airport_tile = null, airport_type = null)
	{
		local best_income = null;
		local best_distance = 0;
		local best_engine = null;
		foreach (engine_id, _ in engine_list) {
			local optimized = Utils.GetEngineOptimalDaysInTransit(engine_id, cargo_type, days_int, aircraft, airport_tile, airport_type);
			if (best_income == null || optimized[0] > best_income) {
				best_income = optimized[0];
				best_distance = optimized[1];
				best_engine = engine_id;
			}
		}
		return [best_engine, best_distance];
	}

	function GetEngineOptimalDaysInTransit(engine_id, cargo_type, days_int, aircraft, airport_tile = null, airport_type = null)
	{
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		local distance_max_speed = Utils.GetEngineTileDist(engine_id, 1000);
		local distance_broken_speed = aircraft ? Utils.GetEngineBrokenRealFakeDist(engine_id, 1000) : distance_max_speed;
		local running_cost = AIEngine.GetRunningCost(engine_id);
		local primary_capacity = ::caches.GetCapacity(engine_id, cargo_type);
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
		local count_interval = Utils.GetEngineTileDist(engine_id, days_int);
		local infra_cost = 0;
		if (aircraft && infrastructure && airport_tile != null && airport_tile > 0) {
			infra_cost = AIAirport.GetMonthlyMaintenanceCost(airport_type);
			if (airport_type == AIAirport.AT_HELIDEPOT || airport_type == AIAirport.AT_HELISTATION) {
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
			if (aircraft && infrastructure && airport_tile != null && airport_tile > 0) {
				local fake_dist = distance_max_speed * days / 1000;
				max_count = (count_interval > 0 ? (fake_dist / count_interval) : max_count) + AirRoute.GetNumTerminals(aircraft_type, airport_type) + AirRoute.GetNumTerminals(aircraft_type, airport_type);
			}
			local income_primary = primary_capacity * AICargo.GetCargoIncome(cargo_type, distance_max_speed * days / 1000, days);
			local secondary_cargo = Utils.GetCargoType(AICargo.CC_MAIL);
			local is_valid_secondary_cargo = AICargo.IsValidCargo(secondary_cargo);
			local income_secondary = is_valid_secondary_cargo ? secondary_capacity * AICargo.GetCargoIncome(secondary_cargo, distance_max_speed * days / 1000, days) : 0;
			local income_max_speed = (income_primary + income_secondary - running_cost * days / 365 - infra_cost * 12 * days / 365 / max_count)/* * multiplier / 100*/;
			if (income_max_speed > 0 && max_count < min_count && max_count != 1) {
				min_count = max_count;
//			} else if (income_max_speed <= 0 && max_count <= min_count && max_count != 1) {
//				min_count = 1000;
			}
//			AILog.Info("engine = " + AIEngine.GetName(engine_id) + " ; days_in_transit = " + days + " ; distance = " + (distance_max_speed * days / 1000) + " ; income = " + income_max_speed + " ; " + (aircraft ? "fake_dist" : "tiledist") + " = " + Utils.GetEngineTileDist(engine_id, days) + " ; max_count = " + max_count);
			if (breakdowns) {
				local income_primary_broken_speed = primary_capacity * AICargo.GetCargoIncome(cargo_type, distance_broken_speed * days / 1000, days);
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
//		AILog.Info("days in transit = " + days_in_transit + " ; min/best distance = " + min_distance + "/" + best_distance + " ; best_income = " + best_income + " ; " + (aircraft ? "fake_dist" : "tiledist") + " = " + Utils.GetEngineTileDist(engine_id, days_in_transit) + " ; min/best count = " + min_count + "/" + best_count);

		return [best_income, best_distance, min_count];
	}

	function EstimateTownRectangle(town_id)
	{
		local town_location = AITown.GetLocation(town_id);
		local top_bottom_tiles = [town_location, town_location];

		while (true) {
			local max_expanded_counter = 0;
			foreach (offset in [-1, AIMap.GetMapSizeX(), 1, -AIMap.GetMapSizeX()]) {
				local tile = (offset > 0).tointeger(); // 0 == top, 1 == bottom
				local offset_tile = top_bottom_tiles[tile] + offset;

				if (!AIMap.IsValidTile(offset_tile)) {
					++max_expanded_counter;
					continue;
				}

				if (!AITown.IsWithinTownInfluence(town_id, offset_tile)) {
					++max_expanded_counter;
					continue;
				}

				top_bottom_tiles[tile] = offset_tile;
			}

			if (max_expanded_counter == 4) {
				return top_bottom_tiles;
			}
		}
	}

	/**
	 * Check if we have enough money (via loan and on bank).
	 */
	function HasMoney(money)
	{
		if (AIGameSettings.IsValid("infinite_money") && AIGameSettings.GetValue("infinite_money")) return true;

		local loan_amount = AICompany.GetLoanAmount();
		local max_loan_amount = AICompany.GetMaxLoanAmount();
		local bank_balance = AICompany.GetBankBalance(::caches.m_my_company_id);
//		AILog.Info("loan_amount = " + loan_amount + "; max_loan_amount = " + max_loan_amount + "; bank_balance = " + bank_balance);
//		AILog.Info("bank_balance + max_loan_amount - loan_amount >= money : " + (bank_balance + max_loan_amount - loan_amount) + " >= " + money + " : " + (bank_balance + max_loan_amount - loan_amount >= money));
		return (bank_balance + max_loan_amount - loan_amount) >= money;
	}

	function GetMoney(money)
	{
		local bank_balance = AICompany.GetBankBalance(::caches.m_my_company_id);
		if (bank_balance >= money) return;
		local request_loan = money - bank_balance;
		local loan_interval = AICompany.GetLoanInterval();
		local over_interval = request_loan % loan_interval;
		request_loan += loan_interval - over_interval;
		local loan_amount = AICompany.GetLoanAmount();
		local max_loan_amount = AICompany.GetMaxLoanAmount();
		if (loan_amount + request_loan > max_loan_amount) {
			AICompany.SetLoanAmount(max_loan_amount);
		} else {
			AICompany.SetLoanAmount(loan_amount + request_loan);
		}
	}

	function RepayLoan()
	{
		local bank_balance = AICompany.GetBankBalance(::caches.m_my_company_id);
		local loan_amount = AICompany.GetLoanAmount();
		local repay_loan = loan_amount - bank_balance > 0 ? loan_amount - bank_balance : 0;
		AICompany.SetMinimumLoanAmount(repay_loan);
	}
};

class MoneyTest
{
	function DoMoneyTest()
	{
		local price = this.GetPrice();
		if (Utils.HasMoney(price)) {
			Utils.GetMoney(price);
		}
		if (this.DoAction()) {
			Utils.RepayLoan();
			return true;
		}
//		AILog.Error(AIError.GetLastErrorString());
		Utils.RepayLoan();
		return false;
	}
};

class TestDemolishTile extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AITile.DemolishTile(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITile.DemolishTile(this.l);
		return cost.GetCosts();
	}

	function TryDemolish(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestRemoveRoadStation extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.RemoveRoadStation(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadStation(this.l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestRemoveRoadDepot extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.RemoveRoadDepot(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadDepot(this.l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestBuildRoad extends MoneyTest
{
	s = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoad(this.s, this.e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoad(this.s, this.e);
		return cost.GetCosts();
	}

	function TryBuild(start, end)
	{
		this.s = start;
		this.e = end;
		return this.DoMoneyTest();
	}
};

class TestBuildTunnel extends MoneyTest
{
	t = null;
	l = null;

	function DoAction()
	{
		return AIExecMode() && AITunnel.BuildTunnel(this.t, this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITunnel.BuildTunnel(this.t, this.l);
		return cost.GetCosts();
	}

	function TryBuild(vehicle_type, location)
	{
		this.t = vehicle_type;
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestRemoveTunnel extends MoneyTest
{
	t = null;

	function DoAction()
	{
		return AIExecMode() && AITunnel.RemoveTunnel(this.t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITunnel.RemoveTunnel(this.t);
		return cost.GetCosts();
	}

	function TryRemove(tile)
	{
		this.t = tile;
		return this.DoMoneyTest();
	}
};

class TestBuildBridge extends MoneyTest
{
	t = null;
	i = null;
	s = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIBridge.BuildBridge(this.t, this.i, this.s, this.e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIBridge.BuildBridge(this.t, this.i, this.s, this.e);
		return cost.GetCosts();
	}

	function TryBuild(vehicle_type, bridge_type, start, end)
	{
		this.t = vehicle_type;
		this.i = bridge_type;
		this.s = start;
		this.e = end;
		return this.DoMoneyTest();
	}
};

class TestRemoveBridge extends MoneyTest
{
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIBridge.RemoveBridge(this.t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIBridge.RemoveBridge(this.t);
		return cost.GetCosts();
	}

	function TryRemove(tile)
	{
		this.t = tile;
		return this.DoMoneyTest();
	}
};

class TestBuildRoadStation extends MoneyTest
{
	l = null;
	e = null;
	t = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoadStation(this.l, this.e, this.t, this.i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoadStation(this.l, this.e, this.t, this.i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicle_type, station_id)
	{
		this.l = location;
		this.e = exit;
		this.t = vehicle_type;
		this.i = station_id;
		return this.DoMoneyTest();
	}
};

class TestBuildDriveThroughRoadStation extends MoneyTest
{
	l = null;
	e = null;
	t = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildDriveThroughRoadStation(this.l, this.e, this.t, this.i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildDriveThroughRoadStation(this.l, this.e, this.t, this.i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicle_type, station_id)
	{
		this.l = location;
		this.e = exit;
		this.t = vehicle_type;
		this.i = station_id;
		return this.DoMoneyTest();
	}
};

class TestBuildRoadDepot extends MoneyTest
{
	l = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoadDepot(this.l, this.e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoadDepot(this.l, this.e);
		return cost.GetCosts();
	}

	function TryBuild(location, exit)
	{
		this.l = location;
		this.e = exit;
		return this.DoMoneyTest();
	}
};

class TestBuildAirport extends MoneyTest
{
	l = null;
	t = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIAirport.BuildAirport(this.l, this.t, this.i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIAirport.BuildAirport(this.l, this.t, this.i);
		return cost.GetCosts();
	}

	function TryBuild(location, airport_type, station_id)
	{
		this.l = location;
		this.t = airport_type;
		this.i = station_id;
		return this.DoMoneyTest();
	}
};

class TestRemoveAirport extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIAirport.RemoveAirport(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIAirport.RemoveAirport(this.l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestRemoveCanal extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveCanal(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveCanal(this.l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestBuildCanal extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildCanal(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildCanal(this.l);
		return cost.GetCosts();
	}

	function TryBuild(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestBuildDock extends MoneyTest
{
	l = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildDock(this.l, this.i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildDock(this.l, this.i);
		return cost.GetCosts();
	}

	function TryBuild(location, station_id)
	{
		this.l = location;
		this.i = station_id;
		return this.DoMoneyTest();
	}
};

class TestBuildLock extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildLock(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildLock(this.l);
		return cost.GetCosts();
	}

	function TryBuild(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestRemoveDock extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveDock(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveDock(this.l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestBuildWaterDepot extends MoneyTest
{
	t = null;
	b = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildWaterDepot(this.t, this.b);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildWaterDepot(this.t, this.b);
		return cost.GetCosts();
	}

	function TryBuild(top, bottom)
	{
		this.t = top;
		this.b = bottom;
		return this.DoMoneyTest();
	}
};

class TestRemoveWaterDepot extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveWaterDepot(this.l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveWaterDepot(this.l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		this.l = location;
		return this.DoMoneyTest();
	}
};

class TestBuildRailStation extends MoneyTest
{
	t = null;
	d = null;
	n = null;
	l = null;
	s = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRailStation(this.t, this.d, this.n, this.l, this.s);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRailStation(this.t, this.d, this.n, this.l, this.s);
		return cost.GetCosts();
	}

	function TryBuild(tile, direction, num_platforms, platform_length, station_id)
	{
		this.t = tile;
		this.d = direction;
		this.n = num_platforms;
		this.l = platform_length;
		this.s = station_id;
		return this.DoMoneyTest();
	}
};

class TestBuildRail extends MoneyTest
{
	f = null;
	l = null;
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRail(this.f, this.l, this.t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRail(this.f, this.l, this.t);
		return cost.GetCosts();
	}

	function TryBuild(from, location, to)
	{
		this.f = from;
		this.l = location;
		this.t = to;
		return this.DoMoneyTest();
	}
};

// class TestConvertRailType extends MoneyTest
// {
// 	s = null;
// 	e = null;
// 	c = null;

// 	function DoAction()
// 	{
// 		return AIExecMode() && AIRail.ConvertRailType(this.s, this.e, this.c);
// 	}

// 	function GetPrice()
// 	{
// 		local cost = AIAccounting();
// 		AITestMode() && AIRail.ConvertRailType(this.s, this.e, this.c);
// 		return cost.GetCosts();
// 	}

// 	function TryConvert(start_tile, end_tile, convert_to)
// 	{
// 		this.s = start_tile;
// 		this.e = end_tile;
// 		this.c = convert_to;
// 		return this.DoMoneyTest();
// 	}
// };

class TestBuildRailDepot extends MoneyTest
{
	t = null;
	f = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRailDepot(this.t, this.f);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRailDepot(this.t, this.f);
		return cost.GetCosts();
	}

	function TryBuild(tile, front)
	{
		this.t = tile;
		this.f = front;
		return this.DoMoneyTest();
	}
};

class TestRemoveRailStationTileRectangle extends MoneyTest
{
	f = null;
	t = null;
	k = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.RemoveRailStationTileRectangle(this.f, this.t, this.k);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.RemoveRailStationTileRectangle(this.f, this.t, this.k);
		return cost.GetCosts();
	}

	function TryRemove(from, to, keep_rail)
	{
		this.f = from;
		this.t = to;
		this.k = keep_rail;
		return this.DoMoneyTest();
	}
};

class TestRemoveRail extends MoneyTest
{
	f = null;
	l = null;
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.RemoveRail(this.f, this.l, this.t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.RemoveRail(this.f, this.l, this.t);
		return cost.GetCosts();
	}

	function TryRemove(from, location, to)
	{
		this.f = from;
		this.l = location;
		this.t = to;
		return this.DoMoneyTest();
	}
};

class TestBuildSignal extends MoneyTest
{
	l = null;
	t = null;
	s = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildSignal(this.l, this.t, this.s);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildSignal(this.l, this.t, this.s);
		return cost.GetCosts();
	}

	function TryBuild(location, to, signal)
	{
		this.l = location;
		this.t = to;
		this.s = signal;
		return this.DoMoneyTest();
	}
};

class TestBuildVehicleWithRefit extends MoneyTest
{
	d = null;
	e = null;
	c = null;
	v = null;

	function DoAction()
	{
		this.v = AIVehicle.BuildVehicleWithRefit(this.d, this.e, this.c);
		return AIVehicle.IsValidVehicle(this.v);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIVehicle.BuildVehicleWithRefit(this.d, this.e, this.c);
		return cost.GetCosts();
	}

	function TryBuild(depot, engine, cargo_type)
	{
		this.d = depot;
		this.e = engine;
		this.c = cargo_type;
		this.DoMoneyTest();
		return this.v;
	}
};

class TestCloneVehicle extends MoneyTest
{
	d = null;
	v = null;
	s = null;
	c = null;

	function DoAction()
	{
		this.c = AIVehicle.CloneVehicle(this.d, this.v, this.s);
		return AIVehicle.IsValidVehicle(this.c);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIVehicle.CloneVehicle(this.d, this.v, this.s);
		return cost.GetCosts();
	}

	function TryClone(depot, vehicle, shared)
	{
		this.d = depot;
		this.v = vehicle;
		this.s = shared;
		this.DoMoneyTest();
		return this.c;
	}
};

class TestPerformTownAction extends MoneyTest
{
	t = null;
	a = null;

	function DoAction()
	{
		return AIExecMode() && AITown.PerformTownAction(this.t, this.a);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITown.PerformTownAction(this.t, this.a);
		return cost.GetCosts();
	}

	function TryPerform(town_id, action)
	{
		this.t = town_id;
		this.a = action;
		return this.DoMoneyTest();
	}

	function TestCost(town_id, action)
	{
		this.t = town_id;
		this.a = action;
		return this.GetPrice();
	}
};

class TestBuildHQ extends MoneyTest
{
	t = null;

	function DoAction()
	{
		return AIExecMode() && AICompany.BuildCompanyHQ(this.t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AICompany.BuildCompanyHQ(this.t);
		return cost.GetCosts();
	}

	function TryBuild(tile)
	{
		this.t = tile;
		return this.DoMoneyTest();
	}
};

class TestFoundTown extends MoneyTest
{
	t = null;
	s = null;
	c = null;
	l = null;
	n = null;

	function DoAction()
	{
		return AIExecMode() && AITown.FoundTown(this.t, this.s, this.c, this.l, this.n);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITown.FoundTown(this.t, this.s, this.c, this.l, this.n);
		return cost.GetCosts();
	}

	function TryFound(tile, size, city, layout, name)
	{
		this.t = tile;
		this.s = size;
		this.c = city;
		this.l = layout;
		this.n = name;
		return this.DoMoneyTest();
	}

	function TestCost(tile, size, city, layout, name)
	{
		this.t = tile;
		this.s = size;
		this.c = city;
		this.l = layout;
		this.n = name;
		return GetPrice();
	}
};
