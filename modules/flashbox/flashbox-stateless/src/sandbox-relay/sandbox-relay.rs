use bytes::Bytes;
use http_body_util::{combinators::BoxBody, BodyExt, Empty};
use hyper::{
    body::Incoming,
    header::{HeaderMap, HeaderName, HeaderValue},
    Method, Request, Response, Uri,
};
use hyper_util::rt::TokioIo;
use std::cell::RefCell;
use std::convert::Infallible;
use std::future::{poll_fn, Future};
use std::io::{self, Write};
use std::net::{TcpListener, TcpStream};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{chown, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::process::Stdio;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime};
use std::{fs, thread};
use tokio::process::Command;
use tokio::sync::Semaphore;
use tokio::time::Sleep;

const DIR: &str = "/run/flashbox/sandboxes";
const IMAGE: &str = "/run/flashbox/image";
const LOGS: &str = "/run/flashbox/logs";

// Pin socket file to prevent attacks by symlinking
async fn connect_socket(path: &Path) -> io::Result<tokio::net::UnixStream> {
    const O_PATH: i32 = 0o10000000;
    const O_NOFOLLOW: i32 = 0o400000;
    let pin = fs::OpenOptions::new()
        .read(true)
        .custom_flags(O_PATH | O_NOFOLLOW)
        .open(path)?;
    tokio::net::UnixStream::connect(format!("/proc/self/fd/{}", pin.as_raw_fd())).await
}

struct Cfg {
    listen: String,
    max_active: usize,
    request_timeout: Duration,
}

fn cfg() -> Cfg {
    let mut c = Cfg {
        listen: "127.0.0.1:8081".into(),
        max_active: 1,
        request_timeout: Duration::from_secs(30),
    };
    let secs = |v: &str| Duration::from_secs(v.parse().expect("seconds"));
    let mut args = std::env::args().skip(1);
    while let Some(k) = args.next() {
        let v = args.next().expect("flag value");
        match k.as_str() {
            "--listen" => c.listen = v,
            "--max-active" => c.max_active = v.parse().expect("--max-active"),
            "--request-timeout" => c.request_timeout = secs(&v),
            _ => panic!("unknown flag {k}"),
        }
    }
    c
}

fn delegate_cgroup() -> io::Result<String> {
    let cgroup = fs::read_to_string("/proc/self/cgroup")?
        .lines()
        .find_map(|l| l.strip_prefix("0::"))
        .ok_or_else(|| io::Error::other("cgroup v2 required"))?
        .to_owned();
    // Move to child cgroup
    let relay = PathBuf::from(format!("/sys/fs/cgroup{cgroup}/relay"));
    fs::create_dir_all(&relay)?;
    fs::write(relay.join("cgroup.procs"), "0")?;
    Ok(cgroup)
}

fn crun() -> Command {
    let mut c = Command::new("crun");
    c.arg("--root")
        .arg(format!("{DIR}/.crun"))
        .stdin(Stdio::null());
    c
}

fn run(c: &mut Command) -> io::Result<()> {
    if c.as_std_mut().status()?.success() {
        Ok(())
    } else {
        Err(io::Error::other(format!("{c:?} failed")))
    }
}

async fn start(c: &mut Command) -> io::Result<()> {
    if c.kill_on_drop(true).status().await?.success() {
        Ok(())
    } else {
        Err(io::Error::other(format!("{c:?} failed")))
    }
}

struct Sandbox {
    name: String,
    dir: PathBuf,
    mounted: bool,
    started: bool,
}

