require("ShipRouteManager.nut");

class ShipRoute extends ShipRouteManager
{
	static COUNT_INTERVAL = 20;
	static STATION_RATING_INTERVAL = 40;

	/* These are saved */
	m_city_from = null;
	m_city_to = null;
	m_dock_from = null;
	m_dock_to = null;
	m_depot_tile = null;
	m_cargo_class = null;
	m_last_vehicle_added = null;
	m_last_vehicle_removed = null;
	m_active_route = null;
	m_sent_to_depot_water_group = null;
	m_group = null;

	/* These are not saved */
	m_engine = null;
	m_vehicle_list = null;
	m_max_vehicle_count_mode = null;
	m_station_id_from = null;
	m_station_id_to = null;
	m_station_name_from = null;
	m_station_name_to = null;
	m_cargo_type = null;
	m_route_dist = null;

	constructor(city_from, city_to, dock_from, dock_to, depot_tile, cargo_class, sent_to_depot_water_group, is_loaded = false)
	{
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_dock_from = dock_from;
		this.m_dock_to = dock_to;
		this.m_depot_tile = depot_tile;
		this.m_cargo_class = cargo_class;
		this.m_sent_to_depot_water_group = sent_to_depot_water_group;

		this.m_max_vehicle_count_mode = AIController.GetSetting("water_cap_mode");
		this.m_group = AIGroup.GROUP_INVALID;
		this.m_last_vehicle_added = 0;
		this.m_last_vehicle_removed = AIDate.GetCurrentDate();
		this.m_active_route = true;

		this.m_vehicle_list = AIList();
		this.m_vehicle_list.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
		this.m_station_id_from = AIStation.GetStationID(dock_from);
		this.m_station_id_to = AIStation.GetStationID(dock_to);
		this.m_station_name_from = AIBaseStation.GetName(this.m_station_id_from);
		this.m_station_name_to = AIBaseStation.GetName(this.m_station_id_to);
		this.m_cargo_type = Utils.GetCargoType(cargo_class);
		this.m_route_dist = AIMap.DistanceManhattan(ShipBuildManager.GetDockDockingTile(dock_from), ShipBuildManager.GetDockDockingTile(dock_to));

		/* This requires the values above to be initialized */
		this.m_engine = this.GetShipEngine();

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
			if (AIVehicle.GetVehicleType(v) != AIVehicle.VT_WATER) {
				AILog.Error("s:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			local num_orders = AIOrder.GetOrderCount(v);
			if (num_orders < 2) {
				AILog.Error("s:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
				this.m_vehicle_list[v] = null;
				continue;
			}
			local order_from = false;
			local order_to = false;
			for (local o = 0; o < num_orders; o++) {
				if (!AIOrder.IsValidVehicleOrder(v, o)) {
					continue;
				}
				if (AIOrder.IsConditionalOrder(v, o)) {
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
				AILog.Error("s:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
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

	function GetEngineList()
	{
		local engine_list = AIEngineList(AIVehicle.VT_WATER);
		foreach (engine_id, _ in engine_list) {
			if (!AIEngine.IsBuildable(engine_id)) {
				engine_list[engine_id] = null;
				continue;
			}
			if (!AIEngine.CanRefitCargo(engine_id, this.m_cargo_type)) {
				engine_list[engine_id] = null;
				continue;
			}
		}

		return engine_list;
	}

	function GetShipEngine()
	{
		local engine_list = this.GetEngineList();
		if (engine_list.IsEmpty()) {
			return this.m_engine == null ? -1 : this.m_engine;
		}

		local best_income = null;
		local best_engine = null;
		foreach (engine_id, _ in engine_list) {
			local multiplier = Utils.GetEngineReliabilityMultiplier(engine_id);
			local max_speed = AIEngine.GetMaxSpeed(engine_id);
			local days_in_transit = (this.m_route_dist * 256 * 16) / (2 * 74 * max_speed);
			local running_cost = AIEngine.GetRunningCost(engine_id);
			local capacity = ::caches.GetBuildWithRefitCapacity(this.m_depot_tile, engine_id, this.m_cargo_type);
			local income = ((capacity * AICargo.GetCargoIncome(this.m_cargo_type, this.m_route_dist, days_in_transit) - running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("Engine: " + AIEngine.GetName(engine_id) + "; Capacity: " + capacity + "; Max Speed: " + max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + running_cost + "; Distance: " + this.m_route_dist + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_engine = engine_id;
			}
		}

		return best_engine == null ? -1 : best_engine;
	}

	function UpgradeEngine()
	{
		if (!this.m_active_route) return;

		this.m_engine = this.GetShipEngine();
	}

	function DeleteSellVehicle(vehicle)
	{
		this.m_vehicle_list[vehicle] = null;
		AIVehicle.SellVehicle(vehicle);
		Utils.RepayLoan();
	}

	function AddVehicle(return_vehicle = false)
	{
		this.ValidateVehicleList();
		if (this.m_max_vehicle_count_mode != 2 && this.m_vehicle_list.Count() >= this.OptimalVehicleCount()) {
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

		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			new_vehicle = TestBuildVehicleWithRefit().TryBuild(this.m_depot_tile, this.m_engine, this.m_cargo_type);
		} else {
			local is_same_vehicle = AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id;
			new_vehicle = TestCloneVehicle().TryClone(this.m_depot_tile, clone_vehicle_id, is_same_vehicle);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			this.m_vehicle_list[new_vehicle] = 2;
			local vehicle_ready_to_start = false;
			local depot_order_flags = AIOrder.OF_SERVICE_IF_NEEDED;
			local load_mode = AIController.GetSetting("water_load_mode");
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					if (AIOrder.AppendOrder(new_vehicle, this.m_depot_tile, depot_order_flags) &&
							AIOrder.AppendOrder(new_vehicle, this.m_dock_from, AIOrder.OF_NONE) &&
							(load_mode == 0 && AIOrder.AppendConditionalOrder(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 1) && AIOrder.SetOrderCondition(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, 0) || true) &&
							AIOrder.AppendOrder(new_vehicle, this.m_depot_tile, depot_order_flags) &&
							AIOrder.AppendOrder(new_vehicle, this.m_dock_to, AIOrder.OF_NONE) &&
							(load_mode == 0 && AIOrder.AppendConditionalOrder(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 1) && AIOrder.SetOrderCondition(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, 0) || true)) {
						vehicle_ready_to_start = true;
					} else {
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
						local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, this.GetSecondDepotOrderIndex(new_vehicle));
						if (new_vehicle_order_depot1_flags != depot_order_flags || new_vehicle_order_depot2_flags != depot_order_flags) {
							AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
							this.DeleteSellVehicle(new_vehicle);
							return null;
						} else {
							vehicle_ready_to_start = true;
						}
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				}
			} else {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, this.GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags != depot_order_flags) {
						if (!AIOrder.SetOrderFlags(new_vehicle, 0, depot_order_flags)) {
							this.DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					if (new_vehicle_order_depot2_flags != depot_order_flags) {
						if (!AIOrder.SetOrderFlags(new_vehicle, this.GetSecondDepotOrderIndex(new_vehicle), depot_order_flags)) {
							this.DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, this.GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags == depot_order_flags && new_vehicle_order_depot2_flags == depot_order_flags) {
						if (load_mode == 0 && !this.HasConditionalOrders(new_vehicle)) {
							if (!this.AddConditionalOrders(new_vehicle)) {
								AILog.Error("Failed to add conditional orders to " + AIVehicle.GetName(new_vehicle));
								this.DeleteSellVehicle(new_vehicle);
								return null;
							}
						}
						vehicle_ready_to_start = true;
					} else {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						this.DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (clone_vehicle_id != share_orders_vid) {
						if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
							AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
							this.DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, this.GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags != depot_order_flags || new_vehicle_order_depot2_flags != depot_order_flags) {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						this.DeleteSellVehicle(new_vehicle);
						return null;
					} else {
						vehicle_ready_to_start = true;
					}
				}
			}
			if (vehicle_ready_to_start) {
				if (!return_vehicle) AIVehicle.StartStopVehicle(new_vehicle);
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

	function OptimalVehicleCount()
	{
		if (this.m_max_vehicle_count_mode == 0) return 10;

//		AILog.Info("this.m_route_dist = " + this.m_route_dist);
		local count_interval = Utils.GetEngineTileDist(this.m_engine, STATION_RATING_INTERVAL);
//		AILog.Info("count_interval = " + count_interval + "; MaxSpeed = " + AIEngine.GetMaxSpeed(this.m_engine));
		local vehicle_count = 1 + (count_interval > 0 ? (2 * this.m_route_dist / count_interval) : 0);
//		AILog.Info("vehicle_count = " + vehicle_count);

		return vehicle_count;
	}

	function GetSecondDepotOrderIndex(vehicle)
	{
		local order_count = AIOrder.GetOrderCount(vehicle);

		local depot_order_count = 0;
		for (local o = 0; o < order_count; o++) {
			if (AIOrder.IsGotoDepotOrder(vehicle, o)) {
				depot_order_count++;
			}
			if (depot_order_count == 2) {
				return o;
			}
		}
		AILog.Error(AIVehicle.GetName(vehicle) + " doesn't have a second ship depot order.");
		return 0;
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

		local buy_vehicle_count = max((((num_vehicles + 1) * 2) >= optimal_vehicle_count ? 1 : 2), (optimal_vehicle_count / 2 - num_vehicles))

		if (buy_vehicle_count > optimal_vehicle_count - num_vehicles) {
			buy_vehicle_count = optimal_vehicle_count - num_vehicles;
		}

		for (local i = 0; i < buy_vehicle_count; ++i) {
			local old_last_vehicle_added = -this.m_last_vehicle_added;
			if (old_last_vehicle_added > 0 && AIDate.GetCurrentDate() - old_last_vehicle_added <= COUNT_INTERVAL) {
				break;
			}
			this.m_last_vehicle_added = 0;
			local added_vehicle = this.AddVehicle(true);
			if (added_vehicle != null) {
				if (num_vehicles % 2 == 1) {
					AIOrder.SkipToOrder(added_vehicle, this.GetSecondDepotOrderIndex(added_vehicle));
				}
				AIVehicle.StartStopVehicle(added_vehicle);
				num_vehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + (num_vehicles % 2 == 1 ? this.m_station_name_to : this.m_station_name_from) + " to " + (num_vehicles % 2 == 1 ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + "/" + optimal_vehicle_count + " ship" + (num_vehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
				if (buy_vehicle_count > 1) {
					this.m_last_vehicle_added *= -1;
					break;
				}
			} else {
				break;
			}
		}
		if (num_vehicles * 2 < (this.m_max_vehicle_count_mode == 0 ? 1 : optimal_vehicle_count) && this.m_last_vehicle_added >= 0) {
			this.m_last_vehicle_added = 0;
		}
		return num_vehicles - num_vehicles_before;
	}

	function RemoveConditionalOrders(vehicle)
	{
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return true;

		local reinitialize;
		do {
			reinitialize = false;
			order_count = AIOrder.GetOrderCount(vehicle);
			for (local o = 0; o < order_count; o++) {
				if (AIOrder.IsConditionalOrder(vehicle, o)) {
					if (AIOrder.RemoveOrder(vehicle, o)) {
						reinitialize = true;
						break;
					} else {
						return false;
					}
				}
			}
		} while (reinitialize);

		return true;
	}

	function AddConditionalOrders(vehicle)
	{
		assert(!this.HasConditionalOrders(vehicle));
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return false;

		local reinitialize;
		do {
			reinitialize = false;
			order_count = AIOrder.GetOrderCount(vehicle);
			for (local o = 0; o < order_count; o++) {
				if (AIOrder.IsGotoStationOrder(vehicle, o) && !AIOrder.IsConditionalOrder(vehicle, o + 1)) {
					if (AIOrder.InsertConditionalOrder(vehicle, o + 1, o) &&
							AIOrder.SetOrderCondition(vehicle, o + 1, AIOrder.OC_LOAD_PERCENTAGE) &&
							AIOrder.SetOrderCompareFunction(vehicle, o + 1, AIOrder.CF_EQUALS) &&
							AIOrder.SetOrderCompareValue(vehicle, o + 1, 0)) {
						reinitialize = true;
						break;
					} else {
						return false;
					}
				}
			}
		} while (reinitialize);

		return true;
	}

	function HasConditionalOrders(vehicle)
	{
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return false;

		for (local o = 0; o < order_count; o++) {
			if (AIOrder.IsConditionalOrder(vehicle, o)) {
				return true;
			}
		}
		return false;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_water_group[0] && AIVehicle.GetGroupID(vehicle_id) != this.m_sent_to_depot_water_group[1]) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.IsStoppedInDepot(vehicle_id)) {
				local depot_order_flags = AIOrder.OF_STOP_IN_DEPOT;
				if (!AIVehicle.HasSharedOrders(vehicle_id)) {
					/* Remove conditional orders */
					if (!this.RemoveConditionalOrders(vehicle_id)) {
						AILog.Info("Failed to remove conditional orders from " + vehicle_name + " when preparing to send it to depot.");
//						AIController.Break(" ");
						return false;
					} else {
						/* Make the ship stop at depot when executing depot orders. */
						local depot_stop1 = AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags);
						local depot_stop2 = AIOrder.SetOrderFlags(vehicle_id, this.GetSecondDepotOrderIndex(vehicle_id), depot_order_flags);
						if (!depot_stop1 && !depot_stop2) {
							AILog.Error("Failed to send " + vehicle_name + " to depot.");
//							AIController.Break(" ");
							return false;
						}
					}
				} else {
					local shared_list = AIVehicleList_SharedOrders(vehicle_id);
					local copy_orders_vid = AIVehicle.VEHICLE_INVALID;
					foreach (v, _ in shared_list) {
						if (v != vehicle_id) {
							copy_orders_vid = v;
							break;
						}
					}
					if (AIVehicle.IsValidVehicle(copy_orders_vid)) {
						if (AIOrder.CopyOrders(vehicle_id, copy_orders_vid)) {
							/* Remove conditional orders */
							if (!this.RemoveConditionalOrders(vehicle_id)) {
								AILog.Info("Failed to remove conditional orders from " + vehicle_name + " when preparing to send it to depot.");
//								AIController.Break(" ");
								return false;
							} else {
								/* Make the ship stop at depot when executing depot orders. */
								local depot_stop1 = AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags);
								local depot_stop2 = AIOrder.SetOrderFlags(vehicle_id, this.GetSecondDepotOrderIndex(vehicle_id), depot_order_flags);
								if (!depot_stop1 && !depot_stop2) {
									AILog.Error("Failed to send " + vehicle_name + " to depot.");
//									AIController.Break(" ");
									return false;
								}
							}
						} else {
							AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//							AIController.Break(" ");
							return false;
						}
					} else {
						AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//						AIController.Break(" ");
						return false;
					}
				}
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
//		AILog.Info("SendNegativeProfitVehiclesToDepot . this.m_last_vehicle_added = " + this.m_last_vehicle_added + "; " + AIDate.GetCurrentDate() + " - " + this.m_last_vehicle_added + " = " + (AIDate.GetCurrentDate() - this.m_last_vehicle_added) + " < 45" + " - " + this.m_station_name_from + " to " + this.m_station_name_to);

//		if (AIDate.GetCurrentDate() - this.m_last_vehicle_removed <= 30) return;

		this.ValidateVehicleList();

		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (this.SendMoveVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_water_group[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_water_group[0]);
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

//		AILog.Info("cargo_waiting = " + (cargo_waiting_from + cargo_waiting_to));
		if (cargo_waiting_from + cargo_waiting_to < 150) {
			foreach (vehicle, _ in vehicle_list) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (max_all_routes_profit / 6)) {
					if (this.SendMoveVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(this.m_sent_to_depot_water_group[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_water_group[0]);
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

				local renewed_vehicle = this.AddVehicle(true);
				if (renewed_vehicle != null) {
					AIOrder.SkipToOrder(renewed_vehicle, skip_to_order);
					AIVehicle.StartStopVehicle(renewed_vehicle);
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + this.m_station_name_from + " to " + this.m_station_name_to + " has been renewed!");
				}
			}
		}
	}

	function GetGroupUsage()
	{
		local max_capacity = 0;
		local used_capacity = 0;
		foreach (v, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(v) == this.m_group) {
				max_capacity += AIVehicle.GetCapacity(v, this.m_cargo_type);
				used_capacity += AIVehicle.GetCargoLoad(v, this.m_cargo_type);
			}
		}
		if (max_capacity == 0) return 0;
		return 100 * used_capacity / max_capacity;
	}

	function AddRemoveVehicleToRoute(maxed_out_num_vehs)
	{
		if (!this.m_active_route) {
			return 0;
		}

		if (this.m_last_vehicle_added <= 0) {
			return this.AddVehiclesToNewRoute();
		}

		if (this.m_max_vehicle_count_mode != AIController.GetSetting("water_cap_mode")) {
			this.m_max_vehicle_count_mode = AIController.GetSetting("water_cap_mode");
//			AILog.Info("this.m_max_vehicle_count_mode = " + this.m_max_vehicle_count_mode);
		}

		if (AIDate.GetCurrentDate() - this.m_last_vehicle_added < 90) {
			return 0;
		}

		local optimal_vehicle_count = this.OptimalVehicleCount();
		this.ValidateVehicleList();
		local num_vehicles = this.m_vehicle_list.Count();
		local num_vehicles_before = num_vehicles;

		if (this.m_max_vehicle_count_mode != 2 && num_vehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local cargo_waiting_from_via_to = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_from, this.m_station_id_to, this.m_cargo_type);
		local cargo_waiting_from_any = AIStation.GetCargoWaitingVia(this.m_station_id_from, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_from = cargo_waiting_from_via_to + cargo_waiting_from_any;
		local cargo_waiting_to_via_from = AICargo.GetDistributionType(this.m_cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(this.m_station_id_to, this.m_station_id_from, this.m_cargo_type);
		local cargo_waiting_to_any = AIStation.GetCargoWaitingVia(this.m_station_id_to, AIStation.STATION_INVALID, this.m_cargo_type);
		local cargo_waiting_to = cargo_waiting_to_via_from + cargo_waiting_to_any;

		local engine_capacity = ::caches.GetCapacity(this.m_engine, this.m_cargo_type);
		local group_usage = this.GetGroupUsage();
//		AILog.Info(AIGroup.GetName(this.m_group) + ": usage = " + group_usage + "; engine_capacity = " + engine_capacity + "; cargo_waiting_from = " + cargo_waiting_from + "; cargo_waiting_to = " + cargo_waiting_to);

		if ((cargo_waiting_from > engine_capacity || cargo_waiting_to > engine_capacity) && group_usage > 66) {
			local number_to_add = max(1, (cargo_waiting_from > cargo_waiting_to ? cargo_waiting_from : cargo_waiting_to) / engine_capacity);

			while (number_to_add) {
				number_to_add--;
				local added_vehicle = this.AddVehicle(true);
				if (added_vehicle != null) {
					num_vehicles++;
					local skipped_order = false;
					if (cargo_waiting_from > cargo_waiting_to) {
						cargo_waiting_from -= engine_capacity;
					} else {
						cargo_waiting_to -= engine_capacity;
						skipped_order = AIOrder.SkipToOrder(added_vehicle, this.GetSecondDepotOrderIndex(added_vehicle));
					}
					AIVehicle.StartStopVehicle(added_vehicle);
					AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on existing route from " + (skipped_order ? this.m_station_name_to : this.m_station_name_from) + " to " + (skipped_order ? this.m_station_name_from : this.m_station_name_to) + "! (" + num_vehicles + (this.m_max_vehicle_count_mode != 2 ? "/" + optimal_vehicle_count : "") + " ship" + (num_vehicles != 1 ? "s" : "") + ", " + this.m_route_dist + " manhattan tiles)");
					if (num_vehicles >= this.m_max_vehicle_count_mode != 2 ? 1 : optimal_vehicle_count) {
						number_to_add = 0;
					}
				}
			}
		}
		return num_vehicles - num_vehicles_before;
	}

	function RenewVehicles()
	{
		this.ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engine);
		local count = 1 + AIGroup.GetNumVehicles(this.m_sent_to_depot_water_group[1], AIVehicle.VT_WATER);

		foreach (vehicle, _ in this.m_vehicle_list) {
//			local vehicle_engine = AIVehicle.GetEngineType(vehicle);
//			if (AIGroup.GetEngineReplacement(this.m_group, vehicle_engine) != this.m_engine) {
//				AIGroup.SetAutoReplace(this.m_group, vehicle_engine, this.m_engine);
//			}
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine && Utils.HasMoney(2 * engine_price * count)) {
				if (this.SendMoveVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(this.m_sent_to_depot_water_group[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + this.m_sent_to_depot_water_group[1]);
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

			::scheduled_removals_table.Ship.rawset(this.m_dock_from, 0);
			::scheduled_removals_table.Ship.rawset(this.m_dock_to, 0);
			::scheduled_removals_table.Ship.rawset(this.m_depot_tile, 0);

			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.DeleteGroup(this.m_group);
			}
			AILog.Warning("Removing unserviced water route from " + this.m_station_name_from + " to " + this.m_station_name_to);
			return true;
		}
		return false;
	}

	function GroupVehicles()
	{
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_water_group[0] && AIVehicle.GetGroupID(vehicle) != this.m_sent_to_depot_water_group[1]) {
				if (!AIGroup.IsValidGroup(this.m_group)) {
					this.m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(this.m_group)) {
			this.m_group = AIGroup.CreateGroup(AIVehicle.VT_WATER, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(this.m_group)) {
				AIGroup.SetName(this.m_group, (this.m_cargo_class == AICargo.CC_PASSENGERS ? "P" : "M") + AIMap.DistanceManhattan(ShipBuildManager.GetDockDockingTile(this.m_dock_from), ShipBuildManager.GetDockDockingTile(this.m_dock_to)) + ": " + this.m_dock_from + " - " + this.m_dock_to);
				AILog.Info("Created " + AIGroup.GetName(this.m_group) + " for water route from " + this.m_station_name_from + " to " + this.m_station_name_to);
			}
		}
	}

	function SaveRoute()
	{
		return [this.m_city_from, this.m_city_to, this.m_dock_from, this.m_dock_to, this.m_depot_tile, this.m_cargo_class, this.m_last_vehicle_added, this.m_last_vehicle_removed, this.m_active_route, this.m_sent_to_depot_water_group, this.m_group];
	}

	function LoadRoute(data)
	{
		local city_from = data[0];
		local city_to = data[1];
		local dock_from = data[2];
		local dock_to = data[3];
		local depot_tile = data[4];
		local cargo_class = data[5];

		local sent_to_depot_water_group = data[9];

		local route = ShipRoute(city_from, city_to, dock_from, dock_to, depot_tile, cargo_class, sent_to_depot_water_group, true);

		route.m_last_vehicle_added = data[6];
		route.m_last_vehicle_removed = data[7];
		route.m_active_route = data[8];
		route.m_group = data[10];

		local vehicle_list = AIVehicleList_Station(route.m_station_id_from);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				route.m_vehicle_list[v] = 2;
			}
		}

		vehicle_list = AIVehicleList_Group(route.m_sent_to_depot_water_group[0]);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 0;
				}
			}
		}

		vehicle_list = AIVehicleList_Group(route.m_sent_to_depot_water_group[1]);
		foreach (v, _ in vehicle_list) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				if (route.m_vehicle_list.HasItem(v)) {
					route.m_vehicle_list[v] = 1;
				}
			}
		}

		return route;
	}
};
