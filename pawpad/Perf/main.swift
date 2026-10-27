// pawpad-perf: reads one recorded Pawpad session (pawpad/Worker/pawpad_recorder.h) and writes its
// report, or compares two. No dependencies beyond Foundation; runs in a second or two.
//
//   pawpad-perf report <session folder>       writes report.md and report.json there
//   pawpad-perf compare <session A> <session B>   prints A against B (from their report.json)
//
// What the numbers mean:
//   Frames on screen   Metal's presentedTime for each frame of the game's own window (DXMT's
//                      display log): what you saw. Time while the window wasn't on screen is
//                      left out, so a minimized game isn't a freeze.
//   1% / 0.1% low      the average frame rate of the slowest 1% / 0.1% of frames.
//   Stutter            a frame shown more than 50 ms (or 100 ms) after the one before.
//   Freeze             more than 0.5 s (or 2 s) without a new frame.
//   Slow frame         a frame that took more than twice the typical (median) time.
//   Present loop       the engine's own record of each frame the game finished (DXMT's frame
//                      log): GPU waits, pacing sleep and shader compiles explain the stutters.
import Foundation

// MARK: Reading

struct Table {
    var columns:[String:Int]=[:]
    var rows:[[Substring]]=[]
    func value(_ row:[Substring],_ name:String) -> Substring? {
        guard let i=columns[name],i<row.count else { return nil }
        return row[i]
    }
    func double(_ row:[Substring],_ name:String) -> Double? { value(row,name).flatMap { Double($0) } }
}
/// A CSV the engine or the recorder wrote (no quoted fields). Rotated segments (.2, .1, then the
/// current file) are read oldest first.
func readCSV(_ paths:[URL]) -> Table {
    var table=Table()
    for path in paths {
        guard let text=try? String(contentsOf:path,encoding:.utf8) else { continue }
        // Logs written inside Wine end their lines with \r\n, which Swift reads as one Character.
        var lines=text.split(whereSeparator:\.isNewline)
        guard !lines.isEmpty else { continue }
        let header=lines.removeFirst().split(separator:",",omittingEmptySubsequences:false).map(String.init)
        if table.columns.isEmpty { for (i,name) in header.enumerated() { table.columns[name]=i } }
        for line in lines { table.rows.append(line.split(separator:",",omittingEmptySubsequences:false)) }
    }
    return table
}
func segments(_ folder:URL,_ base:String) -> [URL] {
    [".2.csv",".1.csv",".csv"].map { folder.appendingPathComponent(base+$0) }.filter { FileManager.default.fileExists(atPath:$0.path) }
}
func readJSONLines(_ url:URL) -> [[String:Any]] {
    guard let text=try? String(contentsOf:url,encoding:.utf8) else { return [] }
    return text.split(whereSeparator:\.isNewline).compactMap { (try? JSONSerialization.jsonObject(with:Data($0.utf8))) as? [String:Any] }
}

// MARK: Statistics

func percentile(_ sorted:[Double],_ p:Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let position=Double(sorted.count-1)*p, low=Int(position.rounded(.down)), high=Int(position.rounded(.up))
    return sorted[low]+(sorted[high]-sorted[low])*(position-Double(low))
}
/// The average frame rate of the slowest FRACTION of frames, from frame times in ms.
func lowFPS(_ descending:[Double],_ fraction:Double) -> Double {
    guard !descending.isEmpty else { return 0 }
    let n=max(1,Int((Double(descending.count)*fraction).rounded()))
    let mean=descending.prefix(n).reduce(0,+)/Double(n)
    return mean>0 ? 1000/mean : 0
}
func r(_ x:Double,_ places:Int=1) -> Double { let f=pow(10,Double(places));return (x*f).rounded()/f }
struct Summary { var count=0, mean=0.0, max=0.0, min=0.0 }
func summary(_ values:[Double]) -> Summary {
    guard !values.isEmpty else { return Summary() }
    return Summary(count:values.count,mean:values.reduce(0,+)/Double(values.count),max:values.max()!,min:values.min()!)
}

