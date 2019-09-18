Utils <- class {}

function Utils::ConvertKmhishSpeedToDisplaySpeed(speed) {
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

/// getNthItem
///
/// @param list - The list to get the item from.
/// @param n - The order of the item.
/// @return - The n-th item of the list, null if not found.
function Utils::getNthItem(list, n) {
	if (list.Count() == 0) {
		AILog.Warning("getNthItem: list is empty!");
		return null;
	}

	if (n + 1 > list.Count()) {
		AILog.Warning("getNthItem: list is too short!");
		return null;
	}

	for (local item = list.Begin(); !list.IsEnd(); item = list.Next()) {
		if (n == 0) {
			//AILog.Info("getNthItem: Found: " + item + " " + list.GetValue(item));
			return item;
		}
		n--;
	}

	return null;
}

function Utils::MyCID() {
	return AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
}

function Utils::getValidOffsetTile(tile, offsetX, offsetY) {
	local oldX = AIMap.GetTileX(tile);
	local oldY = AIMap.GetTileY(tile);

	local newX = oldX;
	local newY = oldY;

	if (offsetX > 0) {
		for (local x = offsetX; x > 0; x--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(newX + 1, newY))) {
				newX = newX + 1;
			}
		}
	} else {
		for (local x = offsetX; x < 0; x++) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(newX - 1, newY))) {
				newX = newX - 1;
			}
		}
	}

	if (offsetY > 0) {
		for (local y = offsetY; y > 0; y--) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(newX, newY + 1))) {
				newY = newY + 1;
			}
		}
	} else {
		for (local y = offsetY; y < 0; y++) {
			if (AIMap.IsValidTile(AIMap.GetTileIndex(newX, newY - 1))) {
				newY = newY - 1;
			}
		}
	}

	return AIMap.GetTileIndex(newX, newY);
}

/// getOffsetTile
///
/// @param tile - The starting tile.
/// @param offsetX - The x-axis offset.
/// @param offsetY - The y-axis offset.
/// @return - The offset tile.
function Utils::getOffsetTile(tile, offsetX, offsetY) {
	local oldX = AIMap.GetTileX(tile);
	local oldY = AIMap.GetTileY(tile);

	local newX = oldX + offsetX;
	local newY = oldY + offsetY;

	local freeform = AIMap.IsValidTile(0) ? 0 : 1;
	if (((newX < freeform) || (newY < freeform)) // 0 if freeform_edges off
		&& (((newX > AIMap.GetMapSizeX() - 2) || (newY > AIMap.GetMapSizeY() - 2)))) {
		return AIMap.TILE_INVALID;
	}

	return AIMap.GetTileIndex(newX, newY);
}

/// getAdjacentTiles
///
/// @param tile - The starting tile.
/// @return - The AITileList of adjacent tiles.
function Utils::getAdjacentTiles(tile) {
	local adjTiles = AITileList();

	local offsetTile = Utils.getOffsetTile(tile, 0, -1)
	if (offsetTile != AIMap.TILE_INVALID) {
		adjTiles.AddTile(offsetTile);
	}

	offsetTile = Utils.getOffsetTile(tile, 1, 0)
	if (offsetTile != AIMap.TILE_INVALID) {
		adjTiles.AddTile(offsetTile);
	}

	offsetTile = Utils.getOffsetTile(tile, 0, 1)
	if (offsetTile != AIMap.TILE_INVALID) {
		adjTiles.AddTile(offsetTile);
	}

	offsetTile = Utils.getOffsetTile(tile, -1, 0)
	if (offsetTile != AIMap.TILE_INVALID) {
		adjTiles.AddTile(offsetTile);
	}

	return adjTiles;
};

function Utils::IsStationBuildableTile(tile) {
	if ((AITile.GetSlope(tile) == AITile.SLOPE_FLAT/* || !AITile.IsCoastTile(tile) || !AITile.HasTransportType(tile, AITile.TRANSPORT_WATER) || Utils.HasMoney(AICompany.GetMaxLoanAmount() * 2)*/) &&
			(AITile.IsBuildable(tile) || AIRoad.IsRoadTile(tile) && !AIRoad.IsDriveThroughRoadStationTile(tile) && !AIRail.IsLevelCrossingTile(tile))) {
		return true;
	}
	return false;
}

