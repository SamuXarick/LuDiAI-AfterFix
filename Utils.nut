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

	function Intersects(ta)
	{
		return ta.sx <= this.ex && ta.ex >= this.sx && ta.sy <= this.ey && ta.ey >= this.sy;
	}

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

	function IsTileMyStationWithoutRailwayStation(tile)
	{
		return AITile.IsStationTile(tile) && AITile.GetOwner(tile) == ::caches.m_my_company_id && !AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_TRAIN);
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
		local veh_type = AIEngine.GetVehicleType(engine_id);
		/* Assuming going in axis, it is the same as distancemanhattan */
		if (veh_type == AIVehicle.VT_ROAD) {
			/* ((max_speed * 2 * 74 * days_in_transit * 3) / 4) / (192 * 16) */
			return AIEngine.GetMaxSpeed(engine_id) * days_in_transit * 444 / 12288;
		} else if (veh_type == AIVehicle.VT_WATER) {
			/* (max_speed * 2 * 74 * days_in_transit) / (256 * 16) */
			return AIEngine.GetMaxSpeed(engine_id) * days_in_transit * 148 / 4096;
		} else {
			assert(!AIEngine.IsValidEngine(engine_id) || !AIEngine.IsBuildable(engine_id));
			return 0;
		}
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
		local price = GetPrice();
		if (Utils.HasMoney(price)) {
			Utils.GetMoney(price);
		}
		if (DoAction()) {
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
		return AIExecMode() && AITile.DemolishTile(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITile.DemolishTile(l);
		return cost.GetCosts();
	}

	function TryDemolish(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveRoadStation extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.RemoveRoadStation(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadStation(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveRoadDepot extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.RemoveRoadDepot(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadDepot(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildRoad extends MoneyTest
{
	s = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoad(s, e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoad(s, e);
		return cost.GetCosts();
	}

	function TryBuild(start, end)
	{
		s = start;
		e = end;
		return DoMoneyTest();
	}
};

class TestBuildTunnel extends MoneyTest
{
	t = null;
	l = null;

	function DoAction()
	{
		return AIExecMode() && AITunnel.BuildTunnel(t, l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITunnel.BuildTunnel(t, l);
		return cost.GetCosts();
	}

	function TryBuild(vehicleType, location)
	{
		t = vehicleType;
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveTunnel extends MoneyTest
{
	t = null;

	function DoAction()
	{
		return AIExecMode() && AITunnel.RemoveTunnel(t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITunnel.RemoveTunnel(t);
		return cost.GetCosts();
	}

	function TryRemove(tile)
	{
		t = tile;
		return DoMoneyTest();
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
		return AIExecMode() && AIBridge.BuildBridge(t, i, s, e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIBridge.BuildBridge(t, i, s, e);
		return cost.GetCosts();
	}

	function TryBuild(vehicleType, bridgeId, start, end)
	{
		t = vehicleType;
		i = bridgeId;
		s = start;
		e = end;
		return DoMoneyTest();
	}
};

class TestRemoveBridge extends MoneyTest
{
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIBridge.RemoveBridge(t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIBridge.RemoveBridge(t);
		return cost.GetCosts();
	}

	function TryRemove(tile)
	{
		t = tile;
		return DoMoneyTest();
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
		return AIExecMode() && AIRoad.BuildRoadStation(l, e, t, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoadStation(l, e, t, i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicleType, stationId)
	{
		l = location;
		e = exit;
		t = vehicleType;
		i = stationId;
		return DoMoneyTest();
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
		return AIExecMode() && AIRoad.BuildDriveThroughRoadStation(l, e, t, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildDriveThroughRoadStation(l, e, t, i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicleType, stationId)
	{
		l = location;
		e = exit;
		t = vehicleType;
		i = stationId;
		return DoMoneyTest();
	}
};

class TestBuildRoadDepot extends MoneyTest
{
	l = null;
	e = null;

	function DoAction()
	{
		return AIExecMode() && AIRoad.BuildRoadDepot(l, e);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoadDepot(l, e);
		return cost.GetCosts();
	}

	function TryBuild(location, exit)
	{
		l = location;
		e = exit;
		return DoMoneyTest();
	}
};

class TestBuildAirport extends MoneyTest
{
	l = null;
	t = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIAirport.BuildAirport(l, t, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIAirport.BuildAirport(l, t, i);
		return cost.GetCosts();
	}

	function TryBuild(airport_location, airport_type, airport_stationId)
	{
		l = airport_location;
		t = airport_type;
		i = airport_stationId;
		if (DoMoneyTest()) {
			return true;
		}
//		assert(AIError.GetLastError() != AIError.ERR_STATION_TOO_SPREAD_OUT);
		return false;
	}
};

class TestRemoveAirport extends MoneyTest
{
	l = null;

	function DoAction()
	{
		if (AIExecMode() && AIAirport.RemoveAirport(l)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIAirport.RemoveAirport(l);
		return cost.GetCosts();
	}

	function TryRemove(airport_location)
	{
		l = airport_location;
		if (DoMoneyTest()) {
			return true;
		}
		return false;
	}
};

class TestRemoveCanal extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveCanal(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveCanal(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildCanal extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildCanal(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildCanal(l);
		return cost.GetCosts();
	}

	function TryBuild(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildDock extends MoneyTest
{
	l = null;
	i = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildDock(l, i);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildDock(l, i);
		return cost.GetCosts();
	}

	function TryBuild(location, stationId)
	{
		l = location;
		i = stationId;
		return DoMoneyTest();
	}
};

class TestBuildLock extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildLock(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildLock(l);
		return cost.GetCosts();
	}

	function TryBuild(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestRemoveDock extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveDock(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveDock(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
	}
};

class TestBuildWaterDepot extends MoneyTest
{
	t = null;
	b = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.BuildWaterDepot(t, b);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.BuildWaterDepot(t, b);
		return cost.GetCosts();
	}

	function TryBuild(top, bottom)
	{
		t = top;
		b = bottom;
		return DoMoneyTest();
	}
};

class TestRemoveWaterDepot extends MoneyTest
{
	l = null;

	function DoAction()
	{
		return AIExecMode() && AIMarine.RemoveWaterDepot(l);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIMarine.RemoveWaterDepot(l);
		return cost.GetCosts();
	}

	function TryRemove(location)
	{
		l = location;
		return DoMoneyTest();
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
		return AIExecMode() && AIRail.BuildRailStation(t, d, n, l, s);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRailStation(t, d, n, l, s);
		return cost.GetCosts();
	}

	function TryBuild(tile, direction, num_platforms, platform_length, stationId)
	{
		t = tile;
		d = direction;
		n = num_platforms;
		l = platform_length;
		s = stationId;
		return DoMoneyTest();
	}
};

class TestBuildRail extends MoneyTest
{
	f = null;
	l = null;
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRail(f, l, t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRail(f, l, t);
		return cost.GetCosts();
	}

	function TryBuild(from, location, to)
	{
		f = from;
		l = location;
		t = to;
		return DoMoneyTest();
	}
};

// class TestConvertRailType extends MoneyTest
// {
// 	s = null;
// 	e = null;
// 	c = null;

// 	function DoAction()
// 	{
// 		return AIExecMode() && AIRail.ConvertRailType(s, e, c);
// 	}

// 	function GetPrice()
// 	{
// 		local cost = AIAccounting();
// 		AITestMode() && AIRail.ConvertRailType(s, e, c);
// 		return cost.GetCosts();
// 	}

// 	function TryConvert(start_tile, end_tile, convert_to)
// 	{
// 		s = start_tile;
// 		e = end_tile;
// 		c = convert_to;
// 		return DoMoneyTest();
// 	}
// };

class TestBuildRailDepot extends MoneyTest
{
	t = null;
	f = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildRailDepot(t, f);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildRailDepot(t, f);
		return cost.GetCosts();
	}

	function TryBuild(tile, front)
	{
		t = tile;
		f = front;
		return DoMoneyTest();
	}
};

class TestRemoveRailStationTileRectangle extends MoneyTest
{
	f = null;
	t = null;
	k = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.RemoveRailStationTileRectangle(f, t, k);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.RemoveRailStationTileRectangle(f, t, k);
		return cost.GetCosts();
	}

	function TryRemove(from, to, keep_rail)
	{
		f = from;
		t = to;
		k = keep_rail;
		return DoMoneyTest();
	}
};

class TestRemoveRail extends MoneyTest
{
	f = null;
	l = null;
	t = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.RemoveRail(f, l, t);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.RemoveRail(f, l, t);
		return cost.GetCosts();
	}

	function TryRemove(from, location, to)
	{
		f = from;
		l = location;
		t = to;
		return DoMoneyTest();
	}
};

class TestBuildSignal extends MoneyTest
{
	l = null;
	t = null;
	s = null;

	function DoAction()
	{
		return AIExecMode() && AIRail.BuildSignal(l, t, s);
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIRail.BuildSignal(l, t, s);
		return cost.GetCosts();
	}

	function TryBuild(location, to, signal)
	{
		l = location;
		t = to;
		s = signal;
		return DoMoneyTest();
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
		v = AIVehicle.BuildVehicleWithRefit(d, e, c);
		if (!AIVehicle.IsValidVehicle(v)) {
			return false;
		}
		return true;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIVehicle.BuildVehicleWithRefit(d, e, c);
		return cost.GetCosts();
	}

	function TryBuild(depot, engine, cargo_type)
	{
		d = depot;
		e = engine;
		c = cargo_type;
		if (DoMoneyTest()) {
			return v;
		}
		return AIVehicle.VEHICLE_INVALID;
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
		c = AIVehicle.CloneVehicle(d, v, s);
		if (!AIVehicle.IsValidVehicle(c)) {
			return false;
		}
		return true;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AIVehicle.CloneVehicle(d, v, s);
		return cost.GetCosts();
	}

	function TryClone(depot, vehicle, shared)
	{
		d = depot;
		v = vehicle;
		s = shared;
		if (DoMoneyTest()) {
			return c;
		}
		return AIVehicle.VEHICLE_INVALID;
	}
};

class TestPerformTownAction extends MoneyTest
{
	t = null;
	a = null;

	function DoAction()
	{
		if (AIExecMode() && AITown.PerformTownAction(t, a)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITown.PerformTownAction(t, a);
		return cost.GetCosts();
	}

	function TryPerform(town_id, action)
	{
		t = town_id;
		a = action;
		return DoMoneyTest();
	}

	function TestCost(town_id, action)
	{
		t = town_id;
		a = action;
		return GetPrice();
	}
};

class TestBuildHQ extends MoneyTest
{
	t = null;

	function DoAction()
	{
		if (AIExecMode() && AICompany.BuildCompanyHQ(t)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AICompany.BuildCompanyHQ(t);
		return cost.GetCosts();
	}

	function TryBuild(tile)
	{
		t = tile;
		return DoMoneyTest();
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
		if (AIExecMode() && AITown.FoundTown(t, s, c, l, n)) {
			return true;
		}
		return false;
	}

	function GetPrice()
	{
		local cost = AIAccounting();
		AITestMode() && AITown.FoundTown(t, s, c, l, n);
		return cost.GetCosts();
	}

	function TryFound(tile, size, city, layout, name)
	{
		t = tile;
		s = size;
		c = city;
		l = layout;
		n = name;
		return DoMoneyTest();
	}

	function TestCost(tile, size, city, layout, name)
	{
		t = tile;
		s = size;
		c = city;
		l = layout;
		n = name;
		return GetPrice();
	}
};
