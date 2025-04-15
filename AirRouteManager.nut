require("AirBuildManager.nut");

class AirRouteManager
{
	m_town_route_array = null;
	m_sent_to_depot_air_group = null;
	m_best_routes_built = null;

	constructor(sent_to_depot_air_group, best_routes_built)
	{
		this.m_town_route_array = [];
		this.m_sent_to_depot_air_group = sent_to_depot_air_group;
		this.m_best_routes_built = best_routes_built;
	}

	function BuildRoute(air_route_manager, air_build_manager, air_town_manager, city_from, city_to, cargo_class, best_routes_built, all_routes_built)
	{
		local route = air_build_manager.BuildAirRoute(air_route_manager, air_town_manager, city_from, city_to, cargo_class, this.m_sent_to_depot_air_group, best_routes_built, all_routes_built);
		if (route != null && route != 0) {
			this.m_town_route_array.append(route);
			air_build_manager.SetRouteFinished();
			return [1, route.m_airport_from, route.m_airport_to];
		}

		return [route, null, null];
	}


	function GetAircraftCount()
	{
		return AIGroup.GetNumVehicles(AIGroup.GROUP_ALL, AIVehicle.VT_AIR);
	}

	function TownRouteExists(city_from, city_to, cargo_class)
	{
		foreach (route in this.m_town_route_array) {
			if (TownPair(city_from, city_to, cargo_class).IsEqual(route.m_city_from, route.m_city_to, route.m_cargo_class)) {
//				AILog.Info("TownRouteExists from " + AITown.GetName(city_from) + " to " + AITown.GetName(city_to));
				return true;
			}
		}

		return false;
	}

	/* the highest last years profit out of all vehicles */
	function HighestProfitLastYear()
	{
		local max_all_routes_profit = null;

		foreach (route in this.m_town_route_array) {
			local max_route_profit = 0;
			foreach (vehicle, _ in route.m_vehicle_list) {
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

	/* won't build any new stations if true */
	function HasMaxStationCount(city_from, city_to, cargo_class)
	{
//		return false;

		local max_town_station_from = (1 + AITown.GetPopulation(city_from) / 1000).tointeger();
		local max_town_station_to = (1 + AITown.GetPopulation(city_to) / 1000).tointeger();

		local city_from_count = 0;
		local city_to_count = 0;

		foreach (route in this.m_town_route_array) {
			if (route.m_city_from == city_from || route.m_city_from == city_to) {
				if (route.m_cargo_class == cargo_class) ++city_from_count;
			}

			if (route.m_city_to == city_to || route.m_city_to == city_from) {
				if (route.m_cargo_class == cargo_class) ++city_to_count;
			}
		}
//		AILog.Info("city_from = " + AITown.GetName(city_from) + " ; city_from_count = " + city_from_count + " ; max_town_station_from = " + max_town_station_from + " ; city_to = " + AITown.GetName(city_to) + " ; city_to_count = " + city_to_count + " ; max_town_station_to = " + max_town_station_to);

		return city_from_count >= max_town_station_from || city_to_count >= max_town_station_to;
	}

	function SaveRouteManager()
	{
		local town_route_array = [];
		foreach (route in this.m_town_route_array) {
			town_route_array.append(route.SaveRoute());
		}

		return [town_route_array, this.m_sent_to_depot_air_group, this.m_best_routes_built];
	}

	function LoadRouteManager(data)
	{
		if (this.m_town_route_array == null) {
			this.m_town_route_array = [];
		}

		local town_route_array = data[0];

		foreach (load in town_route_array) {
			local route = AirRoute.LoadRoute(load);
			this.m_town_route_array.append(route);
		}
		AILog.Info("Loaded " + this.m_town_route_array.len() + " air routes.");

		this.m_sent_to_depot_air_group = data[1];
		this.m_best_routes_built = data[2];
	}
};