// MARK: Report

func report(_ folder:URL) throws -> [String:Any] {
    let fm=FileManager.default
    let session=(try? JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("session.json")))) as? [String:Any] ?? [:]
    let events=readJSONLines(folder.appendingPathComponent("timeline.jsonl"))
    let system=readCSV([folder.appendingPathComponent("system.csv")])
    let files=(try? fm.contentsOfDirectory(atPath:folder.path)) ?? []

    // The game's runs and seconds when its window wasn't on screen.
    var gamePids:[Int]=events.filter { $0["kind"] as? String == "game_started" }.compactMap { $0["pid"] as? Int }
    var hidden=Set<Int>()
    var gameSeconds=Set<Int>()
    for row in system.rows {
        guard let ms=system.double(row,"unix_ms"),let pid=system.double(row,"game_pid"),pid>0 else { continue }
        gameSeconds.insert(Int(ms/1000))
        if system.value(row,"window_on_screen") == "0" { hidden.insert(Int(ms/1000)) }
    }
    if gamePids.isEmpty {
        // No timeline: the display log with the most rows.
        let candidates=files.filter { $0.hasPrefix("display-") && $0.hasSuffix(".csv") && !$0.contains(".hitches") && !$0.contains(".1.") && !$0.contains(".2.") }
        if let biggest=candidates.max(by:{ ((try? fm.attributesOfItem(atPath:folder.appendingPathComponent($0).path)[.size] as? Int) ?? 0) < ((try? fm.attributesOfItem(atPath:folder.appendingPathComponent($1).path)[.size] as? Int) ?? 0) }),
           let pid=Int(biggest.dropFirst("display-".count).dropLast(".csv".count)) { gamePids=[pid] }
    }

    // Frames on screen: per game process, the layer (swapchain) that showed the most frames.
    struct Shown { var at:Double; var unixMs:Double }
    var intervals:[(ms:Double,endUnixMs:Double)]=[], backgroundMs=0.0, shownFrames=0
    for pid in Set(gamePids) {
        let table=readCSV(segments(folder,"display-\(pid)"))
        var byLayer:[Substring:[Shown]]=[:]
        for row in table.rows where table.value(row,"event") == "presented" && table.value(row,"presented_state") == "valid" {
            guard let at=table.double(row,"presented_s"),at>0,let unix=table.double(row,"unix_ms"),let layer=table.value(row,"layer_ptr") else { continue }
            byLayer[layer,default:[]].append(Shown(at:at,unixMs:unix))
        }
        guard let frames=byLayer.values.max(by:{ $0.count < $1.count }) else { continue }
        let sorted=frames.sorted { $0.at < $1.at }
        shownFrames+=sorted.count
        for (a,b) in zip(sorted,sorted.dropFirst()) where b.at>a.at {
            let ms=(b.at-a.at)*1000
            let first=Int((b.unixMs-ms)/1000),last=Int(b.unixMs/1000)
            if (first...max(first,last)).contains(where:{ hidden.contains($0) }) { backgroundMs+=ms;continue }
            intervals.append((ms,b.unixMs))
        }
    }
    let times=intervals.map(\.ms), ascending=times.sorted(), descending=Array(ascending.reversed())
    let measuredS=times.reduce(0,+)/1000, median=percentile(ascending,0.5)
    var shown:[String:Any]=["frames":shownFrames,"measured_seconds":r(measuredS),"background_seconds":r(backgroundMs/1000)]
    if !times.isEmpty {
        let minutes=max(measuredS/60,1e-9)
        shown.merge([
            "average_fps":r(Double(times.count)/max(measuredS,1e-9)),"low_1pct_fps":r(lowFPS(descending,0.01)),"low_01pct_fps":r(lowFPS(descending,0.001)),
            "median_ms":r(median,2),"p95_ms":r(percentile(ascending,0.95),2),"p99_ms":r(percentile(ascending,0.99),2),"max_ms":r(ascending.last!,1),
            "stutters_50ms":times.filter { $0>50 }.count,"stutters_100ms":times.filter { $0>100 }.count,
            "stutters_50ms_per_minute":r(Double(times.filter { $0>50 }.count)/minutes,2),
            "freezes_500ms":times.filter { $0>500 }.count,"freezes_2s":times.filter { $0>2000 }.count,
            "slow_frames":times.filter { $0>2*median }.count,"slow_frames_pct":r(Double(times.filter { $0>2*median }.count)*100/Double(times.count),2),
        ]) { $1 }
    }

    // The engine's present loop: the frames-<windows pid> files whose rows fall in the game's run.
    let runs:[(Double,Double)]={
        var result:[(Double,Double)]=[],start:Double?
        for e in events {
            let t=(e["t"] as? Double) ?? 0
            if e["kind"] as? String == "game_started" { start=t }
            if e["kind"] as? String == "game_ended",let s=start { result.append((s,t));start=nil }
        }
        if let s=start { result.append((s,.infinity)) }
        return result
    }()
    var loop:[String:Any]=[:]
    let frameBases=Set(files.filter { $0.hasPrefix("frames-") && $0.hasSuffix(".csv") && !$0.contains(".events") }.map { name -> String in
        var base=String(name.dropLast(4));if base.hasSuffix(".1") || base.hasSuffix(".2") { base=String(base.dropLast(2)) };return base })
    var best:(table:Table,inRun:Int)?
    for base in frameBases {
        let table=readCSV(segments(folder,base))
        let inRun=table.rows.filter { row in
            guard let us=table.double(row,"unix_us") else { return false }
            return runs.isEmpty || runs.contains { us/1000>=$0.0 && us/1000<=$0.1 }
        }.count
        if inRun>(best?.inRun ?? 0) { best=(table,inRun) }
    }
    if let table=best?.table {
        var present:[Double]=[],waits:[Double]=[],pacing:[Double]=[],compiles=0,stutterCompiles=0,stutters=0
        for row in table.rows {
            guard let us=table.double(row,"unix_us"),runs.isEmpty || runs.contains(where:{ us/1000>=$0.0 && us/1000<=$0.1 }),
                  let interval=table.double(row,"present_interval_us") else { continue }
            let ms=interval/1000,c=Int(table.double(row,"shader_compile_starts") ?? 0)
            present.append(ms);compiles+=c
            waits.append((table.double(row,"frame_latency_wait_us") ?? 0)/1000);pacing.append((table.double(row,"pacing_sleep_us") ?? 0)/1000)
            if ms>50 { stutters+=1;if c>0 { stutterCompiles+=1 } }
        }
        let sorted=present.sorted()
        if !present.isEmpty {
            loop=["frames":present.count,"average_fps":r(Double(present.count)/max(present.reduce(0,+)/1000,1e-9)),"median_ms":r(percentile(sorted,0.5),2),
                  "p99_ms":r(percentile(sorted,0.99),2),"gpu_wait_ms_mean":r(summary(waits).mean,2),"pacing_sleep_ms_mean":r(summary(pacing).mean,2),
                  "shader_compiles":compiles,"stutters_50ms":stutters,"stutters_with_shader_compile":stutterCompiles]
        }
    }

    // Shader translations and pipeline builds.
    var shaders:[String:Any]=[:]
    var shaderTimes:[Double]=[]
    for name in files where name.hasPrefix("shaders-") && name.hasSuffix(".csv") && !name.contains("pipelines") && !name.contains("summary") {
        let table=readCSV([folder.appendingPathComponent(name)])
        shaderTimes+=table.rows.compactMap { table.double($0,"total_us").map { $0/1000 } }
    }
    if !shaderTimes.isEmpty {
        let s=shaderTimes.sorted()
        shaders=["translated":s.count,"total_ms":r(s.reduce(0,+)),"median_ms":r(percentile(s,0.5),2),"max_ms":r(s.last!,1),"over_16ms":s.filter { $0>16.7 }.count]
    }

    // The Mac while the game ran.
    var machine:[String:Any]=[:]
    func column(_ name:String) -> [Double] { system.rows.filter { (system.double($0,"game_pid") ?? 0)>0 }.compactMap { system.double($0,name) } }
    for (name,key) in [("game_cpu_pct","game_cpu_pct"),("game_pcore_pct","game_pcore_pct"),("game_runnable_pct","game_runnable_pct"),("game_threads","game_threads"),
                       ("game_footprint_mb","game_memory_mb"),("game_power_w","game_power_w"),("game_wakeups_per_s","game_wakeups_per_s"),("game_ipc","game_ipc"),
                       ("gpu_device_pct","gpu_pct"),("gpu_memory_mb","gpu_memory_mb"),("ram_used_mb","ram_used_mb"),("swap_mb","swap_mb"),
                       ("cpu_temp_c","cpu_temp_c"),("gpu_temp_c","gpu_temp_c"),("cpu_power_w","cpu_power_w"),("gpu_power_w","gpu_power_w"),
                       ("package_power_w","package_power_w"),("system_power_w","system_power_w"),("pcpu_mhz","pcpu_mhz"),("gpu_mhz","gpu_mhz"),("fan_rpm","fan_rpm")] {
        let s=summary(column(name))
        if s.count>0 { machine[key]=["mean":r(s.mean),"max":r(s.max),"min":r(s.min)] }
    }
    machine["memory_pressure_worst"]=Int(column("memory_pressure").max() ?? 0)
    machine["thermal_state_worst"]=Int(column("thermal_state").max() ?? 0)

    // Every 10 seconds of the game: frames on screen, the Mac.
    var buckets:[Int:[Double]]=[:]
    for (ms,end) in intervals { buckets[Int(end/10000),default:[]].append(ms) }
    var sys10:[Int:[[Substring]]]=[:]
    for row in system.rows where (system.double(row,"game_pid") ?? 0)>0 { if let ms=system.double(row,"unix_ms") { sys10[Int(ms/10000),default:[]].append(row) } }
    let firstBucket=(Array(buckets.keys)+Array(sys10.keys)).min() ?? 0
    var timeline10:[[String:Any]]=[]
    for key in Set(buckets.keys).union(sys10.keys).sorted() {
        var entry:[String:Any]=["t":(key-firstBucket)*10]
        if let t=buckets[key],!t.isEmpty {
            let d=t.sorted(by:>)
            entry["fps"]=r(Double(t.count)/max(t.reduce(0,+)/1000,1e-9));entry["low_1pct_fps"]=r(lowFPS(d,0.01));entry["worst_ms"]=r(d[0])
        }
        let rows=sys10[key] ?? []
        func mean(_ name:String) -> Double? { let v=rows.compactMap { system.double($0,name) };return v.isEmpty ? nil : r(v.reduce(0,+)/Double(v.count)) }
        for (name,key) in [("game_cpu_pct","cpu_pct"),("game_runnable_pct","runnable_pct"),("gpu_device_pct","gpu_pct"),("cpu_temp_c","cpu_c"),("gpu_temp_c","gpu_c"),("package_power_w","package_w"),("game_footprint_mb","memory_mb")] {
            if let v=mean(name) { entry[key]=v }
        }
        timeline10.append(entry)
    }

    // Problems and events, on the session's clock.
    let start=(events.first?["t"] as? Double) ?? 0
    let notable=events.filter { !["recorder_started","recorder_finished"].contains($0["kind"] as? String ?? "") }
    func count(_ kind:String) -> Int { notable.filter { $0["kind"] as? String == kind }.count }
    let finished=events.last { $0["kind"] as? String == "recorder_finished" }
    let problems:[String:Any]=["crashes":count("crash"),"gpu_pipeline_failures":count("gpu_pipeline_failure"),"freezes":count("freeze_started"),
                               "hitches_250ms":count("hitch"),"wine_errors_logged":count("wine_error"),
                               "wine_messages":finished?["wine_messages"] ?? []]
    let eventList:[[String:Any]]=notable.prefix(400).map { e in
        var item=e;item["t_s"]=r(((e["t"] as? Double) ?? start)/1000-start/1000);return item
    }

    return ["schema":1,"session":folder.lastPathComponent,"settings":session.filter { $0.key != "machine" },"machine_record":session["machine"] ?? [:],
            "frames_on_screen":shown,"present_loop":loop,"shaders":shaders,"mac":machine,"problems":problems,"every_10s":timeline10,"events":eventList,
            "game_pids":gamePids]
}

