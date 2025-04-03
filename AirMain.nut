function LuDiAIAfterFix::BuildAirRoute(cityFrom, unfinished) {
	if (unfinished || (airRouteManager.GetAircraftCount() < max(MAX_AIR_VEHICLES - 10, 10)) && ((allRoutesBuilt >> 4) & 3) != 3) {

		local cityTo = null;
		local cC = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassAir : (!unfinished ? cargoClassAir : (cargoClassAir == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS));
		if (!unfinished) {
			cargoClassAir = AIController.GetSetting("select_town_cargo") != 2 ? cargoClassAir : (cC == AICargo.CC_PASSENGERS ? AICargo.CC_MAIL : AICargo.CC_PASSENGERS);

			local cargo = Utils.GetCargoID(cC);

			local tempList = AIEngineList(AIVehicle.VT_AIR);
			local engineList = AIList();
			for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
				if (AIEngine.IsValidEngine(engine) && AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo)) {
					engineList.AddItem(engine, AIEngine.GetPrice(engine));
				}
			}

			if (engineList.Count() == 0) {
				return;
			}

			engineList.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

//			local bestengineinfo = WrightAI.GetBestEngineIncome(engineList, cargo, AirBuildManager.DAYS_INTERVAL);
//			if (bestengineinfo[0] == null) {
//				return;
//			}

//			local fakedist = bestengineinfo[1];
//			local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");

//			local max_order_dist = WrightAI.GetMaximumOrderDistance(bestengineinfo[0]);
//			local max_dist = max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : max_order_dist;
//			local min_order_dist = (fakedist / 2) * (fakedist / 2);
//			local min_dist = min_order_dist > max_dist * 3 / 4 ? !infrastructure && max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : max_dist * 3 / 4 : min_order_dist;

			if (cityFrom == null) {
				cityFrom = airTownManager.GetUnusedCity(((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC);
				if (cityFrom == null) {
					if (AIController.GetSetting("pick_mode") == 1) {
						if (cC == AICargo.CC_PASSENGERS) {
							airTownManager.m_usedCitiesPassList.Clear();
						} else {
							airTownManager.m_usedCitiesMailList.Clear();
						}
					} else {
						if ((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
							bestRoutesBuilt = bestRoutesBuilt | (1 << (4 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
							if (cC == AICargo.CC_PASSENGERS) {
								airTownManager.m_usedCitiesPassList.Clear();
							} else {
								airTownManager.m_usedCitiesMailList.Clear();
							}
//							airTownManager.ClearCargoClassArray(cC);
							AILog.Warning("Best " + AICargo.GetCargoLabel(cargo) + " air routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
						} else {
//							airTownManager.ClearCargoClassArray(cC);
							if ((((allRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) {
								AILog.Warning("All " + AICargo.GetCargoLabel(cargo) + " air routes have been used!");
							}
							allRoutesBuilt = allRoutesBuilt | (1 << (4 + (cC == AICargo.CC_PASSENGERS ? 0 : 1)));
						}
					}
				}
			}

//			if (cityFrom != null) {
//				AILog.Info("New city found: " + AITown.GetName(cityFrom));

//				airTownManager.FindNearCities(cityFrom, min_dist, max_dist, ((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0), cC, fakedist);

//				if (!airTownManager.HasArrayCargoClassPairs(cC)) {
//					AILog.Info("No near city available");
//					cityFrom = null;
//				}
//			}

//			if (cityFrom != null) {
//				for (local i = 0; i < airTownManager.m_nearCityPairArray.len(); ++i) {
//					if (cityFrom == airTownManager.m_nearCityPairArray[i][0] && cC == airTownManager.m_nearCityPairArray[i][2]) {
//						if (!airRouteManager.TownRouteExists(cityFrom, airTownManager.m_nearCityPairArray[i][1], cC)) {
//							cityTo = airTownManager.m_nearCityPairArray[i][1];

//							if (AIController.GetSetting("pick_mode") != 1 && ((((allRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0) && airRouteManager.HasMaxStationCount(cityFrom, cityTo, cC)) {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + airRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
//								cityTo = null;
//								continue;
//							} else {
//								AILog.Info("airRouteManager.HasMaxStationCount(" + AITown.GetName(cityFrom) + ", " + AITown.GetName(cityTo) + ", " + cC + ") == " + airRouteManager.HasMaxStationCount(cityFrom, cityTo, cC));
//								break;
//							}
//						}
//					}
//				}

//				if (cityTo == null) {
//					cityFrom = null;
//				}
//			}

//			if (cityFrom == null && cityTo == null) {
//				reservedMoney -= reservedMoneyAir;
//				reservedMoneyAir = 0;
//			}
		} else {
			if (!Utils.HasMoney(reservedMoneyAir)) {
				return;
			}
		}

		if (unfinished || cityFrom != null/* && cityTo != null*/) {
			if (!unfinished) {
//					AILog.Info("New city found: " + AITown.GetName(cityFrom));
//					AILog.Info("New near city found: " + AITown.GetName(cityTo));
			}

			if (!unfinished) buildTimerAir = 0;
			local from = unfinished ? airBuildManager.m_cityFrom : cityFrom;
			local to = unfinished ? airBuildManager.m_cityTo : cityTo;
			local cargoC = unfinished ? airBuildManager.m_cargoClass : cC;
			local best_routes = unfinished ? airBuildManager.m_best_routes_built : ((((bestRoutesBuilt >> 4) & 3) & (1 << (cC == AICargo.CC_PASSENGERS ? 0 : 1))) != 0);
			local all_routes = (((allRoutesBuilt >> 4) & 3) & (1 << (cargoC == AICargo.CC_PASSENGERS ? 0 : 1))) == 0;

			local start_date = AIDate.GetCurrentDate();
			local routeResult = airRouteManager.BuildRoute(airRouteManager, airBuildManager, airTownManager, from, to, cargoC, best_routes, all_routes);
			buildTimerAir += AIDate.GetCurrentDate() - start_date;
			if (routeResult[0] != null) {
				if (routeResult[0] != 0) {
					reservedMoney -= reservedMoneyAir;
					reservedMoneyAir = 0;
					AILog.Warning("Built " + AICargo.GetCargoLabel(Utils.GetCargoID(cargoC)) + " air route between " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[1])) + " and " + AIBaseStation.GetName(AIStation.GetStationID(routeResult[2])) + " in " + buildTimerAir + " day" + (buildTimerAir != 1 ? "s" : "") + ".");
				}
			} else {
				reservedMoney -= reservedMoneyAir;
				reservedMoneyAir = 0;
				if (to != null) airTownManager.RemoveUsedCityPair(from, to, cC, false);
				AILog.Error("a:" + buildTimerAir + " day" + (buildTimerAir != 1 ? "s" : "") + " wasted!");
			}

//			cityFrom = cityTo; // use this line to look for a new town from the last town
			cityFrom = null;
		}
	}
}

function LuDiAIAfterFix::ResetAirManagementVariables() {
	if (lastAirManagedArray < 0) lastAirManagedArray = airRouteManager.m_townRouteArray.len() - 1;
	if (lastAirManagedManagement < 0) lastAirManagedManagement = 6;
}

function LuDiAIAfterFix::InterruptAirManagement(cur_date) {
	if (AIDate.GetCurrentDate() - cur_date > 1) {
		if (lastAirManagedArray == -1) lastAirManagedManagement--;
		return true;
	}
	return false;
}

function LuDiAIAfterFix::ManageAircraftRoutes() {
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
//		AILog.Info("Route " + i + " from " + AIBaseStation.GetName(AIStation.GetStationID(airRouteManager.m_townRouteArray[i].m_airportFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(airRouteManager.m_townRouteArray[i].m_airportTo)));
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
	local maxAllRoutesProfit = airRouteManager.HighestProfitLastYear();
	for (local i = lastAirManagedArray; i >= 0; --i) {
		if (lastAirManagedManagement != 4) break;
		lastAirManagedArray--;
//		AILog.Info("managing route " + i + ". SendLowProfitVehiclesToDepot");
		if (MAX_AIR_VEHICLES * 0.95 < num_vehs) {
			airRouteManager.m_townRouteArray[i].SendLowProfitVehiclesToDepot(maxAllRoutesProfit);
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
		local cityFrom = airRouteManager.m_townRouteArray[i].m_cityFrom;
		local cityTo = airRouteManager.m_townRouteArray[i].m_cityTo;
		local cargoC = airRouteManager.m_townRouteArray[i].m_cargoClass;
		if (airRouteManager.m_townRouteArray[i].RemoveIfUnserviced()) {
			airRouteManager.m_townRouteArray.remove(i);
			airTownManager.RemoveUsedCityPair(cityFrom, cityTo, cargoC, true);
		}
		if (InterruptAirManagement(cur_date)) return;
	}
	ResetAirManagementVariables();
	if (lastAirManagedManagement == 0) lastAirManagedManagement--;
//	local management_ticks = AIController.GetTick() - start_tick;
//	AILog.Info("Managed " + airRouteManager.m_townRouteArray.len() + " air route" + (airRouteManager.m_townRouteArray.len() != 1 ? "s" : "") + " in " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
}
