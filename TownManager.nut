class TownPair {
	m_cityFrom = null;
	m_cityTo = null;
	m_cargoClass = null;

	constructor(cityFrom, cityTo, cargoClass) {
		m_cityFrom = cityFrom;
		m_cityTo = cityTo;
		m_cargoClass = cargoClass;
	}

	function isEqual(cityFrom, cityTo, cargoClass) {
		if ((m_cityFrom == cityFrom) && (m_cityTo == cityTo) && (m_cargoClass == cargoClass)) {
			return 1;
		}

		if ((m_cityFrom == cityTo) && (m_cityTo == cityFrom) && (m_cargoClass == cargoClass)) {
			return 1;
		}

		return 0;
	}
	
	function hasCargoClass(cargoClass) {
		if (m_cargoClass == cargoClass) {
			return 1;
		}
		
		return 0;
	}

	function saveTownPair() {
		local pair = [];

		pair.append(m_cityFrom);
		pair.append(m_cityTo);
		pair.append(m_cargoClass);

		return pair;
	}

	function loadPair(data) {
		local cityFrom = data[0];
		local cityTo = data[1];
		local cargoClass = data[2];

		return TownPair(cityFrom, cityTo, cargoClass);
	}
}

class TownManager {
	m_townList = null;

	m_nearCityPairArray = null;
	m_usedCitiesPass = null;
	m_usedCitiesMail = null;

	constructor() {

		m_townList = BuildTownList();

		m_nearCityPairArray = [];
		m_usedCitiesPass = AIList();
		m_usedCitiesMail = AIList();
	}

