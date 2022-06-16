class LuDiAIAfterFix extends AIInfo {
	function GetAuthor()        { return "lukin_, Samu"; }
	function GetName()          { return "LuDiAI AfterFix"; }
	function GetDescription()   { return "Transports passengers and mail with trucks, buses, airplanes, helicopters and ships"; }
	function GetVersion()       { return 20; }
	function MinVersionToLoad() { return 19; }
	function GetDate()          { return "16-06-2022"; }
	function CreateInstance()   { return "LuDiAIAfterFix"; }
	function GetShortName()     { return "LDAF"; }
	function GetAPIVersion()    { return "12"; }
	function GetURL()           { return "https://www.tt-forums.net/viewtopic.php?f=65&t=83806"; }
	function UseAsRandomAI()    { return true; }

	function GetSettings() {
		AddSetting({
			name = "select_town_cargo",
			description = "Town cargo",
			easy_value = 2,
			medium_value = 2,
			hard_value = 2,
			custom_value = 0,
			flags = CONFIG_RANDOM,
			min_value = 0,
			max_value = 2
		});

		AddLabels("select_town_cargo", {
			_0 = "Passengers",
			_1 = "Mail",
			_2 = "Passengers and Mail"
		});

		AddSetting({
			name = "pick_mode",
			description = "Town choice priority",
			easy_value = 1,
			medium_value = 2,
			hard_value = 0,
			custom_value = 0,
			flags =  CONFIG_RANDOM,
			min_value = 0,
			max_value = 3
		});

		AddLabels("pick_mode", {
			_0 = "Most cargo produced first",
			_1 = "None, pick at random",
			_2 = "Shorter routes first",
			_3 = "Longer routes first"
		});

		AddSetting({
			name = "is_friendly",
			description = "Is friendly",
			easy_value = 1,
			medium_value = 1,
			hard_value = 0,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
		});

		AddSetting({
			name = "station_spread",
			description = "Can station spread",
			easy_value = 0,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
		});

		AddSetting({
			name = "road_support",
			description = "Road support",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "water_support",
			description = "Water support",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "air_support",
			description = "Air support",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_INGAME
		});

		AddSetting({
			name = "road_days_in_transit",
			description = "Approximate number of days in transit for road routes",
			min_value = 10,
			max_value = 150,
			easy_value = 30,
			medium_value = 45,
			hard_value = 65,
			custom_value = 85,
			random_deviation = 5,
			step_size = 5,
			flags = CONFIG_NONE
		});

		AddSetting({
			name = "pf_profile",
			description = "Road pathfinder profile",
			easy_value = 0,
			medium_value = 1,
			hard_value = 2,
			custom_value = 0,
			flags = CONFIG_RANDOM | CONFIG_INGAME,
			min_value = 0,
			max_value = 2
		});

		AddLabels("pf_profile", {
			_0 = "Custom",
			_1 = "Default",
			_2 = "Fastest"
		});

		AddSetting({
			name = "road_cap_mode",
			description = "Road route capacity mode",
			easy_value = 1,
			medium_value = 0,
			hard_value = 2,
			custom_value = 1,
			flags = CONFIG_RANDOM | CONFIG_INGAME,
			min_value = 0,
			max_value = 2
		});

		AddLabels("road_cap_mode", {
			_0 = "Maximum of 25 road vehicles",
			_1 = "Estimate maximum number of road vehicles",
			_2 = "Adjust number of road vehicles dynamically"
		});

		AddSetting({
			name = "road_load_mode",
			description = "Road route load orders mode",
			easy_value = 2,
			medium_value = 2,
			hard_value = 1,
			custom_value = 0,
			flags = CONFIG_RANDOM | CONFIG_INGAME,
			min_value = 0,
			max_value = 2
		});

		AddLabels("road_load_mode", {
			_0 = "Full load before departing",
			_1 = "Load something before departing",
			_2 = "May load nothing before departing"
		});

		AddSetting({
			name = "water_days_in_transit",
			description = "Approximate number of days in transit for water routes",
			min_value = 10,
			max_value = 150,
			easy_value = 30,
			medium_value = 45,
			hard_value = 65,
			custom_value = 85,
			random_deviation = 5,
			step_size = 5,
			flags = CONFIG_NONE
		});


		AddSetting({
			name = "water_cap_mode",
			description = "Water route capacity mode",
			easy_value = 1,
			medium_value = 0,
			hard_value = 2,
			custom_value = 1,
			flags = CONFIG_RANDOM | CONFIG_INGAME,
			min_value = 0,
			max_value = 2
		});

		AddLabels("water_cap_mode", {
			_0 = "Maximum of 10 ships",
			_1 = "Estimate maximum number of ships",
			_2 = "Adjust number of ships dynamically"
		});

		AddSetting({
			name = "water_load_mode",
			description = "Water route load orders mode",
			easy_value = 1,
			medium_value = 1,
			hard_value = 0,
			custom_value = 0,
			flags = CONFIG_RANDOM | CONFIG_INGAME,
			min_value = 0,
			max_value = 1
		});

		AddLabels("water_load_mode", {
			_0 = "Load something before departing",
			_1 = "May load nothing before departing"
		});

		AddSetting({
			name = "air_load_mode",
			description = "Air route load orders mode",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 0,
			flags = CONFIG_RANDOM | CONFIG_INGAME,
			min_value = 0,
			max_value = 1
		});

		AddLabels("air_load_mode", {
			_0 = "Full load before departing",
			_1 = "May load nothing before departing"
		});

		AddSetting({
			name = "build_statues",
			description = "Build company statues in towns",
			easy_value = 0,
			medium_value = 1,
			hard_value = 1,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
		});

		AddSetting({
			name = "advertise",
			description = "Run advertising campaigns in towns",
			easy_value = 0,
			medium_value = 0,
			hard_value = 1,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
		});

		AddSetting({
			name = "fund_buildings",
			description = "Fund construction of new buildings in towns",
			easy_value = 0,
			medium_value = 0,
			hard_value = 1,
			custom_value = 1,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
		});

		AddSetting({
			name = "found_towns",
			description = "Found towns",
			easy_value = 0,
			medium_value = 0,
			hard_value = 1,
			custom_value = 0,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
		});

		AddSetting({
			name = "build_hq",
			description = "Build headquarters",
			easy_value = 1,
			medium_value = 1,
			hard_value = 1,
			custom_value = 0,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM | CONFIG_INGAME
		});

		AddSetting({
			name = "scp_support",
			description = "AI-GS communication support",
			easy_value = 0,
			medium_value = 0,
			hard_value = 0,
			custom_value = 0,
			flags = CONFIG_BOOLEAN | CONFIG_RANDOM
		});
	}
}

RegisterAI(LuDiAIAfterFix());
