class TownPair
{
	m_city_from = null;
	m_city_to = null;
	m_cargo_class = null;

	constructor(city_from, city_to, cargo_class = null)
	{
		this.m_city_from = city_from;
		this.m_city_to = city_to;
		this.m_cargo_class = cargo_class;
	}

	function IsEqual(city_from, city_to, cargo_class = null)
	{
		if (this.m_cargo_class != cargo_class) return false;

		if (this.m_city_from == city_from && this.m_city_to == city_to) {
			return true;
		}

		if (this.m_city_from == city_to && this.m_city_to == city_from) {
			return true;
		}
	}

	function IsTownPairDataEqual(town_pair_data)
	{
		return this.IsEqual(town_pair_data[0], town_pair_data[1]);
	}
};

class TownManager
{
	static CARGO_TYPE_LIMIT = {
		[AICargo.CC_PASSENGERS] = 70,
		[AICargo.CC_MAIL] = 35,
	};

	/* These are saved */
	m_near_city_pair_array = null;
	m_used_cities_list = null;

	/* These are not saved */
	m_town_list = null;
	m_town_count = null;

	constructor()
	{
		this.m_town_list = AIList();
		this.m_town_count = 0;

		this.m_near_city_pair_array = {};
		this.m_near_city_pair_array.rawset(AICargo.CC_PASSENGERS, []);
		this.m_near_city_pair_array.rawset(AICargo.CC_MAIL, []);
		this.m_used_cities_list = {};
		this.m_used_cities_list.rawset(AICargo.CC_PASSENGERS, AIList());
		this.m_used_cities_list.rawset(AICargo.CC_MAIL, AIList());
	}

	function GetLastMonthProductionDiffRate(town_id, cargo_type)
	{
		local last_month_production = AITown.GetLastMonthProduction(town_id, cargo_type);
		if (AIController.GetSetting("pick_mode") == 0) {
			return (last_month_production - AITown.GetLastMonthSupplied(town_id, cargo_type)) * (100 - AITown.GetLastMonthTransportedPercentage(town_id, cargo_type)) / 100;
		}
		return last_month_production;
	}

	function IsTownGrowing(town_id, cargo_type)
	{
//		return true;
		if (!AIGameSettings.GetValue("town_growth_rate")) return true; // no town grows, just work with it

		local cargo_types_required = AIList();
		foreach (cargo_type2, _ in ::caches.m_cargo_type_list) {
			local town_effect = AICargo.GetTownEffect(cargo_type2);

			if (town_effect != AICargo.TE_NONE) {
//				local effect_name;
//				switch(town_effect) {
//					case AICargo.TE_PASSENGERS: effect_name = "TE_PASSENGERS"; break;
//					case AICargo.TE_MAIL: effect_name = "TE_MAIL"; break;
//					case AICargo.TE_GOODS: effect_name = "TE_GOODS"; break;
//					case AICargo.TE_WATER: effect_name = "TE_WATER"; break;
//					case AICargo.TE_FOOD: effect_name = "TE_FOOD"; break;
//				}
//				AILog.Info(" - Effect of " + AICargo.GetCargoLabel(cargo_type2) + " in " + AITown.GetName(town_id) + " is " + effect_name);
				local cargo_goal = AITown.GetCargoGoal(town_id, town_effect);
				if (cargo_goal != 0) {
//					AILog.Info(" - An amount of " + cargo_goal + " " + AICargo.GetCargoLabel(cargo_type2) + " is required to grow " + AITown.GetName(town_id));
					cargo_types_required[cargo_type2] = cargo_goal;
				}
			}
		}
//		AILog.Info(" ");
		local num_cargo_types_required = cargo_types_required.Count();
		local result = num_cargo_types_required == 0 || (cargo_types_required.HasItem(cargo_type) && num_cargo_types_required == 1);

//		AILog.Info("-- Result for town " + AITown.GetName(town_id) + ": " + result + " - " + num_cargo_types_required + " --");
		return result;
	}

	function BuildTownList()
	{
		local town_count = AITown.GetTownCount();
		if (town_count == this.m_town_count) return;

		this.m_town_count = town_count;

		this.m_town_list = AITownList();
	}