// MARK: Writing

func markdown(_ report:[String:Any]) -> String {
    let s=report["frames_on_screen"] as? [String:Any] ?? [:], loop=report["present_loop"] as? [String:Any] ?? [:]
    let mac=report["mac"] as? [String:Any] ?? [:], problems=report["problems"] as? [String:Any] ?? [:]
    let settings=report["settings"] as? [String:Any] ?? [:], machine=report["machine_record"] as? [String:Any] ?? [:]
    func v(_ d:[String:Any],_ k:String,_ unit:String="") -> String { d[k].map { "\($0)\(unit)" } ?? "–" }
    func m(_ k:String,_ unit:String) -> String {
        guard let x=mac[k] as? [String:Any] else { return "–" }
        return "\(x["mean"] ?? "–")\(unit) (max \(x["max"] ?? "–")\(unit))"
    }
    var out="# Pawpad session \(report["session"] ?? "")\n\n"
    let displays=(machine["displays"] as? [[String:Any]] ?? []).map { d -> String in
        let px=(d["pixels"] as? [Int]).map { "\($0[0])×\($0[1])" } ?? "?"
        return "\(d["name"] ?? "display") \(px) @ \(d["max_fps"] ?? "?") Hz\((d["main"] as? Bool) == true ? " (main)" : "")"
    }.joined(separator:", ")
    out+="\(settings["game"] ?? "game") · engine \(settings["runtime"] ?? "?") · \(machine["chip"] ?? "?") \(machine["memory_gb"] ?? "?") GB · macOS \(machine["macos"] ?? "?")\n"
    out+="Resolution \(settings["width"] ?? "?")×\(settings["height"] ?? "?") · \(displays.isEmpty ? "displays not recorded" : displays)\n\n"
    if let fps=s["average_fps"] {
        out+="**\(fps) FPS average · 1% low \(v(s,"low_1pct_fps")) · \(v(s,"stutters_50ms_per_minute")) stutters a minute · \(v(s,"freezes_500ms")) freezes · \(problems["crashes"] ?? 0) crash messages**\n\n"
    } else {
        out+="**No frames of the game reached the screen in this session.**\n\n"
    }
    out+="## Frames on screen\n\n| | |\n|---|---|\n"
    for (label,key,unit) in [("Measured","measured_seconds"," s"),("Frames","frames",""),("Average FPS","average_fps",""),("1% low FPS","low_1pct_fps",""),
                             ("0.1% low FPS","low_01pct_fps",""),("Median frame time","median_ms"," ms"),("95th / 99th percentile","p95_ms"," ms"),
                             ("Longest frame","max_ms"," ms"),("Stutters over 50 ms","stutters_50ms",""),("Stutters over 100 ms","stutters_100ms",""),
                             ("Freezes over 0.5 s / 2 s","freezes_500ms",""),("Slow frames (over 2× typical)","slow_frames_pct"," %"),("Window not on screen","background_seconds"," s")] {
        var value=v(s,key,unit)
        if key=="p95_ms" { value="\(v(s,"p95_ms")) / \(v(s,"p99_ms")) ms" }
        if key=="freezes_500ms" { value="\(v(s,"freezes_500ms")) / \(v(s,"freezes_2s"))" }
        if key=="stutters_50ms" { value="\(v(s,"stutters_50ms")) (\(v(s,"stutters_50ms_per_minute")) a minute)" }
        out+="| \(label) | \(value) |\n"
    }
    out+="\n## The engine's frame loop\n\n| | |\n|---|---|\n"
    for (label,key,unit) in [("Frames finished","frames",""),("Average FPS","average_fps",""),("Median / 99th percentile","median_ms"," ms"),
                             ("Waiting for the GPU, per frame","gpu_wait_ms_mean"," ms"),("Pacing sleep, per frame","pacing_sleep_ms_mean"," ms"),
                             ("Shader compiles","shader_compiles",""),("Stutters with a shader compile in the same frame","stutters_with_shader_compile","")] {
        var value=v(loop,key,unit)
        if key=="median_ms" { value="\(v(loop,"median_ms")) / \(v(loop,"p99_ms")) ms" }
        if key=="stutters_with_shader_compile" { value="\(v(loop,key)) of \(v(loop,"stutters_50ms"))" }
        out+="| \(label) | \(value) |\n"
    }
    if let sh=report["shaders"] as? [String:Any],!sh.isEmpty {
        out+="\nShaders translated: \(v(sh,"translated")), \(v(sh,"total_ms")) ms in all, median \(v(sh,"median_ms")) ms, slowest \(v(sh,"max_ms")) ms, \(v(sh,"over_16ms")) over a 60 Hz frame.\n"
    }
    out+="\n## The Mac while the game ran\n\n| | |\n|---|---|\n"
    for (label,key,unit) in [("Game CPU (100% = one core)","game_cpu_pct","%"),("…of it on P-cores","game_pcore_pct","%"),("Game threads waiting for a core","game_runnable_pct","%"),
                             ("Game threads","game_threads",""),("Game memory","game_memory_mb"," MB"),("Game CPU power","game_power_w"," W"),("Game wakeups","game_wakeups_per_s","/s"),
                             ("GPU busy","gpu_pct","%"),("GPU memory","gpu_memory_mb"," MB"),("Mac memory used","ram_used_mb"," MB"),("Swap","swap_mb"," MB"),
                             ("CPU temperature","cpu_temp_c"," °C"),("GPU temperature","gpu_temp_c"," °C"),("CPU / GPU power","cpu_power_w"," W"),
                             ("Package power","package_power_w"," W"),("Whole Mac power","system_power_w"," W"),("P-core clock","pcpu_mhz"," MHz"),("GPU clock","gpu_mhz"," MHz"),("Fans","fan_rpm"," rpm")] {
        var value=m(key,unit)
        if key=="cpu_power_w" { value="\(m("cpu_power_w"," W")) / \(m("gpu_power_w"," W"))" }
        out+="| \(label) | \(value) |\n"
    }
    out+="| Memory pressure (worst) | \(["–","normal","warning","–","critical"][min(4,mac["memory_pressure_worst"] as? Int ?? 0)]) |\n"
    out+="| Heat (worst) | \(["nominal","fair","serious","critical"][min(3,mac["thermal_state_worst"] as? Int ?? 0)]) |\n"
    let rows=report["every_10s"] as? [[String:Any]] ?? []
    if !rows.isEmpty {
        out+="\n## Every 10 seconds\n\n| s | FPS | 1% low | worst ms | game CPU % | waiting % | GPU % | CPU °C | GPU °C | package W | game MB |\n|---|---|---|---|---|---|---|---|---|---|---|\n"
        for row in rows.prefix(720) {
            out+="| \(row["t"] ?? "") | \(v(row,"fps")) | \(v(row,"low_1pct_fps")) | \(v(row,"worst_ms")) | \(v(row,"cpu_pct")) | \(v(row,"runnable_pct")) | \(v(row,"gpu_pct")) | \(v(row,"cpu_c")) | \(v(row,"gpu_c")) | \(v(row,"package_w")) | \(v(row,"memory_mb")) |\n"
        }
    }
    out+="\n## Problems\n\n- Crash messages: \(problems["crashes"] ?? 0)\n- GPU pipeline failures: \(problems["gpu_pipeline_failures"] ?? 0)\n"
    out+="- Freezes (window on screen, no frame for 3 s): \(problems["freezes"] ?? 0)\n- Hitches over 250 ms: \(problems["hitches_250ms"] ?? 0)\n"
    let messages=problems["wine_messages"] as? [[String:Any]] ?? []
    if !messages.isEmpty {
        out+="\nMost frequent Wine messages (digits replaced by #):\n\n"
        for message in messages.prefix(15) { out+="- \(message["count"] ?? 0)× `\((message["message"] as? String ?? "").prefix(200))`\n" }
    }
    let events=report["events"] as? [[String:Any]] ?? []
    if !events.isEmpty {
        out+="\n## Timeline\n\n"
        for e in events.prefix(200) {
            var detail=e.filter { !["t","t_s","kind","src"].contains($0.key) }.map { "\($0.key)=\($0.value)" }.sorted().joined(separator:" ")
            if detail.count>220 { detail=String(detail.prefix(220))+"…" }
            out+="- \(e["t_s"] ?? 0) s · **\(e["kind"] ?? "")** \(detail)\n"
        }
    }
    out+="\nFiles: frames on screen from display-<pid>.csv, the frame loop from frames-<pid>.csv, the Mac from system.csv, events from timeline.jsonl.\n"
    return out
}

