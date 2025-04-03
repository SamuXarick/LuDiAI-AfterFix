class Caches {
	_depot_tile = AIMap.TILE_INVALID;

	pass_capacities_list = {};
	mail_capacities_list = {};
	secondary_capacities_list = {}; // secondary capacity for a pass/mail aircraft
	vehicle_lengths = {}; // vehicle length of rail engines
	attach_list = {}; // engine/wagon attachment results of rail engines
	costs_with_refit = {};

	function GetBuildWithRefitCapacity(depot, engine, cargo);
	function GetBuildWithRefitSecondaryCapacity(hangar, engine);
	function GetCapacity(engine, cargo);
	function GetSecondaryCapacity(engine);
	function GetExistingRailDepot(railtype);
	function GetLength(engine, cargo, depot = AIMap.TILE_INVALID);
	function CanAttachToEngine(wagon, engine, cargo, railtype, depot = AIMap.TILE_INVALID);
	function GetCostWithRefit(engine, cargo, depot = AIMap.TILE_INVALID);

	function GetBuildWithRefitCapacity(depot, engine, cargo) {
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {
			if (!this.pass_capacities_list.rawin(engine)) {
				this.pass_capacities_list.rawset(engine, AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo));
//				AILog.Info("Added engine " + AIEngine.GetName(engine) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo) + " " + AICargo.GetCargoLabel(Utils.GetCargoID(AICargo.CC_PASSENGERS)));
			}
			return this.pass_capacities_list.rawget(engine);
		} else if (AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			if (!this.mail_capacities_list.rawin(engine)) {
				this.mail_capacities_list.rawset(engine, AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo));
//				AILog.Info("Added engine " + AIEngine.GetName(engine) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo) + " " + AICargo.GetCargoLabel(Utils.GetCargoID(AICargo.CC_MAIL)));
			}
			return this.mail_capacities_list.rawget(engine);
		}
		assert(false);
	}

	function GetBuildWithRefitSecondaryCapacity(hangar, engine) {
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AIEngine.GetVehicleType(engine) == AIVehicle.VT_ROAD) return 0;
		if (!AICargo.IsValidCargo(Utils.GetCargoID(AICargo.CC_MAIL))) return 0;

		if (!this.secondary_capacities_list.rawin(engine)) {
			local pass_capacity = this.GetBuildWithRefitCapacity(hangar, engine, Utils.GetCargoID(AICargo.CC_PASSENGERS));
			local mail_capacity = this.GetBuildWithRefitCapacity(hangar, engine, Utils.GetCargoID(AICargo.CC_MAIL));
			this.secondary_capacities_list.rawset(engine, mail_capacity - pass_capacity);
//			AILog.Info("Capacity for " + AIEngine.GetName(engine) + ": " + pass_capacity + " " + AICargo.GetCargoLabel(Utils.GetCargoID(AICargo.CC_PASSENGERS)) + ", " + (mail_capacity - pass_capacity) + " " + AICargo.GetCargoLabel(Utils.GetCargoID(AICargo.CC_MAIL)));
		}
		return this.secondary_capacities_list.rawget(engine);
	}

	function GetCapacity(engine, cargo) {
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {
			if (!this.pass_capacities_list.rawin(engine)) {
				return AIEngine.GetCapacity(engine);
			}
			return this.pass_capacities_list.rawget(engine);
		} else if (AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			if (!this.mail_capacities_list.rawin(engine)) {
				return AIEngine.GetCapacity(engine);
			}
			return this.mail_capacities_list.rawget(engine);
		}
		assert(false);
	}

	function GetSecondaryCapacity(engine) {
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AIEngine.GetVehicleType(engine) == AIVehicle.VT_ROAD) return 0;

		if (!this.secondary_capacities_list.rawin(engine)) {
			return 0;
		}
		return this.secondary_capacities_list.rawget(engine);
	}

	function GetExistingRailDepot(railtype) {
		if (!AIRail.IsRailDepotTile(this._depot_tile) || !AICompany.IsMine(AITile.GetOwner(this._depot_tile)) || AIRail.GetRailType(this._depot_tile) != railtype) {
			this._depot_tile = AIMap.TILE_INVALID;
			local depot_list = AIDepotList(AITile.TRANSPORT_RAIL);
			foreach (depot in depot_list) {
				if (AIRail.GetRailType(depot) != railtype) continue;
				this._depot_tile = depot;
				break;
			}
		}
		return this._depot_tile;
	}

	function GetLength(engine, cargo, depot = AIMap.TILE_INVALID) {
		if (!AIEngine.IsValidEngine(engine) || !AIEngine.IsBuildable(engine))
		if (AIEngine.GetVehicleType(engine) != AIVehicle.VT_RAIL) return -1;

		local railtype = AIEngine.GetRailType(engine);
		if (!this.vehicle_lengths.rawin(engine)) {
			local result = false;
			if (!AIRail.IsRailDepotTile(depot)) {
				depot = this.GetExistingRailDepot(railtype);
			}

			if (AIRail.IsRailDepotTile(depot)) {
				local v = TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo);
				if (AIVehicle.IsValidVehicle(v)) {
					local vehicle_length = AIVehicle.GetLength(v);
					this.vehicle_lengths.rawset(engine, vehicle_length);
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
		return this.vehicle_lengths.rawget(engine);
	}

	function CanAttachToEngine(wagon, engine, cargo, railtype, depot = AIMap.TILE_INVALID) {
		if (!AIEngine.IsValidEngine(engine) || !AIEngine.IsBuildable(engine)) return false;
		if (!AIEngine.IsWagon(wagon) || AIEngine.IsWagon(engine)) return false;

		AIRail.SetCurrentRailType(railtype);
		local cargo_engine_wagon = (cargo << 32) | (engine << 16) | wagon;
		if (this.attach_list.rawin(cargo_engine_wagon)) {
			return this.attach_list.rawget(cargo_engine_wagon);
		}

		/* it's not in the list yet */
		local result = null;
		if (!AIRail.IsRailDepotTile(depot)) {
			depot = this.GetExistingRailDepot(railtype);
		}

		if (AIRail.IsRailDepotTile(depot)) {
			local cost = AIAccounting();
			local v = TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo);
//			local error_v = AIError.GetLastErrorString();
			local price = cost.GetCosts();
			local engine_cargo = (engine << 16) | cargo;
			if (!this.costs_with_refit.rawin(engine_cargo)) {
				this.costs_with_refit.rawset(engine_cargo, price);
			}
			cost.ResetCosts();
			if (AIVehicle.IsValidVehicle(v)) {
				local v_cap = AIVehicle.GetCapacity(v, cargo);
				if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {
					if (!this.pass_capacities_list.rawin(engine)) {
						this.pass_capacities_list.rawset(engine, v_cap);
					}
				} else if (AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
					if (!this.mail_capacities_list.rawin(engine)) {
						this.mail_capacities_list.rawset(engine, v_cap);
					}
				} else {
					assert(false);
				}
				if (!this.vehicle_lengths.rawin(engine)) {
					local length = AIVehicle.GetLength(v);
					this.vehicle_lengths.rawset(v, length);
				}
			}
			local w = TestBuildVehicleWithRefit().TryBuild(depot, wagon, cargo);
//			local error_w = AIError.GetLastErrorString();
			price = cost.GetCosts();
			local wagon_cargo = (wagon << 16) | cargo;
			if (!this.costs_with_refit.rawin(wagon_cargo)) {
				this.costs_with_refit.rawset(wagon_cargo, price);
			}
			if (AIVehicle.IsValidVehicle(w)) {
				local w_cap = AIVehicle.GetCapacity(w, cargo);
				if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {
					if (!this.pass_capacities_list.rawin(wagon)) {
						this.pass_capacities_list.rawset(wagon, w_cap);
					}
				} else if (AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
					if (!this.mail_capacities_list.rawin(wagon)) {
						this.mail_capacities_list.rawset(wagon, w_cap);
					}
				} else {
					assert(false);
				}
				if (!this.vehicle_lengths.rawin(wagon)) {
					local length = AIVehicle.GetLength(w);
					this.vehicle_lengths.rawset(w, length);
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

		if (result != null) this.attach_list.rawset(cargo_engine_wagon, result);
//		AILog.Info(AIEngine.GetName(engine) + " -- " + AIEngine.GetName(wagon) + " ? " + result);
		return result == true;
	}

	function GetCostWithRefit(engine, cargo, depot = AIMap.TILE_INVALID) {
		if (!AIEngine.IsValidEngine(engine) || !AIEngine.IsBuildable(engine)) return -1;

		local railtype = AIEngine.GetRailType(engine);
		local engine_cargo = (engine << 16) | cargo;
		if (!this.costs_with_refit.rawin(engine_cargo)) {
			local veh_type = AIEngine.GetVehicleType(engine);
			if (veh_type == AIVehicle.VT_RAIL) {
				local price = -1;
				if (!AIRail.IsRailDepotTile(depot)) {
					depot = this.GetExistingRailDepot(railtype);
				}

				if (AIRail.IsRailDepotTile(depot)) {
					local cost = AIAccounting();
					local v = AITestMode() && TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo);
					price = cost.GetCosts();
					if (price <= 0) {
//						AILog.Error("Retrieved a price of zero for a vehicle with refit");
					} else {
						this.costs_with_refit.rawset(engine_cargo, price);
					}
				}
				return price;
			} else {
				assert(false);
			}
		}
		return this.costs_with_refit.rawget(engine_cargo);
	}

	function SaveCaches() {
		return [_depot_tile, pass_capacities_list, mail_capacities_list, secondary_capacities_list, vehicle_lengths, attach_list, costs_with_refit];
	}

	function LoadCaches(data) {
		_depot_tile = data[0];
		pass_capacities_list = data[1];
		mail_capacities_list = data[2];
		secondary_capacities_list = data[3];
		vehicle_lengths = data[4];
		attach_list = data[5];
		costs_with_refit = data[6];
	}
}
