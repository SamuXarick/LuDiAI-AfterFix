class TownPair {
    m_cityFrom = null;
    m_cityTo = null;

    constructor(cityFrom, cityTo) {
        m_cityFrom = cityFrom;
        m_cityTo = cityTo;
    }

    function isEqual(cityFrom, cityTo) {
        if ((m_cityFrom == cityFrom) && (m_cityTo == cityTo)) {
            return 1;
        }

        if ((m_cityFrom == cityTo) && (m_cityTo == cityFrom)) {
            return 1;
        }

        return 0;
    }

    function saveTownPair() {
        local pair = [];

        pair.append(m_cityFrom);
        pair.append(m_cityTo);

        return pair;
    }

    function loadPair(data) {
        local cityFrom = data[0];
        local cityTo = data[1];

        return TownPair(cityFrom, cityTo);
    }
}

class TownManager {
    m_townList = null;

    m_nearCityPairArray = null;
    m_usedCities = null;

    constructor() {

        m_townList = BuildTownList();

        m_nearCityPairArray = [];
        m_usedCities = AIList();
    }

    function getUnusedCity(bestRoutesBuilt, cargoClass);
	function removeUsedCityPair(fromCity, toCity, usedCities);
    function findNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass);
	function BuildTownList();
	
	function BuildTownList() {
	    m_townList = AITownList();
        if (AIController.GetSetting("cities_only")) {
            m_townList = AITownList();
            m_townList.Valuate(AITown.IsCity);
            m_townList.KeepValue(1);
        }
	}

    function getUnusedCity(bestRoutesBuilt, cargoClass) {
		BuildTownList();

        if (m_townList.Count() == m_usedCities.Count()) {
            return null;
        }

        local localList = AIList();
        localList.AddList(m_townList);
        localList.RemoveList(m_usedCities);

        local unusedTown = null;
        if (AIController.GetSetting("pick_mode") == 1) {
            local randomLocalListItemIndex = AIBase.RandRange(localList.Count() - 1);
            unusedTown = Utils.getNthItem(localList, randomLocalListItemIndex);
            m_usedCities.AddItem(unusedTown, 0);
        }
        else {
			local cargo = Utils.getCargoId(cargoClass);
            localList.Valuate(AITown.GetLastMonthProduction, cargo);
            localList.Sort(AIList.SORT_BY_VALUE, false);

            if (!bestRoutesBuilt) {
                localList.KeepAboveValue(cargoClass == AICargo.CC_PASSENGERS ? 70 : 35);
            }

            if (localList.Count()) {
                unusedTown = localList.Begin();
                m_usedCities.AddItem(unusedTown, 0);
            }
        }

        return unusedTown;
    }
	
	function removeUsedCityPair(fromCity, toCity, usedCities) {
//	    AILog.Info(m_nearCityPairArray.len() + " found in the m_nearCityPairArray");
//	    AILog.Info("Town pair " + AITown.GetName(fromCity) + " and " + AITown.GetName(toCity) + " are being removed...");
        for (local i = m_nearCityPairArray.len() - 1 ; i >= 0; --i) {
            if (m_nearCityPairArray[i].isEqual(fromCity, toCity)) {
//			    AILog.Info("Found pair " + AITown.GetName(m_nearCityPairArray[i].m_cityFrom) + " and " + AITown.GetName(m_nearCityPairArray[i].m_cityTo) + " in m_nearCityPairArray[" + i + "]");
                m_nearCityPairArray.remove(i);
            }
        }

		if (usedCities) {
//		    AILog.Info(m_usedCities.Count() + " found in m_usedCities");
		    local removeList = AIList();
		    for (local u = m_usedCities.Begin(); !m_usedCities.IsEnd(); m_usedCities.Next()) {
		        local removeTown = true;
			    for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
		    	    if (u == m_nearCityPairArray[i].m_cityFrom || u == m_nearCityPairArray[i].m_cityTo) {
			    	    removeTown = false;
			    	}
			    }
			    if (removeTown) {
//			        AILog.Info("Town " + AITown.GetName(u) + " is being removed (removeUsedCityPair)");
			        removeList.AddItem(u, 0);
			    }
		    }

		    m_usedCities.RemoveList(removeList);
		}
	}

    function findNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass) {
//		AILog.Info("fromCity = " + fromCity + "; minDistance = " + minDistance + "; maxDistance = " + maxDistance + "; bestRoutesBuilt = " + bestRoutesBuilt + "; cargoClass = " + cargoClass);
		BuildTownList();

        local localCityList = AIList();
        localCityList.AddList(m_townList);
        localCityList.RemoveList(m_usedCities);
        localCityList.RemoveItem(fromCity); //remove self

        local localPairList = AIList();

        for (local toCity = localCityList.Begin(); !localCityList.IsEnd(); toCity = localCityList.Next()) {

            local distance = AITown.GetDistanceManhattanToTile(fromCity, AITown.GetLocation(toCity));
            if ((distance > maxDistance) || (distance < minDistance)) {
                //AILog.Warning("findNearCity:: Distance too long between " + AITown.GetName(fromCity) + " and " + AITown.GetName(toCity)) ;
            }
            else {
//				AILog.Info("Added " + AITown.GetName(toCity) + " to localPairList, distance = " + distance + " tiles.");
                localPairList.AddItem(toCity, 0);
            }
        }

        if (!localPairList.Count()) {
            return;
        }

		local pick_mode = AIController.GetSetting("pick_mode");
        if (pick_mode == 1) {
            local randomLocalListItemIndex = AIBase.RandRange(localPairList.Count() - 1);
            local toCity = Utils.getNthItem(localPairList, randomLocalListItemIndex);

			local exists = false;
			for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
			    if (m_nearCityPairArray[i].isEqual(fromCity, toCity)) {
				    exists = true;
					break;
				}
			}

			if (!exists) {
                m_nearCityPairArray.append(TownPair(fromCity, toCity));
				return;
			}
        }
        else {
			local fromCity_tile = AITown.GetLocation(fromCity);
			local cargo = Utils.getCargoId(cargoClass);
            localPairList.Valuate(AITown.GetLastMonthProduction, cargo);
            localPairList.Sort(AIList.SORT_BY_VALUE, false);	
			if (pick_mode >= 2) {
				if (!bestRoutesBuilt) {
					localPairList.KeepAboveValue(cargoClass == AICargo.CC_PASSENGERS ? 70 : 35);
				}
				if (!localPairList.Count()) {
					return;
				}
				localPairList.Valuate(AITown.GetDistanceManhattanToTile, fromCity_tile);
				localPairList.Sort(AIList.SORT_BY_VALUE, (pick_mode == 2 ? AIList.SORT_ASCENDING : AIList.SORT_DESCENDING));
			}

//			for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
//				AILog.Info("From " + AITown.GetName(fromCity) + " to " + AITown.GetName(toCity) + " (" + AITown.GetDistanceManhattanToTile(toCity, fromCity_tile) + " tiles)");
//			}

            if (!bestRoutesBuilt) {				
                local exists = false;
                for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
                    if (m_nearCityPairArray[i].isEqual(fromCity, localPairList.Begin())) {
                        exists = true;
                        break;
                    }
                }

                if (!exists) {
                    m_nearCityPairArray.append(TownPair(fromCity, localPairList.Begin()));
                    return;
                }
            } else {
                for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
                    local exists = false;
                    for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
                        if (m_nearCityPairArray[i].isEqual(fromCity, toCity)) {
                            exists = true;
                            break;
                        }
                    }

                    if (!exists) {
                        m_nearCityPairArray.append(TownPair(fromCity, toCity));
                    }
                }
            }
        }

        return;
    }
    
    function saveTownManager() {
        local pairTable = {};
        for(local i = 0; i < m_nearCityPairArray.len(); ++i) {
            pairTable.rawset(i, m_nearCityPairArray[i].saveTownPair());
        }

        local usedTownsTable = {};
        for(local town = m_usedCities.Begin(), i = 0; !m_usedCities.IsEnd(); town = m_usedCities.Next(), ++i) {
            usedTownsTable.rawset(i, town);
        }

        return [pairTable, usedTownsTable];
    }

    function loadTownManager(data) {
        if(m_nearCityPairArray == null) {
            m_nearCityPairArray = [];
        }

        if(m_usedCities == null) {
            m_usedCities = AIList();
        }

        local pairTable = data[0];

        local i = 0;
        while(pairTable.rawin(i)) {
            local pair = TownPair.loadPair(pairTable.rawget(i));
            m_nearCityPairArray.append(pair);

            ++i;
        }
        AILog.Info("Loaded " + m_nearCityPairArray.len() + " near city pairs.");

        local usedTownsTable = data[1];

        i = 0;
        while(usedTownsTable.rawin(i)) {
            local town = usedTownsTable.rawget(i);
            m_usedCities.AddItem(town, 0);

            ++i;
        }
        AILog.Info("Loaded " + m_usedCities.Count() + " used cities.");
    }

}