impl Sandbox {
    async fn spawn(cgroup: &str) -> io::Result<Sandbox> {
        let name = fs::read_to_string("/proc/sys/kernel/random/uuid")?
            .trim()
            .to_owned();
        let dir = PathBuf::from(DIR).join(&name);
        fs::create_dir_all(dir.join("flashbox"))?;
        let mut sb = Sandbox {
            name,
            dir,
            mounted: false,
            started: false,
        };
        fs::create_dir(sb.dir.join("rootfs"))?;
        let log = fs::File::options()
            .create_new(true)
            .append(true)
            .open(sb.dir.join("log"))?;
        log.set_permissions(fs::Permissions::from_mode(0o666))?;
        fs::set_permissions(sb.dir.join("flashbox"), fs::Permissions::from_mode(0o1777))?;
        let mut c = Command::new("jq");
        c.args(["--arg", "cgroup", &format!("{cgroup}/{}", sb.name)])
            .arg(".linux.cgroupsPath = $cgroup")
            .arg(format!("{IMAGE}/config.json"))
            .stdout(fs::File::create(sb.dir.join("config.json"))?);
        start(&mut c).await?;
        sb.mounted = true;
        c = Command::new("mount");
        c.args(["-t", "overlay", "overlay", "-o"])
            .arg(format!("lowerdir={IMAGE}/rootfs:{IMAGE}/empty"))
            .arg(sb.dir.join("rootfs"));
        start(&mut c).await?;
        sb.started = true;
        c = crun();
        c.args(["run", "-d", "--bundle"])
            .arg(&sb.dir)
            .arg(&sb.name)
            .stdout(log.try_clone()?)
            .stderr(log);
        start(&mut c).await?;
        Ok(sb)
    }

    async fn connect(&self) -> io::Result<tokio::net::UnixStream> {
        let path = self.dir.join("flashbox/sock");
        loop {
            match connect_socket(&path).await {
                Ok(up) => return Ok(up),
                Err(e)
                    if matches!(
                        e.kind(),
                        io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused
                    ) => {}
                Err(e) => return Err(e),
            }
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let cleanup = || -> io::Result<()> {
            if self.started {
                run(crun().args(["delete", "-f", &self.name]))?;
            }
            if self.mounted {
                run(Command::new("umount").arg(self.dir.join("rootfs")))?;
            }
            let log = self.dir.join("log");
            if log.exists() {
                chown(&log, Some(0), Some(0))?;
                fs::set_permissions(&log, fs::Permissions::from_mode(0o600))?;
                fs::File::options()
                    .write(true)
                    .open(&log)?
                    .set_times(fs::FileTimes::new().set_modified(SystemTime::now()))?;
                fs::rename(log, PathBuf::from(LOGS).join(format!("{}.log", self.name)))?;
            }
            fs::remove_dir_all(&self.dir)
        };
        if let Err(e) = cleanup() {
            eprintln!("{}: cleanup failed: {e}", self.name);
            std::process::exit(1);
        }
    }
}

fn clean_headers(h: &mut HeaderMap) {
    let listed: Vec<HeaderName> = h
        .get_all("connection")
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(','))
        .filter_map(|v| v.trim().parse().ok())
        .collect();
    for name in listed {
        h.remove(name);
    }
    for name in [
        "connection",
        "keep-alive",
        "proxy-connection",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
        "x-sandbox-id",
        "x-relay-ms",
        "x-deadline-ms",
    ] {
        h.remove(name);
    }
}

type HttpBody = BoxBody<Bytes, hyper::Error>;

fn body(b: Incoming) -> HttpBody {
    b.map_frame(|mut f| {
        if let Some(h) = f.trailers_mut() {
            clean_headers(h);
        }
        f
    })
    .boxed()
}

fn error(status: u16) -> Response<HttpBody> {
    let body = Empty::new().map_err(|e: Infallible| match e {}).boxed();
    Response::builder().status(status).body(body).unwrap()
}

fn ms(d: Duration) -> HeaderValue {
    HeaderValue::from(d.as_millis() as u64)
}

// Remaining time left in milliseconds
fn budget(h: &HeaderMap, max: Duration) -> Result<Duration, u16> {
    let mut values = h.get_all("x-deadline-ms").iter();
    let Some(v) = values.next() else {
        return Ok(max);
    };
    match v
        .to_str()
        .ok()
        .filter(|v| v.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|v| v.parse::<u64>().ok())
    {
        Some(n) if n > 0 && values.next().is_none() => Ok(Duration::from_millis(n).min(max)),
        _ => Err(400),
    }
}