	function GetUnusedCity(best_routes_built, cargo_class)
	{
		this.BuildTownList();

		if (this.m_town_list.Count() == this.m_used_cities_list[cargo_class].Count()) {
			return null;
		}

		local unused_cities_list = AIList();
		unused_cities_list.AddList(this.m_town_list);
		unused_cities_list.RemoveList(this.m_used_cities_list[cargo_class]);

		local unused_town = null;
		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			unused_cities_list.RemoveTop(AIBase.RandRange(unused_cities_list.Count()));
			unused_town = unused_cities_list.Begin();
			this.m_used_cities_list[cargo_class][unused_town] = 0;
		} else {
			local cargo_type = Utils.GetCargoType(cargo_class);
			foreach (town_id, _ in unused_cities_list) {
				if (!best_routes_built) {
					if (!this.IsTownGrowing(town_id, cargo_type)) {
						unused_cities_list[town_id] = null;
						continue;
					}
				}
				local last_month_production = this.GetLastMonthProductionDiffRate(town_id, cargo_type);
				if (!best_routes_built) {
					if (last_month_production <= CARGO_TYPE_LIMIT[cargo_class]) {
						unused_cities_list[town_id] = null;
						continue;
					}
				}
				unused_cities_list[town_id] = last_month_production;
			}

			if (!unused_cities_list.IsEmpty()) {
				unused_town = unused_cities_list.Begin();
				this.m_used_cities_list[cargo_class].AddItem(unused_town, 0);
			}
		}

