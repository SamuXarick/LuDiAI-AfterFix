require("RoadvehBuildManager.nut");

class RoadRouteManager
{
	m_town_route_array = null;
	m_town_manager = null;
	m_sent_to_depot_group = null;
	m_cargo_class = null;
	m_last_route_index_managed = -1;
	m_last_management_managed = -1;
	m_reserved_money = 0;
	m_start_date = -1;
	m_routes_built = null;

	constructor(town_manager)
	{
		this.m_town_route_array = [];
		this.m_town_manager = town_manager;
		this.m_cargo_class = this.SwapCargoClass();
		this.m_start_date = AIDate.DATE_INVALID;
		this.m_routes_built = {};
		this.m_routes_built.rawset("best", {});
		this.m_routes_built.rawset("all", {});
		foreach (route_built in this.m_routes_built) {
			foreach (cargo_class in ::caches.m_cargo_classes) {
				route_built.rawset(cargo_class, false);
			}
		}
	}

	function IsDateTimerRunning()
	{
		return AIDate.IsValidDate(this.m_start_date);
	}

	function StartDateTimer()
	{
		assert(!AIDate.IsValidDate(this.m_start_date));
		this.m_start_date = AIDate.GetCurrentDate();
	}

	function StopDateTimer()
	{
		assert(AIDate.IsValidDate(this.m_start_date));
		this.m_start_date = AIDate.DATE_INVALID;
	}

	function DaysElapsed()
	{
		assert(AIDate.IsValidDate(this.m_start_date));
		return AIDate.GetCurrentDate() - this.m_start_date;
	}

	function IsMoneyReservationPaused()
	{
		assert(this.m_reserved_money != 0);
		return this.m_reserved_money < 0;
	}

	function PauseMoneyReservation()
	{
		assert(this.m_reserved_money > 0);
		::caches.m_reserved_money -= this.m_reserved_money;
		this.m_reserved_money *= -1;
	}

	function ResumeMoneyReservation()
	{
		assert(this.m_reserved_money < 0);
		this.m_reserved_money *= -1;
		::caches.m_reserved_money += this.m_reserved_money;
	}

	function GetNonPausedReservedMoney()
	{
		if (this.IsMoneyReservationPaused()) return 0;
		return this.m_reserved_money;
	}

	function GetReservedMoney()
	{
		assert(this.m_reserved_money != 0);
		return abs(this.m_reserved_money);
	}

	function SetMoneyReservation(money)
	{
		assert(this.m_reserved_money == 0);
		assert(money > 0);
		this.m_reserved_money = money;
		::caches.m_reserved_money += this.m_reserved_money;
	}

	function UpdateMoneyReservation(money)
	{
		assert(this.m_reserved_money != 0);
		assert(money > 0);
		local paused = this.IsMoneyReservationPaused();
		if (paused) this.ResumeMoneyReservation();
		::caches.m_reserved_money -= this.m_reserved_money;
		this.m_reserved_money = money;
		::caches.m_reserved_money += this.m_reserved_money;
		if (paused) this.PauseMoneyReservation();
	}

	function ResetMoneyReservation()
	{
		assert(this.m_reserved_money != 0);
		if (this.IsMoneyReservationPaused()) this.ResumeMoneyReservation();
		::caches.m_reserved_money -= this.m_reserved_money;
		this.m_reserved_money = 0;
	}

