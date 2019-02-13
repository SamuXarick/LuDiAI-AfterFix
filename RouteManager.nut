require("BuildManager.nut");

class RouteManager {
    m_townRouteArray = null;

    constructor() {
        m_townRouteArray = [];
    }

    function buildRoute(buildManager, cityFrom, cityTo, cargoClass, articulated) {
        local route = buildManager.buildRoute(cityFrom, cityTo, cargoClass, articulated);
        if (route != null && route != 0) {
            m_townRouteArray.append(route);
            buildManager.setRouteFinish();
            return [1, route.m_stationFrom, route.m_stationTo];
        }

        return [route, null, null];
    }


    function getRoadVehicleCount() {
        local list = AIVehicleList();
        list.Valuate(AIVehicle.GetVehicleType);
        list.KeepValue(AIVehicle.VT_ROAD);
        return list.Count();
    }

    function townRouteExists(cityFrom, cityTo) {
        for (local i = 0; i < m_townRouteArray.len(); ++i) {
            if (TownPair(cityFrom, cityTo).isEqual(m_townRouteArray[i].m_cityFrom, m_townRouteArray[i].m_cityTo)) {
//              AILog.Info("townRouteExists from " + AITown.GetName(cityFrom) + " to " + AITown.GetName(cityTo));
                return 1;
            }
        }

        return 0;
    }

    //the highest last years profit out of all vehicles
    function highestProfitLastYear(routeManager) {
        local maxAllRoutesProfit = 0;

        for (local i = 0; i < routeManager.m_townRouteArray.len(); ++i) {
            local maxRouteProfit = AIVehicleList_Depot(routeManager.m_townRouteArray[i].m_depotTile);
            maxRouteProfit.Valuate(AIVehicle.GetProfitLastYear);
            maxRouteProfit.Sort(AIList.SORT_BY_VALUE, false);
            maxRouteProfit = maxRouteProfit.GetValue(maxRouteProfit.Begin());

            if (maxRouteProfit > maxAllRoutesProfit) {
                maxAllRoutesProfit = maxRouteProfit;
            }
        }

        return maxAllRoutesProfit;
    }

    //wont build any new stations if 1
    function hasMaxStationCount(cityFrom, cityTo) {
//		return 0;

        local maxTownStationFrom = (1 + AITown.GetPopulation(cityFrom) / 1000).tointeger();
        local maxTownStationTo = (1 + AITown.GetPopulation(cityTo) / 1000).tointeger();

        local cityFromCount = 0;
        local cityToCount = 0;

        for (local i = 0; i < m_townRouteArray.len(); ++i) {
            if (m_townRouteArray[i].m_cityFrom == cityFrom || m_townRouteArray[i].m_cityFrom == cityTo) {
                ++cityFromCount;
            }

            if (m_townRouteArray[i].m_cityTo == cityTo || m_townRouteArray[i].m_cityTo == cityFrom) {
                ++cityToCount;
            }
        }
//      AILog.Info("cityFrom = " + AITown.GetName(cityFrom) + " ; cityFromCount = " + cityFromCount + " ; maxTownStationFrom = " + maxTownStationFrom + " ; cityTo = " + AITown.GetName(cityTo) + " ; cityToCount = " + cityToCount + " ; maxTownStationTo = " + maxTownStationTo);

        if ((cityFromCount >= maxTownStationFrom) || (cityToCount >= maxTownStationTo)) {
            return 1;
        }

        return 0;
    }

    function saveRouteManager() {
        local table = {};

        for(local i = 0; i < m_townRouteArray.len(); ++i) {
            table.rawset(i, m_townRouteArray[i].saveRoute());
        }

        return table;
    }

    function loadRouteManager(data) {
        if(m_townRouteArray == null) {
            m_townRouteArray = [];
        }

        local i = 0;
        local bridges = 0;
        while(data.rawin(i)) {
            local route = Route.loadRoute(data.rawget(i));
            m_townRouteArray.append(route[0]);
            bridges += route[1];
            ++i;
        }

        AILog.Info("Loaded " + m_townRouteArray.len() + " routes with " + bridges + " bridges.");
    }
    
}