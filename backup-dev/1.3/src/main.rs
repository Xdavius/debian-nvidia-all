slint::include_modules!();

use slint::Model;
use std::rc::Rc;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

fn append_and_refresh(weak: &slint::Weak<AppWindow>, logs: &Arc<Mutex<String>>, line: &str) {
    if let Ok(mut buf) = logs.lock() {
        if !buf.is_empty() {
            buf.push('\n');
        }
        buf.push_str(line);
        let text = buf.clone();
        let weak_clone = weak.clone();
        let _ = slint::invoke_from_event_loop(move || {
            if let Some(ui) = weak_clone.upgrade() {
                ui.set_logs(text.into());
            }
        });
    }
}

fn strip_ansi(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let bytes = input.as_bytes();
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == 0x1b {
            i += 1;
            if i < bytes.len() && bytes[i] == b'[' {
                i += 1;
                while i < bytes.len() {
                    let c = bytes[i];
                    if (0x40..=0x7e).contains(&c) {
                        i += 1;
                        break;
                    }
                    i += 1;
                }
                continue;
            }
            continue;
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

fn push_stream_chunk(
    weak: &slint::Weak<AppWindow>,
    logs: &Arc<Mutex<String>>,
    prefix: &str,
    chunk: &[u8],
    carry: &mut String,
) {
    let txt = strip_ansi(&String::from_utf8_lossy(chunk));
    carry.push_str(&txt);
    while let Some(pos) = carry.find(['\n', '\r']) {
        let line = carry[..pos].trim_end();
        if !line.is_empty() {
            append_and_refresh(weak, logs, &format!("[{}] {}", prefix, line));
        }
        carry.drain(..=pos);
    }
}

fn resolve_helper_path() -> Result<PathBuf, String> {
    if let Ok(from_env) = std::env::var("NVIDIA_GUI_HELPER") {
        let p = PathBuf::from(from_env);
        if p.is_file() {
            return Ok(p);
        }
    }

    let exe =
        std::env::current_exe().map_err(|e| format!("Impossible de trouver current_exe: {}", e))?;
    let exe_dir = exe
        .parent()
        .ok_or_else(|| "Impossible de trouver le dossier du binaire".to_string())?;

    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));

    let candidates = [
        manifest_dir.join("debian-nvidia-all-cli.sh"),
        manifest_dir.join("..").join("debian-nvidia-all-cli.sh"),
        exe_dir.join("debian-nvidia-all-cli.sh"),
        exe_dir.join("../debian-nvidia-all-cli.sh"),
        exe_dir.join("../../debian-nvidia-all-cli.sh"),
        cwd.join("debian-nvidia-all-cli.sh"),
    ];

    for c in candidates {
        if c.is_file() {
            return Ok(c);
        }
    }

    Err("Helper introuvable. Definis NVIDIA_GUI_HELPER ou place debian-nvidia-all-cli.sh a cote du binaire.".to_string())
}

