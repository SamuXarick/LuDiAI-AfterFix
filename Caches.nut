class Caches
{
	/* These are saved */
	m_pass_capacities_list = {};
	m_mail_capacities_list = {};
	m_secondary_capacities_list = {}; // secondary capacity for a pass/mail aircraft
	m_depot_tile = AIMap.TILE_INVALID;
	m_vehicle_lengths = {}; // vehicle length of rail engines
	m_attach_list = {}; // engine/wagon attachment results of rail engines
	m_costs_with_refit = {};

	/* This is not saved */
	m_my_company_id = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);

	function GetBuildWithRefitCapacity(depot, engine, cargo_type)
	{
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
			if (!this.m_pass_capacities_list.rawin(engine)) {
				this.m_pass_capacities_list.rawset(engine, AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo_type));
//				AILog.Info("Added engine " + AIEngine.GetName(engine) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo_type) + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_PASSENGERS)));
			}
			return this.m_pass_capacities_list.rawget(engine);
		} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
			if (!this.m_mail_capacities_list.rawin(engine)) {
				this.m_mail_capacities_list.rawset(engine, AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo_type));
//				AILog.Info("Added engine " + AIEngine.GetName(engine) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo_type) + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_MAIL)));
			}
			return this.m_mail_capacities_list.rawget(engine);
		}
		throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in GetBuildWithRefitCapacity";
	}

	function GetBuildWithRefitSecondaryCapacity(hangar, engine)
	{
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AIEngine.GetVehicleType(engine) != AIVehicle.VT_AIR) return 0;
		if (!AICargo.IsValidCargo(Utils.GetCargoType(AICargo.CC_MAIL))) return 0;

		if (!this.m_secondary_capacities_list.rawin(engine)) {
			local pass_capacity = this.GetBuildWithRefitCapacity(hangar, engine, Utils.GetCargoType(AICargo.CC_PASSENGERS));
			local mail_capacity = this.GetBuildWithRefitCapacity(hangar, engine, Utils.GetCargoType(AICargo.CC_MAIL));
			this.m_secondary_capacities_list.rawset(engine, mail_capacity - pass_capacity);
//			AILog.Info("Capacity for " + AIEngine.GetName(engine) + ": " + pass_capacity + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_PASSENGERS)) + ", " + (mail_capacity - pass_capacity) + " " + AICargo.GetCargoLabel(Utils.GetCargoType(AICargo.CC_MAIL)));
		}
		return this.m_secondary_capacities_list.rawget(engine);
	}

	function GetCapacity(engine, cargo_type)
	{
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
			if (!this.m_pass_capacities_list.rawin(engine)) {
				return AIEngine.GetCapacity(engine);
			}
			return this.m_pass_capacities_list.rawget(engine);
		} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
			if (!this.m_mail_capacities_list.rawin(engine)) {
				return AIEngine.GetCapacity(engine);
			}
			return this.m_mail_capacities_list.rawget(engine);
		}
		throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in GetCapacity";
	}

	function GetSecondaryCapacity(engine)
	{
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AIEngine.GetVehicleType(engine) == AIVehicle.VT_ROAD) return 0;

		if (!this.m_secondary_capacities_list.rawin(engine)) {
			return 0;
		}
		return this.m_secondary_capacities_list.rawget(engine);
	}

	function GetExistingRailDepot(rail_type)
	{
		if (!AIRail.IsRailDepotTile(this.m_depot_tile) || AITile.GetOwner(this.m_depot_tile) != ::caches.m_my_company_id || AIRail.GetRailType(this.m_depot_tile) != rail_type) {
			this.m_depot_tile = AIMap.TILE_INVALID;
			local depot_list = AIDepotList(AITile.TRANSPORT_RAIL);
			foreach (depot in depot_list) {
				if (AIRail.GetRailType(depot) != rail_type) continue;
				this.m_depot_tile = depot;
				break;
			}
		}
		return this.m_depot_tile;
	}

	function GetLength(engine, cargo_type, depot = AIMap.TILE_INVALID)
	{
		if (!AIEngine.IsValidEngine(engine) || !AIEngine.IsBuildable(engine))
		if (AIEngine.GetVehicleType(engine) != AIVehicle.VT_RAIL) return -1;

		local rail_type = AIEngine.GetRailType(engine);
		if (!this.m_vehicle_lengths.rawin(engine)) {
			local result = false;
			if (!AIRail.IsRailDepotTile(depot)) {
				depot = this.GetExistingRailDepot(rail_type);
			}

			if (AIRail.IsRailDepotTile(depot)) {
				local v = TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo_type);
				if (AIVehicle.IsValidVehicle(v)) {
					local vehicle_length = AIVehicle.GetLength(v);
					this.m_vehicle_lengths.rawset(engine, vehicle_length);
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
		return this.m_vehicle_lengths.rawget(engine);
	}

	function CanAttachToEngine(wagon, engine, cargo_type, rail_type, depot = AIMap.TILE_INVALID)
	{
		if (!AIEngine.IsValidEngine(engine) || !AIEngine.IsBuildable(engine)) return false;
		if (!AIEngine.IsWagon(wagon) || AIEngine.IsWagon(engine)) return false;

		AIRail.SetCurrentRailType(rail_type);
		local cargo_engine_wagon = (cargo_type << 32) | (engine << 16) | wagon;
		if (this.m_attach_list.rawin(cargo_engine_wagon)) {
			return this.m_attach_list.rawget(cargo_engine_wagon);
		}

		/* it's not in the list yet */
		local result = null;
		if (!AIRail.IsRailDepotTile(depot)) {
			depot = this.GetExistingRailDepot(rail_type);
		}

		if (AIRail.IsRailDepotTile(depot)) {
			local cost = AIAccounting();
			local v = TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo_type);
//			local error_v = AIError.GetLastErrorString();
			local price = cost.GetCosts();
			local engine_cargo = (engine << 16) | cargo_type;
			if (!this.m_costs_with_refit.rawin(engine_cargo)) {
				this.m_costs_with_refit.rawset(engine_cargo, price);
			}
			cost.ResetCosts();
			if (AIVehicle.IsValidVehicle(v)) {
				local v_cap = AIVehicle.GetCapacity(v, cargo_type);
				if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
					if (!this.m_pass_capacities_list.rawin(engine)) {
						this.m_pass_capacities_list.rawset(engine, v_cap);
					}
				} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
					if (!this.m_mail_capacities_list.rawin(engine)) {
						this.m_mail_capacities_list.rawset(engine, v_cap);
					}
				} else {
					throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in CanAttachToEngine";
				}
				if (!this.m_vehicle_lengths.rawin(engine)) {
					local length = AIVehicle.GetLength(v);
					this.m_vehicle_lengths.rawset(v, length);
				}
			}
			local w = TestBuildVehicleWithRefit().TryBuild(depot, wagon, cargo_type);
//			local error_w = AIError.GetLastErrorString();
			price = cost.GetCosts();
			local wagon_cargo = (wagon << 16) | cargo_type;
			if (!this.m_costs_with_refit.rawin(wagon_cargo)) {
				this.m_costs_with_refit.rawset(wagon_cargo, price);
			}
			if (AIVehicle.IsValidVehicle(w)) {
				local w_cap = AIVehicle.GetCapacity(w, cargo_type);
				if (AICargo.HasCargoClass(cargo_type, AICargo.CC_PASSENGERS)) {
					if (!this.m_pass_capacities_list.rawin(wagon)) {
						this.m_pass_capacities_list.rawset(wagon, w_cap);
					}
				} else if (AICargo.HasCargoClass(cargo_type, AICargo.CC_MAIL)) {
					if (!this.m_mail_capacities_list.rawin(wagon)) {
						this.m_mail_capacities_list.rawset(wagon, w_cap);
					}
				} else {
					throw "cargo_type " + cargo_type + "does not belong to either CargoClass AICargo.CC_PASSENGERS nor AICargo.CC_MAIL in CanAttachToEngine";
				}
				if (!this.m_vehicle_lengths.rawin(wagon)) {
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
//				if (!AIVehicle.IsValidVehicle(v)) AILog.Error("Failed to build engine with refit to check if it can attach to wagon. " + error_v);
//				if (!AIVehicle.IsValidVehicle(w)) AILog.Error("Failed to build wagon with refit to check if it can attach to engine. " + error_w);
				if (AIVehicle.IsValidVehicle(v)) AIVehicle.SellVehicle(v);
				if (AIVehicle.IsValidVehicle(w)) AIVehicle.SellVehicle(w);
				/* Failed to build one of the vehicles. Assume that it can attach. */
				return true;
			}
		} else {
			/* No depot for testing. Assume that it can attach. */
			return true;
		}

		if (result != null) this.m_attach_list.rawset(cargo_engine_wagon, result);
//		AILog.Info(AIEngine.GetName(engine) + " -- " + AIEngine.GetName(wagon) + " ? " + result);
		return result == true;
	}

	function GetCostWithRefit(engine, cargo_type, depot = AIMap.TILE_INVALID)
	{
		if (!AIEngine.IsValidEngine(engine) || !AIEngine.IsBuildable(engine)) return -1;

		local rail_type = AIEngine.GetRailType(engine);
		local engine_cargo = (engine << 16) | cargo_type;
		if (!this.m_costs_with_refit.rawin(engine_cargo)) {
			local veh_type = AIEngine.GetVehicleType(engine);
			if (veh_type == AIVehicle.VT_RAIL) {
				local price = -1;
				if (!AIRail.IsRailDepotTile(depot)) {
					depot = this.GetExistingRailDepot(rail_type);
				}

				if (AIRail.IsRailDepotTile(depot)) {
					local cost = AIAccounting();
					local v = AITestMode() && TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo_type);
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
		return [this.m_depot_tile, this.m_pass_capacities_list, this.m_mail_capacities_list, this.m_secondary_capacities_list, this.m_vehicle_lengths, this.m_attach_list, this.m_costs_with_refit];
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
	}
};