function Utils::AreOtherStationsNearby(tile, cargoClass, stationId) {
	local stationType = cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP;

	//check if there are other stations squareSize squares nearby
	local squareSize = AIStation.GetCoverageRadius(stationType);
	if (stationId == AIStation.STATION_NEW) {
		squareSize = squareSize * 2;
	}

	local square = AITileList();
	if (!AIController.GetSetting("is_friendly")) {
		//dont care about enemy stations when is_friendly is off
		square.AddRectangle(Utils.getValidOffsetTile(tile, (-1) * squareSize, (-1) * squareSize),
			Utils.getValidOffsetTile(tile, squareSize, squareSize));

		//if another road station of mine is nearby return true
		for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
			if (Utils.isTileMyRoadStation(tile, cargoClass)) { //negate second expression to merge your stations
				return true;
			}
		}
	}
	else {
		square.AddRectangle(Utils.getValidOffsetTile(tile, (-1) * squareSize, (-1) * squareSize),
			Utils.getValidOffsetTile(tile, squareSize, squareSize));

		//if any other station is nearby, except my own airports, return true
		for (local tile = square.Begin(); !square.IsEnd(); tile = square.Next()) {
			if (AITile.IsStationTile(tile)) {
				if (AITile.GetOwner(tile) != Utils.MyCID()) {
					return true;
				} else {
					local stationTiles = AITileList_StationType(AIStation.GetStationID(tile), stationType);
					if (stationTiles.HasItem(tile)) {
						return true;
					}
				}
			}
		}
	}

	return false;
};

function Utils::isTileMyRoadStation(tile, cargoClass) {
	if (AITile.IsStationTile(tile) && AITile.GetOwner(tile) == Utils.MyCID() &&
			AIStation.HasStationType(AIStation.GetStationID(tile), cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP)) {
		return 1;
	}

	return 0;
}

function Utils::isTileMyStationWithoutAirport(tile) { // Checks RoadStation
	if (AITile.IsStationTile(tile) && AITile.GetOwner(tile) == Utils.MyCID() &&
			!AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_AIRPORT)) {
		return 1;
	}

	return 0;
}

function Utils::isTileMyStationWithoutRoadStation(tile, cargoClass) { // Checks Airport
	if (AITile.IsStationTile(tile) && AITile.GetOwner(tile) == Utils.MyCID() &&
			!AIStation.HasStationType(AIStation.GetStationID(tile), cargoClass == AICargo.CC_PASSENGERS ? AIStation.STATION_BUS_STOP : AIStation.STATION_TRUCK_STOP)) {
		return 1;
	}

	return 0;
}

function Utils::isTileMyStationWithoutRoadStationOfAnyType(tile) {
	if (AITile.IsStationTile(tile) && AITile.GetOwner(tile) == Utils.MyCID() &&
			!AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_BUS_STOP) &&
			!AIStation.HasStationType(AIStation.GetStationID(tile), AIStation.STATION_TRUCK_STOP)) {
		return 1;
	}
	
	return 0;
}

/// getCargoId - Returns either mail cargo id, or passenger cargo id.
///
/// @param cargoClass - either AICargo.CC_MAIL, or AICargo.CC_PASSENGERS
/// @return - Cargo list.
function Utils::getCargoId(cargoClass) {
	local cargoList = AICargoList();
	cargoList.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);

	local cargoId = null;
	for (cargoId = cargoList.Begin(); !cargoList.IsEnd(); cargoId = cargoList.Next()) {
		if (AICargo.HasCargoClass(cargoId, cargoClass)) {
			break;
		}
	}

	/* both AICargo.CC_MAIL and AICargo.CC_PASSENGERS should return the first available cargo */
	return cargoId;
}

