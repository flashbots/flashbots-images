use std::io::{self, Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering::SeqCst};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};
use std::{fs, mem, thread};

struct Cfg {
    image: String,
    listen: String,
    pool: usize,
    sock_dir: PathBuf, // max length 108 chars
    data_dir: Option<PathBuf>,
    ready_timeout: Duration,
    request_timeout: Duration,
    queue_timeout: Duration,
    run_args: Vec<String>,
}

fn cfg() -> Cfg {
    let mut c = Cfg {
        image: "localhost/flashbox:latest".into(),
        listen: "127.0.0.1:8081".into(),
        pool: 8,
        sock_dir: "/run/flashbox/sandboxes".into(),
        data_dir: None,
        ready_timeout: Duration::from_secs(60),
        request_timeout: Duration::from_secs(30),
        queue_timeout: Duration::from_secs(5),
        run_args: vec![],
    };
    let secs = |v: &str| Duration::from_secs(v.parse().expect("seconds"));
    let mut args = std::env::args().skip(1);
    while let Some(k) = args.next() {
        let v = args.next().expect("flag value");
        match k.as_str() {
            "--image" => c.image = v,
            "--listen" => c.listen = v,
            "--pool" => c.pool = v.parse().expect("--pool"),
            "--sock-dir" => c.sock_dir = v.into(),
            "--data-dir" => c.data_dir = Some(v.into()),
            "--ready-timeout" => c.ready_timeout = secs(&v),
            "--request-timeout" => c.request_timeout = secs(&v),
            "--queue-timeout" => c.queue_timeout = secs(&v),
            "--run-args" => c.run_args = v.split_whitespace().map(String::from).collect(),
            _ => panic!("unknown flag {k}"),
        }
    }
    c
}

fn podman() -> Command {
    let mut c = Command::new("podman");
    c.stdout(Stdio::null());
    c
}

fn run(c: &mut Command) -> io::Result<()> {
    if c.status()?.success() {
        Ok(())
    } else {
        Err(io::Error::other(format!("{c:?} failed")))
    }
}

// warming, ready or serving
static LIVE: AtomicUsize = AtomicUsize::new(0);

struct Sandbox {
    name: String,
    dir: PathBuf,
    born: Instant,
}

impl Sandbox {
    fn spawn(cfg: &Cfg, seq: u64) -> io::Result<Sandbox> {
        let name = format!("flashbox-{seq}");
        let dir = cfg.sock_dir.join(&name);
        fs::create_dir_all(&dir)?;
        LIVE.fetch_add(1, SeqCst);
        let sb = Sandbox {
            name,
            dir,
            born: Instant::now(),
        };
        let mut c = podman();
        c.args("run -d --rm --replace --network none --init --cap-drop all --security-opt no-new-privileges --read-only --tmpfs /tmp".split(' '))
            .args(["--name", &sb.name, "-v", &format!("{}:/flashbox", sb.dir.display())]);
        if let Some(d) = &cfg.data_dir {
            c.args(["-v", &format!("{}:/data:ro,nosuid,nodev", d.display())]);
        }
        c.args(&cfg.run_args).arg(&cfg.image);
        run(&mut c)?;
        Ok(sb)
    }

    fn sock(&self) -> PathBuf {
        self.dir.join("sock")
    }
}

impl Drop for Sandbox {
    fn drop(&mut self) {
        let _ = run(podman().args(["rm", "-f", "--ignore", "-t", "0", &self.name]));
        let _ = fs::remove_dir_all(&self.dir);
        LIVE.fetch_sub(1, SeqCst);
    }
}

#[derive(Default)]
struct Pool {
    ready: Mutex<Vec<Sandbox>>,
    cv: Condvar,
}

impl Pool {
    fn put(&self, sb: Sandbox) {
        self.ready.lock().unwrap().push(sb);
        self.cv.notify_one();
    }

    fn take(&self, timeout: Duration) -> Option<Sandbox> {
        let deadline = Instant::now() + timeout;
        let mut q = self.ready.lock().unwrap();
        loop {
            if let Some(sb) = q.pop() {
                return Some(sb);
            }
            let left = deadline.checked_duration_since(Instant::now())?;
            q = self.cv.wait_timeout(q, left).unwrap().0;
        }
    }

    fn keep_full(&self, cfg: &Cfg) {
        let mut warming = Vec::new();
        let mut seq = 0;
        loop {
            for sb in warming.extract_if(.., |sb: &mut Sandbox| {
                UnixStream::connect(sb.sock()).is_ok()
            }) {
                self.put(sb);
            }
            warming.retain(|sb| {
                let ok = sb.born.elapsed() < cfg.ready_timeout;
                if !ok {
                    eprintln!("{}: never became ready", sb.name);
                }
                ok
            });
            while LIVE.load(SeqCst) < cfg.pool {
                seq += 1;
                match Sandbox::spawn(cfg, seq) {
                    Ok(sb) => warming.push(sb),
                    Err(e) => {
                        eprintln!("{e}");
                        break;
                    }
                }
            }
            thread::sleep(Duration::from_millis(100));
        }
    }
}

#[derive(Clone, Copy, Default)]
enum Body {
    #[default]
    Head,
    Len(u64),
    ChunkSize,
    Chunk(u64),
    ChunkCrlf,
    Trailers,
    Eof,
    Done,
}

#[derive(Default)]
struct Response {
    body: Body,
    line: Vec<u8>,
}

