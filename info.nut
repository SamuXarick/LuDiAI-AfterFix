class LuDiAIAfterFix extends AIInfo
{
	function GetAuthor()        { return "lukin_, Samu"; }
	function GetName()          { return "LuDiAI AfterFix"; }
	function GetDescription()   { return "Transports passengers and mail with trucks, buses, airplanes, helicopters, ships and trains"; }
	function GetVersion()       { return 26; }
	function MinVersionToLoad() { return 26; }
	function GetDate()          { return "11-04-2026"; }
	function CreateInstance()   { return "LuDiAIAfterFix"; }
	function GetShortName()     { return "LDAF"; }
	function GetAPIVersion()    { return "15"; }
	function GetURL()           { return "https://www.tt-forums.net/viewtopic.php?f=65&t=83806"; }
	function UseAsRandomAI()    { return true; }

	function GetSettings()
	{
		AIInfo.AddSetting({
			name = "select_town_cargo",
			description = "Town cargo",
			min_value = 0,
			max_value = 2,
			default_value = 2,
			flags = AIInfo.CONFIG_NONE,
		});

		AIInfo.AddLabels("select_town_cargo", {
			_0 = "Passengers",
			_1 = "Mail",
			_2 = "Passengers and Mail",
		});

		AIInfo.AddSetting({
			name = "randomize_towns",
			description = "Randomize town choices",
			default_value = 0,
			flags = AIInfo.CONFIG_BOOLEAN,
		});

		AIInfo.AddSetting({
			name = "is_friendly",
			description = "Is friendly",
			default_value = 0,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "station_spread",
			description = "Can station spread",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "rail_support",
			description = "Rail support",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "road_support",
			description = "Road support",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "water_support",
			description = "Water support",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "air_support",
			description = "Air support",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "exclusive_attempt_days",
			description = "Days dedicated to exclusively attempting a transport mode",
			min_value = 0,
			max_value = 1000,
			default_value = 60,
			step_size = 5,
			flags = AIInfo.CONFIG_INGAME,
		});

		AddSetting({
			name = "rail_pf_profile",
			description = "Rail pathfinder profile",
			min_value = 0,
			max_value = 2,
			default_value = 2,
			flags = AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddLabels("rail_pf_profile", {
			_0 = "SingleRail",
			_1 = "DoubleRail",
			_2 = "RailRedux",
		});

		AIInfo.AddSetting({
			name = "pf_profile",
			description = "Road pathfinder profile",
			min_value = 0,
			max_value = 2,
			default_value = 2,
			flags = AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddLabels("pf_profile", {
			_0 = "Custom",
			_1 = "Default",
			_2 = "Fastest",
		});

		AIInfo.AddSetting({
			name = "road_load_mode",
			description = "Road route load orders mode",
			min_value = 0,
			max_value = 2,
			default_value = 1,
			flags = AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddLabels("road_load_mode", {
			_0 = "Full load before departing",
			_1 = "Load something before departing",
			_2 = "May load nothing before departing",
		});

		AIInfo.AddSetting({
			name = "water_cap_mode",
			description = "Water route capacity mode",
			min_value = 0,
			max_value = 2,
			default_value = 2,
			flags = AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddLabels("water_cap_mode", {
			_0 = "Maximum of 10 ships",
			_1 = "Estimate maximum number of ships",
			_2 = "Adjust number of ships dynamically",
		});

		AIInfo.AddSetting({
			name = "water_load_mode",
			description = "Water route load orders mode",
			min_value = 0,
			max_value = 1,
			default_value = 0,
			flags = AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddLabels("water_load_mode", {
			_0 = "Load something before departing",
			_1 = "May load nothing before departing",
		});

		AIInfo.AddSetting({
			name = "air_load_mode",
			description = "Air route load orders mode",
			min_value = 0,
			max_value = 1,
			default_value = 1,
			flags = AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddLabels("air_load_mode", {
			_0 = "Full load before departing",
			_1 = "May load nothing before departing",
		});

		AIInfo.AddSetting({
			name = "build_statues",
			description = "Build company statues in towns",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "advertise",
			description = "Run advertising campaigns in towns",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "fund_buildings",
			description = "Fund construction of new buildings in towns",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "found_towns",
			description = "Found towns",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "exclusive_rights",
			description = "Buy exclusive transport rights in towns",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "bribe_authority",
			description = "Bribe towns to abort competitors' exclusive transport rights",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});

		AIInfo.AddSetting({
			name = "build_hq",
			description = "Build headquarters",
			default_value = 1,
			flags = AIInfo.CONFIG_BOOLEAN | AIInfo.CONFIG_INGAME,
		});
	}
};

RegisterAI(LuDiAIAfterFix());
