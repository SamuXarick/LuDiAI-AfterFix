require("AirRouteManager.nut");

class AirRoute extends AirRouteManager
{
	/* These are saved */
	m_city_from = null;
	m_city_to = null;
	m_airport_from = null;
	m_airport_to = null;
	m_cargo_class = null;
	m_group = null;
	m_last_vehicle_added = null;
	m_last_vehicle_removed = null;
	m_renew_vehicles = null;
	m_sent_to_depot_air_group = null;
	m_active_route = null;

	/* These are unsaved */
	m_engine = null;
	m_vehicle_list = null;
	m_station_id_from = null;
	m_station_id_to = null;
	m_station_name_from = null;
	m_station_name_to = null;
	m_cargo_type = null;
	m_squared_dist = null;
	m_fake_dist = null;
	m_airport_type_from = null;
	m_airport_type_to = null;

	constructor(city_from, city_to, airport_from, airport_to, cargo_class, sent_to_depot_air_group, is_loaded = false)
	{
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_airport_from = airport_from;
		this.m_airport_to = airport_to;
		this.m_cargo_class = cargo_class;
		this.m_sent_to_depot_air_group = sent_to_depot_air_group;

		this.m_group = AIGroup.GROUP_INVALID;
		this.m_last_vehicle_added = 0;
		this.m_last_vehicle_removed = AIDate.GetCurrentDate();
		this.m_renew_vehicles = true;
		this.m_active_route = true;

		this.m_vehicle_list = AIList();
		this.m_station_id_from = AIStation.GetStationID(airport_from);
		this.m_station_id_to = AIStation.GetStationID(airport_to);
		this.m_station_name_from = AIBaseStation.GetName(this.m_station_id_from);
		this.m_station_name_to = AIBaseStation.GetName(this.m_station_id_to);
		this.m_cargo_type = Utils.GetCargoType(cargo_class);
		this.m_squared_dist = AIMap.DistanceSquare(airport_from, airport_to);
		this.m_fake_dist = Utils.DistanceRealFake(airport_from, airport_to);
		this.m_airport_type_from = AIAirport.GetAirportType(airport_from);
		this.m_airport_type_to = AIAirport.GetAirportType(airport_to);

		/* This requires the values above to be initialized */
		this.m_engine = this.GetAircraftEngine();

		if (!is_loaded) {
			this.AddVehiclesToNewRoute();
		}
	}

