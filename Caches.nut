class Caches
{
	/* These are saved */
	m_pass_capacities_list = {};
	m_mail_capacities_list = {};
	m_secondary_capacities_list = {}; // secondary capacity for a pass/mail aircraft
	m_depot_tile = AIMap.TILE_INVALID;
	m_vehicle_lengths = {}; // vehicle length of rail engines
	m_attach_list = {}; // engine_id/wagon_id attachment results of rail engines
	m_costs_with_refit = {};
	m_reserved_money = 0;

	/* These are not saved */
	m_my_company_id = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	m_cargo_type_list = AICargoList();
	m_cargo_classes = [AICargo.CC_PASSENGERS, AICargo.CC_MAIL];

	constructor()
	{
		this.m_cargo_type_list.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
	}

	function GetBuildWithRefitCapacity(depot_tile, engine_id, cargo_type)
	{
//		if (!AIEngine.IsBuildable(engine_id)) return 0;
		if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
			if (!this.m_pass_capacities_list.rawin(engine_id)) {
				this.m_pass_capacities_list.rawset(engine_id, AIVehicle.GetBuildWithRefitCapacity(depot_tile, engine_id, cargo_type));
//				AILog.Info("Added engine_id " + AIEngine.GetName(engine_id) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot_tile, engine_id, cargo_type) + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_PASSENGERS)));
			}
			return this.m_pass_capacities_list.rawget(engine_id);
		} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
			if (!this.m_mail_capacities_list.rawin(engine_id)) {
				this.m_mail_capacities_list.rawset(engine_id, AIVehicle.GetBuildWithRefitCapacity(depot_tile, engine_id, cargo_type));
//				AILog.Info("Added engine_id " + AIEngine.GetName(engine_id) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot_tile, engine_id, cargo_type) + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_MAIL)));
			}
			return this.m_mail_capacities_list.rawget(engine_id);
		}
		throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in GetBuildWithRefitCapacity";
	}

	function GetBuildWithRefitSecondaryCapacity(hangar_tile, engine_id)
	{
//		if (!AIEngine.IsBuildable(engine_id)) return 0;
		if (AIEngine.GetVehicleType(engine_id) != AIVehicle.VT_AIR) return 0;
		if (!AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) return 0;

		if (!this.m_secondary_capacities_list.rawin(engine_id)) {
			local pass_capacity = this.GetBuildWithRefitCapacity(hangar_tile, engine_id, Utils.GetCargoType(AICargo.CC_PASSENGERS));
			local mail_capacity = this.GetBuildWithRefitCapacity(hangar_tile, engine_id, Utils.GetCargoType(AICargo.CC_MAIL));
			this.m_secondary_capacities_list.rawset(engine_id, mail_capacity - pass_capacity);
//			AILog.Info("Capacity for " + AIEngine.GetName(engine_id) + ": " + pass_capacity + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_PASSENGERS)) + ", " + (mail_capacity - pass_capacity) + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_MAIL)));
		}
		return this.m_secondary_capacities_list.rawget(engine_id);
	}

	function GetCapacity(engine_id, cargo_type)
	{
//		if (!AIEngine.IsBuildable(engine_id)) return 0;
		if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
			if (!this.m_pass_capacities_list.rawin(engine_id)) {
				return AIEngine.GetCapacity(engine_id);
			}
			return this.m_pass_capacities_list.rawget(engine_id);
		} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
			if (!this.m_mail_capacities_list.rawin(engine_id)) {
				return AIEngine.GetCapacity(engine_id);
			}
			return this.m_mail_capacities_list.rawget(engine_id);
		}
		throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in GetCapacity";
	}

	function GetSecondaryCapacity(engine_id)
	{
//		if (!AIEngine.IsBuildable(engine_id)) return 0;
		if (AIEngine.GetVehicleType(engine_id) == AIVehicle.VT_ROAD) return 0;

		if (!this.m_secondary_capacities_list.rawin(engine_id)) {
			return 0;
		}
		return this.m_secondary_capacities_list.rawget(engine_id);
	}

	function GetExistingRailDepot(rail_type)
	{
		if (!AIRail.IsRailDepotTile(this.m_depot_tile) || AITile.GetOwner(this.m_depot_tile) != ::caches.m_my_company_id || AIRail.GetRailType(this.m_depot_tile) != rail_type) {
			this.m_depot_tile = AIMap.TILE_INVALID;
			local depot_list = AIDepotList(AITile.TRANSPORT_RAIL);
			foreach (depot_tile in depot_list) {
				if (AIRail.GetRailType(depot_tile) != rail_type) continue;
				this.m_depot_tile = depot_tile;
				break;
			}
		}
		return this.m_depot_tile;
	}

	function GetLength(engine_id, cargo_type, depot_tile = AIMap.TILE_INVALID)
	{
		if (!AIEngine.IsValidEngine(engine_id) || !AIEngine.IsBuildable(engine_id))
		if (AIEngine.GetVehicleType(engine_id) != AIVehicle.VT_RAIL) return -1;

		local rail_type = AIEngine.GetRailType(engine_id);
		if (!this.m_vehicle_lengths.rawin(engine_id)) {
			local result = false;
			if (!AIRail.IsRailDepotTile(depot_tile)) {
				depot_tile = this.GetExistingRailDepot(rail_type);
			}

			if (AIRail.IsRailDepotTile(depot_tile)) {
				local v = TestBuildVehicleWithRefit().TryBuild(depot_tile, engine_id, cargo_type);
				if (AIVehicle.IsValidVehicle(v)) {
					local vehicle_length = AIVehicle.GetLength(v);
					this.m_vehicle_lengths.rawset(engine_id, vehicle_length);
					AIVehicle.SellVehicle(v);
					result = true;
//				} else {
//					AILog.Error("Failed to build vehicle with refit to check its length");
				}
			}

			if (!result) {
				/* Assume default length of 8 */
				return 8;
			}
		}
		return this.m_vehicle_lengths.rawget(engine_id);
	}

	function CanAttachToEngine(wagon_id, engine_id, cargo_type, rail_type, depot_tile = AIMap.TILE_INVALID)
	{
		if (!AIEngine.IsValidEngine(engine_id) || !AIEngine.IsBuildable(engine_id)) return false;
		if (!AIEngine.IsWagon(wagon_id) || AIEngine.IsWagon(engine_id)) return false;

		AIRail.SetCurrentRailType(rail_type);
		local cargo_engine_wagon = (cargo_type << 32) | (engine_id << 16) | wagon_id;
		if (this.m_attach_list.rawin(cargo_engine_wagon)) {
			return this.m_attach_list.rawget(cargo_engine_wagon);
		}

		/* it's not in the list yet */
		local result = null;
		if (!AIRail.IsRailDepotTile(depot_tile)) {
			depot_tile = this.GetExistingRailDepot(rail_type);
		}

		if (AIRail.IsRailDepotTile(depot_tile)) {
			local cost = AIAccounting();
			local v = TestBuildVehicleWithRefit().TryBuild(depot_tile, engine_id, cargo_type);
//			local error_v = AIError.GetLastErrorString();
			local price = cost.GetCosts();
			local engine_cargo = (engine_id << 16) | cargo_type;
			if (!this.m_costs_with_refit.rawin(engine_cargo)) {
				this.m_costs_with_refit.rawset(engine_cargo, price);
			}
			cost.ResetCosts();
			if (AIVehicle.IsValidVehicle(v)) {
				local v_cap = AIVehicle.GetCapacity(v, cargo_type);
				if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
					if (!this.m_pass_capacities_list.rawin(engine_id)) {
						this.m_pass_capacities_list.rawset(engine_id, v_cap);
					}
				} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
					if (!this.m_mail_capacities_list.rawin(engine_id)) {
						this.m_mail_capacities_list.rawset(engine_id, v_cap);
					}
				} else {
					throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in CanAttachToEngine";
				}
				if (!this.m_vehicle_lengths.rawin(engine_id)) {
					local length = AIVehicle.GetLength(v);
					this.m_vehicle_lengths.rawset(v, length);
				}
			}
			local w = TestBuildVehicleWithRefit().TryBuild(depot_tile, wagon_id, cargo_type);
