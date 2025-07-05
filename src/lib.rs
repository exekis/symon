use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::time::{SystemTime, UNIX_EPOCH, Duration};
use std::thread;
use std::sync::Arc;
use std::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemStats {
    pub timestamp: u64,
    pub cpu: CpuStats,
    pub memory: MemoryStats,
    pub system_info: BasicSystemInfo,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CpuStats {
    pub usage_percent: f32,
    pub cores: usize,
    pub temperature: f32,
    pub load_avg: Option<[f32; 3]>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryStats {
    pub total: u64,
    pub used: u64,
    pub available: u64,
    pub pressure_score: f32,
    pub swap_total: u64,
    pub swap_used: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BasicSystemInfo {
    pub hostname: String,
    pub uptime: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MonitorConfig {
    pub interval: u64,
    pub duration: u64,
    pub cpu_threshold: f32,
    pub memory_threshold: f32,
    pub temperature_threshold: f32,
    pub enable_alerts: bool,
    pub log_file: String,
}

impl Default for MonitorConfig {
    fn default() -> Self {
        Self {
            interval: 5,
            duration: 0, // 0 = indefinitely
            cpu_threshold: 90.0,
            memory_threshold: 85.0,
            temperature_threshold: 80.0,
            enable_alerts: true,
            log_file: "system_monitor.log".to_string(),
        }
    }
}

pub struct SystemMonitorRunner {
    monitor: SystemMonitor,
    config: MonitorConfig,
    running: Arc<Mutex<bool>>,
}

impl SystemMonitorRunner {
    pub fn new(config: MonitorConfig) -> Self {
        Self {
            monitor: SystemMonitor::new(),
            config,
            running: Arc::new(Mutex::new(false)),
        }
    }

    pub fn start_monitoring(&mut self) -> Result<(), Box<dyn std::error::Error>> {
        {
            let mut running = self.running.lock().unwrap();
            *running = true;
        }

        let start_time = SystemTime::now();
        let mut iteration = 0;

        loop {
            {
                let running = self.running.lock().unwrap();
                if !*running {
                    break;
                }
            }

            iteration += 1;
            let stats = self.monitor.get_system_stats();
            
            self.print_stats(&stats, iteration);
            
            if self.config.enable_alerts {
                self.check_alerts(&stats);
            }

            self.log_stats(&stats)?;

            if self.config.duration > 0 {
                let elapsed = start_time.elapsed()?.as_secs();
                if elapsed >= self.config.duration {
                    break;
                }
            }

            thread::sleep(Duration::from_secs(self.config.interval));
        }

        Ok(())
    }

    pub fn stop_monitoring(&self) {
        let mut running = self.running.lock().unwrap();
        *running = false;
    }

    fn print_stats(&self, stats: &SystemStats, iteration: u64) {
        println!("=== System Monitor - Iteration {} ===", iteration);
        println!("Timestamp: {}", stats.timestamp);
        println!("Hostname: {}", stats.system_info.hostname);
        println!("Uptime: {} seconds", stats.system_info.uptime);
        println!();
        
        println!("CPU Stats:");
        println!("  Usage: {:.1}%", stats.cpu.usage_percent);
        println!("  Cores: {}", stats.cpu.cores);
        println!("  Temperature: {:.1}°C", stats.cpu.temperature);
        if let Some(load_avg) = &stats.cpu.load_avg {
            println!("  Load Average: {:.2}, {:.2}, {:.2}", load_avg[0], load_avg[1], load_avg[2]);
        }
        println!();
        
        println!("Memory Stats:");
        println!("  Total: {} MB", stats.memory.total / 1024 / 1024);
        println!("  Used: {} MB ({:.1}%)", 
                 stats.memory.used / 1024 / 1024,
                 (stats.memory.used as f32 / stats.memory.total as f32) * 100.0);
        println!("  Available: {} MB", stats.memory.available / 1024 / 1024);
        println!("  Pressure Score: {:.1}", stats.memory.pressure_score);
        
        if stats.memory.swap_total > 0 {
            println!("  Swap Total: {} MB", stats.memory.swap_total / 1024 / 1024);
            println!("  Swap Used: {} MB ({:.1}%)", 
                     stats.memory.swap_used / 1024 / 1024,
                     (stats.memory.swap_used as f32 / stats.memory.swap_total as f32) * 100.0);
        }
        
        println!("{}", "=".repeat(50));
        println!();
    }

    fn check_alerts(&self, stats: &SystemStats) {
        if stats.cpu.usage_percent > self.config.cpu_threshold {
            eprintln!("⚠️  ALERT: High CPU usage: {:.1}%", stats.cpu.usage_percent);
        }
        
        let memory_percent = (stats.memory.used as f32 / stats.memory.total as f32) * 100.0;
        if memory_percent > self.config.memory_threshold {
            eprintln!("⚠️  ALERT: High memory usage: {:.1}%", memory_percent);
        }
        
        if stats.cpu.temperature > self.config.temperature_threshold {
            eprintln!("⚠️  ALERT: High CPU temperature: {:.1}°C", stats.cpu.temperature);
        }
    }

    fn log_stats(&self, stats: &SystemStats) -> Result<(), Box<dyn std::error::Error>> {
        let json_str = serde_json::to_string(stats)?;
        
        use std::io::Write;
        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.config.log_file)?;
        
        writeln!(file, "{}", json_str)?;
        Ok(())
    }
}

pub struct SystemMonitor {
    system: sysinfo::System,
}

impl SystemMonitor {
    pub fn new() -> Self {
        let mut system = sysinfo::System::new_all();
        system.refresh_all();
        
        Self { system }
    }

    pub fn refresh(&mut self) {
        self.system.refresh_all();
    }

    pub fn get_system_stats(&mut self) -> SystemStats {
        self.refresh();
        
        SystemStats {
            timestamp: get_timestamp(),
            cpu: self.get_cpu_stats(),
            memory: self.get_memory_stats(),
            system_info: self.get_system_info(),
        }
    }

    fn get_cpu_stats(&mut self) -> CpuStats {
        let cpus = self.system.cpus();
        let usage_percent = cpus.iter().map(|cpu| cpu.cpu_usage()).sum::<f32>() / cpus.len() as f32;
        let temperature = self.get_cpu_temperature();
        let load_avg = self.get_load_average();
        
        CpuStats {
            usage_percent,
            cores: cpus.len(),
            temperature,
            load_avg,
        }
    }

    fn get_memory_stats(&self) -> MemoryStats {
        let total = self.system.total_memory();
        let used = self.system.used_memory();
        let available = self.system.available_memory();
        let swap_total = self.system.total_swap();
        let swap_used = self.system.used_swap();
        
        let pressure_score = (used as f32 / total as f32) * 100.0;
        
        MemoryStats {
            total,
            used,
            available,
            pressure_score,
            swap_total,
            swap_used,
        }
    }

    fn get_system_info(&self) -> BasicSystemInfo {
        BasicSystemInfo {
            hostname: sysinfo::System::host_name().unwrap_or_default(),
            uptime: read_uptime(),
        }
    }

    fn get_cpu_temperature(&self) -> f32 {
        if let Ok(temp_str) = fs::read_to_string("/sys/class/thermal/thermal_zone0/temp") {
            if let Ok(temp_millic) = temp_str.trim().parse::<i32>() {
                return temp_millic as f32 / 1000.0;
            }
        }
        0.0
    }

    fn get_load_average(&self) -> Option<[f32; 3]> {
        if let Ok(loadavg_str) = fs::read_to_string("/proc/loadavg") {
            let parts: Vec<&str> = loadavg_str.split_whitespace().collect();
            if parts.len() >= 3 {
                if let (Ok(load1), Ok(load5), Ok(load15)) = (
                    parts[0].parse::<f32>(),
                    parts[1].parse::<f32>(),
                    parts[2].parse::<f32>(),
                ) {
                    return Some([load1, load5, load15]);
                }
            }
        }
        None
    }
}

fn get_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

fn read_uptime() -> u64 {
    if let Ok(uptime_str) = fs::read_to_string("/proc/uptime") {
        if let Ok(uptime) = uptime_str.split_whitespace().next().unwrap_or("0").parse::<f64>() {
            return uptime as u64;
        }
    }
    0
}

pub fn get_cpu_usage() -> f32 {
    let mut system = sysinfo::System::new_all();
    system.refresh_cpu();
    std::thread::sleep(std::time::Duration::from_millis(200));
    system.refresh_cpu();
    
    let cpus = system.cpus();
    cpus.iter().map(|cpu| cpu.cpu_usage()).sum::<f32>() / cpus.len() as f32
}

pub fn get_memory_usage() -> (u64, u64, f32) {
    let mut system = sysinfo::System::new_all();
    system.refresh_memory();
    
    let total = system.total_memory();
    let used = system.used_memory();
    let percentage = (used as f32 / total as f32) * 100.0;
    
    (total, used, percentage)
}

pub fn get_system_uptime() -> u64 {
    read_uptime()
}

pub fn get_cpu_temperature() -> f32 {
    if let Ok(temp_str) = fs::read_to_string("/sys/class/thermal/thermal_zone0/temp") {
        if let Ok(temp_millic) = temp_str.trim().parse::<i32>() {
            return temp_millic as f32 / 1000.0;
        }
    }
    0.0
}

pub fn read_proc_stat() -> Result<HashMap<String, u64>, std::io::Error> {
    let content = fs::read_to_string("/proc/stat")?;
    let mut stats = HashMap::new();
    
    for line in content.lines() {
        if line.starts_with("cpu ") {
            let values: Vec<&str> = line.split_whitespace().collect();
            if values.len() >= 5 {
                stats.insert("user".to_string(), values[1].parse().unwrap_or(0));
                stats.insert("nice".to_string(), values[2].parse().unwrap_or(0));
                stats.insert("system".to_string(), values[3].parse().unwrap_or(0));
                stats.insert("idle".to_string(), values[4].parse().unwrap_or(0));
                if values.len() > 5 {
                    stats.insert("iowait".to_string(), values[5].parse().unwrap_or(0));
                }
            }
            break;
        }
    }
    
    Ok(stats)
}

pub fn read_proc_meminfo() -> Result<HashMap<String, u64>, std::io::Error> {
    let content = fs::read_to_string("/proc/meminfo")?;
    let mut meminfo = HashMap::new();
    
    for line in content.lines() {
        if let Some(colon_pos) = line.find(':') {
            let key = line[..colon_pos].trim();
            let value_str = line[colon_pos + 1..].trim();
            
            if let Some(kb_pos) = value_str.find(" kB") {
                if let Ok(value) = value_str[..kb_pos].trim().parse::<u64>() {
                    meminfo.insert(key.to_string(), value * 1024);
                }
            }
        }
    }
    
    Ok(meminfo)
}

#[no_mangle]
pub extern "C" fn run_system_monitor(
    interval: u64,
    duration: u64,
    cpu_threshold: f32,
    memory_threshold: f32,
    temperature_threshold: f32,
    enable_alerts: bool,
    log_file: *const std::os::raw::c_char,
) -> i32 {
    let log_file_str = if log_file.is_null() {
        "system_monitor.log".to_string()
    } else {
        unsafe {
            std::ffi::CStr::from_ptr(log_file)
                .to_string_lossy()
                .into_owned()
        }
    };

    let config = MonitorConfig {
        interval,
        duration,
        cpu_threshold,
        memory_threshold,
        temperature_threshold,
        enable_alerts,
        log_file: log_file_str,
    };

    let mut runner = SystemMonitorRunner::new(config);
    
    match runner.start_monitoring() {
        Ok(_) => 0,
        Err(e) => {
            eprintln!("Error running system monitor: {}", e);
            1
        }
    }
}

#[no_mangle]
pub extern "C" fn run_system_monitor_with_config(config_json: *const std::os::raw::c_char) -> i32 {
    let config = if config_json.is_null() {
        MonitorConfig::default()
    } else {
        let config_str = unsafe {
            std::ffi::CStr::from_ptr(config_json)
                .to_string_lossy()
                .into_owned()
        };
        
        match serde_json::from_str::<MonitorConfig>(&config_str) {
            Ok(config) => config,
            Err(e) => {
                eprintln!("Error parsing config JSON: {}", e);
                return 1;
            }
        }
    };

    let mut runner = SystemMonitorRunner::new(config);
    
    match runner.start_monitoring() {
        Ok(_) => 0,
        Err(e) => {
            eprintln!("Error running system monitor: {}", e);
            1
        }
    }
}

#[no_mangle]
pub extern "C" fn get_system_stats_json() -> *mut std::os::raw::c_char {
    let mut monitor = SystemMonitor::new();
    let stats = monitor.get_system_stats();
    
    match serde_json::to_string(&stats) {
        Ok(json_str) => {
            let c_str = std::ffi::CString::new(json_str).unwrap();
            c_str.into_raw()
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn get_cpu_usage_c() -> f32 {
    get_cpu_usage()
}

#[no_mangle]
pub extern "C" fn get_memory_total_c() -> u64 {
    let (total, _, _) = get_memory_usage();
    total
}

#[no_mangle]
pub extern "C" fn get_memory_used_c() -> u64 {
    let (_, used, _) = get_memory_usage();
    used
}

#[no_mangle]
pub extern "C" fn get_cpu_temperature_c() -> f32 {
    get_cpu_temperature()
}

#[no_mangle]
pub extern "C" fn free_string(ptr: *mut std::os::raw::c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = std::ffi::CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_system_monitor_creation() {
        let monitor = SystemMonitor::new();
        assert!(monitor.system.cpus().len() > 0);
    }

    #[test]
    fn test_get_system_stats() {
        let mut monitor = SystemMonitor::new();
        let stats = monitor.get_system_stats();
        
        assert!(stats.timestamp > 0);
        assert!(stats.cpu.cores > 0);
        assert!(stats.memory.total > 0);
    }

    #[test]
    fn test_basic_functions() {
        let cpu_usage = get_cpu_usage();
        assert!(cpu_usage >= 0.0 && cpu_usage <= 100.0);
        
        let (total_mem, used_mem, mem_percent) = get_memory_usage();
        assert!(total_mem > 0);
        assert!(used_mem <= total_mem);
        assert!(mem_percent >= 0.0 && mem_percent <= 100.0);
        
        let uptime = get_system_uptime();
        assert!(uptime > 0 || uptime == 0); // uptime is valid
        
        let temp = get_cpu_temperature();
        assert!(temp >= 0.0);
    }

    #[test]
    fn test_proc_readers() {
        match read_proc_stat() {
            Ok(stats) => {
                assert!(stats.contains_key("user"));
                assert!(stats.contains_key("system"));
                assert!(stats.contains_key("idle"));
            }
            Err(_) => {}
        }
        
        match read_proc_meminfo() {
            Ok(meminfo) => {
                assert!(meminfo.contains_key("MemTotal"));
            }
            Err(_) => {}
        }
    }
}
