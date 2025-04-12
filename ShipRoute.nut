require("ShipRouteManager.nut");

class ShipRoute extends ShipRouteManager
{
	MAX_VEHICLE_COUNT_MODE = AIController.GetSetting("water_cap_mode");
	COUNT_INTERVAL = 20;
	STATION_RATING_INTERVAL = 40;

	m_city_from = null;
	m_city_to = null;
	m_dockFrom = null;
	m_dockTo = null;
	m_depot_tile = null;
	m_cargo_class = null;

	m_engine = null;
	m_group = null;

	m_last_vehicle_added = null;
	m_last_vehicle_removed = null;

	m_sentToDepotWaterGroup = null;

	m_active_route = null;

	m_vehicle_list = null;

	constructor(city_from, city_to, dockFrom, dockTo, depot_tile, cargo_class, sentToDepotWaterGroup, is_loaded = 0)
	{
		m_city_from = city_from;
		m_city_to = city_to;
		m_dockFrom = dockFrom;
		m_dockTo = dockTo;
		m_depot_tile = depot_tile;
		m_cargo_class = cargo_class;

		m_engine = GetShipEngine(cargo_class);
		m_group = AIGroup.GROUP_INVALID;
		m_sentToDepotWaterGroup = sentToDepotWaterGroup;

		m_last_vehicle_added = 0;
		m_last_vehicle_removed = AIDate.GetCurrentDate();

		m_active_route = true;

		m_vehicle_list = {};

		if (!is_loaded) {
			AddVehiclesToNewRoute(cargo_class);
		}
	}

	function ValidateVehicleList()
	{
		local station_from = AIStation.GetStationID(m_dockFrom);
		local station_to = AIStation.GetStationID(m_dockTo);

		local removelist = AIList();
		foreach (v, _ in m_vehicle_list) {
			if (AIVehicle.IsValidVehicle(v)) {
				if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
					local num_orders = AIOrder.GetOrderCount(v);
					if (num_orders >= 2) {
						local order_from = false;
						local order_to = false;
						for (local o = 0; o < num_orders; o++) {
							if (AIOrder.IsValidVehicleOrder(v, o) && !AIOrder.IsConditionalOrder(v, o)) {
								local station_id = AIStation.GetStationID(AIOrder.GetOrderDestination(v, o));
								if (station_id == station_from) order_from = true;
								if (station_id == station_to) order_to = true;
							}
						}
						if (!order_from || !order_to) {
							removelist.AddItem(v, 0);
						}
					} else {
						removelist.AddItem(v, 0);
					}
				} else {
					removelist.AddItem(v, 0);
				}
			} else {
				removelist.AddItem(v, 0);
			}
		}