//			local error_w = AIError.GetLastErrorString();
			price = cost.GetCosts();
			local wagon_cargo = (wagon_id << 16) | cargo_type;
			if (!this.m_costs_with_refit.rawin(wagon_cargo)) {
				this.m_costs_with_refit.rawset(wagon_cargo, price);
			}
			if (AIVehicle.IsValidVehicle(w)) {
				local w_cap = AIVehicle.GetCapacity(w, cargo_type);
				if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
					if (!this.m_pass_capacities_list.rawin(wagon_id)) {
						this.m_pass_capacities_list.rawset(wagon_id, w_cap);
					}
				} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
					if (!this.m_mail_capacities_list.rawin(wagon_id)) {
						this.m_mail_capacities_list.rawset(wagon_id, w_cap);
					}
				} else {
					throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in CanAttachToEngine";
				}
				if (!this.m_vehicle_lengths.rawin(wagon_id)) {
					local length = AIVehicle.GetLength(w);
					this.m_vehicle_lengths.rawset(w, length);
				}
			}
			if (AIVehicle.IsValidVehicle(v) && AIVehicle.IsValidVehicle(w)) {
				local res1 = AIVehicle.MoveWagon(w, 0, v, 0);
				local res2 = false;
				if (res1) {
					res2 = AITestMode() && AIVehicle.StartStopVehicle(v);
				}
				result = res1 && res2;
				AIVehicle.SellVehicle(v);
				if (!res1) AIVehicle.SellVehicle(w);
			} else {
//				if (!AIVehicle.IsValidVehicle(v)) AILog.Error("Failed to build engine_id with refit to check if it can attach to wagon_id. " + error_v);
//				if (!AIVehicle.IsValidVehicle(w)) AILog.Error("Failed to build wagon_id with refit to check if it can attach to engine_id. " + error_w);
				if (AIVehicle.IsValidVehicle(v)) AIVehicle.SellVehicle(v);
				if (AIVehicle.IsValidVehicle(w)) AIVehicle.SellVehicle(w);
				/* Failed to build one of the vehicles. Assume that it can attach. */
				return true;
			}
		} else {
			/* No depot_tile for testing. Assume that it can attach. */
			return true;
		}

		if (result != null) this.m_attach_list.rawset(cargo_engine_wagon, result);
