use std::fs::{self, File};
use std::io::{self, ErrorKind::NotFound};
use std::os::unix::{fs::OpenOptionsExt, fs::PermissionsExt, process::CommandExt};
use std::process::{Command, ExitCode};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const LOGS: &str = "/run/flashbox/logs";
const USAGE: &str = "commands: initialize upload deploy start stop status logs\nconnect to db with: ssh -N -L 6379:127.0.0.1:6379 <ip>";
const LOG_USAGE: &str = "logs [<id> | delete <id> | delete --older-than <timestamp> | delete --all]";
const O_NOFOLLOW: i32 = 0o400000;
const O_NONBLOCK: i32 = 0o4000;

fn ignore_missing<T>(result: io::Result<T>) -> io::Result<Option<T>> {
    match result {
        Err(e) if e.kind() == NotFound => Ok(None),
        result => result.map(Some),
    }
}

fn sudo(args: &[&str]) -> io::Result<()> {
    Err(Command::new("/usr/bin/sudo").args(args).exec())
}

fn active() -> io::Result<bool> {
    let status = Command::new("/usr/bin/systemctl").args(["-q", "is-active", "sandbox-relay"]).status()?;
    Ok(status.success())
}

fn safe_id(id: &str) -> bool {
    !id.is_empty() && !id.starts_with('-') && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
}

fn log_path(id: &str) -> String {
    format!("{LOGS}/{id}.log")
}

fn log_files() -> io::Result<Vec<(SystemTime, String)>> {
    let mut logs = Vec::new();
    for entry in fs::read_dir(LOGS)? {
        let entry = entry?;
        let name = entry.file_name();
        let Some(id) = name.to_str().and_then(|s| s.strip_suffix(".log")).filter(|s| safe_id(s)) else {
            continue;
        };
        if let Some(meta) = ignore_missing(entry.metadata())?.filter(fs::Metadata::is_file) {
            logs.push((meta.modified()?, id.to_owned()));
        }
    }
    logs.sort_unstable_by(|a, b| b.cmp(a));
    Ok(logs)
}

fn delete_logs(cutoff: Option<SystemTime>) -> io::Result<()> {
    log_files()?
        .iter()
        .filter(|(time, _)| cutoff.is_none_or(|cutoff| *time <= cutoff))
        .try_for_each(|(_, id)| ignore_missing(fs::remove_file(log_path(id))).map(drop))
}

fn timestamp(value: &str) -> io::Result<SystemTime> {
    let seconds = value.parse::<u64>().map_err(|_| io::Error::other("invalid timestamp"))?;
    UNIX_EPOCH.checked_add(Duration::from_secs(seconds)).ok_or_else(|| io::Error::other("invalid timestamp"))
}

/// Logs are only visible once they are at least five minutes old
fn logs(args: &[&str]) -> io::Result<()> {
    let cutoff = SystemTime::now() - Duration::from_secs(300);
    match args {
        [] => {
            println!("{LOG_USAGE}");
            for (_, id) in log_files()?.iter().filter(|(time, _)| *time <= cutoff).take(20) {
                println!("{id}");
            }
        }
        [id] if safe_id(id) => {
            let open = File::options().read(true).custom_flags(O_NOFOLLOW | O_NONBLOCK).open(log_path(id));
            let Some(mut file) = ignore_missing(open)? else { return Err(io::Error::other("id not found")) };
            let meta = file.metadata()?;
            if !meta.is_file() || meta.modified()? > cutoff {
                return Err(io::Error::other("id not found"));
            }
            io::copy(&mut file, &mut io::stdout().lock())?;
        }
        ["delete", id] if safe_id(id) => ignore_missing(fs::remove_file(log_path(id)))?.unwrap_or(()),
        ["delete", "--all"] => delete_logs(None)?,
        ["delete", "--older-than", value] => delete_logs(Some(timestamp(value)?))?,
        _ => return Err(io::Error::other(LOG_USAGE)),
    }
    Ok(())
}

fn searcher(args: &[&str]) -> io::Result<()> {
    match args {
        ["logs", rest @ ..] => sudo(&[&["-u", "sandbox", "/usr/bin/searchersh", "--logs"], rest].concat()),
        ["initialize"] => {
            if !Command::new("/usr/bin/sudo").args(["tdx-init", "set-passphrase"]).status()?.success() {
                return Err(io::Error::other("initialize failed"));
            }
            for path in ["/persistent/searcher", "/persistent/searcher/data"] {
                fs::create_dir_all(path)?;
                fs::set_permissions(path, fs::Permissions::from_mode(0o2775))?;
            }
            sudo(&["systemctl", "start", "flashbox-data"])
        }
        ["upload"] => {
            io::copy(&mut io::stdin().lock(), &mut File::create("/persistent/searcher/.flashbox.tar")?)?;
            fs::rename("/persistent/searcher/.flashbox.tar", "/persistent/searcher/flashbox.tar")
        }
        ["deploy"] if active()? => Err(io::Error::other("stop first")),
        ["deploy"] => sudo(&["systemctl", "restart", "flashbox-deploy"]),
        [command @ ("start" | "stop")] => sudo(&["systemctl", command, "sandbox-relay"]),
        ["status"] => {
            println!("{}", if active()? { "running" } else { "stopped" });
            Ok(())
        }
        _ => Err(io::Error::other(USAGE)),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        ["--logs", rest @ ..] => logs(rest),
        ["-c", command] => searcher(&command.split_ascii_whitespace().collect::<Vec<_>>()),
        _ => Err(io::Error::other(USAGE)),
    };
    result.map_or_else(|e| { eprintln!("{e}"); ExitCode::FAILURE }, |()| ExitCode::SUCCESS)
}
