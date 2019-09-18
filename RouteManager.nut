require("BuildManager.nut");

class RouteManager {
	m_townRouteArray = null;
	m_sentToDepotRoadGroup = [AIGroup.GROUP_INVALID, AIGroup.GROUP_INVALID];
	m_best_routes_built = null;

	constructor(sentToDepotRoadGroup, best_routes_built) {
		m_townRouteArray = [];
		m_sentToDepotRoadGroup = sentToDepotRoadGroup;
		m_best_routes_built = best_routes_built;
	}

	function buildRoute(buildManager, cityFrom, cityTo, cargoClass, articulated, best_routes_built) {
		local route = buildManager.buildRoute(cityFrom, cityTo, cargoClass, articulated, m_sentToDepotRoadGroup, best_routes_built);
		if (route != null && route != 0) {
			m_townRouteArray.append(route);
			buildManager.setRouteFinish();
			return [1, route.m_stationFrom, route.m_stationTo];
		}

		return [route, null, null];
	}


	function getRoadVehicleCount() {
		local list = AIVehicleList();
		local vehiclecount = 0;
		for (local vehicle = list.Begin(); !list.IsEnd(); vehicle = list.Next()) {
			if (AIVehicle.GetVehicleType(vehicle) == AIVehicle.VT_ROAD) {
				vehiclecount++;
			}
		}

		return vehiclecount;
	}

	function townRouteExists(cityFrom, cityTo, cargoClass) {
		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (TownPair(cityFrom, cityTo, cargoClass).isEqual(m_townRouteArray[i].m_cityFrom, m_townRouteArray[i].m_cityTo, m_townRouteArray[i].m_cargoClass)) {
//				AILog.Info("townRouteExists from " + AITown.GetName(cityFrom) + " to " + AITown.GetName(cityTo));
				return 1;
			}
		}

		return 0;
	}

	//the highest last years profit out of all vehicles
	function highestProfitLastYear() {
		local maxAllRoutesProfit = null;

		for (local i = 0; i < this.m_townRouteArray.len(); ++i) {
			local removelist = AIList();
			local maxRouteProfit = AIVehicleList_Station(AIStation.GetStationID(this.m_townRouteArray[i].m_stationFrom));
			for (local vehicle = maxRouteProfit.Begin(); !maxRouteProfit.IsEnd(); vehicle = maxRouteProfit.Next()) {
				if (AIVehicle.GetVehicleType(vehicle) == AIVehicle.VT_ROAD) {
					maxRouteProfit.SetValue(vehicle, AIVehicle.GetProfitLastYear(vehicle));
				} else {
					removelist.AddItem(vehicle, 0);
				}
			}
			maxRouteProfit.RemoveList(removelist);
			maxRouteProfit.Sort(AIList.SORT_BY_VALUE, false);
			maxRouteProfit = maxRouteProfit.GetValue(maxRouteProfit.Begin());

			if (maxAllRoutesProfit == null || maxRouteProfit > maxAllRoutesProfit) {
				maxAllRoutesProfit = maxRouteProfit;
			}
		}

		return maxAllRoutesProfit;
	}

	//wont build any new stations if 1
	function hasMaxStationCount(cityFrom, cityTo, cargoClass) {
//		return 0;

		local maxTownStationFrom = (1 + AITown.GetPopulation(cityFrom) / 1000).tointeger();
		local maxTownStationTo = (1 + AITown.GetPopulation(cityTo) / 1000).tointeger();

		local cityFromCount = 0;
		local cityToCount = 0;

		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			if (m_townRouteArray[i].m_cityFrom == cityFrom || m_townRouteArray[i].m_cityFrom == cityTo) {
				if (m_townRouteArray[i].m_cargoClass == cargoClass) ++cityFromCount;
			}

			if (m_townRouteArray[i].m_cityTo == cityTo || m_townRouteArray[i].m_cityTo == cityFrom) {
				if (m_townRouteArray[i].m_cargoClass == cargoClass) ++cityToCount;
			}
		}
//		AILog.Info("cityFrom = " + AITown.GetName(cityFrom) + " ; cityFromCount = " + cityFromCount + " ; maxTownStationFrom = " + maxTownStationFrom + " ; cityTo = " + AITown.GetName(cityTo) + " ; cityToCount = " + cityToCount + " ; maxTownStationTo = " + maxTownStationTo);

		if ((cityFromCount >= maxTownStationFrom) || (cityToCount >= maxTownStationTo)) {
			return 1;
		}

		return 0;
	}

	function saveRouteManager() {
		local routemanager = [];
		local table = {};

		for (local i = 0; i < m_townRouteArray.len(); ++i) {
			table.rawset(i, m_townRouteArray[i].saveRoute());
		}

		routemanager.append(table);
		routemanager.append(m_sentToDepotRoadGroup);
		routemanager.append(m_best_routes_built);

		return routemanager;
	}

	function loadRouteManager(data) {
		if (m_townRouteArray == null) {
			m_townRouteArray = [];
		}

		local routearray = data[0];

		local i = 0;
		local bridges = 0;
		while(routearray.rawin(i)) {
			local route = Route.loadRoute(routearray.rawget(i));
			m_townRouteArray.append(route[0]);
			bridges += route[1];
			++i;
		}

		m_sentToDepotRoadGroup = data[1];
		m_best_routes_built = data[2];

		AILog.Info("Loaded " + m_townRouteArray.len() + " routes with " + bridges + " bridges.");
	}

}