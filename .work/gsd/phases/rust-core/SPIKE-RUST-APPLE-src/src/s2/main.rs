// S2 — Vision from Rust. Runs VNDetectFaceRectanglesRequest (the request the
// project actually uses) on a CC0 sample, plus VNDetectRectanglesRequest as a
// non-empty control (no CC0 sample contains a face). The completion handler
// feeds a std::sync::mpsc channel; work happens on a non-main thread.

use block2::RcBlock;
use objc2::rc::Retained;
use objc2::AnyThread;
use objc2_foundation::{NSArray, NSDictionary, NSString, NSURL};
use objc2_vision::{
    VNDetectFaceRectanglesRequest, VNDetectRectanglesRequest, VNImageRequestHandler, VNImageOption,
    VNRequest,
};
use std::ptr::NonNull;
use std::sync::mpsc;

fn main() {
    let path = std::env::args().nth(1).unwrap_or_else(|| {
        format!(
            "{}/Library/Application Support/Lightamer/TestRAW/ColorChecker.ARW",
            std::env::var("HOME").unwrap()
        )
    });
    println!("image: {path}");
    let (tx, rx) = mpsc::channel::<String>();

    let tx_cb = tx.clone();
    let worker = std::thread::spawn(move || unsafe {
        println!("worker thread: {:?}", std::thread::current().id());
        let url = NSURL::fileURLWithPath(&NSString::from_str(&path));
        let opts = NSDictionary::<VNImageOption, objc2::runtime::AnyObject>::new();
        let handler = VNImageRequestHandler::initWithURL_options(
            VNImageRequestHandler::alloc(),
            &url,
            &opts,
        );

        // ---- face rectangles (project's request) ----
        let cb_block = RcBlock::new(move |req: NonNull<VNRequest>, err: *mut objc2_foundation::NSError| {
            let n = if err.is_null() {
                req.as_ref().results().map(|r| r.len()).unwrap_or(0)
            } else {
                usize::MAX
            };
            tx_cb
                .send(format!(
                    "face completion callback on thread {:?}: results={}",
                    std::thread::current().id(),
                    n
                ))
                .ok();
        });
        let face = VNDetectFaceRectanglesRequest::initWithCompletionHandler(
            VNDetectFaceRectanglesRequest::alloc(),
            RcBlock::as_ptr(&cb_block),
        );
        let face_req: &VNRequest = &*(Retained::as_ptr(&face) as *const VNRequest);
        let face_arr = NSArray::from_slice(&[face_req]);
        match handler.performRequests_error(&face_arr) {
            Ok(()) => {}
            Err(e) => {
                tx.send(format!("face perform error: {}", e.localizedDescription())).ok();
            }
        }
        let face_boxes = collect_boxes(face.results());
        tx.send(format!("face boxes: {}", face_boxes.len())).ok();
        for b in &face_boxes {
            tx.send(format!("face {:.6},{:.6},{:.6},{:.6}", b[0], b[1], b[2], b[3])).ok();
        }

        // ---- rectangles control (non-empty observation marshalling) ----
        let rect = VNDetectRectanglesRequest::init(VNDetectRectanglesRequest::alloc());
        let rect_req: &VNRequest = &*(Retained::as_ptr(&rect) as *const VNRequest);
        let rect_arr = NSArray::from_slice(&[rect_req]);
        match handler.performRequests_error(&rect_arr) {
            Ok(()) => {}
            Err(e) => {
                tx.send(format!("rect perform error: {}", e.localizedDescription())).ok();
            }
        }
        let obs = VNDetectRectanglesRequest::results(&rect).unwrap_or_default();
        let mut rect_boxes: Vec<[f64; 4]> = obs
            .to_vec()
            .iter()
            .map(|o| {
                let r = o.boundingBox();
                [r.origin.x, r.origin.y, r.size.width, r.size.height]
            })
            .collect();
        rect_boxes.sort_by(|a, b| a.partial_cmp(b).unwrap());
        tx.send(format!("rect boxes: {}", rect_boxes.len())).ok();
        for b in &rect_boxes {
            tx.send(format!("rect {:.6},{:.6},{:.6},{:.6}", b[0], b[1], b[2], b[3])).ok();
        }
        tx.send("done".to_string()).ok();
    });

    let mut lines = Vec::new();
    while let Ok(msg) = rx.recv() {
        if msg == "done" {
            break;
        }
        println!("main<-channel: {msg}");
        lines.push(msg);
    }
    worker.join().unwrap();

    // canonical dump for byte comparison against the Swift reference
    let mut face: Vec<String> = lines.iter().filter(|l| l.starts_with("face ") && l.contains(',')).cloned().collect();
    let mut rect: Vec<String> = lines.iter().filter(|l| l.starts_with("rect ") && l.contains(',')).cloned().collect();
    face.sort();
    rect.sort();
    let mut out = String::new();
    out.push_str(&format!("faces {}\n", face.len()));
    for l in &face {
        out.push_str(l);
        out.push('\n');
    }
    out.push_str(&format!("rects {}\n", rect.len()));
    for l in &rect {
        out.push_str(l);
        out.push('\n');
    }
    std::fs::write("out/s2-rust.txt", &out).unwrap();
    println!("wrote out/s2-rust.txt");
}

unsafe fn collect_boxes(
    results: Option<Retained<NSArray<objc2_vision::VNFaceObservation>>>,
) -> Vec<[f64; 4]> {
    let mut v: Vec<[f64; 4]> = results
        .map(|a| a.to_vec())
        .unwrap_or_default()
        .iter()
        .map(|o| {
            let r = o.boundingBox();
            [r.origin.x, r.origin.y, r.size.width, r.size.height]
        })
        .collect();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v
}