	function getUnusedCity(bestRoutesBuilt, cargoClass);
	function removeUsedCityPair(fromCity, toCity, usedCities);
	function findNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass);
	function BuildTownList();
	function HasArrayCargoClassPairs(cargoClass);
	function ClearCargoClassArray(cargoClass);
	
	function ClearCargoClassArray(cargoClass) {
		for (local i = m_nearCityPairArray.len() - 1; i >= 0; --i) {
			if (m_nearCityPairArray[i].hasCargoClass(cargoClass)) {
				m_nearCityPairArray.remove(i);
			}
		}
	}
	
	function HasArrayCargoClassPairs(cargoClass) {
		for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
			if (m_nearCityPairArray[i].hasCargoClass(cargoClass)) {
				return true;
			}
		}
		return false;
	}

	function GetLastMonthProductionDiffRate(town, cargo) {
		return (AITown.GetLastMonthProduction(town, cargo) - AITown.GetLastMonthSupplied(town, cargo)) * (100 - AITown.GetLastMonthTransportedPercentage(town, cargo)) / 100;
	}

	function BuildTownList() {
		m_townList = AITownList();
		if (AIController.GetSetting("cities_only")) {
			m_townList = AITownList();
			local removelist = AIList();
			for (local town = m_townList.Begin(); !m_townList.IsEnd(); town = m_townList.Next()) {
				if (!AITown.IsCity(town)) {
					removelist.AddItem(town, 0);
				}
			}
			m_townList.RemoveList(removelist);
		}
	}

	function getUnusedCity(bestRoutesBuilt, cargoClass) {
		BuildTownList();

		if (m_townList.Count() == (cargoClass == AICargo.CC_PASSENGERS ? m_usedCitiesPass.Count() : m_usedCitiesMail.Count())) {
			return null;
		}

		local localList = AIList();
		localList.AddList(m_townList);
		localList.RemoveList(cargoClass == AICargo.CC_PASSENGERS ? m_usedCitiesPass : m_usedCitiesMail);

		local unusedTown = null;
		local pick_mode = AIController.GetSetting("pick_mode");
		if (pick_mode == 1) {
			local randomLocalListItemIndex = AIBase.RandRange(localList.Count());
			unusedTown = Utils.getNthItem(localList, randomLocalListItemIndex);
			if (cargoClass == AICargo.CC_PASSENGERS) {
				m_usedCitiesPass.AddItem(unusedTown, 0);
			} else {
				m_usedCitiesMail.AddItem(unusedTown, 0);
			}
		}
		else {
			local cargo = Utils.getCargoId(cargoClass);
			for (local town = localList.Begin(); !localList.IsEnd(); town = localList.Next()) {
				localList.SetValue(town, (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, cargo) : AITown.GetLastMonthProduction(town, cargo)));
			}
			localList.Sort(AIList.SORT_BY_VALUE, false);

			if (!bestRoutesBuilt) {
				local cargolimit = cargoClass == AICargo.CC_PASSENGERS ? 70 : 35;

				local templist = AIList();
				templist.AddList(localList);
				for (local town = localList.Begin(); !localList.IsEnd(); town = localList.Next()) {
					if (!Utils.IsTownGrowing(town, cargo)) {
						templist.RemoveItem(town);
						continue;
					}
					if (localList.GetValue(town) <= cargolimit) {
						templist.RemoveItem(town);
						continue;
					}
				}
				localList.KeepList(templist);
			}

			if (localList.Count()) {
				unusedTown = localList.Begin();
				if (cargoClass == AICargo.CC_PASSENGERS) {
					m_usedCitiesPass.AddItem(unusedTown, 0);
				} else {
					m_usedCitiesMail.AddItem(unusedTown, 0);
				}
			}
		}

		return unusedTown;
	}

	function removeUsedCityPair(fromCity, toCity, cargoClass, usedCities) {
//		AILog.Info(m_nearCityPairArray.len() + " found in the m_nearCityPairArray");
//		AILog.Info("Town pair " + AITown.GetName(fromCity) + " and " + AITown.GetName(toCity) + "( " + AICargo.GetCargoLabel(Utils.getCargoId(cargoClass)) + ") are being removed...");
		for (local i = m_nearCityPairArray.len() - 1; i >= 0; --i) {
			if (m_nearCityPairArray[i].isEqual(fromCity, toCity, cargoClass)) {
//				AILog.Info("Found pair " + AITown.GetName(m_nearCityPairArray[i].m_cityFrom) + " and " + AITown.GetName(m_nearCityPairArray[i].m_cityTo) + "( " + AICargo.GetCargoLabel(Utils.getCargoId(m_nearCityPairArray[i].m_cargoClass)) + ") in m_nearCityPairArray[" + i + "]");
				m_nearCityPairArray.remove(i);
			}
		}

		if (usedCities) {
			if (cargoClass == AICargo.CC_PASSENGERS) {
//				AILog.Info(m_usedCitiesPass.Count() + " found in m_usedCitiesPass");
				local removeList = AIList();
				for (local u = m_usedCitiesPass.Begin(); !m_usedCitiesPass.IsEnd(); m_usedCitiesPass.Next()) {
					local removeTown = true;
					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
						if ((u == m_nearCityPairArray[i].m_cityFrom || u == m_nearCityPairArray[i].m_cityTo) && m_nearCityPairArray[i].m_cargoClass == cargoClass) {
							removeTown = false;
						}
					}
					if (removeTown) {
//						AILog.Info("Town " + AITown.GetName(u) + " is being removed (removeUsedCityPair)");
						removeList.AddItem(u, 0);
					}
				}

				m_usedCitiesPass.RemoveList(removeList);
			} else {
//				AILog.Info(m_usedCitiesMail.Count() + " found in m_usedCitiesMail");
				local removeList = AIList();
				for (local u = m_usedCitiesMail.Begin(); !m_usedCitiesMail.IsEnd(); m_usedCitiesMail.Next()) {
					local removeTown = true;
					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
						if ((u == m_nearCityPairArray[i].m_cityFrom || u == m_nearCityPairArray[i].m_cityTo) && m_nearCityPairArray[i].m_cargoClass == cargoClass) {
							removeTown = false;
						}
					}
					if (removeTown) {
//						AILog.Info("Town " + AITown.GetName(u) + " is being removed (removeUsedCityPair)");
						removeList.AddItem(u, 0);
					}
				}

				m_usedCitiesMail.RemoveList(removeList);
			}
		}
	}

	function findNearCities(fromCity, minDistance, maxDistance, bestRoutesBuilt, cargoClass) {
//		AILog.Info("fromCity = " + fromCity + "; minDistance = " + minDistance + "; maxDistance = " + maxDistance + "; bestRoutesBuilt = " + bestRoutesBuilt + "; cargoClass = " + cargoClass);
		BuildTownList();

		local localCityList = AIList();
		localCityList.AddList(m_townList);
		localCityList.RemoveList(cargoClass == AICargo.CC_PASSENGERS ? m_usedCitiesPass : m_usedCitiesMail);
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
			local randomLocalListItemIndex = AIBase.RandRange(localPairList.Count());
			local toCity = Utils.getNthItem(localPairList, randomLocalListItemIndex);

			local exists = false;
			for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
				if (m_nearCityPairArray[i].isEqual(fromCity, toCity, cargoClass)) {
					exists = true;
					break;
				}
			}

			if (!exists) {
				m_nearCityPairArray.append(TownPair(fromCity, toCity, cargoClass));
				return;
			}
		}
		else {
			local fromCity_tile = AITown.GetLocation(fromCity);
			local cargo = Utils.getCargoId(cargoClass);
			local cargolimit = cargoClass == AICargo.CC_PASSENGERS ? 70 : 35;
			for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
				localPairList.SetValue(town, (pick_mode == 0 ? TownManager.GetLastMonthProductionDiffRate(town, cargo) : AITown.GetLastMonthProduction(town, cargo)));
			}
			localPairList.Sort(AIList.SORT_BY_VALUE, false);

			if (!bestRoutesBuilt) {
				local templist = AIList();
				templist.AddList(localPairList);
				for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
					if (pick_mode != 1 && !Utils.IsTownGrowing(town, cargo)) {
						templist.RemoveItem(town);
						continue;
					}
					if (pick_mode >= 2 && localPairList.GetValue(town) <= cargolimit) {
						templist.RemoveItem(town);
						continue;
					}
				}
				localPairList.KeepList(templist);
			}
			
			if (!localPairList.Count()) {
				return;
			}

			if (pick_mode >= 2) {
				for (local town = localPairList.Begin(); !localPairList.IsEnd(); town = localPairList.Next()) {
					localPairList.SetValue(town, AITown.GetDistanceManhattanToTile(town, fromCity_tile));
				}
				localPairList.Sort(AIList.SORT_BY_VALUE, (pick_mode == 2 ? AIList.SORT_ASCENDING : AIList.SORT_DESCENDING));
			}

