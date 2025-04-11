function LuDiAIAfterFix::BuildAirRoute(city_from, unfinished)
{
	if (unfinished || (airRouteManager.GetAircraftCount() < max(MAX_AIR_VEHICLES - 10, 10)) && ((allRoutesBuilt >> 4) & 3) != 3) {

		local city_to = null;
		local cargo_class = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassAir : (!unfinished ? cargoClassAir : (cargoClassAir == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
		if (!unfinished) {
			cargoClassAir = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassAir : (cargo_class == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

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
				city_from = airTownManager.GetUnusedCity(((((bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class);
				if (city_from == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						airTownManager.m_usedCitiesList[cargo_class].Clear();
					} else if ((((bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
						bestRoutesBuilt = bestRoutesBuilt | (1 << (4 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
						airTownManager.m_usedCitiesList[cargo_class].Clear();
//						airTownManager.m_nearCityPairArray[cargo_class].clear();
						AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " air routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
					} else {
//						airTownManager.m_nearCityPairArray[cargo_class].clear();
						if ((((allRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " air routes have been used!");
						}
						allRoutesBuilt = allRoutesBuilt | (1 << (4 + (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1)));
					}
				}
			}

//			if (city_from != null) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));

//				airTownManager.FindNearCities(city_from, min_dist, max_dist, ((((bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cargo_class, fake_dist);

//				if (!airTownManager.m_nearCityPairArray[cargo_class].len()) {
//					AILog.Info("No near city available");
//					city_from = null;
//				}
//			}

//			if (city_from != null) {
//				foreach (near_city_pair in airTownManager.m_nearCityPairArray[cargo_class]; ++i) {
//					if (city_from == near_city_pair[0]) {
//						if (!airRouteManager.TownRouteExists(city_from, near_city_pair[1], cargo_class)) {
//							city_to = near_city_pair[1];

//							if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && airRouteManager.HasMaxStationCount(city_from, city_to, cargo_class)) {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + airRouteManager.HasMaxStationCount(city_from, city_to, cargo_class));
//								city_to = null;
//								continue;
//							} else {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(city_from) + ", " + AITown.GetName(city_to) + ", " + cargo_class + ") == " + airRouteManager.HasMaxStationCount(city_from, city_to, cargo_class));
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
//				reservedMoney -= reservedMoneyAir;
//				reservedMoneyAir = 0;
//			}
//		} else {
//			if (!Utils.HasMoney(reservedMoneyAir)) {
//				return;
//			}
		}

		if (unfinished || city_from != null/* && city_to != null*/) {
//			if (!unfinished) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));
//				AILog.Info("New near city found: " + AITown.GetName(city_to));
//			}

			if (!unfinished) buildTimerAir = 0;
			local arg_city_from = unfinished ? airBuildManager.m_city_from : city_from;
			local arg_city_to = unfinished ? airBuildManager.m_city_to : city_to;
			local arg_cargo_class = unfinished ? airBuildManager.m_cargo_class : cargo_class;
			local best_routes = unfinished ? airBuildManager.m_best_routes_built : ((((bestRoutesBuilt >> 4) & 3) & (1 << (cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);
			local all_routes = (((allRoutesBuilt >> 4) & 3) & (1 << (arg_cargo_class == AICargo.CC_PASSENGERS ? 0 : 1))) == 0;

			local start_date = AIDate.GetCurrentDate();
			local route_result = airRouteManager.BuildRoute(airRouteManager, airBuildManager, airTownManager, arg_city_from, arg_city_to, arg_cargo_class, best_routes, all_routes);
			buildTimerAir += AIDate.GetCurrentDate() - start_date;
			if (route_result[0] != null) {
				if (route_result[0] != 0) {
					reservedMoney -= reservedMoneyAir;
					reservedMoneyAir = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoType(arg_cargo_class)) + " air route between " + AIBaseStation.GetName(AIStation.GetStationID(route_result[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(route_result[2])) + " in " + buildTimerAir + " day" + (buildTimerAir != 1 ? "s" : "") + ".");
				}
			} else {
				reservedMoney -= reservedMoneyAir;
				reservedMoneyAir = 0;
				if (arg_city_to != null) airTownManager.RemoveUsedCityPair(arg_city_from, arg_city_to, cargo_class, false);
				AILog.Error("a:" + buildTimerAir + " day" + (buildTimerAir != 1 ? "s" : "") + " wasted!");
			}

//			city_from = city_to; // use this line to look for a new town from the last town
			city_from = null;
		}
	}
}

function LuDiAIAfterFix::ResetAirManagementVariables()
{
	if (lastAirManagedArray < 0) lastAirManagedArray = airRouteManager.m_townRouteArray.len() - 1;
	if (lastAirManagedManagement < 0) lastAirManagedManagement = 6;
}

function LuDiAIAfterFix::InterruptAirManagement(cur_date)
{
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (lastAirManagedArray == -1) lastAirManagedManagement--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageAircraftRoutes()
{
	local max_aircraft = AIGameSettings.GetValue("max_aircraft");
	if (max_aircraft != MAX_AIR_VEHICLES) {
		MAX_AIR_VEHICLES = max_aircraft;
		AILog.Info("MAX_AIR_VEHICLES = " + MAX_AIR_VEHICLES);
	}

	local cur_date = AIDate.GetCurrentDate();
	ResetAirManagementVariables();

//	for (local i = lastAirManagedArray; i >= 0; --i) {
//		if (lastAirManagedManagement != 7) break;
//		lastAirManagedArray--;
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(airRouteManager.m_townRouteArray[i].m_airport_from)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(airRouteManager.m_townRouteArray[i].m_airport_to)));
//		if (InterruptAirManagement(cur_date)) return;
//	}
//	ResetAirManagementVariables();
//	if (lastAirManagedManagement == 7) lastAirManagedManagement--;
//
//	local start_tick = AIController.GetTick();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 6) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". RenewVehicles");
		airRouteManager.m_townRouteArray[i].RenewVehicles();
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 6) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 5) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". SendNegativeProfitVehiclesToDepot");
		airRouteManager.m_townRouteArray[i].SendNegativeProfitVehiclesToDepot();
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 5) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	local num_vehs = airRouteManager.GetAircraftCount();
	local max_all_routes_profit = airRouteManager.HighestProfitLastYear();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 4) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (MAX_AIR_VEHICLES * 0.95 < num_vehs) {
			airRouteManager.m_townRouteArray[i].SendLowProfitVehiclesToDepot(max_all_routes_profit);
		}
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 4) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 3) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". UpgradeEngine");
		airRouteManager.m_townRouteArray[i].UpgradeEngine();
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 3) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 2) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". SellVehiclesInDepot");
		airRouteManager.m_townRouteArray[i].SellVehiclesInDepot();
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 2) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	num_vehs = airRouteManager.GetAircraftCount();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 1) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". AddRemoveVehicleToRoute");
		if (num_vehs < MAX_AIR_VEHICLES) {
			num_vehs += airRouteManager.m_townRouteArray[i].AddRemoveVehicleToRoute(num_vehs < MAX_AIR_VEHICLES);
		}
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 1) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");

//	local start_tick = AIController.GetTick();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 0) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". RemoveIfUnserviced");
		local arg_city_from = airRouteManager.m_townRouteArray[i].m_city_from;
		local arg_city_to = airRouteManager.m_townRouteArray[i].m_city_to;
		local arg_cargo_class = airRouteManager.m_townRouteArray[i].m_cargo_class;
		if (airRouteManager.m_townRouteArray[i].RemoveIfUnserviced()) {
			airRouteManager.m_townRouteArray.remove(i);
			airTownManager.RemoveUsedCityPair(arg_city_from, arg_city_to, arg_cargo_class, true);
		}
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 0) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}
