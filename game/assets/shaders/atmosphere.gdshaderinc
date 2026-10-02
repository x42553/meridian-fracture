// Atmosphere globals written by ViewAtmosphere.apply_mood(); used for fake sky reflections, glitter and drifting cloud
// shadows so every material agrees with the WorldEnvironment without probes. atm_night lives in view_common.gdshaderinc.
global uniform vec3 atm_sun_dir;       // unit vector pointing TO the sun (world space)
global uniform vec3 atm_sun_color;     // linear, energy scaled
global uniform vec3 atm_sky_horizon;   // linear
global uniform vec3 atm_sky_zenith;    // linear
global uniform vec4 atm_cloud;         // x = shadow strength, y = scale (1/m), zw = drift (m/s)