		return unused_town;
	}

	function ResetCityPair(from_city, to_city, cargo_class, remove_all)
	{
//		AILog.Info(this.m_near_city_pair_array[cargo_class].len() + " found in the this.m_near_city_pair_array[" + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + "]");
//		AILog.Info("Town pair " + AITown.GetName(from_city) + " and " + AITown.GetName(to_city) + " (" + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + ") are being removed...");
		for (local i = this.m_near_city_pair_array[cargo_class].len() - 1; i >= 0; --i) {
			if (TownPair(from_city, to_city).IsTownPairDataEqual(this.m_near_city_pair_array[cargo_class][i])) {
//				AILog.Info("Found pair " + AITown.GetName(this.m_near_city_pair_array[cargo_class][i][0]) + " and " + AITown.GetName(this.m_near_city_pair_array[cargo_class][i][1]) + " in this.m_near_city_pair_array[" + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + "][" + i + "]");
				this.m_near_city_pair_array[cargo_class].remove(i);
				break;
			}
		}

		/* The following code is too slow */
//		if (remove_all) {
//			AILog.Info(this.m_used_cities_list[cargo_class].Count() + " found in this.m_used_cities_list[" + cargo_class + "]");
//			foreach (town_id, _ in this.m_used_cities_list[cargo_class]) {
//				local remove_town = true;
//				foreach (near_city_pair in this.m_near_city_pair_array[cargo_class]) {
//					if (town_id == near_city_pair[0] || town_id == near_city_pair[1]) {
//						remove_town = false;
//						break;
//					}
//				}
//				if (remove_town) {
//					AILog.Info("Town " + AITown.GetName(town_id) + " is being removed (ResetCityPair)");
//					this.m_used_cities_list[cargo_class][town_id] = null;
//				}
//			}
//		}
	}

	function DistanceFunction(fake_dist, town_id, tile)
	{
		if (fake_dist) return AITown.GetDistanceSquareToTile(town_id, tile);
		return AITown.GetDistanceManhattanToTile(town_id, tile);
	}

	function FindNearCities(from_city, min_distance, max_distance, best_routes_built, cargo_class, max_fake_dist = 0)
	{
//		AILog.Info("from_city = " + from_city + "; min_distance = " + min_distance + "; max_distance = " + max_distance + "; best_routes_built = " + best_routes_built + "; cargo_class = " + cargo_class + "; fakedist = " + fake_dist);
		this.BuildTownList();

		local unused_cities_list = AIList();
		unused_cities_list.AddList(this.m_town_list);
		unused_cities_list.RemoveList(this.m_used_cities_list[cargo_class]);
		unused_cities_list.RemoveItem(from_city); // remove self

		local from_city_location = AITown.GetLocation(from_city);
		foreach (town_id, _ in unused_cities_list) {
			local unused_town_location = AITown.GetLocation(town_id);
			local distance = this.DistanceFunction(max_fake_dist, from_city, unused_town_location);
			local fake = max_fake_dist != 0 ? WrightAI.DistanceRealFake(from_city_location, unused_town_location) : 0;
			if (distance > max_distance || distance < min_distance || fake > max_fake_dist) {
				unused_cities_list[town_id] = null;
			}
		}

		if (unused_cities_list.IsEmpty()) {
			return;
		}

		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			unused_cities_list.RemoveTop(AIBase.RandRange(unused_cities_list.Count()));
			local unused_town = unused_cities_list.Begin();

			local exists = false;
			foreach (near_city_pair in this.m_near_city_pair_array[cargo_class]) {
				if (TownPair(from_city, unused_town).IsTownPairDataEqual(near_city_pair)) {
					exists = true;
					break;
				}
			}

			if (!exists) {
				this.m_near_city_pair_array[cargo_class].append([from_city, unused_town]);
				return;
			}
		} else {
			local cargo_type = Utils.GetCargoType(cargo_class);
			foreach (town_id, _ in unused_cities_list) {
				if (!best_routes_built) {
					if (!this.IsTownGrowing(town_id, cargo_type)) {
						unused_cities_list[town_id] = null;
						continue;
					}
				}
				local last_month_production = this.GetLastMonthProductionDiffRate(town_id, cargo_type);
				if (!best_routes_built) {
					if (pick_mode >= 2 && unused_cities_list[town_id] <= CARGO_TYPE_LIMIT[cargo_class]) {
						unused_cities_list[town_id] = null;
						continue;
					}
				}
				unused_cities_list[town_id] = last_month_production;
			}

			if (unused_cities_list.IsEmpty()) {
				return;
			}

			if (pick_mode >= 2) {
				unused_cities_list.Sort(AIList.SORT_BY_ITEM, AIList.SORT_ASCENDING);
				foreach (town_id, _ in unused_cities_list) {
					unused_cities_list[town_id] = this.DistanceFunction(fake_dist, town_id, from_city_location);
				}
				unused_cities_list.Sort(AIList.SORT_BY_VALUE, (pick_mode == 2 ? AIList.SORT_ASCENDING : AIList.SORT_DESCENDING));
			}

			if (!best_routes_built) {
				local unused_town = unused_cities_list.Begin();

				local exists = false;
				foreach (near_city_pair in this.m_near_city_pair_array[cargo_class]) {
					if (TownPair(from_city, unused_town).IsTownPairDataEqual(near_city_pair)) {
						exists = true;
						break;
					}
				}

				if (!exists) {
					this.m_near_city_pair_array[cargo_class].append([from_city, unused_town]);
					return;
				}
			} else {
//				local start_tick = AIController.GetTick();
//				AILog.Info("FindNearCities . best_routes_built . unused_cities_list: " + unused_cities_list.Count() + " items; this.m_near_city_pair_array[" + AICargo.GetCargoLabel(Utils.GetCargoType(cargo_class)) + "]: " + this.m_near_city_pair_array[cargo_class].len() + " items.");
				local count = 0;
				foreach (town_id, _ in unused_cities_list) {
					local exists = false;
					foreach (near_city_pair in this.m_near_city_pair_array[cargo_class]) {
						if (TownPair(from_city, town_id).IsTownPairDataEqual(near_city_pair)) {
							exists = true;
							break;
						}
					}

					if (!exists) {
						this.m_near_city_pair_array[cargo_class].append([from_city, town_id]);
						count++;
						if (count == 10) break; // too many towns in unused_cities_list will slow IsTownPairDataEqual down over time
					}
				}
//				local management_ticks = AIController.GetTick() - start_tick;
//				AILog.Info("FindNearCities " + management_ticks + " tick" + (management_ticks != 1 ? "s" : "") + ".");
			}
		}
	}

	function SaveTownManager()
	{
		return [this.m_near_city_pair_array, this.m_used_cities_list];
	}

	function LoadTownManager(data)
	{
		this.m_near_city_pair_array = data[0];
		AILog.Info("Loaded " + this.m_near_city_pair_array[AICargo.CC_PASSENGERS].len() + " near city pairs Pass.");
		AILog.Info("Loaded " + this.m_near_city_pair_array[AICargo.CC_MAIL].len() + " near city pairs Mail.");

		this.m_used_cities_list = data[1];
		AILog.Info("Loaded " + this.m_used_cities_list[AICargo.CC_PASSENGERS].Count() + " used cities Pass.");
		AILog.Info("Loaded " + this.m_used_cities_list[AICargo.CC_MAIL].Count() + " used cities Mail.");
	}
};