fn skip(b: &mut &[u8], n: u64) -> u64 {
    let k = usize::try_from(n).map_or(b.len(), |n| n.min(b.len()));
    *b = &b[k..];
    n - k as u64
}

impl Response {
    fn line(&mut self, b: &mut &[u8], end: &[u8]) -> Option<Vec<u8>> {
        self.line.push(b[0]);
        *b = &b[1..];
        self.line.ends_with(end).then(|| mem::take(&mut self.line))
    }

    // Returns true once response is complete
    fn feed(&mut self, mut b: &[u8]) -> bool {
        use Body::*;
        while !b.is_empty() {
            self.body = match self.body {
                Head => match self.line(&mut b, b"\r\n\r\n") {
                    Some(h) => head(&h),
                    None => Head,
                },
                Len(n) => match skip(&mut b, n) {
                    0 => Done,
                    n => Len(n),
                },
                Chunk(n) => match skip(&mut b, n) {
                    0 => ChunkCrlf,
                    n => Chunk(n),
                },
                ChunkSize => match self.line(&mut b, b"\r\n") {
                    Some(l) => match chunk_size(&l) {
                        0 => Trailers,
                        n => Chunk(n),
                    },
                    None => ChunkSize,
                },
                ChunkCrlf => match self.line(&mut b, b"\r\n") {
                    Some(_) => ChunkSize,
                    None => ChunkCrlf,
                },
                Trailers => match self.line(&mut b, b"\r\n") {
                    Some(l) if l == b"\r\n" => Done,
                    _ => Trailers,
                },
                Eof => return false,
                Done => return true,
            };
            if matches!(self.body, Done) {
                return true;
            }
        }
        false
    }
}

fn chunk_size(line: &[u8]) -> u64 {
    let s = String::from_utf8_lossy(line);
    u64::from_str_radix(s.trim().split(';').next().unwrap_or(""), 16).unwrap_or(0)
}

fn head(head: &[u8]) -> Body {
    let head = String::from_utf8_lossy(head).to_ascii_lowercase();
    let status: u16 = head.get(9..12).and_then(|s| s.parse().ok()).unwrap_or(0);
    match status {
        100..200 => return Body::Head,
        204 | 304 => return Body::Done,
        _ => {}
    }
    let mut len = None;
    for (k, v) in head.lines().skip(1).filter_map(|l| l.split_once(':')) {
        match k.trim() {
            "transfer-encoding" if v.contains("chunked") => return Body::ChunkSize,
            "content-length" => len = v.trim().parse().ok(),
            _ => {}
        }
    }
    match len {
        Some(0) => Body::Done,
        Some(n) => Body::Len(n),
        None => Body::Eof,
    }
}

// Sends data from the sandbox to the client
// `sent` records bytes transferred before error
fn copy_response(up: &mut UnixStream, client: &mut TcpStream, sent: &mut usize) -> io::Result<()> {
    let mut resp = Response::default();
    let mut buf = vec![0; 64 << 10];
    loop {
        let n = up.read(&mut buf)?;
        if n == 0 {
            return Ok(());
        }
        client.write_all(&buf[..n])?;
        *sent += n;
        if resp.feed(&buf[..n]) {
            return Ok(());
        }
    }
}

fn relay(cfg: &Cfg, mut client: TcpStream, sb: &Sandbox) -> io::Result<()> {
    let mut up = UnixStream::connect(sb.sock())?;
    client.set_read_timeout(Some(cfg.request_timeout))?;
    up.set_read_timeout(Some(cfg.request_timeout))?;
    let (mut c2, mut u2) = (client.try_clone()?, up.try_clone()?);
    let t = thread::spawn(move || {
        let _ = io::copy(&mut c2, &mut u2);
        let _ = u2.shutdown(Shutdown::Write);
    });
    let mut sent = 0;
    let r = copy_response(&mut up, &mut client, &mut sent);
    if r.is_err() && sent == 0 {
        let _ = client.write_all(
            b"HTTP/1.1 504 Gateway Timeout\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        );
    }
    let _ = client.shutdown(Shutdown::Both);
    let _ = up.shutdown(Shutdown::Both);
    let _ = t.join();
    r
}

fn handle(cfg: &Cfg, pool: &Pool, mut client: TcpStream) {
    let Some(sb) = pool.take(cfg.queue_timeout) else {
        eprintln!("no ready sandbox");
        let _ = client.write_all(
            b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
        );
        return;
    };
    let t0 = Instant::now();
    match relay(cfg, client, &sb) {
        Ok(()) => eprintln!("{}: {:?}", sb.name, t0.elapsed()),
        Err(e) => eprintln!("{}: {e}", sb.name),
    }
}

fn main() {
    let cfg = Arc::new(cfg());
    let _ = run(podman().args(["rm", "-af", "-t", "0"]));
    run(podman().args(["image", "exists", &cfg.image])).expect("image not found");
    fs::create_dir_all(&cfg.sock_dir).expect("sock dir");
    let pool = Arc::new(Pool::default());
    thread::spawn({
        let (cfg, pool) = (cfg.clone(), pool.clone());
        move || pool.keep_full(&cfg)
    });
    let listener = TcpListener::bind(&cfg.listen).expect("bind");
    eprintln!(
        "listening on {} pool={} image={}",
        cfg.listen, cfg.pool, cfg.image
    );
    for client in listener.incoming().flatten() {
        let (cfg, pool) = (cfg.clone(), pool.clone());
        thread::spawn(move || handle(&cfg, &pool, client));
    }
}