function Utils::IsTownGrowing(town, cargo) {
//	return true;
	if (!AIGameSettings.GetValue("town_growth_rate")) return true; // no town grows, just work with it

	local cargoList = AICargoList();
	cargoList.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
	local cargoRequired = AIList();
	for (local cargo_type = cargoList.Begin(); !cargoList.IsEnd(); cargo_type = cargoList.Next()) {
		local town_effect = AICargo.GetTownEffect(cargo_type);
		local class_name = "";
//		for (local cc = 0; cc <= 15; cc++) {
//			local cargo_class = 1 << cc;
//			if (AICargo.HasCargoClass(cargo_type, cargo_class)) {
//				if (class_name != "") class_name += ", ";
//				switch(cargo_class) {
//					case AICargo.CC_PASSENGERS: class_name += "CC_PASSENGERS"; break;
//					case AICargo.CC_MAIL: class_name += "CC_MAIL"; break;
//					case AICargo.CC_EXPRESS: class_name += "CC_EXPRESS"; break;
//					case AICargo.CC_ARMOURED: class_name += "CC_ARMOURED"; break;
//					case AICargo.CC_BULK: class_name += "CC_BULK"; break;
//					case AICargo.CC_PIECE_GOODS: class_name += "CC_PIECE_GOODS"; break;
//					case AICargo.CC_LIQUID: class_name += "CC_LIQUID"; break;
//					case AICargo.CC_REFRIGERATED: class_name += "CC_REFRIGERATED"; break;
//					case AICargo.CC_HAZARDOUS: class_name += "CC_HAZARDOUS"; break;
//					case AICargo.CC_COVERED: class_name += "CC_COVERED"; break;
//					case 1 << 15: class_name += "CC_SPECIAL"; break;
//					default: class_name += "CC_NOAVAILABLE (" + cargo_class + ")"; break;
//				}
//			}
//		}
//		AILog.Info("Cargo " + cargo_type + ": " + AICargo.GetCargoLabel(cargo_type) + (class_name == "" ? "" : "; CargoClass = " + class_name));
		if (town_effect != AICargo.TE_NONE) {
			local effect_name;
			switch(town_effect) {
				case AICargo.TE_PASSENGERS: effect_name = "TE_PASSENGERS"; break;
				case AICargo.TE_MAIL: effect_name = "TE_MAIL"; break;
				case AICargo.TE_GOODS: effect_name = "TE_GOODS"; break;
				case AICargo.TE_WATER: effect_name = "TE_WATER"; break;
				case AICargo.TE_FOOD: effect_name = "TE_FOOD"; break;
			}
//			AILog.Info(" - Effect of " + AICargo.GetCargoLabel(cargo_type) + " in " + AITown.GetName(town) + " is " + effect_name);
			local cargo_goal = AITown.GetCargoGoal(town, town_effect);
			if (cargo_goal != 0) {
//				AILog.Info(" - An amount of " + cargo_goal + " " + AICargo.GetCargoLabel(cargo_type) + " is required to grow " + AITown.GetName(town));
				cargoRequired.AddItem(cargo_type, cargo_goal);
			}
		}
	}
//	AILog.Info(" ");
	local num_cargo_types_required = cargoRequired.Count();
	local result = null;
	if (num_cargo_types_required == 0 || cargoRequired.HasItem(cargo) && num_cargo_types_required == 1) {
		result = true;
	} else {
		result = false;
	}
//	AILog.Info("-- Result for town " + AITown.GetName(town) + ": " + result + " - " + num_cargo_types_required + " --");
	return result;
}

