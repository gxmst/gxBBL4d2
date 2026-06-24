// gxLdBot prototype entry point.
// L4D2 loads director_base_addon.nut from script addons.

if (!("GxLdBot_Loaded" in getroottable())) {
	::GxLdBot_Loaded <- true;
	IncludeScript("gxldbot/main");
}
