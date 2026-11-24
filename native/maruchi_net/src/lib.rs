use std::collections::VecDeque;
use std::ffi::CStr;
use std::io::{ErrorKind, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::os::raw::c_char;
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicI32, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::thread;
use std::time::Duration;

const STATE_DISCONNECTED: i32 = 0;
const STATE_CONNECTING: i32 = 1;
const STATE_CONNECTED: i32 = 2;
const STATE_ERROR: i32 = 3;

const MAX_FRAME_LEN: usize = 1024 * 1024; // 1 MiB safety cap
const MAX_INBOUND_QUEUE: usize = 512;

struct NetState {
    state: AtomicI32,
    stop_flag: Mutex<Option<Arc<AtomicBool>>>,
    outbound: Mutex<VecDeque<Vec<u8>>>,
    inbound: Mutex<VecDeque<Vec<u8>>>,
    last_error: Mutex<String>,
}

impl NetState {
    fn new() -> Self {
        Self {
            state: AtomicI32::new(STATE_DISCONNECTED),
            stop_flag: Mutex::new(None),
            outbound: Mutex::new(VecDeque::new()),
            inbound: Mutex::new(VecDeque::new()),
            last_error: Mutex::new(String::new()),
        }
    }

    fn set_error(&self, msg: String) {
        if let Ok(mut e) = self.last_error.lock() {
            *e = msg;
        }
        self.state.store(STATE_ERROR, Ordering::SeqCst);
    }

    fn stop_current(&self) {
        if let Ok(mut guard) = self.stop_flag.lock() {
            if let Some(flag) = guard.take() {
                flag.store(true, Ordering::SeqCst);
            }
        }
        if let Ok(mut out) = self.outbound.lock() {
            out.clear();
        }
        if let Ok(mut inc) = self.inbound.lock() {
            inc.clear();
        }
    }
}

fn global_net() -> &'static NetState {
    static INSTANCE: OnceLock<NetState> = OnceLock::new();
    INSTANCE.get_or_init(NetState::new)
}

fn worker_loop(host: String, port: u16, stop: Arc<AtomicBool>) {
    let net = global_net();

    let addr = match format!("{}:{}", host, port).to_socket_addrs() {
        Ok(mut iter) => match iter.next() {
            Some(a) => a,
            None => {
                net.set_error(format!("No address resolved for {}:{}", host, port));
                return;
            }
        },
        Err(e) => {
            net.set_error(format!("DNS resolve failed: {}", e));
            return;
        }
    };

    if stop.load(Ordering::SeqCst) {
        net.state.store(STATE_DISCONNECTED, Ordering::SeqCst);
        return;
    }

    let mut stream = match TcpStream::connect_timeout(&addr, Duration::from_secs(5)) {
        Ok(s) => s,
        Err(e) => {
            net.set_error(format!("Connect failed ({}): {}", addr, e));
            return;
        }
    };

    let _ = stream.set_nodelay(true);
    let _ = stream.set_nonblocking(true);

    if stop.load(Ordering::SeqCst) {
        net.state.store(STATE_DISCONNECTED, Ordering::SeqCst);
        return;
    }

    net.state.store(STATE_CONNECTED, Ordering::SeqCst);

    let mut read_buf: Vec<u8> = Vec::with_capacity(8192);
    let mut temp = [0u8; 4096];
    let mut write_buf: Vec<u8> = Vec::new();
    let mut write_offset: usize = 0;

    while !stop.load(Ordering::SeqCst) {
        let mut did_work = false;

        // 1. Drain outbound queue into contiguous write buffer (4-byte BE length + payload)
        if write_offset >= write_buf.len() {
            write_buf.clear();
            write_offset = 0;
            if let Ok(mut out) = net.outbound.lock() {
                while let Some(msg) = out.pop_front() {
                    if msg.len() <= MAX_FRAME_LEN {
                        let len_bytes = (msg.len() as u32).to_be_bytes();
                        write_buf.extend_from_slice(&len_bytes);
                        write_buf.extend_from_slice(&msg);
                    }
                    if write_buf.len() >= 65536 {
                        break;
                    }
                }
            }
        }

        // 2. Non-blocking write
        if write_offset < write_buf.len() {
            match stream.write(&write_buf[write_offset..]) {
                Ok(0) => {
                    net.set_error("Connection closed during write".to_string());
                    return;
                }
                Ok(n) => {
                    write_offset += n;
                    did_work = true;
                }
                Err(ref e) if e.kind() == ErrorKind::WouldBlock => {}
                Err(e) => {
                    net.set_error(format!("Write error: {}", e));
                    return;
                }
            }
        }

        // 3. Non-blocking read
        loop {
            match stream.read(&mut temp) {
                Ok(0) => {
                    if !stop.load(Ordering::SeqCst) {
                        net.set_error("Server closed connection".to_string());
                    } else {
                        net.state.store(STATE_DISCONNECTED, Ordering::SeqCst);
                    }
                    return;
                }
                Ok(n) => {
                    read_buf.extend_from_slice(&temp[..n]);
                    did_work = true;
                }
                Err(ref e) if e.kind() == ErrorKind::WouldBlock => break,
                Err(e) => {
                    net.set_error(format!("Read error: {}", e));
                    return;
                }
            }
        }

        // 4. Parse complete frames from read_buf
        while read_buf.len() >= 4 {
            let frame_len =
                u32::from_be_bytes([read_buf[0], read_buf[1], read_buf[2], read_buf[3]]) as usize;
            if frame_len > MAX_FRAME_LEN {
                net.set_error(format!("Frame too large: {} bytes", frame_len));
                return;
            }
            if read_buf.len() < 4 + frame_len {
                break;
            }
            let payload = read_buf[4..4 + frame_len].to_vec();
            read_buf.drain(..4 + frame_len);

            if let Ok(mut inc) = net.inbound.lock() {
                if inc.len() >= MAX_INBOUND_QUEUE {
                    inc.pop_front();
                }
                inc.push_back(payload);
            }
        }

        if !did_work {
            thread::sleep(Duration::from_millis(2));
        }
    }

    net.state.store(STATE_DISCONNECTED, Ordering::SeqCst);
}

