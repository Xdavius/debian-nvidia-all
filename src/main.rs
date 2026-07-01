slint::include_modules!();

use slint::Model;
use std::io::{Read, Write};
use std::path::Path;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

#[derive(Clone)]
struct PendingRun {
    helper: PathBuf,
    pidx: usize,
    profile_text: String,
}

struct DepInspection {
    has_missing: bool,
    missing_tools: String,
    missing_packages: String,
    missing_spdx: bool,
    missing_pacstall: bool,
    missing_kernel_headers: bool,
    kernel_release: String,
    kernel_header_packages: String,
}

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

fn append_ui_log(ui: &AppWindow, line: &str) {
    let mut cur = ui.get_logs().to_string();
    if !cur.is_empty() {
        cur.push('\n');
    }
    cur.push_str(line);
    ui.set_logs(cur.into());
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

fn libxkbcommon_x11_available() -> bool {
    let candidates = [
        "/usr/lib/x86_64-linux-gnu/libxkbcommon-x11.so",
        "/usr/lib/x86_64-linux-gnu/libxkbcommon-x11.so.0",
        "/usr/lib64/libxkbcommon-x11.so",
        "/usr/lib64/libxkbcommon-x11.so.0",
        "/usr/lib/libxkbcommon-x11.so",
        "/usr/lib/libxkbcommon-x11.so.0",
    ];

    if candidates.iter().any(|p| Path::new(p).exists()) {
        return true;
    }

    if let Ok(output) = Command::new("ldconfig").arg("-p").output() {
        let text = String::from_utf8_lossy(&output.stdout);
        return text.contains("libxkbcommon-x11.so");
    }

    false
}

fn env_truthy(name: &str) -> bool {
    matches!(
        std::env::var(name)
            .ok()
            .map(|v| v.trim().to_ascii_lowercase())
            .as_deref(),
        Some("1" | "true" | "yes" | "on")
    )
}

fn inspect_dependencies(helper: &Path) -> Result<DepInspection, String> {
    let output = Command::new("bash")
        .arg(helper)
        .arg("--inspect-dependencies")
        .output()
        .map_err(|e| format!("Echec lancement inspect dependencies: {}", e))?;

    if !output.status.success() {
        return Err("Le backend a echoue pendant l'inspection des dependances.".to_string());
    }

    let mut has_missing = false;
    let mut missing_tools = String::new();
    let mut missing_packages = String::new();
    let mut missing_spdx = false;
    let mut missing_pacstall = false;
    let mut missing_kernel_headers = false;
    let mut kernel_release = String::new();
    let mut kernel_header_packages = String::new();

    let text = String::from_utf8_lossy(&output.stdout);
    for line in text.lines() {
        let mut parts = line.splitn(2, '=');
        if let (Some(k), Some(v)) = (parts.next(), parts.next()) {
            match k {
                "HAS_MISSING" => has_missing = v.trim() == "true",
                "MISSING_TOOLS" => missing_tools = v.trim().to_string(),
                "MISSING_PACKAGES" => missing_packages = v.trim().to_string(),
                "MISSING_SPDX" => missing_spdx = v.trim() == "true",
                "MISSING_PACSTALL" => missing_pacstall = v.trim() == "true",
                "MISSING_KERNEL_HEADERS" => missing_kernel_headers = v.trim() == "true",
                "KERNEL_RELEASE" => kernel_release = v.trim().to_string(),
                "KERNEL_HEADER_PACKAGES" => kernel_header_packages = v.trim().to_string(),
                _ => {}
            }
        }
    }

    Ok(DepInspection {
        has_missing,
        missing_tools,
        missing_packages,
        missing_spdx,
        missing_pacstall,
        missing_kernel_headers,
        kernel_release,
        kernel_header_packages,
    })
}

fn build_install_cmdline(helper: &Path, pidx: usize, profile_text: &str) -> String {
    let helper_path = helper.to_string_lossy().replace('\'', "'\\''");

    let mut ver_arg = "--branch recommended".to_string();
    let mut module_arg = "";
    if pidx == 0 {
        ver_arg = "--branch recommended".to_string();
    } else if pidx == 1 {
        ver_arg = "--branch latest".to_string();
    } else if let Some(start) = profile_text.find('(') {
        if let Some(end) = profile_text.find(')') {
            let ver = &profile_text[start + 1..end];
            ver_arg = format!("--version {}", ver);
        }
    }
    if pidx == 2 {
        module_arg = " --nvidia-open false";
    }

    format!(
        "NVIDIA_GUI_BACKEND=1 bash '{}' --check-dependencies && NVIDIA_GUI_BACKEND=1 bash '{}' --source online {}{} --action 1",
        helper_path, helper_path, ver_arg, module_arg
    )
}

fn spawn_install_run(weak: slint::Weak<AppWindow>, helper: PathBuf, pidx: usize, profile_text: String) {
    thread::spawn(move || {
        let cmdline = build_install_cmdline(&helper, pidx, &profile_text);
        let helper_dir = helper
            .parent()
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("."));

        let mut child = match Command::new("script")
            .arg("-qefc")
            .arg(cmdline)
            .arg("/dev/null")
            .current_dir(helper_dir)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                let weak_err = weak.clone();
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
            let weak_out = weak.clone();
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
            let weak_err = weak.clone();
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
            let weak_tick = weak.clone();
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

        let weak_done = weak.clone();
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
}

fn main() {
    if std::env::var("SLINT_BACKEND").is_err() {
        // Prefer FemtoVG to avoid software-renderer minimize/restore stalls on some systems.
        std::env::set_var("SLINT_BACKEND", "winit-femtovg");
    }
    let has_wayland = std::env::var("WAYLAND_DISPLAY").ok().filter(|v| !v.is_empty()).is_some()
        || std::env::var("WAYLAND_SOCKET").ok().filter(|v| !v.is_empty()).is_some();
    let has_x11 = std::env::var("DISPLAY").ok().filter(|v| !v.is_empty()).is_some();

    let create_default_ui = || -> AppWindow {
        match AppWindow::new() {
            Ok(ui) => ui,
            Err(e1) => {
                // Graceful fallback if OpenGL/FemtoVG is not available on the host.
                std::env::set_var("SLINT_BACKEND", "winit-software");
                AppWindow::new().unwrap_or_else(|e2| {
                    panic!("Cannot create UI (femtovg: {}; software: {})", e1, e2)
                })
            }
        }
    };

    let ui = if has_wayland {
        if !has_x11 {
            eprintln!("[gui] DISPLAY absent, fallback Wayland natif.");
            create_default_ui()
        } else if !libxkbcommon_x11_available() {
            eprintln!("[gui] libxkbcommon-x11 absente, fallback Wayland natif.");
            create_default_ui()
        } else {
            let old_wayland_display = std::env::var_os("WAYLAND_DISPLAY");
            let old_wayland_socket = std::env::var_os("WAYLAND_SOCKET");
            std::env::remove_var("WAYLAND_DISPLAY");
            std::env::remove_var("WAYLAND_SOCKET");

            let x11_attempt = std::panic::catch_unwind(std::panic::AssertUnwindSafe(AppWindow::new));

            match old_wayland_display {
                Some(v) => std::env::set_var("WAYLAND_DISPLAY", v),
                None => std::env::remove_var("WAYLAND_DISPLAY"),
            }
            match old_wayland_socket {
                Some(v) => std::env::set_var("WAYLAND_SOCKET", v),
                None => std::env::remove_var("WAYLAND_SOCKET"),
            }

            match x11_attempt {
                Ok(Ok(ui)) => {
                    eprintln!("[gui] XWayland mode actif.");
                    ui
                }
                Ok(Err(e)) => {
                    eprintln!(
                        "[gui] XWayland init echec: {}. Fallback Wayland natif.",
                        e
                    );
                    create_default_ui()
                }
                Err(_) => {
                    eprintln!("[gui] XWayland panic capturee. Fallback Wayland natif.");
                    create_default_ui()
                }
            }
        }
    } else {
        create_default_ui()
    };
    ui.set_window_maximized(false);
    ui.set_use_custom_frame(has_wayland);

    let drag_origin = Arc::new(Mutex::new((0i32, 0i32)));
    {
        let weak_drag_start = ui.as_weak();
        let drag_origin_start = drag_origin.clone();
        ui.on_window_drag_start(move || {
            if let Some(ui) = weak_drag_start.upgrade() {
                let p = ui.window().position();
                if let Ok(mut origin) = drag_origin_start.lock() {
                    *origin = (p.x, p.y);
                }
            }
        });
    }
    {
        let weak_drag = ui.as_weak();
        let drag_origin_move = drag_origin.clone();
        ui.on_window_drag(move |dx, dy| {
            if let Some(ui) = weak_drag.upgrade() {
                if let Ok(origin) = drag_origin_move.lock() {
                    let nx = origin.0 + dx.round() as i32;
                    let ny = origin.1 + dy.round() as i32;
                    ui.window().set_position(slint::PhysicalPosition::new(nx, ny));
                }
            }
        });
    }
    {
        let weak_min = ui.as_weak();
        ui.on_window_minimize(move || {
            if let Some(ui) = weak_min.upgrade() {
                ui.window().set_minimized(true);
            }
        });
    }
    {
        let weak_max = ui.as_weak();
        ui.on_window_toggle_maximize(move || {
            if let Some(ui) = weak_max.upgrade() {
                let next = !ui.window().is_maximized();
                ui.window().set_maximized(next);
                ui.set_window_maximized(next);
            }
        });
    }
    {
        let weak_close = ui.as_weak();
        ui.on_window_close(move || {
            if let Some(ui) = weak_close.upgrade() {
                let _ = ui.hide();
            }
        });
    }

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

    let pending_run: Arc<Mutex<Option<PendingRun>>> = Arc::new(Mutex::new(None));
    let pending_run_for_onrun = pending_run.clone();
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
        ui.set_logs("".into());
        append_ui_log(&ui, "[step 1/4] Resolution du backend CLI...");
        ui.set_status("Preparation...".into());

        let helper = match resolve_helper_path() {
            Ok(p) => p,
            Err(e) => {
                ui.set_status("Impossible de trouver le helper".into());
                ui.set_logs(e.into());
                ui.set_running(false);
                return;
            }
        };

        append_ui_log(&ui, "[step 2/4] Inspection des dependances...");
        ui.set_status("Verification dependances...".into());
        let dep_report = match inspect_dependencies(&helper) {
            Ok(v) => v,
            Err(e) => {
                ui.set_status("Echec verification dependances".into());
                ui.set_logs(e.into());
                ui.set_running(false);
                return;
            }
        };
        let mut dep_report = dep_report;
        if env_truthy("NVIDIA_GUI_TEST_MISSING_DEPS") {
            append_ui_log(&ui, "[test] NVIDIA_GUI_TEST_MISSING_DEPS=1 actif: simulation dependances manquantes.");
            dep_report.has_missing = true;
            if dep_report.missing_tools.is_empty() {
                dep_report.missing_tools = "curl lspci".to_string();
            }
            if dep_report.missing_packages.is_empty() {
                dep_report.missing_packages = "curl pciutils".to_string();
            }
            dep_report.missing_spdx = true;
            dep_report.missing_pacstall = true;
            dep_report.missing_kernel_headers = true;
            if dep_report.kernel_release.is_empty() {
                dep_report.kernel_release = "6.12.0-amd64".to_string();
            }
            if dep_report.kernel_header_packages.is_empty() {
                dep_report.kernel_header_packages =
                    "linux-headers-6.12.0-amd64 linux-headers-amd64".to_string();
            }
        }

        if dep_report.has_missing {
            let mut details = Vec::new();
            if !dep_report.missing_tools.is_empty() {
                details.push(format!("Outils manquants: {}", dep_report.missing_tools));
            }
            if !dep_report.missing_packages.is_empty() {
                details.push(format!("Paquets a installer: {}", dep_report.missing_packages));
            }
            if dep_report.missing_kernel_headers {
                details.push(format!(
                    "Headers noyau manquants ({}): {}",
                    dep_report.kernel_release, dep_report.kernel_header_packages
                ));
            }
            if dep_report.missing_spdx {
                details.push("Paquet requis manquant: spdx-licenses".to_string());
            }
            if dep_report.missing_pacstall {
                details.push("Outil requis manquant: pacstall".to_string());
            }
            let msg = format!(
                "L'installation necessite des dependances supplementaires.\n{}\n\nVoulez-vous continuer ?",
                details.join("\n")
            );
            append_ui_log(&ui, "[step 2/4] Dependances manquantes detectees.");
            for line in details {
                append_ui_log(&ui, &format!("[dep] {}", line));
            }
            ui.set_dep_popup_message(msg.into());
            ui.set_dep_popup_visible(true);
            ui.set_status("Confirmation dependances requise".into());
            if let Ok(mut slot) = pending_run_for_onrun.lock() {
                *slot = Some(PendingRun {
                    helper,
                    pidx,
                    profile_text,
                });
            }
            return;
        }

        append_ui_log(&ui, "[step 2/4] Dependances: OK");
        append_ui_log(&ui, "[step 3/4] Lancement check/install backend...");
        ui.set_status(format!("Execution en cours: profile={}...", profile_text).into());
        ui.set_running(true);
        spawn_install_run(weak.clone(), helper, pidx, profile_text);
    });

    {
        let weak_yes = ui.as_weak();
        let pending_yes = pending_run.clone();
        ui.on_dep_popup_yes(move || {
            let Some(ui) = weak_yes.upgrade() else {
                return;
            };
            ui.set_dep_popup_visible(false);
            let pending = pending_yes.lock().ok().and_then(|mut s| s.take());
            if let Some(run) = pending {
                append_ui_log(&ui, "[step 3/4] Confirmation utilisateur: OUI");
                append_ui_log(&ui, "[step 3/4] Lancement check/install backend...");
                ui.set_status(format!("Execution en cours: profile={}...", run.profile_text).into());
                ui.set_running(true);
                spawn_install_run(weak_yes.clone(), run.helper, run.pidx, run.profile_text);
            }
        });
    }
    {
        let weak_no = ui.as_weak();
        let pending_no = pending_run.clone();
        ui.on_dep_popup_no(move || {
            if let Ok(mut slot) = pending_no.lock() {
                *slot = None;
            }
            if let Some(ui) = weak_no.upgrade() {
                append_ui_log(&ui, "[step 3/4] Confirmation utilisateur: NON");
                ui.set_dep_popup_visible(false);
                ui.set_running(false);
                ui.set_status("Interrompu".into());
            }
        });
    }

    ui.run().expect("UI run failed");
}