		for (local v = removelist.Begin(); !removelist.IsEnd(); v = removelist.Next()) {
			local exists = AIVehicle.IsValidVehicle(v);
			if (exists) {
				AILog.Error("s:Vehicle ID " + v + " no longer belongs to this route, but it exists! " + AIVehicle.GetName(v));
//				AIController.Break(" ");
			}
			m_vehicle_list.rawdelete(v);
		}
	}

	function SentToDepotList(i)
	{
		local sent_to_depot_list = AIList();
		ValidateVehicleList();
		foreach (vehicle, status in m_vehicle_list) {
			if (status == i) sent_to_depot_list.AddItem(vehicle, i);
		}
		return sent_to_depot_list;
	}

	function GetEngineList(cargo_class)
	{
		local cargo_type = Utils.GetCargoType(cargo_class);

		local tempList = AIEngineList(AIVehicle.VT_WATER);
		local engineList = AIList();
		for (local engine = tempList.Begin(); !tempList.IsEnd(); engine = tempList.Next()) {
			if (AIEngine.IsBuildable(engine) && AIEngine.CanRefitCargo(engine, cargo_type)) {
				engineList.AddItem(engine, 0);
			}
		}

		return engineList;
	}

	function GetShipEngine(cargo_class)
	{
		local engineList = GetEngineList(cargo_class);
		if (engineList.IsEmpty()) return m_engine == null ? -1 : m_engine;

		local cargo_type = Utils.GetCargoType(cargo_class);

		local distance = AIMap.DistanceManhattan(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));
		local best_income = null;
		local best_engine = null;
		for (local engine = engineList.Begin(); !engineList.IsEnd(); engine = engineList.Next()) {
			local multiplier = Utils.GetEngineReliabilityMultiplier(engine);
			local max_speed = AIEngine.GetMaxSpeed(engine);
			local days_in_transit = (distance * 256 * 16) / (2 * 74 * max_speed);
			local running_cost = AIEngine.GetRunningCost(engine);
			local capacity = ::caches.GetBuildWithRefitCapacity(m_depot_tile, engine, cargo_type);
			local income = ((capacity * AICargo.GetCargoIncome(cargo_type, distance, days_in_transit) - running_cost * days_in_transit / 365) * 365 / days_in_transit) * multiplier;
//			AILog.Info("Engine: " + AIEngine.GetName(engine) + "; Capacity: " + capacity + "; Max Speed: " + max_speed + "; Days in transit: " + days_in_transit + "; Running Cost: " + running_cost + "; Distance: " + distance + "; Income: " + income);
			if (best_income == null || income > best_income) {
				best_income = income;
				best_engine = engine;
			}
		}

		return best_engine == null ? -1 : best_engine;
	}

	function UpgradeEngine()
	{
		if (!m_active_route) return;

		m_engine = GetShipEngine(m_cargo_class);
	}

	function DeleteSellVehicle(vehicle)
	{
		m_vehicle_list.rawdelete(vehicle);
		AIVehicle.SellVehicle(vehicle);
		Utils.RepayLoan();
	}

	function AddVehicle(return_vehicle = false)
	{
		ValidateVehicleList();
		if (MAX_VEHICLE_COUNT_MODE != 2 && m_vehicle_list.len() >= OptimalVehicleCount()) {
			return null;
		}

		/* Clone vehicle, share orders */
		local clone_vehicle_id = AIVehicle.VEHICLE_INVALID;
		local share_orders_vid = AIVehicle.VEHICLE_INVALID;
		foreach (vehicle_id, _ in m_vehicle_list) {
			if (m_engine != null && AIEngine.IsValidEngine(m_engine) && AIEngine.IsBuildable(m_engine)) {
				if (AIVehicle.GetEngineType(vehicle_id) == m_engine) {
					clone_vehicle_id = vehicle_id;
				}
			}
			if (AIVehicle.GetGroupID(vehicle_id) == m_group && AIGroup.IsValidGroup(m_group)) {
				share_orders_vid = vehicle_id;
			}
		}

		local new_vehicle = AIVehicle.VEHICLE_INVALID;
		if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
			new_vehicle = TestBuildVehicleWithRefit().TryBuild(this.m_depot_tile, this.m_engine, Utils.GetCargoType(m_cargo_class));
		} else {
			new_vehicle = TestCloneVehicle().TryClone(this.m_depot_tile, clone_vehicle_id, (AIVehicle.IsValidVehicle(share_orders_vid) && share_orders_vid == clone_vehicle_id) ? true : false);
		}

		if (AIVehicle.IsValidVehicle(new_vehicle)) {
			m_vehicle_list.rawset(new_vehicle, 2);
			local vehicle_ready_to_start = false;
			local depot_order_flags = AIOrder.OF_SERVICE_IF_NEEDED;
			local load_mode = AIController.GetSetting("water_load_mode");
			if (!AIVehicle.IsValidVehicle(clone_vehicle_id)) {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					if (AIOrder.AppendOrder(new_vehicle, m_depot_tile, depot_order_flags) &&
							AIOrder.AppendOrder(new_vehicle, m_dockFrom, AIOrder.OF_NONE) &&
							(load_mode == 0 && AIOrder.AppendConditionalOrder(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 1) && AIOrder.SetOrderCondition(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, 0) || true) &&
							AIOrder.AppendOrder(new_vehicle, m_depot_tile, depot_order_flags) &&
							AIOrder.AppendOrder(new_vehicle, m_dockTo, AIOrder.OF_NONE) &&
							(load_mode == 0 && AIOrder.AppendConditionalOrder(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 1) && AIOrder.SetOrderCondition(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.OC_LOAD_PERCENTAGE) && AIOrder.SetOrderCompareFunction(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, AIOrder.CF_EQUALS) && AIOrder.SetOrderCompareValue(new_vehicle, AIOrder.GetOrderCount(new_vehicle) - 2, 0) || true)) {
						vehicle_ready_to_start = true;
					} else {
						DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
						local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
						local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
						if (new_vehicle_order_depot1_flags != depot_order_flags || new_vehicle_order_depot2_flags != depot_order_flags) {
							AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
							DeleteSellVehicle(new_vehicle);
							return null;
						} else {
							vehicle_ready_to_start = true;
						}
					} else {
						AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
						DeleteSellVehicle(new_vehicle);
						return null;
					}
				}
			} else {
				if (!AIVehicle.IsValidVehicle(share_orders_vid)) {
					local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags != depot_order_flags) {
						if (!AIOrder.SetOrderFlags(new_vehicle, 0, depot_order_flags)) {
							DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					if (new_vehicle_order_depot2_flags != depot_order_flags) {
						if (!AIOrder.SetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle), depot_order_flags)) {
							DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags == depot_order_flags && new_vehicle_order_depot2_flags == depot_order_flags) {
						if (load_mode == 0 && !HasConditionalOrders(new_vehicle)) {
							if (!AddConditionalOrders(new_vehicle)) {
								AILog.Error("Failed to add conditional orders to " + AIVehicle.GetName(new_vehicle));
								DeleteSellVehicle(new_vehicle);
								return null;
							}
						}
						vehicle_ready_to_start = true;
					} else {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						DeleteSellVehicle(new_vehicle);
						return null;
					}
				} else {
					if (clone_vehicle_id != share_orders_vid) {
						if (!AIOrder.ShareOrders(new_vehicle, share_orders_vid)) {
							AILog.Error("Could not share " + AIVehicle.GetName(new_vehicle) + " orders with " + AIVehicle.GetName(share_orders_vid));
							DeleteSellVehicle(new_vehicle);
							return null;
						}
					}
					local new_vehicle_order_depot1_flags = AIOrder.GetOrderFlags(new_vehicle, 0);
					local new_vehicle_order_depot2_flags = AIOrder.GetOrderFlags(new_vehicle, GetSecondDepotOrderIndex(new_vehicle));
					if (new_vehicle_order_depot1_flags != depot_order_flags || new_vehicle_order_depot2_flags != depot_order_flags) {
						AILog.Error("Order Flags of " + AIVehicle.GetName(new_vehicle) + " mismatch! " + new_vehicle_order_depot1_flags + "/" + new_vehicle_order_depot2_flags + " != " + depot_order_flags + "/" + depot_order_flags + " ; clone_vehicle_id = " + (!AIVehicle.IsValidVehicle(clone_vehicle_id) ? "null" : AIVehicle.GetName(clone_vehicle_id)) + " ; share_orders_vid = " + (AIVehicle.IsValidVehicle(share_orders_vid) ? "null" : AIVehicle.GetName(share_orders_vid)));
						DeleteSellVehicle(new_vehicle);
						return null;
					} else {
						vehicle_ready_to_start = true;
					}
				}
			}
			if (vehicle_ready_to_start) {
				if (!return_vehicle) AIVehicle.StartStopVehicle(new_vehicle);
//				AILog.Info("new_vehicle = " + AIVehicle.GetName(new_vehicle) + "; clone_vehicle_id = " + AIVehicle.GetName(clone_vehicle_id) + "; share_orders_vid = " + AIVehicle.GetName(share_orders_vid));

				m_last_vehicle_added = AIDate.GetCurrentDate();

				if (AIGroup.IsValidGroup(m_group) && AIVehicle.GetGroupID(new_vehicle) != m_group) {
					AIGroup.MoveVehicle(m_group, new_vehicle);
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
		if (MAX_VEHICLE_COUNT_MODE == 0) return 10;

		local dockDistance = AIMap.DistanceManhattan(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));
//		AILog.Info("dockDistance = " + dockDistance);
		local count_interval = (AIEngine.GetMaxSpeed(this.m_engine) * 2 * 74 * STATION_RATING_INTERVAL) / (256 * 16);
//		AILog.Info("count_interval = " + count_interval + "; MaxSpeed = " + AIEngine.GetMaxSpeed(this.m_engine));
		local vehicleCount = 1 + (count_interval > 0 ? (2 * dockDistance / count_interval) : 0);
//		AILog.Info("vehicleCount = " + vehicleCount);

		return vehicleCount;
	}

	function GetSecondDepotOrderIndex(vehicle)
	{
		local order_count = AIOrder.GetOrderCount(vehicle);

		local depot_order_count = 0;
		for (local i = 0; i < order_count; i++) {
			if (AIOrder.IsGotoDepotOrder(vehicle, i)) {
				depot_order_count++;
			}
			if (depot_order_count == 2) {
				return i;
			}
		}
		AILog.Error(AIVehicle.GetName(vehicle) + " doesn't have a second ship depot order.");
		return 0;
	}

	function AddVehiclesToNewRoute(cargo_class)
	{
		m_group = GroupVehicles();
		local optimal_vehicle_count = OptimalVehicleCount();

		ValidateVehicleList();
		local numvehicles = m_vehicle_list.len();
		local numvehicles_before = numvehicles;
		if (numvehicles >= optimal_vehicle_count) {
			if (m_last_vehicle_added < 0) m_last_vehicle_added *= -1;
			return 0;
		}

		local routedist = AIMap.DistanceManhattan(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));

		local buyVehicleCount = max((((numvehicles + 1) * 2) >= optimal_vehicle_count ? 1 : 2), (optimal_vehicle_count / 2 - numvehicles))

		if (buyVehicleCount > optimal_vehicle_count - numvehicles) {
			buyVehicleCount = optimal_vehicle_count - numvehicles;
		}

		for (local i = 0; i < buyVehicleCount; ++i) {
			local old_lastVehicleAdded = -m_last_vehicle_added;
			if (old_lastVehicleAdded > 0 && AIDate.GetCurrentDate() - old_lastVehicleAdded <= COUNT_INTERVAL) {
				break;
			}
			m_last_vehicle_added = 0;
			local added_vehicle = AddVehicle(true);
			if (added_vehicle != null) {
				local nameFrom = AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom));
				local nameTo = AIBaseStation.GetName(AIStation.GetStationID(m_dockTo));
				if (numvehicles % 2 == 1) {
					AIOrder.SkipToOrder(added_vehicle, GetSecondDepotOrderIndex(added_vehicle));
				}
				AIVehicle.StartStopVehicle(added_vehicle);
				numvehicles++;
				AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on new route from " + (numvehicles % 2 == 1 ? nameTo : nameFrom) + " to " + (numvehicles % 2 == 1 ? nameFrom : nameTo) + "! (" + numvehicles + "/" + optimal_vehicle_count + " ship" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
				if (buyVehicleCount > 1) {
					m_last_vehicle_added *= -1;
					break;
				}
			} else {
				break;
			}
		}
		if (numvehicles * 2 < (MAX_VEHICLE_COUNT_MODE == 0 ? 1 : optimal_vehicle_count) && m_last_vehicle_added >= 0) {
			m_last_vehicle_added = 0;
		}
		return numvehicles - numvehicles_before;
	}

	function RemoveConditionalOrders(vehicle)
	{
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return true;

		local interrupted;
		do {
			interrupted = false;
			order_count = AIOrder.GetOrderCount(vehicle);
			for (local i = 0; i < order_count; i++) {
				if (AIOrder.IsConditionalOrder(vehicle, i)) {
					if (AIOrder.RemoveOrder(vehicle, i)) {
						interrupted = true;
						break;
					} else {
						return false;
					}
				}
			}
		} while (interrupted);

		return true;
	}

	function AddConditionalOrders(vehicle)
	{
		assert(!HasConditionalOrders(vehicle));
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return false;

		local interrupted;
		do {
			interrupted = false;
			order_count = AIOrder.GetOrderCount(vehicle);
			for (local i = 0; i < order_count; i++) {
				if (AIOrder.IsGotoStationOrder(vehicle, i) && !AIOrder.IsConditionalOrder(vehicle, i + 1)) {
					if (AIOrder.InsertConditionalOrder(vehicle, i + 1, i) &&
							AIOrder.SetOrderCondition(vehicle, i + 1, AIOrder.OC_LOAD_PERCENTAGE) &&
							AIOrder.SetOrderCompareFunction(vehicle, i + 1, AIOrder.CF_EQUALS) &&
							AIOrder.SetOrderCompareValue(vehicle, i + 1, 0)) {
						interrupted = true;
						break;
					} else {
						return false;
					}
				}
			}
		} while (interrupted);

		return true;
	}

	function HasConditionalOrders(vehicle)
	{
		local order_count = AIOrder.GetOrderCount(vehicle);
		if (order_count == 0) return false;

		for (local i = 0; i < order_count; i++) {
			if (AIOrder.IsConditionalOrder(vehicle, i)) {
				return true;
			}
		}
		return false;
	}

	function SendMoveVehicleToDepot(vehicle_id)
	{
		if (AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotWaterGroup[0] && AIVehicle.GetGroupID(vehicle_id) != m_sentToDepotWaterGroup[1]) {
			local vehicle_name = AIVehicle.GetName(vehicle_id);
			if (!AIVehicle.IsStoppedInDepot(vehicle_id)) {
				local depot_order_flags = AIOrder.OF_STOP_IN_DEPOT;
				if (!AIVehicle.HasSharedOrders(vehicle_id)) {
					/* Remove conditional orders */
					if (!RemoveConditionalOrders(vehicle_id)) {
						AILog.Info("Failed to remove conditional orders from " + vehicle_name + " when preparing to send it to depot.");
//						AIController.Break(" ");
						return 0;
					} else {
						/* Make the ship stop at depot when executing depot orders. */
						local depotstop1 = AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags);
						local depotstop2 = AIOrder.SetOrderFlags(vehicle_id, GetSecondDepotOrderIndex(vehicle_id), depot_order_flags);
						if (!depotstop1 && !depotstop2) {
							AILog.Error("Failed to send " + vehicle_name + " to depot.");
//							AIController.Break(" ");
							return 0;
						}
					}
				} else {
					local shared_list = AIVehicleList_SharedOrders(vehicle_id);
					local copy_orders_vid = AIVehicle.VEHICLE_INVALID;
					for (local v = shared_list.Begin(); !shared_list.IsEnd(); v = shared_list.Next()) {
						if (v != vehicle_id) {
							copy_orders_vid = v;
							break;
						}
					}
					if (AIVehicle.IsValidVehicle(copy_orders_vid)) {
						if (AIOrder.CopyOrders(vehicle_id, copy_orders_vid)) {
							/* Remove conditional orders */
							if (!RemoveConditionalOrders(vehicle_id)) {
								AILog.Info("Failed to remove conditional orders from " + vehicle_name + " when preparing to send it to depot.");
//								AIController.Break(" ");
								return 0;
							} else {
								/* Make the ship stop at depot when executing depot orders. */
								local depotstop1 = AIOrder.SetOrderFlags(vehicle_id, 0, depot_order_flags);
								local depotstop2 = AIOrder.SetOrderFlags(vehicle_id, GetSecondDepotOrderIndex(vehicle_id), depot_order_flags);
								if (!depotstop1 && !depotstop2) {
									AILog.Error("Failed to send " + vehicle_name + " to depot.");
//									AIController.Break(" ");
									return 0;
								}
							}
						} else {
							AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//							AIController.Break(" ");
							return 0;
						}
					} else {
						AILog.Error("Failed to copy orders from " + AIVehicle.GetName(copy_orders_vid) + " to " + vehicle_name + " when unsharing orders");
//						AIController.Break(" ");
						return 0;
					}
				}
			}
			m_last_vehicle_removed = AIDate.GetCurrentDate();

			AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)) + " has been sent to its depot!");

			return 1;
		}

		return 0;
	}

	function SendNegativeProfitVehiclesToDepot()
	{
		if (m_last_vehicle_added <= 0 || AIDate.GetCurrentDate() - m_last_vehicle_added <= 30) return;
//		AILog.Info("SendNegativeProfitVehiclesToDepot . m_last_vehicle_added = " + m_last_vehicle_added + "; " + AIDate.GetCurrentDate() + " - " + m_last_vehicle_added + " = " + (AIDate.GetCurrentDate() - m_last_vehicle_added) + " < 45" + " - " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)));

//		if (AIDate.GetCurrentDate() - m_last_vehicle_removed <= 30) return;

		ValidateVehicleList();

		foreach (vehicle, _ in m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730 && AIVehicle.GetProfitLastYear(vehicle) < 0) {
				if (SendMoveVehicleToDepot(vehicle)) {
					if (!AIGroup.MoveVehicle(m_sentToDepotWaterGroup[0], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotWaterGroup[0]);
					} else {
						m_vehicle_list.rawset(vehicle, 0);
					}
					return;
				}
			}
		}
	}

	function SendLowProfitVehiclesToDepot(maxAllRoutesProfit)
	{
		ValidateVehicleList();
		local vehicleList = AIList();
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetAge(vehicle) > 730) {
				vehicleList.AddItem(vehicle, 0);
			}
		}
		if (vehicleList.IsEmpty()) return;

		local cargo_type = Utils.GetCargoType(m_cargo_class);
		local station1 = AIStation.GetStationID(m_dockFrom);
		local station2 = AIStation.GetStationID(m_dockTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

//		AILog.Info("cargoWaiting = " + (cargoWaiting1 + cargoWaiting2));
		if (cargoWaiting1 + cargoWaiting2 < 150) {
			for (local vehicle = vehicleList.Begin(); !vehicleList.IsEnd(); vehicle = vehicleList.Next()) {
				if (AIVehicle.GetProfitLastYear(vehicle) < (maxAllRoutesProfit / 6)) {
					if (SendMoveVehicleToDepot(vehicle)) {
						if (!AIGroup.MoveVehicle(m_sentToDepotWaterGroup[0], vehicle)) {
							AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotWaterGroup[0]);
						} else {
							m_vehicle_list.rawset(vehicle, 0);
						}
					}
				}
			}
		}
	}

	function SellVehiclesInDepot()
	{
		local sent_to_depot_list = this.SentToDepotList(0);

		for (local vehicle = sent_to_depot_list.Begin(); !sent_to_depot_list.IsEnd(); vehicle = sent_to_depot_list.Next()) {
			if (m_vehicle_list.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local vehicle_name = AIVehicle.GetName(vehicle);
				DeleteSellVehicle(vehicle);

				AILog.Info(vehicle_name + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)) + " has been sold!");
			}
		}

		sent_to_depot_list = this.SentToDepotList(1);

		for (local vehicle = sent_to_depot_list.Begin(); !sent_to_depot_list.IsEnd(); vehicle = sent_to_depot_list.Next()) {
			if (m_vehicle_list.rawin(vehicle) && AIVehicle.IsStoppedInDepot(vehicle)) {
				local skip_to_order = AIOrder.ResolveOrderPosition(vehicle, AIOrder.ORDER_CURRENT);
				DeleteSellVehicle(vehicle);

				local renewed_vehicle = AddVehicle(true);
				if (renewed_vehicle != null) {
					AIOrder.SkipToOrder(renewed_vehicle, skip_to_order);
					AIVehicle.StartStopVehicle(renewed_vehicle);
					AILog.Info(AIVehicle.GetName(renewed_vehicle) + " on route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)) + " has been renewed!");
				}
			}
		}
	}

	function GetGroupUsage()
	{
		local max_capacity = 0;
		local used_capacity = 0;
		local cargo_type = Utils.GetCargoType(m_cargo_class);
		foreach (v, _ in m_vehicle_list) {
			if (AIVehicle.GetGroupID(v) == m_group) {
				max_capacity += AIVehicle.GetCapacity(v, cargo_type);
				used_capacity += AIVehicle.GetCargoLoad(v, cargo_type);
			}
		}
		if (max_capacity == 0) return 0;
		return 100 * used_capacity / max_capacity;
	}

	function AddRemoveVehicleToRoute(maxed_out_num_vehs)
	{
		if (!m_active_route) {
			return 0;
		}

		if (m_last_vehicle_added <= 0) {
			return AddVehiclesToNewRoute(m_cargo_class);
		}

		if (MAX_VEHICLE_COUNT_MODE != AIController.GetSetting("water_cap_mode")) {
			MAX_VEHICLE_COUNT_MODE = AIController.GetSetting("water_cap_mode");
//			AILog.Info("MAX_VEHICLE_COUNT_MODE = " + MAX_VEHICLE_COUNT_MODE);
		}

		if (AIDate.GetCurrentDate() - m_last_vehicle_added < 90) {
			return 0;
		}

		local optimal_vehicle_count = OptimalVehicleCount();
		ValidateVehicleList();
		local numvehicles = m_vehicle_list.len();
		local numvehicles_before = numvehicles;

		if (MAX_VEHICLE_COUNT_MODE != 2 && numvehicles >= optimal_vehicle_count && maxed_out_num_vehs) {
			return 0;
		}

		local cargo_type = Utils.GetCargoType(m_cargo_class);
		local station1 = AIStation.GetStationID(m_dockFrom);
		local station2 = AIStation.GetStationID(m_dockTo);
		local cargoWaiting1via2 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station1, station2, cargo_type);
		local cargoWaiting1any = AIStation.GetCargoWaitingVia(station1, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting1 = cargoWaiting1via2 + cargoWaiting1any;
		local cargoWaiting2via1 = AICargo.GetDistributionType(cargo_type) == AICargo.DT_MANUAL ? 0 : AIStation.GetCargoWaitingVia(station2, station1, cargo_type);
		local cargoWaiting2any = AIStation.GetCargoWaitingVia(station2, AIStation.STATION_INVALID, cargo_type);
		local cargoWaiting2 = cargoWaiting2via1 + cargoWaiting2any;

		local engine_capacity = ::caches.GetCapacity(this.m_engine, cargo_type);
		local group_usage = GetGroupUsage();
//		AILog.Info(AIGroup.GetName(this.m_group) + ": usage = " + group_usage + "; engine_capacity = " + engine_capacity + "; cargoWaiting1 = " + cargoWaiting1 + "; cargoWaiting2 = " + cargoWaiting2);

		if ((cargoWaiting1 > engine_capacity || cargoWaiting2 > engine_capacity) && group_usage > 66) {
			local number_to_add = max(1, (cargoWaiting1 > cargoWaiting2 ? cargoWaiting1 : cargoWaiting2) / engine_capacity);
			local routedist = AIMap.DistanceManhattan(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo));
			while (number_to_add) {
				number_to_add--;
				local added_vehicle = AddVehicle(true);
				if (added_vehicle != null) {
					numvehicles++;
					local skipped_order = false;
					if (cargoWaiting1 > cargoWaiting2) {
						cargoWaiting1 -= engine_capacity;
					} else {
						cargoWaiting2 -= engine_capacity;
						AIOrder.SkipToOrder(added_vehicle, GetSecondDepotOrderIndex(added_vehicle));
						skipped_order = true;
					}
					AIVehicle.StartStopVehicle(added_vehicle);
					AILog.Info("Added " + AIEngine.GetName(this.m_engine) + " on existing route from " + AIBaseStation.GetName(skipped_order ? station2 : station1) + " to " + AIBaseStation.GetName(skipped_order ? station1 : station2) + "! (" + numvehicles + (MAX_VEHICLE_COUNT_MODE != 2 ? "/" + optimal_vehicle_count : "") + " ship" + (numvehicles != 1 ? "s" : "") + ", " + routedist + " manhattan tiles)");
					if (numvehicles >= MAX_VEHICLE_COUNT_MODE != 2 ? 1 : optimal_vehicle_count) {
						number_to_add = 0;
					}
				}
			}
		}
		return numvehicles - numvehicles_before;
	}

	function RenewVehicles()
	{
		ValidateVehicleList();
		local engine_price = AIEngine.GetPrice(this.m_engine);
		local count = 1 + AIGroup.GetNumVehicles(m_sentToDepotWaterGroup[1], AIVehicle.VT_WATER);

		foreach (vehicle, _ in this.m_vehicle_list) {
//			local vehicle_engine = AIVehicle.GetEngineType(vehicle);
//			if (AIGroup.GetEngineReplacement(m_group, vehicle_engine) != m_engine) {
//				AIGroup.SetAutoReplace(m_group, vehicle_engine, m_engine);
//			}
			if (AIVehicle.GetAgeLeft(vehicle) <= 365 || AIVehicle.GetEngineType(vehicle) != this.m_engine && Utils.HasMoney(2 * engine_price * count)) {
				if (SendMoveVehicleToDepot(vehicle)) {
					count++;
					if (!AIGroup.MoveVehicle(m_sentToDepotWaterGroup[1], vehicle)) {
						AILog.Error("Failed to move " + AIVehicle.GetName(vehicle) + " to " + m_sentToDepotWaterGroup[1]);
					} else {
						m_vehicle_list.rawset(vehicle, 1);
					}
				}
			}
		}
	}

	function RemoveIfUnserviced()
	{
		ValidateVehicleList();
		if (this.m_vehicle_list.len() == 0 && (((!AIEngine.IsValidEngine(m_engine) || !AIEngine.IsBuildable(m_engine)) && m_last_vehicle_added == 0) ||
				(AIDate.GetCurrentDate() - m_last_vehicle_added >= 90) && m_last_vehicle_added > 0)) {
			m_active_route = false;

			local dockFrom_name = AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom));
			::scheduledRemovalsTable.Ship.rawset(m_dockFrom, 0);

			local dockTo_name = AIBaseStation.GetName(AIStation.GetStationID(m_dockTo));
			::scheduledRemovalsTable.Ship.rawset(m_dockTo, 0);

			::scheduledRemovalsTable.Ship.rawset(m_depot_tile, 0);

			if (AIGroup.IsValidGroup(m_group)) {
				AIGroup.DeleteGroup(m_group);
			}
			AILog.Warning("Removing unserviced water route from " + dockFrom_name + " to " + dockTo_name);
			return true;
		}
		return false;
	}

	function GroupVehicles()
	{
		foreach (vehicle, _ in this.m_vehicle_list) {
			if (AIVehicle.GetGroupID(vehicle) != AIGroup.GROUP_DEFAULT && AIVehicle.GetGroupID(vehicle) != m_sentToDepotWaterGroup[0] && AIVehicle.GetGroupID(vehicle) != m_sentToDepotWaterGroup[1]) {
				if (!AIGroup.IsValidGroup(m_group)) {
					m_group = AIVehicle.GetGroupID(vehicle);
					break;
				}
			}
		}

		if (!AIGroup.IsValidGroup(m_group)) {
			m_group = AIGroup.CreateGroup(AIVehicle.VT_WATER, AIGroup.GROUP_INVALID);
			if (AIGroup.IsValidGroup(m_group)) {
				AIGroup.SetName(m_group, (m_cargo_class == AICargo.CC_PASSENGERS ? "P" : "M") + AIMap.DistanceManhattan(Utils.GetDockDockingTile(m_dockFrom), Utils.GetDockDockingTile(m_dockTo)) + ": " + m_dockFrom + " - " + m_dockTo);
				AILog.Info("Created " + AIGroup.GetName(m_group) + " for water route from " + AIBaseStation.GetName(AIStation.GetStationID(m_dockFrom)) + " to " + AIBaseStation.GetName(AIStation.GetStationID(m_dockTo)));
			}
		}

		return m_group;
	}

	function SaveRoute()
	{
		return [m_city_from, m_city_to, m_dockFrom, m_dockTo, m_depot_tile, m_cargo_class, m_last_vehicle_added, m_last_vehicle_removed, m_active_route, m_sentToDepotWaterGroup, m_group];
	}

	function LoadRoute(data)
	{
		local city_from = data[0];
		local city_to = data[1];
		local dockFrom = data[2];
		local dockTo = data[3];
		local depot_tile = data[4];
		local cargo_class = data[5];

		local sentToDepotWaterGroup = data[9];

		local route = ShipRoute(city_from, city_to, dockFrom, dockTo, depot_tile, cargo_class, sentToDepotWaterGroup, 1);

		route.m_last_vehicle_added = data[6];
		route.m_last_vehicle_removed = data[7];
		route.m_active_route = data[8];
		route.m_group = data[10];

		local vehicleList = AIVehicleList_Station(AIStation.GetStationID(route.m_dockFrom));
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				route.m_vehicle_list.rawset(v, 2);
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotWaterGroup[0]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				if (route.m_vehicle_list.rawin(v)) {
					route.m_vehicle_list.rawset(v, 0);
				}
			}
		}

		vehicleList = AIVehicleList_Group(route.m_sentToDepotWaterGroup[1]);
		for (local v = vehicleList.Begin(); !vehicleList.IsEnd(); v = vehicleList.Next()) {
			if (AIVehicle.GetVehicleType(v) == AIVehicle.VT_WATER) {
				if (route.m_vehicle_list.rawin(v)) {
					route.m_vehicle_list.rawset(v, 1);
				}
			}
		}

		return route;
	}
};