//		AILog.Info(AIEngine.GetName(engine_id) + " -- " + AIEngine.GetName(wagon_id) + " ? " + result);
		return result == true;
	}

	function GetCostWithRefit(engine_id, cargo_type, depot_tile = AIMap.TILE_INVALID)
	{
		if (!AIEngine.IsValidEngine(engine_id) || !AIEngine.IsBuildable(engine_id)) return -1;

		local rail_type = AIEngine.GetRailType(engine_id);
		local engine_cargo = (engine_id << 16) | cargo_type;
		if (!this.m_costs_with_refit.rawin(engine_cargo)) {
			local veh_type = AIEngine.GetVehicleType(engine_id);
			if (veh_type == AIVehicle.VT_RAIL) {
				local price = -1;
				if (!AIRail.IsRailDepotTile(depot_tile)) {
					depot_tile = this.GetExistingRailDepot(rail_type);
				}

				if (AIRail.IsRailDepotTile(depot_tile)) {
					local cost = AIAccounting();
					local v = AITestMode() && TestBuildVehicleWithRefit().TryBuild(depot_tile, engine_id, cargo_type);
					price = cost.GetCosts();
					if (price <= 0) {
//						AILog.Error("Retrieved a price of zero for a vehicle with refit");
					} else {
						this.m_costs_with_refit.rawset(engine_cargo, price);
					}
				}
				return price;
			} else {
				throw "veh_type " + veh_type + "unexpected in GetCostWithRefit";
			}
		}
		return this.m_costs_with_refit.rawget(engine_cargo);
	}

	function SaveCaches()
	{
		return [this.m_depot_tile, this.m_pass_capacities_list, this.m_mail_capacities_list, this.m_secondary_capacities_list, this.m_vehicle_lengths, this.m_attach_list, this.m_costs_with_refit, this.m_reserved_money];
	}

	function LoadCaches(data)
	{
		this.m_depot_tile = data[0];
		this.m_pass_capacities_list = data[1];
		this.m_mail_capacities_list = data[2];
		this.m_secondary_capacities_list = data[3];
		this.m_vehicle_lengths = data[4];
		this.m_attach_list = data[5];
		this.m_costs_with_refit = data[6];
		this.m_reserved_money = data[7];
	}
};
