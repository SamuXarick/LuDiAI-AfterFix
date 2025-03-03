class Caches {
	_depot_tile = AIMap.TILE_INVALID;

	pass_capacities_list = {};
	mail_capacities_list = {};
	secondary_capacities_list = {}; // secondary capacity for a pass/mail aircraft
	vehicle_lengths = {}; // vehicle length of rail engines
	attach_list = [];
	costs_with_refit = [];

	function GetBuildWithRefitCapacity(depot, engine, cargo);
	function GetBuildWithRefitSecondaryCapacity(hangar, engine);
	function GetCapacity(engine, cargo);
	function GetSecondaryCapacity(engine);
	function BuildFirstDepot(veh_type = AIVehicle.VT_RAIL);
	function GetLength(engine, cargo, depot = AIMap.TILE_INVALID);
	function CanAttachToEngine(wagon, engine, cargo, railtype, depot = AIMap.TILE_INVALID);
	function GetCostWithRefit(engine, cargo, depot = AIMap.TILE_INVALID);

	function GetBuildWithRefitCapacity(depot, engine, cargo) {
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AICargo.HasCargoClass(cargo, AICargo.CC_PASSENGERS)) {
			if (!this.pass_capacities_list.rawin(engine)) {
				this.pass_capacities_list.rawset(engine, AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo));
//				AILog.Info("Added engine " + AIEngine.GetName(engine) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo) + " " + AICargo.GetCargoLabel(Utils.getCargoId(AICargo.CC_PASSENGERS)));
			}
			return this.pass_capacities_list.rawget(engine);
		} else if (AICargo.HasCargoClass(cargo, AICargo.CC_MAIL)) {
			if (!this.mail_capacities_list.rawin(engine)) {
				this.mail_capacities_list.rawset(engine, AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo));
//				AILog.Info("Added engine " + AIEngine.GetName(engine) + ": " + AIVehicle.GetBuildWithRefitCapacity(depot, engine, cargo) + " " + AICargo.GetCargoLabel(Utils.getCargoId(AICargo.CC_MAIL)));
			}
			return this.mail_capacities_list.rawget(engine);
		}
		assert(false);
	}

	function GetBuildWithRefitSecondaryCapacity(hangar, engine) {
//		if (!AIEngine.IsBuildable(engine)) return 0;
		if (AIEngine.GetVehicleType(engine) == AIVehicle.VT_ROAD) return 0;
		if (!AICargo.IsValidCargo(Utils.getCargoId(AICargo.CC_MAIL))) return 0;

		if (!this.secondary_capacities_list.rawin(engine)) {
			local pass_capacity = this.GetBuildWithRefitCapacity(hangar, engine, Utils.getCargoId(AICargo.CC_PASSENGERS));
			local mail_capacity = this.GetBuildWithRefitCapacity(hangar, engine, Utils.getCargoId(AICargo.CC_MAIL));
			this.secondary_capacities_list.rawset(engine, mail_capacity - pass_capacity);
//			AILog.Info("Capacity for " + AIEngine.GetName(engine) + ": " + pass_capacity + " " + AICargo.GetCargoLabel(Utils.getCargoId(AICargo.CC_PASSENGERS)) + ", " + (mail_capacity - pass_capacity) + " " + AICargo.GetCargoLabel(Utils.getCargoId(AICargo.CC_MAIL)));
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

	function BuildFirstDepot(veh_type = AIVehicle.VT_RAIL) {
		assert(veh_type == AIVehicle.VT_RAIL);

		local num_tries = 50;
		local tile = AIMap.TILE_INVALID;
		while (this._depot_tile == AIMap.TILE_INVALID && --num_tries > 0) {
			tile = AIBase.RandRange(AIMap.GetMapSize());
			if (!AIMap.IsValidTile(tile)) continue;

			local offsets = [AIMap.GetTileIndex(0, 1), AIMap.GetTileIndex(0, -1), AIMap.GetTileIndex(1, 0), AIMap.GetTileIndex(-1, 0)];
			foreach (offset in offsets) {
				local tile_offset = tile + offset;
				if (AIMap.IsValidTile(tile_offset)) {
					if (veh_type == AIVehicle.VT_RAIL) {
						if (!AIRail.IsRailTypeAvailable(AIRail.GetCurrentRailType())) {
							local railtypes = AIRailTypeList();
							if (!railtypes.IsEmpty()) {
								AIRail.SetCurrentRailType(railtype.Begin());
							}
						}
						if (TestBuildRailDepot().TryBuild(tile, tile_offset)) {
							this._depot_tile = tile;
							break;
						}
					}
				}
			}
		}
		return this._depot_tile;
	}

	function GetLength(engine, cargo, depot = AIMap.TILE_INVALID) {
		local railtype = AIEngine.GetRailType(engine);
		AIRail.SetCurrentRailType(railtype);
		if (!this.vehicle_lengths.rawin(engine)) {
			local veh_type = AIEngine.GetVehicleType(engine);
			if (veh_type == AIVehicle.VT_RAIL) {
				local remove_depot = false;
				local length = -1;
				if (!AIRail.IsRailDepotTile(depot)) {
					depot = this.BuildFirstDepot();
				}

				if (AIRail.IsRailDepotTile(depot)) {
					AIRail.ConvertRailType(depot, depot, railtype);
					local v = TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo);
					if (AIVehicle.IsValidVehicle(v)) {
						local vehicle_length = AIVehicle.GetLength(v);
						this.vehicle_lengths.rawset(engine, vehicle_length);
						AIVehicle.SellVehicle(v);
						length = vehicle_length;
					} else {
						AILog.Error("Failed to build vehicle with refit to check its length");
					}
				}
				if (remove_depot) {
					if (!TestDemolishTile().TryDemolish(depot)) {
						::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depot, RailStructType.DEPOT, railtype));
					}
				}
				return length;
			} else {
				assert(false);
			}
		}
		return this.vehicle_lengths.rawget(engine);
	}

	function CanAttachToEngine(wagon, engine, cargo, railtype, depot = AIMap.TILE_INVALID) {
		assert(AIEngine.IsWagon(wagon));
		assert(!AIEngine.IsWagon(engine));
		AIRail.SetCurrentRailType(railtype);

		local combo = [engine, wagon, cargo];
		if (Utils.ArrayHasItem(this.attach_list, combo)) {
			return Utils.ArrayGetValue(this.attach_list, combo);
		}

		/* it's not in the list yet */
		local remove_depot = false;
		local result = false;
		if (!AIRail.IsRailDepotTile(depot)) {
			depot = this.BuildFirstDepot();
		}

		if (AIRail.IsRailDepotTile(depot)) {
			AIRail.ConvertRailType(depot, depot, railtype);
			local cost = AIAccounting();
			local v = TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo);
			local error_v = AIError.GetLastErrorString();
			local price = cost.GetCosts();
			local pair = [engine, cargo];
			if (!Utils.ArrayHasItem(this.costs_with_refit, pair)) {
				this.costs_with_refit.append([pair, price]);
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
			local error_w = AIError.GetLastErrorString();
			price = cost.GetCosts();
			pair = [wagon, cargo];
			if (!Utils.ArrayHasItem(this.costs_with_refit, pair)) {
				this.costs_with_refit.append([pair, price]);
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
				if (res1 && res2) {
					result = true;
				}
				AIVehicle.SellVehicle(v);
				if (!res1) AIVehicle.SellVehicle(w);
			} else {
				if (!AIVehicle.IsValidVehicle(v)) AILog.Error("Failed to build engine with refit to check if it can attach to wagon. " + error_v);
				if (!AIVehicle.IsValidVehicle(w)) AILog.Error("Failed to build wagon with refit to check if it can attach to engine. " + error_w);
				if (AIVehicle.IsValidVehicle(v)) AIVehicle.SellVehicle(v);
				if (AIVehicle.IsValidVehicle(w)) AIVehicle.SellVehicle(w);
				return true;
			}
		}
		if (remove_depot) {
			if (!TestDemolishTile().TryDemolish(depot)) {
				::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depot, RailStructType.DEPOT, railtype));
			}
		}

		if (result) this.attach_list.append([combo, result]);