func compare(_ a:URL,_ b:URL) throws {
    func load(_ url:URL) throws -> [String:Any] {
        let path=url.appendingPathComponent("report.json")
        if !FileManager.default.fileExists(atPath:path.path) { try write(url) }
        return (try JSONSerialization.jsonObject(with:Data(contentsOf:path))) as? [String:Any] ?? [:]
    }
    let x=try load(a),y=try load(b)
    func get(_ d:[String:Any],_ path:[String]) -> Double? {
        var value:Any?=d
        for key in path { value=(value as? [String:Any])?[key] }
        return (value as? NSNumber)?.doubleValue
    }
    print("| | \(a.lastPathComponent) | \(b.lastPathComponent) | change |\n|---|---|---|---|")
    for (label,path) in [("Average FPS",["frames_on_screen","average_fps"]),("1% low FPS",["frames_on_screen","low_1pct_fps"]),("0.1% low FPS",["frames_on_screen","low_01pct_fps"]),
                         ("Median frame ms",["frames_on_screen","median_ms"]),("99th percentile ms",["frames_on_screen","p99_ms"]),("Stutters a minute",["frames_on_screen","stutters_50ms_per_minute"]),
                         ("Freezes over 0.5 s",["frames_on_screen","freezes_500ms"]),("Shader compiles",["present_loop","shader_compiles"]),("Game CPU %",["mac","game_cpu_pct","mean"]),
                         ("Waiting for a core %",["mac","game_runnable_pct","mean"]),("GPU busy %",["mac","gpu_pct","mean"]),("Package W",["mac","package_power_w","mean"]),
                         ("GPU °C (max)",["mac","gpu_temp_c","max"]),("Game memory MB (max)",["mac","game_memory_mb","max"]),("Crash messages",["problems","crashes"])] {
        let p=get(x,path),q=get(y,path)
        let change:String={ guard let p,let q else { return "" };let d=q-p;return p != 0 ? String(format:"%+.1f (%+.0f%%)",d,d/p*100) : String(format:"%+.1f",d) }()
        print("| \(label) | \(p.map { String(r($0)) } ?? "–") | \(q.map { String(r($0)) } ?? "–") | \(change) |")
    }
}

func write(_ folder:URL) throws {
    let value=try report(folder)
    let json=try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys])
    try json.write(to:folder.appendingPathComponent("report.json"),options:.atomic)
    try markdown(value).write(to:folder.appendingPathComponent("report.md"),atomically:true,encoding:.utf8)
}

let arguments=CommandLine.arguments
do {
    switch arguments.count>2 ? arguments[1] : "" {
    case "report":
        let folder=URL(fileURLWithPath:arguments[2])
        try write(folder)
        print(markdown(try report(folder)).split(separator:"\n").prefix(6).joined(separator:"\n"))
    case "compare" where arguments.count>3:
        try compare(URL(fileURLWithPath:arguments[2]),URL(fileURLWithPath:arguments[3]))
    default:
        FileHandle.standardError.write(Data("usage: pawpad-perf report <session folder> | compare <session A> <session B>\n".utf8));exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("pawpad-perf: \(error)\n".utf8));exit(1)
}