	function ValidateVehicleList()
	{
		foreach (v, _ in this.m_vehicle_list) {
			if (!AIVehicle.IsValidVehicle(v)) {
				this.m_vehicle_list[v] = null;
				continue;
			}
			if (AIVehicle.GetVehicleType(v) != AIVehicle.VT_AIR) {
				AILog.Error("a:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			local num_orders = AIOrder.GetOrderCount(v);
			if (num_orders != 2) {
				AILog.Error("a:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			local order_from = false;
			local order_to = false;
			for (local o = 0; o < num_orders; o++) {
				if (!AIOrder.IsValidVehicleOrder(v, o)) {
					continue;
				}
				local station_id = AIStation.GetStationID(AIOrder.GetOrderDestination(v, o));
				if (station_id == this.m_station_id_from) {
					order_from = true;
				}
				if (station_id == this.m_station_id_to) {
					order_to = true;
				}
			}
			if (!order_from || !order_to) {
				AILog.Error("a:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
		}
	}

	function SentToDepotList(i)
	{
		local sent_to_depot_list = AIList();
		this.ValidateVehicleList();
		foreach (vehicle, status in this.m_vehicle_list) {
			if (status == i) {
				sent_to_depot_list[vehicle] = i;
			}
		}
		return sent_to_depot_list;
	}

	function GetAircraftEngine()
	{
		local small_aircraft = this.m_airport_type_from == AIAirport.AT_SMALL || this.m_airport_type_to == AIAirport.AT_SMALL ||
			this.m_airport_type_from == AIAirport.AT_COMMUTER || this.m_airport_type_to == AIAirport.AT_COMMUTER;

		local helicopter = this.m_airport_type_from == AIAirport.AT_HELIPORT || this.m_airport_type_to == AIAirport.AT_HELIPORT ||
			this.m_airport_type_from == AIAirport.AT_HELIDEPOT || this.m_airport_type_to == AIAirport.AT_HELIDEPOT ||
			this.m_airport_type_from == AIAirport.AT_HELISTATION || this.m_airport_type_to == AIAirport.AT_HELISTATION;

		local hangar = helicopter ? this.m_airport_type_from == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(this.m_airport_to) : AIAirport.GetHangarOfAirport(this.m_airport_from) : AIAirport.GetHangarOfAirport(this.m_airport_from);

		local engine_list = AIEngineList(AIVehicle.VT_AIR);
		foreach (engine_id, _ in engine_list) {
			if (AIEngine.IsValidEngine(engine_id) && AIEngine.IsBuildable(engine_id) && AIEngine.CanRefitCargo(engine_id, this.m_cargo_type)) {
				if (small_aircraft && AIEngine.GetPlaneType(engine_id) == AIAirport.PT_BIG_PLANE) {
					engine_list[engine_id] = null;
					continue;
				}
				if (helicopter && AIEngine.GetPlaneType(engine_id) != AIAirport.PT_HELICOPTER) {
					engine_list[engine_id] = null;
					continue;
				}
				if (Utils.GetMaximumOrderDistance(engine_id) < this.m_squared_dist) {
					engine_list[engine_id] = null;
					continue;
				}
				local primary_capacity = ::caches.GetBuildWithRefitCapacity(hangar, engine_id, this.m_cargo_type);
				local secondary_cargo = Utils.GetCargoType(AICargo.CC_MAIL);
				local is_valid_secondary_cargo = AICargo.IsValidCargo(secondary_cargo);
				local secondary_capacity = (AIController.GetSetting("select_town_cargo") == 2 && is_valid_secondary_cargo) ? ::caches.GetBuildWithRefitSecondaryCapacity(hangar, engine_id) : 0;
				local days_in_transit = (this.m_fake_dist * 256 * 16) / (2 * 74 * AIEngine.GetMaxSpeed(engine_id));
				local multiplier = Utils.GetEngineReliabilityMultiplier(engine_id);
				local income_primary = primary_capacity * AICargo.GetCargoIncome(this.m_cargo_type, this.m_fake_dist, days_in_transit);
				local income_secondary = is_valid_secondary_cargo ? secondary_capacity * AICargo.GetCargoIncome(secondary_cargo, this.m_fake_dist, days_in_transit) : 0;
				local running_cost = AIEngine.GetRunningCost(engine_id);
				local engine_income = (income_primary + income_secondary - running_cost * days_in_transit / 365) * multiplier;
//				AILog.Info("engine_id = " + AIEngine.GetName(engine_id) + "; engine_income = " + engine_income);
				if (engine_income <= 0) {
					engine_list[engine_id] = null;
					continue;
				}
				engine_list[engine_id] = engine_income;
			}
		}
		if (engine_list.IsEmpty()) {
			return this.m_engine == null ? -1 : this.m_engine;
		}
		return engine_list.Begin();
	}

	function UpgradeEngine()
	{
		if (!this.m_active_route || !this.m_renew_vehicles) return;

		this.m_engine = this.GetAircraftEngine();
	}

	function DeleteSellVehicle(vehicle)
	{
		this.m_vehicle_list[vehicle] = null;
		assert(AIVehicle.SellVehicle(vehicle));
		Utils.RepayLoan();
	}

	function AddVehicle(return_vehicle = false, skip_order = false)
	{
		this.ValidateVehicleList();
		if (this.m_vehicle_list.Count() >= this.OptimalVehicleCount()) {
			return null;
		}

		if (!this.m_renew_vehicles) {
			return null;
		}

		/* Clone vehicle, share orders */
		local clone_vehicle_id = AIVehicle.VEHICLE_INVALID;
		local share_orders_vid = AIVehicle.VEHICLE_INVALID;
		foreach (vehicle_id, _ in this.m_vehicle_list) {
			if (this.m_engine != null && AIEngine.IsValidEngine(this.m_engine) && AIEngine.IsBuildable(this.m_engine)) {
				if (AIVehicle.GetEngineType(vehicle_id) == this.m_engine) {
					clone_vehicle_id = vehicle_id;
				}
			}
			if (AIVehicle.GetGroupID(vehicle_id) == this.m_group && AIGroup.IsValidGroup(this.m_group)) {
				share_orders_vid = vehicle_id;
			}
		}

		local hangar1 = this.m_airport_type_from == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(this.m_airport_to) : AIAirport.GetHangarOfAirport(this.m_airport_from);
		local hangar2 = this.m_airport_type_to == AIAirport.AT_HELIPORT ? AIAirport.GetHangarOfAirport(this.m_airport_from) : AIAirport.GetHangarOfAirport(this.m_airport_to);
		local best_hangar = skip_order == true ? hangar2 : hangar1;

		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			new_vehicle = TestBuildVehicleWithRefit().TryBuild(best_hangar, this.m_engine, this.m_cargo_type);
		} else {
			local is_same_vehicle = AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id;
			new_vehicle = TestCloneVehicle().TryClone(best_hangar, clone_vehicle_id, is_same_vehicle);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			this.m_vehicle_list[new_vehicle] = 2;
			local vehicle_ready_to_start = false;
			local order_1 = AIAirport.IsHangarTile(this.m_airport_from) ? AIMap.GetTileIndex(AIMap.GetTileX(this.m_airport_from), AIMap.GetTileY(this.m_airport_from) + 1) : this.m_airport_from;
			local order_2 = AIAirport.IsHangarTile(this.m_airport_to) ? AIMap.GetTileIndex(AIMap.GetTileX(this.m_airport_to), AIMap.GetTileY(this.m_airport_to) + 1) : this.m_airport_to;
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					local load_mode = AIController.GetSetting("air_load_mode");
					if (AIOrder.AppendOrder(new_vehicle, order_1, (load_mode == 0 ? AIOrder.OF_FULL_LOAD_ANY : AIOrder.OF_NONE)) &&
							AIOrder.AppendOrder(new_vehicle, order_2, (load_mode == 0 ? AIOrder.OF_FULL_LOAD_ANY : AIOrder.OF_NONE))) {
						vehicle_ready_to_start = true;
					} else {
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						vehicle_ready_to_start = true;
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				}
			} else {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					vehicle_ready_to_start = true;
				} else {
					if (clone_vehicle_id != share_orders_vid) {
						if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
							AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
							this.DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					vehicle_ready_to_start = true;
				}
			}
			if (vehicle_ready_to_start) {
				if (AIMap.DistanceSquare(best_hangar, this.m_airport_from) > AIMap.DistanceSquare(best_hangar, this.m_airport_to)) {
					AIOrder.SkipToOrder(new_vehicle, 1);
				}
				AIVehicle.StartStopVehicle(new_vehicle);
//				AILog.Info("new_vehicle = " + AIVehicle.GetName(new_vehicle) + "; clone_vehicle_id = " + AIVehicle.GetName(clone_vehicle_id) + "; share_orders_vid = " + AIVehicle.GetName(share_orders_vid));

				this.m_last_vehicle_added = AIDate.GetCurrentDate();

				if (AIGroup.IsValidGroup(this.m_group) && AIVehicle.GetGroupID(new_vehicle) != this.m_group) {
					AIGroup.MoveVehicle(this.m_group, new_vehicle);
				}
				if (return_vehicle) {
					return new_vehicle;
				} else {
					return 1;
				}
			}
		} else {
			return null;
		}
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

	function OptimalVehicleCount()
	{
		local count_interval = (AIEngine.GetMaxSpeed(this.m_engine) * 2 * 74 * AirBuildManager.DAYS_INTERVAL / 256) / 16;
		local aircraft_type = AIEngine.GetPlaneType(this.m_engine);
		local num_terminals = this.GetNumTerminals(aircraft_type, this.m_airport_type_from) + this.GetNumTerminals(aircraft_type, this.m_airport_type_to);
		return (count_interval > 0 ? (this.m_fake_dist / count_interval) : 0) + num_terminals;
	}

	function AddVehiclesToNewRoute()
	{
		this.GroupVehicles();
		local optimal_vehicle_count = this.OptimalVehicleCount();

		this.ValidateVehicleList();
		local num_vehicles = this.m_vehicle_list.Count();
		local num_vehicles_before = num_vehicles;
		if (num_vehicles >= optimal_vehicle_count) {
			if (this.m_last_vehicle_added < 0) this.m_last_vehicle_added *= -1;
			return 0;
		}

		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		local buy_vehicle_count = max(0, (infrastructure ? 8 : 2) - num_vehicles);

		if (buy_vehicle_count > optimal_vehicle_count - num_vehicles) {
			buy_vehicle_count = optimal_vehicle_count - num_vehicles;
		}

		for (local i = 0; i < buy_vehicle_count; ++i) {
			local old_last_vehicle_added = -this.m_last_vehicle_added;
			if (!infrastructure && (old_last_vehicle_added > 0 && AIDate.GetCurrentDate() - old_last_vehicle_added <= 3)) {
				break;
			}
			this.m_last_vehicle_added = 0;
			local added_vehicle = this.AddVehicle(true, (num_vehicles % 2) == 1);
			if (added_vehicle != null) {
				num_vehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + (num_vehicles % 2 == 1 ? this.m_station_name_to : this.m_station_name_from) + " to " + (num_vehicles % 2 == 1 ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + "/" + optimal_vehicle_count + " aircraft, " + this.m_fake_dist + " realfake tiles)");
				if (buy_vehicle_count > 1) {
					this.m_last_vehicle_added *= -1;
					if (!infrastructure) break;
				}
			} else {
				break;
			}
		}
		if (num_vehicles < optimal_vehicle_count && buy_vehicle_count > 1 && this.m_last_vehicle_added >= 0) {
			this.m_last_vehicle_added = 0;
		}
		return num_vehicles - num_vehicles_before;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_air_group[0] && AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_air_group[1] && AIVehicle.GetState(vehicle_id) != AIVehicle.VS_CRASHED) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			local airport1_hangars = AIAirport.GetNumHangars(this.m_airport_from) != 0;
			local airport2_hangars = AIAirport.GetNumHangars(this.m_airport_to) != 0;
			if (!(airport1_hangars && airport2_hangars)) {
				if (airport1_hangars) {
					AIOrder.SkipToOrder(vehicle_id, 0);
				} else {
					AIOrder.SkipToOrder(vehicle_id, 1);
				}
			}
			if (!AIVehicle.IsStoppedInDepot(vehicle_id) && !AIVehicle.SendVehicleToDepot(vehicle_id)) {
				AILog.Info("Failed to send " + vehicle_name + " to depot. Will try again later.");
				return false;
			}
			this.m_last_vehicle_removed = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + this.m_station_name_from + " to " + this.m_station_name_to + " has been sent to its depot!");

			return true;
		}

		return false;
	}

	function SendNegativeProfitVehiclesToDepot()
	{
		if (this.m_last_vehicle_added <= 0 || AIDate.GetCurrentDate() - this.m_last_vehicle_added <= 30) return;
//		AILog.Info("this.SendNegativeProfitVehiclesToDepot . this.m_last_vehicle_added = " + this.m_last_vehicle_added + "; " + AIDate.GetCurrentDate() + " - " + this.m_last_vehicle_added + " = " + (AIDate.GetCurrentDate() - this.m_last_vehicle_added) + " < 45" + " - " + this.m_station_name_from + " to " + this.m_station_name_to);

//		if (AIDate.GetCurrentDate() - this.m_last_vehicle_removed <= 30) return;

		this.ValidateVehicleList();

		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (SendMoveVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_air_group[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_air_group[0]);
					} else {
						this.m_vehicle_list[vehicle] = 0;
					}
					return;
				}
			}
		}
	}

	function SendLowProfitVehiclesToDepot(max_all_routes_profit)
	{
		this.ValidateVehicleList();
		local vehicle_list = AIList();
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730) {
				vehicle_list[vehicle] = 0;
			}
		}
		if (vehicle_list.IsEmpty()) return;

		local cargo_waiting_from_via_to = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_from, this.m_station_id_to, this.m_cargo_type);
		local cargo_waiting_from_any = AIStation.GetCargoWaitingVia(this.m_station_id_from, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_from = cargo_waiting_from_via_to + cargo_waiting_from_any;
		local cargo_waiting_to_via_from = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_to, this.m_station_id_from, this.m_cargo_type);
		local cargo_waiting_to_any = AIStation.GetCargoWaitingVia(this.m_station_id_to, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_to = cargo_waiting_to_via_from + cargo_waiting_to_any;

//		AILog.Info("cargoWaiting = " + (cargo_waiting_from + cargo_waiting_to));
		if (cargo_waiting_from + cargo_waiting_to < 150) {
			foreach (vehicle, _ in vehicle_list) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (max_all_routes_profit / 6)) {
					if (this.SendMoveVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(this.m_sent_to_depot_air_group[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_air_group[0]);
						} else {
							this.m_vehicle_list[vehicle] = 0;
						}
					}
				}
			}
		}
	}

	function SellVehiclesInDepot()
	{
		local sent_to_depot_list = this.SentToDepotList(0);

		foreach (vehicle, _ in sent_to_depot_list) {
			if (this.m_vehicle_list.HasItem(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				this.DeleteSellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + this.m_station_name_from + " to " + this.m_station_name_to + " has been sold!");
			}
		}

		sent_to_depot_list = this.SentToDepotList(1);

		foreach (vehicle, _ in sent_to_depot_list) {
			if (this.m_vehicle_list.HasItem(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_to_order = AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT);
				this.DeleteSellVehicle(vehicle);

				local renewed_vehicle = this.AddVehicle(true, skip_to_order);
				if (renewed_vehicle != null) {
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + (skip_to_order < 1 ? this.m_station_name_from : this.m_station_name_to) + " to " + (skip_to_order < 1 ? this.m_station_name_to : this.m_station_name_from) + " has been renewed!");
				}
			}
		}
	}

	function AddRemoveVehicleToRoute(maxed_out_num_vehs)
	{
		if (!this.m_active_route) {
			return 0;
		}

		if (this.m_last_vehicle_added <= 0) {
			return this.AddVehiclesToNewRoute();
		}

		if (!this.m_renew_vehicles) {
			return 0;
		}

		if (AIDate.GetCurrentDate() - this.m_last_vehicle_added < 90) {
			return 0;
		}

		this.ValidateVehicleList();
		local num_vehicles = this.m_vehicle_list.Count();
		local num_vehicles_before = num_vehicles;

		local optimal_vehicle_count = this.OptimalVehicleCount();
		if (num_vehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local best_route_profit = null;
		local youngest_route_aircraft = null;
		foreach (v, _ in this.m_vehicle_list) {
			local age = AIVehicle.GetAge(v);
			if (youngest_route_aircraft == null || age < youngest_route_aircraft) {
				youngest_route_aircraft = age;
			}
			local profit = AIVehicle.GetProfitLastYear(v) + AIVehicle.GetProfitThisYear(v);
			if (best_route_profit == null || profit > best_route_profit) {
				best_route_profit = profit;
			}
		}

		/* This route doesn't seem to be profitable. Stop adding more aircraft */
		local infrastructure = AIGameSettings.GetValue("infrastructure_maintenance");
		if (best_route_profit != null && best_route_profit - infrastructure * (AIAirport.GetMonthlyMaintenanceCost(this.m_airport_type_from) + AIAirport.GetMonthlyMaintenanceCost(this.m_airport_type_to)) * 12 / optimal_vehicle_count < 10000) {
//			AILog.Info("This route doesn't seem to be profitable. Stop adding more aircraft " + (best_route_profit - infrastructure * (AIAirport.GetMonthlyMaintenanceCost(this.m_airport_type_from) + AIAirport.GetMonthlyMaintenanceCost(this.m_airport_type_to)) * 12 / optimal_vehicle_count) + " youngest_route_aircraft = " + youngest_route_aircraft + " num_vehicles = " + num_vehicles);

			if (youngest_route_aircraft > 730 && num_vehicles > 2) {
				/* Send the vehicles to depot if we didn't do so yet */
				local airport1_hangars = AIAirport.GetNumHangars(this.m_airport_from) != 0;
				local airport2_hangars = AIAirport.GetNumHangars(this.m_airport_to) != 0;
				foreach (vehicle, _ in this.m_vehicle_list) {
					if (AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_air_group[0] && AIVehicle.GetState(vehicle) != AIVehicle.VS_CRASHED) {
						if (AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_air_group[1]) {
							if (!(airport1_hangars && airport2_hangars)) {
								if (airport1_hangars) {
									AIOrder.SkipToOrder(vehicle, 0);
								} else {
									AIOrder.SkipToOrder(vehicle, 1);
								}
							}
							if (AIVehicle.SendVehicleToDepot(vehicle)) {
								AILog.Info("Sending " + AIVehicle.GetName(vehicle) + " to hangar to close unprofitable route.");
								if (!AIGroup.MoveVehicle(this.m_sent_to_depot_air_group[0], vehicle)) {
									AILog.Error("Failed to move vehicle " + AIVehicle.GetName(vehicle) + " to group " + this.m_sent_to_depot_air_group[0]);
								} else {
									this.m_vehicle_list[vehicle] = 0;
								}
							}
						} else {
							AILog.Info("Sending " + AIVehicle.GetName(vehicle) + " to hangar to close unprofitable route.");
							if (!AIGroup.MoveVehicle(this.m_sent_to_depot_air_group[0], vehicle)) {
								AILog.Error("Failed to move vehicle " + AIVehicle.GetName(vehicle) + " to group " + this.m_sent_to_depot_air_group[0]);
							} else {
								this.m_vehicle_list[vehicle] = 0;
							}
						}
					}
				}
			}
			return 0;
		}

		/* Do not build a new vehicle once one of the airports becomes unavailable (small airport) */
		if (!infrastructure && (!AIAirport.IsValidAirportType(this.m_airport_type_from) || !AIAirport.IsValidAirportType(this.m_airport_type_to))) {
			this.m_renew_vehicles = false;
			return 0;
		}

		/* Do not build a new vehicle anymore once helidepots become available for routes where one of the airports isn't dedicated for helicopters */
		if (AIAirport.IsValidAirportType(AIAirport.AT_HELISTATION) || AIAirport.IsValidAirportType(AIAirport.AT_HELIDEPOT)) {
			if (this.m_airport_type_from == AIAirport.AT_HELIPORT && this.m_airport_type_to != AIAirport.AT_HELISTATION && this.m_airport_type_to != AIAirport.AT_HELIDEPOT ||
					this.m_airport_type_to == AIAirport.AT_HELIPORT && this.m_airport_type_from != AIAirport.AT_HELISTATION && this.m_airport_type_from != AIAirport.AT_HELIDEPOT) {
				this.m_renew_vehicles = false;
				return 0;
			}
		}

		local cargo_waiting_from_via_to = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_from, this.m_station_id_to, this.m_cargo_type);
		local cargo_waiting_from_any = AIStation.GetCargoWaitingVia(this.m_station_id_from, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_from = cargo_waiting_from_via_to + cargo_waiting_from_any;
		local cargo_waiting_to_via_from = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_to, this.m_station_id_from, this.m_cargo_type);
		local cargo_waiting_to_any = AIStation.GetCargoWaitingVia(this.m_station_id_to, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_to = cargo_waiting_to_via_from + cargo_waiting_to_any;

		local engine_capacity = ::caches.GetCapacity(this.m_engine, this.m_cargo_type);
		local capacity_check = infrastructure ? min(engine_capacity, 100) : engine_capacity;

		if (cargo_waiting_from < capacity_check && cargo_waiting_to < capacity_check) {
			return 0;
		}

		local number_to_add = max (1, (cargo_waiting_from > cargo_waiting_to ? cargo_waiting_from : cargo_waiting_to) / engine_capacity);
		while (number_to_add) {
			number_to_add--;
			local added_vehicle = this.AddVehicle(true, cargo_waiting_from <= cargo_waiting_to);
			if (added_vehicle != null) {
				num_vehicles++;
				local skipped_order = false;
				if (cargo_waiting_from > cargo_waiting_to) {
					cargo_waiting_from -= engine_capacity;
				} else {
					cargo_waiting_to -= engine_capacity;
					skipped_order = true;
				}
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on existing route from " + (skipped_order ? this.m_station_name_to : this.m_station_name_from) + " to " + (skipped_order ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + "/" + optimal_vehicle_count + " aircraft, " + this.m_fake_dist + " fakedist tiles)");
				if (num_vehicles >= optimal_vehicle_count) {
					number_to_add = 0;
				}
			}
		}
		return num_vehicles - num_vehicles_before;
	}

	function RenewVehicles()
	{
		if (!this.m_renew_vehicles) {
			return;
		}

		this.ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engine);
		local count = 1 + AIGroup.GetNumVehicles(this.m_sent_to_depot_air_group[1], AIVehicle.VT_AIR);

		foreach (vehicle, _ in this.m_vehicle_list) {
//			local vehicle_engine = AIVehicle.GetEngineType(vehicle);
//			if (AIGroup.GetEngineReplacement(this.m_group, vehicle_engine) != this.m_engine) {
//				AIGroup.SetAutoReplace(this.m_group, vehicle_engine, this.m_engine);
//			}
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine && Utils.HasMoney(2 * engine_price * count)) {
				if (SendMoveVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_air_group[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_air_group[1]);
					} else {
						this.m_vehicle_list[vehicle] = 1;
					}
				}
			}
		}
	}

	function RemoveIfUnserviced()
	{
		this.ValidateVehicleList();
		if (this.m_vehicle_list.IsEmpty() && (((!AIEngine.IsValidEngine(this.m_engine) || !AIEngine.IsBuildable(this.m_engine)) && this.m_last_vehicle_added == 0) ||
				(AIDate.GetCurrentDate() - this.m_last_vehicle_added >= 90) && this.m_last_vehicle_added > 0)) {
			this.m_active_route = false;

			::scheduled_removals_table.Aircraft.rawset(this.m_airport_from, 0);
			::scheduled_removals_table.Aircraft.rawset(this.m_airport_to, 0);

			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.DeleteGroup(this.m_group);
			}
			AILog.Warning("Removing unserviced air route from " + this.m_station_name_from + " to " + this.m_station_name_to);
			return true;
		}
		return false;
	}

	function GroupVehicles()
	{
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_air_group[0] && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_air_group[1]) {
				if (!AIGroup.IsValidGroup(this.m_group)) {
					this.m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(this.m_group)) {
			this.m_group = AIGroup.CreateGroup(AIVehicle.VT_AIR, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(this.m_group)) {
				local a = "L";
				if (this.m_airport_type_from == AIAirport.AT_COMMUTER || this.m_airport_type_from == AIAirport.AT_SMALL || this.m_airport_type_to == AIAirport.AT_COMMUTER || this.m_airport_type_to == AIAirport.AT_SMALL) {
					a = "S";
				}
				if (this.m_airport_type_from == AIAirport.AT_HELISTATION || this.m_airport_type_from == AIAirport.AT_HELIDEPOT || this.m_airport_type_from == AIAirport.AT_HELIPORT || this.m_airport_type_to == AIAirport.AT_HELISTATION || this.m_airport_type_to == AIAirport.AT_HELIDEPOT || this.m_airport_type_to == AIAirport.AT_HELIPORT) {
					a = "H";
				}
				AIGroup.SetName(this.m_group, a + this.m_fake_dist + ": " + this.m_airport_from + " - " + this.m_airport_to);
				AILog.Info("Created " + AIGroup.GetName(this.m_group) + " for air route from " + this.m_station_name_from + " to " + this.m_station_name_to);
			}
		}
	}

	function SaveRoute()
	{
		return [this.m_city_from, this.m_city_to, this.m_airport_from, this.m_airport_to, this.m_cargo_class, this.m_last_vehicle_added, this.m_last_vehicle_removed, this.m_active_route, this.m_sent_to_depot_air_group, this.m_group, this.m_renew_vehicles];
	}

	function LoadRoute(data)
	{
		local city_from = data[0];
		local city_to = data[1];
		local airport_from = data[2];
		local airport_to = data[3];

		local cargo_class = data[4];

		local sent_to_depot_air_group = data[8];

		local route = AirRoute(city_from, city_to, airport_from, airport_to, cargo_class, sent_to_depot_air_group, true);

		route.m_last_vehicle_added = data[5];
		route.m_last_vehicle_removed = data[6];
		route.m_active_route = data[7];
		route.m_group = data[9];
		route.m_renew_vehicles = data[10];

		local vehicle_list = AIVehicleList_Station(route.m_station_id_from);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
				route.m_vehicle_list[v] = 2;
			}
		}

		vehicle_list = AIVehicleList_Group(route.m_sent_to_depot_air_group[0]);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 0;
				}
			}
		}

		vehicle_list = AIVehicleList_Group(route.m_sent_to_depot_air_group[1]);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_AIR) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 1;
				}
			}
		}

		return route;
	}
};