//		AILog.Info(AIEngine.GetName(engine) + " -- " + AIEngine.GetName(wagon) + " ? " + result);
		return result;
	}

	function GetCostWithRefit(engine, cargo, depot = AIMap.TILE_INVALID) {
		local railtype = AIEngine.GetRailType(engine);
		AIRail.SetCurrentRailType(railtype);
		local pair = [engine, cargo];
		if (!Utils.ArrayHasItem(this.costs_with_refit, pair)) {
			local veh_type = AIEngine.GetVehicleType(engine);
			if (veh_type == AIVehicle.VT_RAIL) {
				local remove_depot = false;
				local price = -1;
				if (!AIRail.IsRailDepotTile(depot)) {
					depot = this.BuildFirstDepot();
				}

				if (AIRail.IsRailDepotTile(depot)) {
					AIRail.ConvertRailType(depot, depot, railtype);
					local cost = AIAccounting();
					local v = AITestMode() && TestBuildVehicleWithRefit().TryBuild(depot, engine, cargo);
					price = cost.GetCosts();
					if (price <= 0) {
						AILog.Error("Retrieved a price of zero for a vehicle with refit");
					} else {
						this.costs_with_refit.append([pair, price]);
					}
				}
				if (remove_depot) {
					if (!TestDemolishTile().TryDemolish(depot)) {
						::scheduledRemovalsTable.Train.append(RailStruct.SetStruct(depot, RailStructType.DEPOT, railtype));
					}
				}
				return price;
			} else {
				assert(false);
			}
		}
		return Utils.ArrayGetValue(this.costs_with_refit, pair);
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