fn main() {
    if std::env::var("SLINT_BACKEND").is_err() {
        // Prefer FemtoVG to avoid software-renderer minimize/restore stalls on some systems.
        std::env::set_var("SLINT_BACKEND", "winit-femtovg");
    }
    let ui = match AppWindow::new() {
        Ok(ui) => ui,
        Err(_) => {
            // Graceful fallback if OpenGL/FemtoVG is not available on the host.
            std::env::set_var("SLINT_BACKEND", "winit-software");
            AppWindow::new().expect("Cannot create UI")
        }
    };

    let default_profiles: Vec<slint::SharedString> = vec![
        "Recommande".into(),
        "Latest".into(),
        "Legacy 580xx".into(),
        "Legacy 470xx".into(),
        "Legacy 390xx".into(),
    ];
    let model = Rc::new(slint::VecModel::from(default_profiles));
    ui.set_profile_model(model.into());
    ui.set_profile_index(0);

    let weak_init = ui.as_weak();
    thread::spawn(move || {
        let mut rec = String::new();
        let mut lat = String::new();
        let mut l580 = String::new();
        let mut l470 = String::new();
        let mut l390 = String::new();
        let mut lat_support = String::new();

        if let Ok(helper) = resolve_helper_path() {
            if let Ok(output) = Command::new("timeout")
                .arg("15s")
                .arg("bash")
                .arg(&helper)
                .arg("--print-versions")
                .output()
            {
                let text = String::from_utf8_lossy(&output.stdout);
                for line in text.lines() {
                    let mut parts = line.splitn(2, '=');
                    if let (Some(k), Some(v)) = (parts.next(), parts.next()) {
                        match k {
                            "RECOMMENDED" => rec = v.to_string(),
                            "LATEST" => lat = v.to_string(),
                            "LEGACY580" => l580 = v.to_string(),
                            "LEGACY470" => l470 = v.to_string(),
                            "LEGACY390" => l390 = v.to_string(),
                            "LATEST_SUPPORT" => lat_support = v.to_string(),
                            _ => {}
                        }
                    }
                }
            }
        }

        let mut profiles: Vec<slint::SharedString> = Vec::new();
        if !rec.is_empty() {
            profiles.push(format!("Recommande ({})", rec).into());
        } else {
            profiles.push("Recommande".into());
        }

        if !lat.is_empty() {
            let supp = if !lat_support.is_empty() { format!(" - {}", lat_support) } else { "".to_string() };
            profiles.push(format!("Latest ({}){}", lat, supp).into());
        } else {
            profiles.push("Latest".into());
        }

        if !l580.is_empty() { profiles.push(format!("Legacy 580xx ({})", l580).into()); } else { profiles.push("Legacy 580xx".into()); }
        if !l470.is_empty() { profiles.push(format!("Legacy 470xx ({})", l470).into()); } else { profiles.push("Legacy 470xx".into()); }
        if !l390.is_empty() { profiles.push(format!("Legacy 390xx ({})", l390).into()); } else { profiles.push("Legacy 390xx".into()); }

        let _ = slint::invoke_from_event_loop(move || {
            if let Some(ui) = weak_init.upgrade() {
                let old_idx = ui.get_profile_index().max(0) as usize;
                let len = profiles.len();
                ui.set_profile_model(Rc::new(slint::VecModel::from(profiles)).into());
                if len > 0 {
                    ui.set_profile_index(old_idx.min(len - 1) as i32);
                } else {
                    ui.set_profile_index(0);
                }
            }
        });
    });


    let weak_copy = ui.as_weak();
    ui.on_copy_logs(move || {
        let Some(ui) = weak_copy.upgrade() else {
            return;
        };
        let logs = ui.get_logs().to_string();
        match std::fs::File::create("/tmp/nvidia-driver-run-gui.log") {
            Ok(mut f) => {
                if f.write_all(logs.as_bytes()).is_ok() {
                    ui.set_status("Logs ecrits dans /tmp/nvidia-driver-run-gui.log".into());
                } else {
                    ui.set_status("Echec ecriture du fichier de logs".into());
                }
            }
            Err(_) => ui.set_status("Impossible de creer /tmp/nvidia-driver-run-gui.log".into()),
        }
    });

    let weak = ui.as_weak();
    ui.on_run(move || {
        let Some(ui) = weak.upgrade() else {
            return;
        };
        if ui.get_running() {
            return;
        }

        let profile_model = ui.get_profile_model();

        let pidx = ui.get_profile_index() as usize;

        let profile_text = profile_model
            .row_data(pidx)
            .unwrap_or_default()
            .to_string();

        ui.set_status(format!("Execution en cours: profile={}...", profile_text).into());
        ui.set_logs("".into());
        ui.set_running(true);

        let weak_thread = weak.clone();
        thread::spawn(move || {
            let helper = match resolve_helper_path() {
                Ok(p) => p,
                Err(e) => {
                    let weak_err = weak_thread.clone();
                    let _ = slint::invoke_from_event_loop(move || {
                        if let Some(ui) = weak_err.upgrade() {
                            ui.set_status("Impossible de trouver le helper".into());
                            ui.set_logs(e.into());
                            ui.set_running(false);
                        }
                    });
                    return;
                }
            };

            let helper_path = helper.to_string_lossy().replace('\'', "'\\''");
            
            let mut ver_arg = "--branch recommended".to_string();
            if pidx == 0 { ver_arg = "--branch recommended".to_string(); }
            else if pidx == 1 { ver_arg = "--branch latest".to_string(); }
            else {
                if let Some(start) = profile_text.find('(') {
                    if let Some(end) = profile_text.find(')') {
                        let ver = &profile_text[start+1..end];
                        ver_arg = format!("--version {}", ver);
                    }
                }
            }
            
            let mut cmdline = format!(
                "bash '{}' --source online {}",
                helper_path, ver_arg
            );

            cmdline.push_str(" --action 1");

            let mut child = match Command::new("script")
                .arg("-qefc")
                .arg(cmdline)
                .arg("/dev/null")
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn()
            {
                Ok(c) => c,
                Err(e) => {
                    let weak_err = weak_thread.clone();
                    let _ = slint::invoke_from_event_loop(move || {
                        if let Some(ui) = weak_err.upgrade() {
                            ui.set_status("Impossible de lancer le backend".into());
                            ui.set_logs(format!("Erreur lancement backend (script/PTTY): {}\nInstalle util-linux (commande `script`) ou signale le probleme.", e).into());
                            ui.set_running(false);
                        }
                    });
                    return;
                }
            };

            let logs = Arc::new(Mutex::new(String::new()));
            let running_flag = Arc::new(AtomicBool::new(true));
            let mut joins = Vec::new();

            if let Some(stdout) = child.stdout.take() {
                let weak_out = weak_thread.clone();
                let logs_out = logs.clone();
                let running_out = running_flag.clone();
                joins.push(thread::spawn(move || {
                    let mut reader = stdout;
                    let mut buf = [0u8; 1024];
                    let mut carry = String::new();
                    loop {
                        match reader.read(&mut buf) {
                            Ok(0) => break,
                            Ok(n) => push_stream_chunk(&weak_out, &logs_out, "stdout", &buf[..n], &mut carry),
                            Err(_) => break,
                        }
                    }
                    let tail = carry.trim();
                    if !tail.is_empty() {
                        append_and_refresh(&weak_out, &logs_out, &format!("[stdout] {}", tail));
                    }
                    running_out.store(false, Ordering::Relaxed);
                }));
            }

            if let Some(stderr) = child.stderr.take() {
                let weak_err = weak_thread.clone();
                let logs_err = logs.clone();
                let running_err = running_flag.clone();
                joins.push(thread::spawn(move || {
                    let mut reader = stderr;
                    let mut buf = [0u8; 1024];
                    let mut carry = String::new();
                    loop {
                        match reader.read(&mut buf) {
                            Ok(0) => break,
                            Ok(n) => push_stream_chunk(&weak_err, &logs_err, "stderr", &buf[..n], &mut carry),
                            Err(_) => break,
                        }
                    }
                    let tail = carry.trim();
                    if !tail.is_empty() {
                        append_and_refresh(&weak_err, &logs_err, &format!("[stderr] {}", tail));
                    }
                    running_err.store(false, Ordering::Relaxed);
                }));
            }

            {
                let weak_tick = weak_thread.clone();
                let logs_tick = logs.clone();
                let running_tick = running_flag.clone();
                joins.push(thread::spawn(move || {
                    while running_tick.load(Ordering::Relaxed) {
                        thread::sleep(Duration::from_secs(10));
                        if running_tick.load(Ordering::Relaxed) {
                            append_and_refresh(&weak_tick, &logs_tick, "[info] pacstall en cours...");
                        }
                    }
                }));
            }

            let status = child.wait();
            running_flag.store(false, Ordering::Relaxed);
            for j in joins {
                let _ = j.join();
            }

            let weak_done = weak_thread.clone();
            let final_logs = logs.lock().map(|s| s.clone()).unwrap_or_else(|_| String::new());
            let _ = slint::invoke_from_event_loop(move || {
                if let Some(ui) = weak_done.upgrade() {
                    if final_logs.trim().is_empty() {
                        ui.set_logs("Aucune sortie produite.".into());
                    }
                    match status {
                        Ok(exit) if exit.success() => ui.set_status("Termine avec succes".into()),
                        Ok(exit) if exit.code() == Some(130) => ui.set_status("Annule par l'utilisateur".into()),
                        Ok(exit) => ui.set_status(format!("Echec (code {:?})", exit.code()).into()),
                        Err(e) => ui.set_status(format!("Echec attente process: {}", e).into()),
                    }
                    ui.set_running(false);
                }
            });
        });
    });

    ui.run().expect("UI run failed");
}
