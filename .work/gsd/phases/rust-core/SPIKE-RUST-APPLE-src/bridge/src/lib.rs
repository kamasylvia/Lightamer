// S5 — minimal Rust core exposed to Swift via UniFFI, including a raw
// MTLTexture pointer that is used in place (no pixel copy into Rust).
uniffi::setup_scaffolding!();

use objc2::rc::Retained;
use objc2::runtime::ProtocolObject;
use objc2_metal::{MTLRegion, MTLSize, MTLTexture};
use std::ffi::c_void;
use std::ptr::NonNull;
use std::future::Future;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};

#[uniffi::export(callback_interface)]
pub trait EventListener: Send + Sync {
    fn on_event(&self, msg: String);
}

#[derive(uniffi::Object)]
pub struct Core {
    listener: Mutex<Option<Arc<dyn EventListener>>>,
}

#[uniffi::export]
impl Core {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self { listener: Mutex::new(None) })
    }

    /// sync method
    pub fn ping(&self, name: String) -> String {
        format!("pong:{name} from rust {} on {:?}", std::env::consts::ARCH, std::thread::current().id())
    }

    /// async method: returns Pending once and is woken from a timer thread.
    pub async fn slow_add(&self, a: i64, b: i64) -> i64 {
        Delay::new(20).await;
        a + b
    }

    /// event callback (delivered from a Rust-owned thread)
    pub fn set_listener(&self, listener: Box<dyn EventListener>) {
        *self.listener.lock().unwrap() = Some(Arc::from(listener));
    }

    pub fn fire_event(&self, msg: String) {
        let l = self.listener.lock().unwrap().clone();
        std::thread::spawn(move || {
            if let Some(l) = l {
                l.on_event(format!("{msg} (thread {:?})", std::thread::current().id()));
            }
        });
    }

    /// Read width/height/pixelFormat straight off the caller's MTLTexture.
    pub fn texture_info(&self, texture_ptr: u64) -> String {
        unsafe {
            let Some(tex) = retain_texture(texture_ptr) else {
                return "null texture".into();
            };
            format!(
                "{}x{} pixelFormat={}",
                tex.width(),
                tex.height(),
                tex.pixelFormat().0
            )
        }
    }

    /// Write one RGBA8 pixel row directly into the caller's texture storage.
    /// Demonstrates zero-copy: the pixels never enter a Rust buffer copy of the image.
    pub fn paint_texture(&self, texture_ptr: u64, r: u8, g: u8, b: u8, a: u8) -> bool {
        unsafe {
            let Some(tex) = retain_texture(texture_ptr) else {
                return false;
            };
            let w = tex.width();
            let h = tex.height();
            let mut row = vec![0u8; w * 4];
            for x in 0..w {
                row[x * 4] = r;
                row[x * 4 + 1] = g;
                row[x * 4 + 2] = b;
                row[x * 4 + 3] = a;
            }
            let region = MTLRegion {
                origin: objc2_metal::MTLOrigin { x: 0, y: 0, z: 0 },
                size: MTLSize { width: w, height: h.min(1), depth: 1 },
            };
            tex.replaceRegion_mipmapLevel_withBytes_bytesPerRow(
                region,
                0,
                NonNull::new_unchecked(row.as_mut_ptr() as *mut c_void),
                w * 4,
            );
            true
        }
    }
}

unsafe fn retain_texture(ptr: u64) -> Option<Retained<ProtocolObject<dyn MTLTexture>>> {
    if ptr == 0 {
        return None;
    }
    Retained::retain(ptr as *mut ProtocolObject<dyn MTLTexture>)
}


// A runtime-free timer future: the first poll registers a waker and returns
// Pending; a background thread wakes it after `ms`. This proves UniFFI's async
// bridge without dragging a tokio reactor into the core.
struct Delay {
    shared: Arc<Mutex<DelayState>>,
}

#[derive(Default)]
struct DelayState {
    done: bool,
    waker: Option<Waker>,
}

impl Delay {
    fn new(ms: u64) -> Self {
        let shared = Arc::new(Mutex::new(DelayState::default()));
        let s2 = shared.clone();
        std::thread::spawn(move || {
            std::thread::sleep(std::time::Duration::from_millis(ms));
            let waker = {
                let mut st = s2.lock().unwrap();
                st.done = true;
                st.waker.take()
            };
            if let Some(w) = waker {
                w.wake();
            }
        });
        Self { shared }
    }
}

impl Future for Delay {
    type Output = ();
    fn poll(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<()> {
        let mut st = self.shared.lock().unwrap();
        if st.done {
            Poll::Ready(())
        } else {
            st.waker = Some(cx.waker().clone());
            Poll::Pending
        }
    }
}
