function LuDiAIAfterFix::BuildAirRoute()
{
	if (!AIController.GetSetting("air_support")) return true; // assume true to keep rotating this.transport_mode_rotation

	local unfinished = this.air_build_manager.HasUnfinishedRoute();
	if (unfinished || (this.air_route_manager.GetAircraftCount() < max(AIGameSettings.GetValue("max_aircraft") - 10, 10)) && Utils.ListHasValue(this.air_route_manager.m_routes_built.all, false)) {
//		local city_from = null;
//		local city_to = null;
		local cargo_class = this.air_route_manager.m_cargo_class;
		if (!unfinished) {
			if (!this.air_route_manager.IsDateTimerRunning()) this.air_route_manager.StartDateTimer();
//			if (this.air_route_manager.m_reserved_money == 0) this.air_route_manager.SwapCargoClass();
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
				if (this.air_route_manager.m_reserved_money != 0) {
					this.air_route_manager.ResetMoneyReservation();
				}
				this.air_route_manager.SwapCargoClass();
				return true;
			}

//			engine_list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING); // sort price

//			local best_engine_id_info = Utils.GetBestEngineIncome(engine_list, cargo_type, AirBuildManager.DAYS_INTERVAL);
//			if (best_engine_id_info[0] == null) {
//				if (this.air_route_manager.m_reserved_money != 0) {
//					this.air_route_manager.ResetMoneyReservation();
//				}
//				this.air_route_manager.SwapCargoClass();
//				return true;
//			}

//			local fake_dist = best_engine_id_info[1];
//			local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");

//			local max_order_dist = Utils.GetMaximumOrderDistance(best_engine_id_info[0]);
//			local max_dist = max_order_dist > AIMap.GetMapSize() ? AIMap.GetMapSize() : max_order_dist;
//			local min_order_dist = (fake_dist / 2) * (fake_dist / 2);
//			local min_dist = min_order_dist > max_dist * 3 / 4 ? !infrastructure && max_dist * 3 / 4 > AIMap.GetMapSize() / 8 ? AIMap.GetMapSize() / 8 : max_dist * 3 / 4 : min_order_dist;

//			if (city_from == null) {
//				city_from = this.air_town_manager.GetUnusedCity(this.air_route_manager.m_routes_built.best[cargo_class], cargo_class);
//				if (city_from == null) {
//					if (AIController.GetSetting("pick_mode") == 1) {
//						this.air_town_manager.m_used_cities_list[cargo_class].Clear();
//					} else if (!this.air_route_manager.m_routes_built.best[cargo_class]) {
//						this.air_route_manager.m_routes_built.best[cargo_class] = true;
//						this.air_town_manager.m_used_cities_list[cargo_class].Clear();
///						this.air_town_manager.m_near_city_pair_array[cargo_class].clear();
//						AILog.Warning("Best " + AICargo.GetCargoLabel(cargo_type) + " air routes have been used! Year: " + AIDate.GetYear(AIDate.GetCurrentDate()));
//					} else {
///						this.air_town_manager.m_near_city_pair_array[cargo_class].clear();
//						if (!this.air_route_manager.m_routes_built.all[cargo_class]) {
//							AILog.Warning("All " + AICargo.GetCargoLabel(cargo_type) + " air routes have been used!");
//						}
//						this.air_route_manager.m_routes_built.all[cargo_class] = true;
//					}
//				}
//			}

//			if (city_from != null) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));

//				this.air_town_manager.FindNearCities(city_from, min_dist, max_dist, this.air_route_manager.m_routes_built.best[cargo_class], cargo_class, fake_dist);

//				if (!this.air_town_manager.m_near_city_pair_array[cargo_class].len()) {
//					AILog.Info("No near city available");
//					city_from = null;
//				}
//			}

//			if (city_from != null) {
//				foreach (near_city_pair in this.air_town_manager.m_near_city_pair_array[cargo_class]; ++i) {
//					if (city_from == near_city_pair[0]) {
//						if (!this.air_route_manager.TownRouteExists(city_from, near_city_pair[1], cargo_class)) {
//							city_to = near_city_pair[1];

//							if (AIController.GetSetting("pick_mode") != 1 && !this.air_route_manager.m_routes_built.all[cargo_class] && this.air_route_manager.HasMaxStationCount(city_from, city_to, cargo_class)) {
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
//				if (this.air_route_manager.m_reserved_money != 0) this.air_route_manager.ResetMoneyReservation();
//				this.air_route_manager.SwapCargoClass();
//			}
		} else {
			if (!Utils.HasMoney(this.air_route_manager.GetReservedMoney())) {
				if (this.air_route_manager.DaysElapsed() <= 60) {
					return 0;
				}
				if (!this.air_route_manager.IsMoneyReservationPaused()) {
					this.air_route_manager.PauseMoneyReservation();
				}
				return 2; // allow skipping to next transport mode
			}
		}

//		if (unfinished || city_from != null/* && city_to != null*/) {
//			if (!unfinished) {
//				AILog.Info("New city found: " + AITown.GetName(city_from));
//				AILog.Info("New near city found: " + AITown.GetName(city_to));
//			}

//			city_from = unfinished ? this.air_build_manager.m_city_from : city_from;
//			city_to = unfinished ? this.air_build_manager.m_city_to : city_to;
			cargo_class = unfinished ? this.air_build_manager.m_cargo_class : cargo_class;

			return this.air_route_manager.BuildRoute(this.air_route_manager, this.air_build_manager, this.air_town_manager, /*city_from, city_to, */cargo_class);
//		}
	}
	return true;
}