#[no_mangle]
pub extern "system" fn maruchi_connect(host_ptr: *const c_char, port: i32) -> i32 {
    if host_ptr.is_null() || port <= 0 || port > 65535 {
        return 0;
    }
    let host = match unsafe { CStr::from_ptr(host_ptr) }.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return 0,
    };

    let net = global_net();
    net.stop_current();
    if let Ok(mut e) = net.last_error.lock() {
        e.clear();
    }
    net.state.store(STATE_CONNECTING, Ordering::SeqCst);

    let stop = Arc::new(AtomicBool::new(false));
    if let Ok(mut guard) = net.stop_flag.lock() {
        *guard = Some(Arc::clone(&stop));
    }

    let port_u16 = port as u16;
    thread::spawn(move || worker_loop(host, port_u16, stop));
    1
}

#[no_mangle]
pub extern "system" fn maruchi_disconnect() -> i32 {
    let net = global_net();
    net.stop_current();
    net.state.store(STATE_DISCONNECTED, Ordering::SeqCst);
    1
}

#[no_mangle]
pub extern "system" fn maruchi_state() -> i32 {
    global_net().state.load(Ordering::SeqCst)
}

#[no_mangle]
pub extern "system" fn maruchi_send(data_ptr: *const u8, len: i32) -> i32 {
    if data_ptr.is_null() || len <= 0 || (len as usize) > MAX_FRAME_LEN {
        return 0;
    }
    let net = global_net();
    let st = net.state.load(Ordering::SeqCst);
    if st != STATE_CONNECTED && st != STATE_CONNECTING {
        return 0;
    }
    let slice = unsafe { std::slice::from_raw_parts(data_ptr, len as usize) };
    if let Ok(mut out) = net.outbound.lock() {
        out.push_back(slice.to_vec());
        return 1;
    }
    0
}

#[no_mangle]
pub extern "system" fn maruchi_poll(buf_ptr: *mut u8, buf_cap: i32) -> i32 {
    if buf_ptr.is_null() || buf_cap <= 0 {
        return 0;
    }
    let net = global_net();
    if let Ok(mut inc) = net.inbound.lock() {
        if let Some(front) = inc.front() {
            let need = front.len();
            if need > (buf_cap as usize) {
                return -(need as i32);
            }
            let msg = inc.pop_front().unwrap();
            unsafe {
                ptr::copy_nonoverlapping(msg.as_ptr(), buf_ptr, need);
            }
            return need as i32;
        }
    }
    0
}

#[no_mangle]
pub extern "system" fn maruchi_last_error(buf_ptr: *mut u8, buf_cap: i32) -> i32 {
    if buf_ptr.is_null() || buf_cap <= 0 {
        return 0;
    }
    let net = global_net();
    if let Ok(err) = net.last_error.lock() {
        let bytes = err.as_bytes();
        let copy_len = bytes.len().min(buf_cap as usize);
        if copy_len > 0 {
            unsafe {
                ptr::copy_nonoverlapping(bytes.as_ptr(), buf_ptr, copy_len);
            }
        }
        return copy_len as i32;
    }
    0
}