//			for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
//				AILog.Info("From " + AITown.GetName(fromCity) + " to " + AITown.GetName(toCity) + " (" + AITown.GetDistanceManhattanToTile(toCity, fromCity_tile) + " tiles)");
//			}

			if (!bestRoutesBuilt) {
				local exists = false;
				for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
					if (m_nearCityPairArray[i].isEqual(fromCity, localPairList.Begin(), cargoClass)) {
						exists = true;
						break;
					}
				}

				if (!exists) {
					m_nearCityPairArray.append(TownPair(fromCity, localPairList.Begin(), cargoClass));
					return;
				}
			} else {
				for (local toCity = localPairList.Begin(); !localPairList.IsEnd(); toCity = localPairList.Next()) {
					local exists = false;
					for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
						if (m_nearCityPairArray[i].isEqual(fromCity, toCity, cargoClass)) {
							exists = true;
							break;
						}
					}

					if (!exists) {
						m_nearCityPairArray.append(TownPair(fromCity, toCity, cargoClass));
					}
				}
			}
		}

		return;
	}

	function saveTownManager() {
		local pairTable = {};
		for (local i = 0; i < m_nearCityPairArray.len(); ++i) {
			pairTable.rawset(i, m_nearCityPairArray[i].saveTownPair());
		}

		local usedTownsPassTable = {};
		for (local town = m_usedCitiesPass.Begin(), i = 0; !m_usedCitiesPass.IsEnd(); town = m_usedCitiesPass.Next(), ++i) {
			usedTownsPassTable.rawset(i, town);
		}
		
		local usedTownsMailTable = {};
		for (local town = m_usedCitiesMail.Begin(), i = 0; !m_usedCitiesMail.IsEnd(); town = m_usedCitiesMail.Next(), ++i) {
			usedTownsMailTable.rawset(i, town);
		}

		return [pairTable, usedTownsPassTable, usedTownsMailTable];
	}

	function loadTownManager(data) {
		if (m_nearCityPairArray == null) {
			m_nearCityPairArray = [];
		}

		if (m_usedCitiesPass == null) {
			m_usedCitiesPass = AIList();
		}
		
		if (m_usedCitiesMail == null) {
			m_usedCitiesMail = AIList();
		}

		local pairTable = data[0];

		local i = 0;
		while(pairTable.rawin(i)) {
			local pair = TownPair.loadPair(pairTable.rawget(i));
			m_nearCityPairArray.append(pair);

			++i;
		}
		AILog.Info("Loaded " + m_nearCityPairArray.len() + " near city pairs.");

		local usedTownsPassTable = data[1];

		i = 0;
		while(usedTownsPassTable.rawin(i)) {
			local town = usedTownsPassTable.rawget(i);
			m_usedCitiesPass.AddItem(town, 0);

			++i;
		}
		AILog.Info("Loaded " + m_usedCitiesPass.Count() + " used cities Pass.");
		
		local usedTownsMailTable = data[2];

		i = 0;
		while(usedTownsMailTable.rawin(i)) {
			local town = usedTownsMailTable.rawget(i);
			m_usedCitiesMail.AddItem(town, 0);

			++i;
		}
		AILog.Info("Loaded " + m_usedCitiesMail.Count() + " used cities Mail.");
	}

}