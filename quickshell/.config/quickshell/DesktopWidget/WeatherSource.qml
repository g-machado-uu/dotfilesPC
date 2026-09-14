import Quickshell
import Quickshell.Io
import QtQuick

// Weather for the desktop widget and the control centre, from Open-Meteo (free,
// no key, no account).
//
// Each surface keeps its own instance rather than sharing one: they come and
// go independently, and one of them should not dictate when the other
// refreshes. Using the same component still means both show the same readings
// in the same units.
Item {
    id: src

    // Free-text place name, e.g. "Belfast, UK". Anything after the first comma
    // is a hint used to pick between same-named places rather than being sent
    // to the geocoder.
    property string location: "Belfast, UK"

    // Set false by the widget while it is off screen: there is no point
    // refreshing weather nobody can see.
    property bool active: true

    // Set by the widget while its sections are in flight. A fetch landing
    // mid-animation would parse a document, rebuild the forecast row and resize
    // the surface in one of the frames that should have been spent moving, so
    // refreshes wait for the widget to stand still.
    property bool busy: false

    readonly property bool loaded: _loaded
    property bool _loaded: false
    property string error: ""

    property string place: ""
    property real latitude: NaN
    property real longitude: NaN

    // --- CURRENT CONDITIONS ---
    property int code: 0
    property bool isDay: true
    property real temperature: 0
    property real apparent: 0
    property int humidity: 0
    // Wind is requested in knots (wind_speed_unit=kn) so it can be reported the
    // way an aviation METAR does.
    property real windSpeed: 0
    property int windDirection: 0
    property real windGust: 0
    // Mean sea level pressure, i.e. the QNH, in hPa.
    property real pressure: 0
    property real todayMin: 0
    property real todayMax: 0

    // Three entries of { day, code, min, max } for the days after today.
    property var forecast: []

    // Rounded degrees, the one temperature format used across the widget.
    function fmt(t: real): string {
        return Math.round(t) + "°"
    }

    function pad(n: int, width: int): string {
        let s = String(Math.round(n))
        while (s.length < width)
            s = "0" + s
        return s
    }

    // The wind group of a METAR: direction the wind blows *from*, rounded to
    // the nearest ten degrees, then the mean speed in knots — "19008KT". Calm
    // is "00000KT", north is 360 rather than 000, and a gust is appended only
    // when it runs 10 knots or more above the mean, which is the reporting
    // rule METAR uses.
    // Takes its readings as arguments rather than reaching for the properties
    // directly, so the binding below re-evaluates whenever one of them changes;
    // a no-argument call would be bound to nothing and go stale after the first
    // fetch.
    function metarWind(speed: real, direction: int, gust: real): string {
        const kt = Math.round(speed)
        if (kt < 1)
            return "00000KT"
        let dir = Math.round(direction / 10) * 10
        if (dir <= 0)
            dir = 360
        else if (dir > 360)
            dir = dir % 360
        const g = Math.round(gust)
        const gustPart = (g - kt >= 10) ? "G" + src.pad(g, 2) : ""
        return src.pad(dir, 3) + src.pad(kt, 2) + gustPart + "KT"
    }

    readonly property string windMetar:
        src.metarWind(src.windSpeed, src.windDirection, src.windGust)

    // ------------------------------------------------------------------
    // GEOCODING
    // ------------------------------------------------------------------
    function geocode(): void {
        const parts = src.location.split(",")
        const name = parts[0].trim()
        if (name === "")
            return
        geoProc.command = ["bash", "-c",
            "curl -s --max-time 12 'https://geocoding-api.open-meteo.com/v1/search?name="
            + encodeURIComponent(name) + "&count=10&language=en&format=json'"]
        geoProc.running = false
        geoProc.running = true
    }

    Process {
        id: geoProc
        stdout: StdioCollector {
            onStreamFinished: {
                const hint = src.location.split(",").slice(1).join(",").trim().toLowerCase()
                try {
                    const res = JSON.parse(this.text).results
                    if (!res || res.length === 0) {
                        src.error = "Location not found"
                        return
                    }
                    let pick = res[0]
                    if (hint !== "") {
                        for (let i = 0; i < res.length; i++) {
                            const r = res[i]
                            const hay = [r.country, r.country_code, r.admin1]
                                .filter(v => v !== undefined)
                                .join(" ").toLowerCase()
                            if (hay.indexOf(hint) >= 0) {
                                pick = r
                                break
                            }
                        }
                    }
                    src.latitude = pick.latitude
                    src.longitude = pick.longitude
                    src.place = pick.name
                        + (pick.country_code ? ", " + pick.country_code : "")
                    src.error = ""
                    src.fetch()
                } catch (e) {
                    src.error = "No connection"
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // FORECAST
    // ------------------------------------------------------------------
    function fetch(): void {
        if (isNaN(src.latitude))
            return
        weatherProc.command = ["bash", "-c",
            "curl -s --max-time 12 'https://api.open-meteo.com/v1/forecast?latitude="
            + src.latitude + "&longitude=" + src.longitude
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature"
            + ",is_day,weather_code,wind_speed_10m,wind_direction_10m"
            + ",wind_gusts_10m,pressure_msl"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
            + "&wind_speed_unit=kn"
            + "&timezone=auto&forecast_days=4'"]
        weatherProc.running = false
        weatherProc.running = true
    }

    Process {
        id: weatherProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    src.temperature = d.current.temperature_2m
                    src.code = d.current.weather_code
                    src.isDay = d.current.is_day === 1
                    src.apparent = d.current.apparent_temperature
                    src.humidity = d.current.relative_humidity_2m
                    src.windSpeed = d.current.wind_speed_10m
                    src.windDirection = d.current.wind_direction_10m
                    src.windGust = d.current.wind_gusts_10m
                    src.pressure = d.current.pressure_msl
                    src.todayMax = d.daily.temperature_2m_max[0]
                    src.todayMin = d.daily.temperature_2m_min[0]

                    const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                    let out = []
                    // Skip index 0 (today) — the section above already covers it.
                    for (let i = 1; i < d.daily.time.length && i < 4; i++) {
                        out.push({
                            "day": names[new Date(d.daily.time[i] + "T12:00:00").getDay()],
                            "code": d.daily.weather_code[i],
                            "min": d.daily.temperature_2m_min[i],
                            "max": d.daily.temperature_2m_max[i]
                        })
                    }
                    src.forecast = out
                    src._loaded = true
                    src.error = ""
                } catch (e) {
                    src.error = "No connection"
                }
            }
        }
    }

    // Re-geocode when the place changes, otherwise just re-fetch.
    function refresh(): void {
        if (isNaN(src.latitude))
            src.geocode()
        else
            src.fetch()
    }

    onLocationChanged: {
        src.latitude = NaN
        src._loaded = false
        src.geocode()
    }

    Component.onCompleted: src.geocode()

    // The widget is on screen from the moment the session starts, which is
    // usually before the network is up, so the first few attempts are expected
    // to fail. Retry quickly until something lands, then settle into a slow
    // refresh.
    Timer {
        interval: src._loaded ? 15 * 60 * 1000 : 20 * 1000
        repeat: true
        running: true
        onTriggered: src.refreshWhenStill()
    }

    // Hold a refresh back until nothing is moving, then run it.
    function refreshWhenStill(): void {
        stillness.restart()
    }

    Timer {
        id: stillness
        interval: 250
        onTriggered: {
            if (src.busy)
                stillness.restart()
            else
                src.refresh()
        }
    }

    // Catch up as soon as the widget comes back on screen, so a machine that
    // was asleep for hours is not showing yesterday's weather.
    onActiveChanged: {
        if (src.active)
            src.refreshWhenStill()
    }
}