function Utils::checkAdjacentAirport(stationTile, cargoClass, stationId)
{
	if (stationId != AIStation.STATION_NEW) {
		return stationId;
	}

	if (!AIController.GetSetting("station_spread")) {
		return AIStation.STATION_NEW;
	}

	local spread_rad = AIGameSettings.GetValue("station_spread") - 1;

	local tileList = AITileList();
	local spreadrectangle = [Utils.getValidOffsetTile(stationTile, (-1) * spread_rad, (-1) * spread_rad), Utils.getValidOffsetTile(stationTile, spread_rad, spread_rad)];
	tileList.AddRectangle(spreadrectangle[0], spreadrectangle[1]);

	local templist = AITileList();
	for (local tile = tileList.Begin(); !tileList.IsEnd(); tile = tileList.Next()) {
		if (Utils.isTileMyStationWithoutRoadStationOfAnyType(tile)) {
			tileList.SetValue(tile, AIStation.GetStationID(tile));
		} else {
			templist.AddTile(tile);
		}
	}
	tileList.RemoveList(templist);

	local airportList = AIList();

	for (local tile = tileList.Begin(); !tileList.IsEnd(); tileList.Next()) {
		airportList.AddItem(tileList.GetValue(tile), AITile.GetDistanceManhattanToTile(tile, stationTile));
	}

	local spreadrectangle_top_x = AIMap.GetTileX(spreadrectangle[0]);
	local spreadrectangle_top_y = AIMap.GetTileY(spreadrectangle[0]);
	local spreadrectangle_bot_x = AIMap.GetTileX(spreadrectangle[1]);
	local spreadrectangle_bot_y = AIMap.GetTileY(spreadrectangle[1]);

	local list = AIList();
	list.AddList(airportList);
	for (local airportId = airportList.Begin(); !airportList.IsEnd(); airportId = airportList.Next()) {
		local airportTiles = AITileList_StationType(airportId, AIStation.STATION_ANY);
		local airport_top_x = AIMap.GetTileX(AIBaseStation.GetLocation(airportId));
		local airport_top_y = AIMap.GetTileY(AIBaseStation.GetLocation(airportId));
		local airport_bot_x = airport_top_x;
		local airport_bot_y = airport_top_y;
		for (local tile = airportTiles.Begin(); !airportTiles.IsEnd(); tile = airportTiles.Next()) {
			local tile_x = AIMap.GetTileX(tile);
			local tile_y = AIMap.GetTileY(tile);
			if (tile_x < airport_top_x) {
				airport_top_x = tile_x;
			}
			if (tile_x > airport_bot_x) {
				airport_bot_x = tile_x;
			}
			if (tile_y < airport_top_y) {
				airport_top_y = tile_y;
			}
			if (tile_y > airport_bot_y) {
				airport_bot_y = tile_y;
			}
		}

		if (spreadrectangle_top_x > airport_top_x ||
			spreadrectangle_top_y > airport_top_y ||
			spreadrectangle_bot_x < airport_bot_x ||
			spreadrectangle_bot_y < airport_bot_y) {
			list.RemoveItem(airportId);
		}
	}
	list.Sort(AIList.SORT_BY_VALUE, true);

	local adjacentStation = AIStation.STATION_NEW;
	if (list.Count()) {
		adjacentStation = list.Begin();
		AILog.Info("adjacentStation = " + AIStation.GetName(adjacentStation) + " ; stationtTile = " + AIMap.GetTileX(stationTile) + "," + AIMap.GetTileY(stationTile));
	}

	return adjacentStation;
}

/**
 * Distance a road vehicle engine runs when moving at its maximum speed for the given time
 */
function Utils::GetEngineTileDist(engine_id, days_in_transit)
{
	/* Assuming going in axis, it is the same as distancemanhattan */
	local tiledist = ((AIEngine.GetMaxSpeed(engine_id) * 2 * 74 * days_in_transit * 3) / 4) / (192 * 16);
	return tiledist;
}

/**
 * Check if we have enough money (via loan and on bank).
 */
function Utils::HasMoney(money)
{
	local loan_amount = AICompany.GetLoanAmount();
	local max_loan_amount = AICompany.GetMaxLoanAmount();
	local bank_balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	if (bank_balance + max_loan_amount - loan_amount >= money) return true;
	return false;
}