	function BuildRoute(road_build_manager, city_from, city_to, cargo_class, articulated)
	{
		if (this.m_sent_to_depot_group == null) {
			this.m_sent_to_depot_group = [];
			for (local i = 0; i <= 1; i++) {
				this.m_sent_to_depot_group.append(AIGroup.CreateGroup(AIVehicle.VT_ROAD, AIGroup.GROUP_INVALID));
				assert(AIGroup.IsValidGroup(this.m_sent_to_depot_group[i]));
			}
			assert(AIGroup.SetName(this.m_sent_to_depot_group[0], "0: Road vehicles to sell"));
			assert(AIGroup.SetName(this.m_sent_to_depot_group[1], "1: Road vehicles to renew"));
		}

		local route = road_build_manager.BuildRoadRoute(city_from, city_to, cargo_class, articulated, this.m_sent_to_depot_group, this.m_routes_built.best[cargo_class]);
		local elapsed = this.DaysElapsed();
		if (route != null) {
			if (typeof(route) == "instance") {
				this.m_town_route_array.append(route);
				road_build_manager.SetRouteFinished();
				this.ResetMoneyReservation();
				this.SwapCargoClass();
				AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + " road route between " + route.m_station_name_from + " and " + route.m_station_name_to  + " in " + elapsed + " day" + (elapsed != 1 ? "s" : "") + ".");
				this.StopDateTimer();
				return true;
			}
			assert(typeof(route) == "integer");
			if (elapsed <= 60) {
				return route;
			}
			if (!this.IsMoneyReservationPaused()) {
				this.PauseMoneyReservation();
			}
			return route | 2; // allow skipping to next transport mode
		} else {
			this.ResetMoneyReservation();
			this.SwapCargoClass();
			this.StopDateTimer();
			this.m_town_manager.ResetCityPair(city_from, city_to, cargo_class, false);
			AILog.Error("r:" + elapsed + " day" + (elapsed != 1 ? "s" : "") + " wasted!");
			return false;
		}
	}

	function GetRoadVehicleCount()
	{
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_ROAD);
	}

	function TownRouteExists(city_from, city_to, cargo_class)
	{
		foreach (route in this.m_town_route_array) {
			if (TownPair(city_from, city_to, cargo_class).IsEqual(route.m_city_from, route.m_city_to, route.m_cargo_class)) {
//				AILog.Info("TownRouteExists from " + AITown.GetName(city_from) + " to " + AITown.GetName(city_to));
				return true;
			}
		}

		return false;
	}

	/* the highest last years profit out of all vehicles */
	function HighestProfitLastYear()
	{
		local max_all_routes_profit = null;

		foreach (route in this.m_town_route_array) {
			local max_route_profit = 0;
			foreach (vehicle, _ in route.m_vehicle_list) {
				local profit = AIVehicle.GetProfitLastYear(vehicle);
				if (max_route_profit < profit) {
					max_route_profit = profit;
				}
			}

			if (max_all_routes_profit == null || max_route_profit > max_all_routes_profit) {
				max_all_routes_profit = max_route_profit;
			}
		}

		return max_all_routes_profit;
	}

	/* won't build any new stations if true */
	function HasMaxStationCount(city_from, city_to, cargo_class)
	{
//		return false;

		local max_town_station_from = (1 + AITown.GetPopulation(city_from) / 1000).tointeger();
		local max_town_station_to = (1 + AITown.GetPopulation(city_to) / 1000).tointeger();

		local city_from_count = 0;
		local city_to_count = 0;

		foreach (route in this.m_town_route_array) {
			if (route.m_city_from == city_from || route.m_city_from == city_to) {
				if (route.m_cargo_class == cargo_class) ++city_from_count;
			}

			if (route.m_city_to == city_to || route.m_city_to == city_from) {
				if (route.m_cargo_class == cargo_class) ++city_to_count;
			}
		}
//		AILog.Info("city_from = " + AITown.GetName(city_from) + " ; city_from_count = " + city_from_count + " ; max_town_station_from = " + max_town_station_from + " ; city_to = " + AITown.GetName(city_to) + " ; city_to_count = " + city_to_count + " ; max_town_station_to = " + max_town_station_to);

		return city_from_count >= max_town_station_from || city_to_count >= max_town_station_to;
	}

	function SwapCargoClass()
	{
		switch (AIController.GetSetting("select_town_cargo")) {
			case 0: { // Passengers
				this.m_cargo_class = AICargo.CC_PASSENGERS;
				return this.m_cargo_class;
			}
			case 1: { // Mail
				if (AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) {
					this.m_cargo_class = AICargo.CC_MAIL;
				} else {
					this.m_cargo_class = AICargo.CC_PASSENGERS;
				}
				return this.m_cargo_class;
			}
			case 2: { // Passengers and Mail
				if (this.m_cargo_class == AICargo.CC_PASSENGERS) {
					if (AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) {
						this.m_cargo_class = AICargo.CC_MAIL;
					} else {
						this.m_cargo_class = AICargo.CC_PASSENGERS;
					}
				} else if (this.m_cargo_class == AICargo.CC_MAIL) {
					this.m_cargo_class = AICargo.CC_PASSENGERS;
				} else if (this.m_cargo_class == null) {
					if (AIBase.Chance(1, 2)) {
						if (AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) {
							this.m_cargo_class = AICargo.CC_MAIL;
						} else {
							this.m_cargo_class = AICargo.CC_PASSENGERS;
						}
					} else {
						this.m_cargo_class = AICargo.CC_PASSENGERS;
					}
				}
				return this.m_cargo_class;
			}
		}
	}

	function ResetRoadManagementVariables()
	{
		if (this.m_last_route_index_managed < 0) this.m_last_route_index_managed = this.m_town_route_array.len() - 1;
		if (this.m_last_management_managed < 0) this.m_last_management_managed = 8;
	}

	function InterruptRoadManagement(cur_date)
	{
		if (AIDate.GetCurrentDate() - cur_date > 1) {
			if (this.m_last_route_index_managed == -1) this.m_last_management_managed--;
			return true;
		}
		return false;
	}

	function ManageRoadvehRoutes(road_town_manager)
	{
		local max_roadveh = AIGameSettings.GetValue("max_roadveh");

		local cur_date = AIDate.GetCurrentDate();
		this.ResetRoadManagementVariables();

//		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
//			if (this.m_last_management_managed != 9) break;
//			this.m_last_route_index_managed--;
//			AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(this.m_town_route_array[i].m_station_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.m_town_route_array[i].m_station_to)));
//			if (this.InterruptRoadManagement(cur_date)) return;
//		}
//		this.ResetRoadManagementVariables();
//		if (this.m_last_management_managed == 9) this.m_last_management_managed--;
//
//		local start_tick = AIController.GetTick();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 8) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". RenewVehicles");
			this.m_town_route_array[i].RenewVehicles();
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 8) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 7) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
			this.m_town_route_array[i].SendNegativeProfitVehiclesToDepot();
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 7) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		local num_vehs = this.GetRoadVehicleCount();
		local max_all_routes_profit = this.HighestProfitLastYear();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 6) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
			if (max_roadveh * 0.95 < num_vehs) {
				this.m_town_route_array[i].SendLowProfitVehiclesToDepot(max_all_routes_profit);
			}
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 6) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 5) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". UpgradeEngine");
			this.m_town_route_array[i].UpgradeEngine();
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 5) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 4) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". SellVehiclesInDepot");
			this.m_town_route_array[i].SellVehiclesInDepot();
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 4) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 3) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". UpgradeBridges")
			this.m_town_route_array[i].UpgradeBridges();
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 3) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = this.GetRoadVehicleCount();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 2) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
			if (num_vehs < max_roadveh) {
				num_vehs += this.m_town_route_array[i].AddRemoveVehicleToRoute(num_vehs < max_roadveh);
			}
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 2) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		num_vehs = this.GetRoadVehicleCount();
		if (AIController.GetSetting("station_spread") && AIGameSettings.GetValue("distant_join_stations")) {
			for (local i = this.m_last_route_index_managed; i >= 0; --i) {
				if (this.m_last_management_managed != 1) break;
				this.m_last_route_index_managed--;
//				AILog.Info("managing route " + i + ". ExpandRoadStation");
				if (max_roadveh > num_vehs) {
					this.m_town_route_array[i].ExpandRoadStation();
				}
				if (this.InterruptRoadManagement(cur_date)) return;
			}
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 1) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//		local start_tick = AIController.GetTick();
		for (local i = this.m_last_route_index_managed; i >= 0; --i) {
			if (this.m_last_management_managed != 0) break;
			this.m_last_route_index_managed--;
//			AILog.Info("managing route " + i + ". RemoveIfUnserviced");
			local city_from = this.m_town_route_array[i].m_city_from;
			local city_to = this.m_town_route_array[i].m_city_to;
			local cargo_class = this.m_town_route_array[i].m_cargo_class;
			if (this.m_town_route_array[i].RemoveIfUnserviced()) {
				this.m_town_route_array.remove(i);
				road_town_manager.ResetCityPair(city_from, city_to, cargo_class, true);
			}
			if (this.InterruptRoadManagement(cur_date)) return;
		}
		this.ResetRoadManagementVariables();
		if (this.m_last_management_managed == 0) this.m_last_management_managed--;
//		local management_ticks = AIController.GetTick() - start_tick;
//		AILog.Info("Managed " + this.m_town_route_array.len() + " road route" + (this.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
	}


	function SaveRouteManager()
	{
		local town_route_array = [];
		foreach (route in this.m_town_route_array) {
			town_route_array.append(route.SaveRoute());
		}

		return [town_route_array, this.m_sent_to_depot_group, this.m_cargo_class, this.m_last_route_index_managed, this.m_last_management_managed, this.m_reserved_money, this.m_start_date, this.m_routes_built];
	}

	function LoadRouteManager(data)
	{
		local town_route_array = data[0];

		local num_bridges = 0;
		foreach (loaded_route in town_route_array) {
			local route = RoadRoute.LoadRoute(loaded_route);
			this.m_town_route_array.append(route[0]);
			num_bridges += route[1];
		}
		AILog.Info("Loaded " + this.m_town_route_array.len() + " road routes with " + num_bridges + " bridges.");

		this.m_sent_to_depot_group = data[1];
		this.m_cargo_class = data[2];
		this.m_last_route_index_managed = data[3];
		this.m_last_management_managed = data[4];
		this.m_reserved_money = data[5];
		this.m_start_date = data[6];
		this.m_routes_built = data[7];
	}
};