async fn relay(
    cfg: &Cfg,
    cgroup: &str,
    started: Instant,
    deadline: &RefCell<Pin<Box<Sleep>>>,
    mut req: Request<Incoming>,
) -> Result<Response<HttpBody>, u16> {
    if req.method() == Method::CONNECT || req.headers().contains_key("upgrade") {
        return Err(400);
    }
    let expires = started + budget(req.headers(), cfg.request_timeout)?;
    deadline.borrow_mut().as_mut().reset(expires.into());
    if Instant::now() >= expires {
        return Err(504);
    }
    let relay_started = Instant::now();
    let mut name = None;
    let result = tokio::time::timeout_at(expires.into(), async {
        let sb = Sandbox::spawn(cgroup).await?;
        name = Some(sb.name.clone());
        let up = sb.connect().await?;
        let (mut sender, conn) = hyper::client::conn::http1::Builder::new()
            .max_buf_size(64 << 10)
            .handshake(TokioIo::new(up))
            .await
            .map_err(io::Error::other)?;
        tokio::spawn(async move {
            let _ = conn.await;
            drop(sb);
        });
        let parts = std::mem::take(req.uri_mut()).into_parts();
        *req.uri_mut() = parts.path_and_query.map_or_else(Uri::default, Uri::from);
        let h = req.headers_mut();
        clean_headers(h);
        h.insert("connection", HeaderValue::from_static("close"));
        h.insert(
            "x-deadline-ms",
            ms(expires.saturating_duration_since(Instant::now())),
        );
        sender
            .send_request(req.map(body))
            .await
            .map(|r| r.map(body))
            .map_err(io::Error::other)
    })
    .await;
    let mut resp = match result {
        Ok(Ok(r)) => r,
        Ok(Err(e)) => {
            eprintln!("sandbox: {e}");
            error(502)
        }
        Err(_) => error(504),
    };
    let h = resp.headers_mut();
    clean_headers(h);
    if let Some(name) = name {
        h.insert("x-sandbox-id", name.parse().unwrap());
        h.insert("x-relay-ms", ms(relay_started.elapsed()));
    }
    Ok(resp)
}

fn handle(cfg: &Cfg, cgroup: &str, client: TcpStream, started: Instant) -> io::Result<()> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?;
    client.set_nonblocking(true)?;
    rt.block_on(async {
        let client = TokioIo::new(tokio::net::TcpStream::from_std(client)?);
        let deadline = RefCell::new(Box::pin(tokio::time::sleep_until(
            (started + cfg.request_timeout).into(),
        )));
        let service = hyper::service::service_fn(|req| async {
            Ok::<_, Infallible>(
                relay(cfg, cgroup, started, &deadline, req)
                    .await
                    .unwrap_or_else(error),
            )
        });
        let mut http = hyper::server::conn::http1::Builder::new();
        http.keep_alive(false).max_buf_size(64 << 10);
        tokio::select! {
            biased;
            r = http.serve_connection(client, service) => r.map_err(io::Error::other),
            _ = poll_fn(|cx| deadline.borrow_mut().as_mut().poll(cx)) => {
                Err(io::Error::new(io::ErrorKind::TimedOut, "deadline"))
            }
        }
    })
}

fn main() {
    let cfg = Arc::new(cfg());
    let cgroup = Arc::new(delegate_cgroup().expect("delegate cgroup"));
    fs::metadata(format!("{IMAGE}/config.json")).expect("no image deployed");
    let slots = Arc::new(Semaphore::new(cfg.max_active));
    let listener = TcpListener::bind(&cfg.listen).expect("bind");
    eprintln!(
        "listening on {} max-active={}",
        listener.local_addr().unwrap(),
        cfg.max_active
    );
    for mut client in listener.incoming().flatten() {
        let started = Instant::now();
        let Ok(slot) = slots.clone().try_acquire_owned() else {
            let _ = client.set_write_timeout(Some(Duration::from_millis(100)));
            let _ = client.write_all(b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            continue;
        };
        let (cfg, cgroup) = (cfg.clone(), cgroup.clone());
        thread::spawn(move || {
            let _slot = slot;
            if let Err(e) = handle(&cfg, &cgroup, client, started) {
                eprintln!("request: {e}");
            }
        });
    }
}
