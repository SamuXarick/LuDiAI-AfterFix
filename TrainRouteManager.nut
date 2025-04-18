require("TrainBuildManager.nut");

class RailRouteManager {
	m_town_route_array = null;
	m_sentToDepotRailGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sent_to_depot_rail_group, best_routes_built) {
		m_town_route_array = [];
		m_sentToDepotRailGroup = sent_to_depot_rail_group;
		m_best_routes_built = best_routes_built;
	}

	function BuildRoute(rail_build_manager, city_from, city_to, cargo_class, best_routes_built, rail_type) {
		local route = rail_build_manager.BuildRailRoute(city_from, city_to, cargo_class, m_sentToDepotRailGroup, best_routes_built, rail_type);
		if (route != null && route != 0) {
			m_town_route_array.append(route);
			rail_build_manager.SetRouteFinished();
			return [1, route.m_station_from, route.m_station_to];
		}

		return [route, null, null];
	}


	function GetTrainCount() {
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_RAIL);
	}

	function TownRouteExists(city_from, city_to, cargo_class) {
		for (local i = 0; i < m_town_route_array.len(); ++i) {
			if (TownPair(city_from, city_to, cargo_class).IsEqual(m_town_route_array[i].m_city_from, m_town_route_array[i].m_city_to, m_town_route_array[i].m_cargo_class)) {
//				AILog.Info("TownRouteExists from " + AITown.GetName(city_from) + " to " + AITown.GetName(city_to));
				return 1;
			}
		}

		return 0;
	}

	/* the highest last years profit out of all vehicles */
	function HighestProfitLastYear() {
		local max_all_routes_profit = null;

		for (local i = 0; i < this.m_town_route_array.len(); ++i) {
			local max_route_profit = 0;
			foreach (vehicle, _ in this.m_town_route_array[i].m_vehicle_list) {
				local profit = AIVehicle.GetProfitLastYear(vehicle);
				if (max_route_profit < profit) {
					max_route_profit = profit;
				}
			}

			if (max_all_routes_profit == null || max_route_profit > max_all_routes_profit) {
				max_all_routes_profit = max_route_profit;
			}
		}

		return max_all_routes_profit;
	}

	/* won't build any new stations if 1 */
	function HasMaxStationCount(city_from, city_to, cargo_class) {
//		return 0;

		local max_town_station_from = (1 + AITown.GetPopulation(city_from) / 1000).tointeger();
		local max_town_station_to = (1 + AITown.GetPopulation(city_to) / 1000).tointeger();

		local city_from_count = 0;
		local city_to_count = 0;

		for (local i = 0; i < m_town_route_array.len(); ++i) {
			if (m_town_route_array[i].m_city_from == city_from || m_town_route_array[i].m_city_from == city_to) {
				if (m_town_route_array[i].m_cargo_class == cargo_class) ++city_from_count;
			}

			if (m_town_route_array[i].m_city_to == city_to || m_town_route_array[i].m_city_to == city_from) {
				if (m_town_route_array[i].m_cargo_class == cargo_class) ++city_to_count;
			}
		}
//		AILog.Info("city_from = " + AITown.GetName(city_from) + " ; city_from_count = " + city_from_count + " ; max_town_station_from = " + max_town_station_from + " ; city_to = " + AITown.GetName(city_to) + " ; city_to_count = " + city_to_count + " ; max_town_station_to = " + max_town_station_to);

		if ((city_from_count >= max_town_station_from) || (city_to_count >= max_town_station_to)) {
			return 1;
		}

		return 0;
	}

	function SaveRouteManager() {
		local array = [];
		for (local i = 0; i < m_town_route_array.len(); ++i) {
			array.append(m_town_route_array[i].SaveRoute());
		}

		return [array, m_sentToDepotRailGroup, m_best_routes_built];
	}

	function LoadRouteManager(data) {
		if (m_town_route_array == null) {
			m_town_route_array = [];
		}

		local routearray = data[0];

		local bridges = 0;
		for (local i = 0; i < routearray.len(); i++) {
			local route = RailRoute.LoadRoute(routearray[i]);
			m_town_route_array.append(route[0]);
			bridges += route[1];
		}
		AILog.Info("Loaded " + m_town_route_array.len() + " rail routes with " + bridges + " bridges.");

		m_sentToDepotRailGroup = data[1];
		m_best_routes_built = data[2];
	}

}
