use symon_core::{run_system_monitor_with_config, MonitorConfig};
use std::env;
use std::fs;

fn main() {
    let args: Vec<String> = env::args().collect();
    
    let config = if args.len() > 1 {
        let config_path = &args[1];
        match fs::read_to_string(config_path) {
            Ok(config_str) => {
                match serde_json::from_str::<MonitorConfig>(&config_str) {
                    Ok(config) => config,
                    Err(e) => {
                        eprintln!("Error parsing config file {}: {}", config_path, e);
                        std::process::exit(1);
                    }
                }
            }
            Err(e) => {
                eprintln!("Error reading config file {}: {}", config_path, e);
                std::process::exit(1);
            }
        }
    } else {
        MonitorConfig::default()
    };

    println!("Starting System Monitor...");
    println!("Config: {:?}", config);
    println!("Press Ctrl+C to stop");
    println!();

    let config_json = serde_json::to_string(&config).unwrap();
    let config_cstr = std::ffi::CString::new(config_json).unwrap();
    
    let result = run_system_monitor_with_config(config_cstr.as_ptr());
    
    if result != 0 {
        eprintln!("System monitor exited with error code: {}", result);
        std::process::exit(result);
    }
}