function Utils::GetMoney(money)
{
	local bank_balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
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

function Utils::RepayLoan()
{
	local bank_balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	local loan_amount = AICompany.GetLoanAmount();
	local repay_loan = loan_amount - bank_balance > 0 ? loan_amount - bank_balance : 0;
	AICompany.SetMinimumLoanAmount(repay_loan);
}

class MoneyTest {
	function DoMoneyTest() {
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
}

class TestDemolishTile extends MoneyTest {
	l = null;

	function DoAction() {
		return AIExecMode() && AITile.DemolishTile(l);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AITile.DemolishTile(l);
		return cost.GetCosts();
	}

	function TryDemolish(location) {
		l = location;
		return DoMoneyTest();
	}
}

class TestRemoveRoadStation extends MoneyTest {
	l = null;

	function DoAction() {
		return AIExecMode() && AIRoad.RemoveRoadStation(l);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadStation(l);
		return cost.GetCosts();
	}

	function TryRemove(location) {
		l = location;
		return DoMoneyTest();
	}
}

class TestRemoveRoadDepot extends MoneyTest {
	l = null;

	function DoAction() {
		return AIExecMode() && AIRoad.RemoveRoadDepot(l);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIRoad.RemoveRoadDepot(l);
		return cost.GetCosts();
	}

	function TryRemove(location) {
		l = location;
		return DoMoneyTest();
	}
}

class TestBuildRoad extends MoneyTest {
	s = null;
	e = null;

	function DoAction() {
		return AIExecMode() && AIRoad.BuildRoad(s, e);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoad(s, e);
		return cost.GetCosts();
	}

	function TryBuild(start, end) {
		s = start;
		e = end;
		return DoMoneyTest();
	}
}

class TestBuildTunnel extends MoneyTest {
	t = null;
	l = null;

	function DoAction() {
		return AIExecMode() && AITunnel.BuildTunnel(t, l);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AITunnel.BuildTunnel(t, l);
		return cost.GetCosts();
	}

	function TryBuild(vehicleType, location) {
		t = vehicleType;
		l = location;
		return DoMoneyTest();
	}
}

class TestBuildBridge extends MoneyTest {
	t = null;
	i = null;
	s = null;
	e = null;

	function DoAction() {
		return AIExecMode() && AIBridge.BuildBridge(t, i, s, e);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIBridge.BuildBridge(t, i, s, e);
		return cost.GetCosts();
	}

	function TryBuild(vehicleType, bridgeId, start, end) {
		t = vehicleType;
		i = bridgeId;
		s = start;
		e = end;
		return DoMoneyTest();
	}
}

class TestBuildRoadStation extends MoneyTest {
	l = null;
	e = null;
	t = null;
	i = null;

	function DoAction() {
		return AIExecMode() && AIRoad.BuildRoadStation(l, e, t, i);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildRoadStation(l, e, t, i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicleType, stationId) {
		l = location;
		e = exit;
		t = vehicleType;
		i = stationId;
		return DoMoneyTest();
	}
}

class TestBuildDriveThroughRoadStation extends MoneyTest {
	l = null;
	e = null;
	t = null;
	i = null;

	function DoAction() {
		return AIExecMode() && AIRoad.BuildDriveThroughRoadStation(l, e, t, i);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIRoad.BuildDriveThroughRoadStation(l, e, t, i);
		return cost.GetCosts();
	}

	function TryBuild(location, exit, vehicleType, stationId) {
		l = location;
		e = exit;
		t = vehicleType;
		i = stationId;
		return DoMoneyTest();
	}
}

class TestBuildRoadDepot extends MoneyTest {
	l = null;
	e = null;

	function DoAction() {
		return AIExecMode() && AIRoad.BuildRoadDepot(l, e);
	}

	function GetPrice() {
	   local cost = AIAccounting();
	   AITestMode() && AIRoad.BuildRoadDepot(l, e);
	   return cost.GetCosts();
	}

	function TryBuild(location, exit) {
		l = location;
		e = exit;
		return DoMoneyTest();
	}
}

class TestBuildAirport extends MoneyTest {
	l = null;
	t = null;
	i = null;

	function DoAction() {
		return AIExecMode() && AIAirport.BuildAirport(l, t, i);
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIAirport.BuildAirport(l, t, i);
		return cost.GetCosts();
	}

	function TryBuild(airport_location, airport_type, airport_stationId) {
		l = airport_location;
		t = airport_type;
		i = airport_stationId;
		if (DoMoneyTest()) {
			return true;
		}
		assert(AIError.GetLastError() != AIError.ERR_STATION_TOO_SPREAD_OUT);
		return false;
	}
}

class TestBuildAircraft extends MoneyTest {
	h = null;
	e = null;
	v = null;

	function DoAction() {
		v = AIVehicle.BuildVehicle(h, e);
		if (!AIVehicle.IsValidVehicle(v)) {
			return false;
		}
		return true;
	}

	function GetPrice() {
		return AIEngine.GetPrice(e);
	}

	function TryBuild(best_hangar, engine) {
		h = best_hangar;
		e = engine;
		if (DoMoneyTest()) {
			return v;
		}
		return AIVehicle.VEHICLE_INVALID;
	}
}

class TestCloneAircraft extends MoneyTest {
	d = null;
	v = null;
	s = null;
	c = null;

	function DoAction() {
		c = AIVehicle.CloneVehicle(d, v, s);
		if (!AIVehicle.IsValidVehicle(c)) {
			return false;
		}
		return true;
	}

	function GetPrice() {
		return AIEngine.GetPrice(AIVehicle.GetEngineType(v)) + 12500;
	}

	function TryClone(depot, vehicle, shared) {
		d = depot;
		v = vehicle;
		s = shared;
		if (DoMoneyTest()) {
			return c;
		}
		return AIVehicle.VEHICLE_INVALID;
	}
}

class TestRefitAircraft extends MoneyTest {
	v = null;
	c = null;

	function DoAction() {
		if (AIExecMode() && AIVehicle.RefitVehicle(v, c)) {
			return true;
		}
		AIVehicle.SellVehicle(v);
		return false;
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIVehicle.RefitVehicle(v, c);
		return cost.GetCosts();
	}

	function TryRefit(vehicle, cargoId) {
		v = vehicle;
		c = cargoId;
		return DoMoneyTest();
	}
}

class TestRemoveAirport extends MoneyTest {
	l = null;

	function DoAction() {
		if (AIExecMode() && AIAirport.RemoveAirport(l)) {
			return true;
		}
		return false;
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIAirport.RemoveAirport(l);
		return cost.GetCosts();
	}

	function TryRemove(airport_location) {
		l = airport_location;
		if (DoMoneyTest()) {
			return true;
		}
		return false;
	}
}

class TestBuildRoadVehicle extends MoneyTest {
	d = null;
	e = null;
	v = null;

	function DoAction() {
		v = AIVehicle.BuildVehicle(d, e);
		if (!AIVehicle.IsValidVehicle(v)) {
			return false;
		}
		return true;
	}

	function GetPrice() {
		return AIEngine.GetPrice(e);
	}

	function TryBuild(depot, engine) {
		d = depot;
		e = engine;
		if (DoMoneyTest()) {
			return v;
		}
		return AIVehicle.VEHICLE_INVALID;
	}
}

class TestCloneRoadVehicle extends MoneyTest {
	d = null;
	v = null;
	s = null;
	c = null;

	function DoAction() {
		c = AIVehicle.CloneVehicle(d, v, s);
		if (!AIVehicle.IsValidVehicle(c)) {
			return false;
		}
		return true;
	}

	function GetPrice() {
		return AIEngine.GetPrice(AIVehicle.GetEngineType(v));
	}

	function TryClone(depot, vehicle, shared) {
		d = depot;
		v = vehicle;
		s = shared;
		if (DoMoneyTest()) {
			return c;
		}
		return AIVehicle.VEHICLE_INVALID;
	}
}

class TestRefitRoadVehicle extends MoneyTest {
	v = null;
	c = null;

	function DoAction() {
		if (AIExecMode() && AIVehicle.RefitVehicle(v, c)) {
			return true;
		}
		AIVehicle.SellVehicle(v);
		return false;
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AIVehicle.RefitVehicle(v, c);
		return cost.GetCosts();
	}

	function TryRefit(vehicle, cargoId) {
		v = vehicle;
		c = cargoId;
		return DoMoneyTest();
	}
}

class TestPerformTownAction extends MoneyTest {
	t = null;
	a = null;

	function DoAction() {
		if (AIExecMode() && AITown.PerformTownAction(t, a)) {
			return true;
		}
		return false;
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AITown.PerformTownAction(t, a);
		return cost.GetCosts();
	}

	function TryPerform(town, action) {
		t = town;
		a = action;
		return DoMoneyTest();
	}

	function TestCost(town, action) {
		t = town;
		a = action;
		return GetPrice();
	}
}

class TestBuildHQ extends MoneyTest {
	t = null;

	function DoAction() {
		if (AIExecMode() && AICompany.BuildCompanyHQ(t)) {
			return true;
		}
		return false;
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AICompany.BuildCompanyHQ(t);
		return cost.GetCosts();
	}

	function TryBuild(tile) {
		t = tile;
		return DoMoneyTest();
	}
}

class TestFoundTown extends MoneyTest {
	t = null;
	s = null;
	c = null;
	l = null;
	n = null;

	function DoAction() {
		if (AIExecMode() && AITown.FoundTown(t, s, c, l, n)) {
			return true;
		}
		return false;
	}

	function GetPrice() {
		local cost = AIAccounting();
		AITestMode() && AITown.FoundTown(t, s, c, l, n);
		return cost.GetCosts();
	}

	function TryFound(tile, size, city, layout, name) {
		t = tile;
		s = size;
		c = city;
		l = layout;
		n = name;
		return DoMoneyTest();
	}

	function TestCost(tile, size, city, layout, name) {
		t = tile;
		s = size;
		c = city;
		l = layout;
		n = name;
		return GetPrice();
	}
}