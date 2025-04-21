function LuDiAIAfterFix::BuildAirRoute()
{
	if (!AIController.GetSetting("air_support")) return;

	local unfinished = this.air_build_manager.HasUnfinishedRoute();
	if (unfinished || (this.air_route_manager.GetAircraftCount() < max(AIGameSettings.GetValue("max_aircraft") - 10, 10)) && ((this.allRoutesBuilt >> 4) & 3) != 3) {
		local city_from = null;
		local city_to = null;
		local cargo_class = this.air_route_manager.m_cargo_class;
		if (!unfinished) {
			this.air_route_manager.SwapCargoClass();

			local cargo_type = Utils.GetCargoType(cargo_class);

			local engine_list = AIEngineList(AIVehicle.VT_AIR);
			foreach (engine_id, _ in engine_list) {
				if (!AIEngine.IsValidEngine(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.IsBuildable(engine_id)) {
					engine_list[engine_id] = null;
					continue;
				}
				if (!AIEngine.CanRefitCargo(engine_id, cargo_type)) {
					engine_list[engine_id] = null;
					continue;
				}
				engine_list[engine_id] = AIEngine.GetPrice(engine_id);
			}

			if (engine_list.IsEmpty()) {
				return;
			}

//			engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

//			local best_engine_id_info = WrightAI().GetBestEngineIncome(engine_list, cargo_type, AirBuildManager.DAYS_INTERVAL);
//			if (best_engine_id_info[0] == null) {
//				return;
//			}

//			local fake_dist = best_engine_id_info[1];
//			local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");

//			local max_order_dist = WrightAI.GetMaximumOrderDistance(best_engine_id_info[0]);
//			local max_dist = max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : max_order_dist;
//			local min_order_dist = (fake_dist / 2) * (fake_dist / 2);
//			local min_dist = min_order_dist > max_dist * 3 / 4 ? !infrastructure && max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : max_dist * 3 / 4 : min_order_dist;

			if (city_from == null) {
				city_from = this.airTownManager.GetUnusedCity(((((this.bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						this.airTownManager.m_used_cities_list[cargo_class].Clear();
					} else if ((((this.bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
						this.bestRoutesBuilt = this.bestRoutesBuilt | (1 << (4 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
						this.airTownManager.m_used_cities_list[cargo_class].Clear();
//						this.airTownManager.m_near_city_pair_array[cargo_class].clear();
						AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " air routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
					} else {
//						this.airTownManager.m_near_city_pair_array[cargo_class].clear();
						if ((((this.allRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " air routes have been used!");
						}
						this.allRoutesBuilt = this.allRoutesBuilt | (1 << (4 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
					}
				}
			}

//			if (city_from != null) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));

//				this.airTownManager.FindNearCities(city_from, min_dist, max_dist, ((((this.bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class, fake_dist);

//				if (!this.airTownManager.m_near_city_pair_array[cargo_class].len()) {
//					AILog.Info("No near city available");
//					city_from = null;
//				}
//			}

//			if (city_from != null) {
//				foreach (near_city_pair in this.airTownManager.m_near_city_pair_array[cargo_class]; ++i) {
//					if (city_from == near_city_pair[0]) {
//						if (!this.air_route_manager.TownRouteExists(city_from, near_city_pair[1], cargo_class)) {
//							city_to = near_city_pair[1];

//							if (AIController.GetSetting("pick_mode") != 1 && ((((this.allRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && this.air_route_manager.HasMaxStationCount(city_from, city_to, cargo_class)) {
//								AILog.Info("this.air_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.air_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
//								city_to = null;
//								continue;
//							} else {
//								AILog.Info("this.air_route_manager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + this.air_route_manager.HasMaxStationCount(city_from, city_to, cargo_class));
//								break;
//							}
//						}
//					}
//				}

//				if (city_to == null) {
//					city_from = null;
//				}
//			}

//			if (city_from == null && city_to == null) {
//				this.reservedMoney -= this.reservedMoneyAir;
//				this.reservedMoneyAir = 0;
//			}
//		} else {
//			if (!Utils.HasMoney(this.reservedMoneyAir)) {
//				return;
//			}
		}

		if (unfinished || city_from != null/* && city_to != null*/) {
//			if (!unfinished) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));
//				AILog.Info("New near city found: " + AITown.GetName(city_to));
//			}

			if (!unfinished) this.buildTimerAir = 0;
			city_from = unfinished ? this.air_build_manager.m_city_from : city_from;
			city_to = unfinished ? this.air_build_manager.m_city_to : city_to;
			cargo_class = unfinished ? this.air_build_manager.m_cargo_class : cargo_class;
			local best_routes_built = unfinished ? this.air_build_manager.m_best_routes_built : ((((this.bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);
			local all_routes_built = (((this.allRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0;

			local start_date = AIDate.GetCurrentDate();
			local route_result = this.air_route_manager.BuildRoute(this.air_route_manager, this.air_build_manager, this.airTownManager, city_from, city_to, cargo_class, best_routes_built, all_routes_built);
			this.buildTimerAir += AIDate.GetCurrentDate() - start_date;
			if (route_result[0] != null) {
				if (route_result[0] != 0) {
					this.reservedMoney -= this.reservedMoneyAir;
					this.reservedMoneyAir = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + " air route between " + AIBaseStation.GetName(AIStation.GetStationID(route_result[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(route_result[2])) + " in " + this.buildTimerAir + " day" + (this.buildTimerAir != 1 ? "s" : "") + ".");
				}
			} else {
				this.reservedMoney -= this.reservedMoneyAir;
				this.reservedMoneyAir = 0;
				if (city_to != null) this.airTownManager.ResetCityPair(city_from, city_to, cargo_class, false);
				AILog.Error("a:" + this.buildTimerAir + " day" + (this.buildTimerAir != 1 ? "s" : "") + " wasted!");
			}
		}
	}
}

function LuDiAIAfterFix::ResetAirManagementVariables()
{
	if (this.lastAirManagedArray < 0) this.lastAirManagedArray = this.air_route_manager.m_town_route_array.len() - 1;
	if (this.lastAirManagedManagement < 0) this.lastAirManagedManagement = 6;
}

function LuDiAIAfterFix::InterruptAirManagement(cur_date)
{
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (this.lastAirManagedArray == -1) this.lastAirManagedManagement--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageAircraftRoutes()
{
	local max_aircraft = AIGameSettings.GetValue("max_aircraft");

	local cur_date = AIDate.GetCurrentDate();
	this.ResetAirManagementVariables();

//	for (local i = this.lastAirManagedArray; i >= 0; --i) {
//		if (this.lastAirManagedManagement != 7) break;
//		this.lastAirManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(this.air_route_manager.m_town_route_array[i].m_airport_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(this.air_route_manager.m_town_route_array[i].m_airport_to)));
//		if (this.InterruptAirManagement(cur_date)) return;
//	}
//	this.ResetAirManagementVariables();
//	if (this.lastAirManagedManagement == 7) this.lastAirManagedManagement--;
//
//	local start_tick = AIController.GetTick();
	for (local i = this.lastAirManagedArray; i >= 0; --i) {
		if (this.lastAirManagedManagement != 6) break;
		this.lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		this.air_route_manager.m_town_route_array[i].RenewVehicles();
		if (this.InterruptAirManagement(cur_date)) return;
	}
	this.ResetAirManagementVariables();
	if (this.lastAirManagedManagement == 6) this.lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.air_route_manager.m_town_route_array.len() + " air route" + (this.air_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastAirManagedArray; i >= 0; --i) {
		if (this.lastAirManagedManagement != 5) break;
		this.lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		this.air_route_manager.m_town_route_array[i].SendNegativeProfitVehiclesToDepot();
		if (this.InterruptAirManagement(cur_date)) return;
	}
	this.ResetAirManagementVariables();
	if (this.lastAirManagedManagement == 5) this.lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.air_route_manager.m_town_route_array.len() + " air route" + (this.air_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = this.air_route_manager.GetAircraftCount();
	local max_all_routes_profit = this.air_route_manager.HighestProfitLastYear();
	for (local i = this.lastAirManagedArray; i >= 0; --i) {
		if (this.lastAirManagedManagement != 4) break;
		this.lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (max_aircraft * 0.95 < num_vehs) {
			this.air_route_manager.m_town_route_array[i].SendLowProfitVehiclesToDepot(max_all_routes_profit);
		}
		if (this.InterruptAirManagement(cur_date)) return;
	}
	this.ResetAirManagementVariables();
	if (this.lastAirManagedManagement == 4) this.lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.air_route_manager.m_town_route_array.len() + " air route" + (this.air_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastAirManagedArray; i >= 0; --i) {
		if (this.lastAirManagedManagement != 3) break;
		this.lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeEngine");
		this.air_route_manager.m_town_route_array[i].UpgradeEngine();
		if (this.InterruptAirManagement(cur_date)) return;
	}
	this.ResetAirManagementVariables();
	if (this.lastAirManagedManagement == 3) this.lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.air_route_manager.m_town_route_array.len() + " air route" + (this.air_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastAirManagedArray; i >= 0; --i) {
		if (this.lastAirManagedManagement != 2) break;
		this.lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		this.air_route_manager.m_town_route_array[i].SellVehiclesInDepot();
		if (this.InterruptAirManagement(cur_date)) return;
	}
	this.ResetAirManagementVariables();
	if (this.lastAirManagedManagement == 2) this.lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.air_route_manager.m_town_route_array.len() + " air route" + (this.air_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = this.air_route_manager.GetAircraftCount();
	for (local i = this.lastAirManagedArray; i >= 0; --i) {
		if (this.lastAirManagedManagement != 1) break;
		this.lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < max_aircraft) {
			num_vehs += this.air_route_manager.m_town_route_array[i].AddRemoveVehicleToRoute(num_vehs < max_aircraft);
		}
		if (this.InterruptAirManagement(cur_date)) return;
	}
	this.ResetAirManagementVariables();
	if (this.lastAirManagedManagement == 1) this.lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.air_route_manager.m_town_route_array.len() + " air route" + (this.air_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = this.lastAirManagedArray; i >= 0; --i) {
		if (this.lastAirManagedManagement != 0) break;
		this.lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local city_from = this.air_route_manager.m_town_route_array[i].m_city_from;
		local city_to = this.air_route_manager.m_town_route_array[i].m_city_to;
		local cargo_class = this.air_route_manager.m_town_route_array[i].m_cargo_class;
		if (this.air_route_manager.m_town_route_array[i].RemoveIfUnserviced()) {
			this.air_route_manager.m_town_route_array.remove(i);
			this.airTownManager.ResetCityPair(city_from, city_to, cargo_class, true);
		}
		if (this.InterruptAirManagement(cur_date)) return;
	}
	this.ResetAirManagementVariables();
	if (this.lastAirManagedManagement == 0) this.lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + this.air_route_manager.m_town_route_array.len() + " air route" + (this.air_route_manager.m_town_route_array.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}
