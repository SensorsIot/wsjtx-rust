use super::*;
use crate::decoder::search::complete;
// Every item once, in input order, for 1..8 threads and a slow item.
// Proves: TC-057-002
#[test]
fn map_keeps_input_order_on_any_thread_count() {
    let items: Vec<u64> = (0..200).collect();
    let never = || false;
    for threads in [1, 2, 4, 8] {
        let mut budget = CpuBudget::new(&never);
        let out = complete(map(
            threads,
            &items,
            &mut budget,
            || 0u64,
            |&x, calls, _| {
                *calls += 1;
                if x == 3 {
                    std::thread::sleep(Duration::from_millis(30));
                }
                x * x
            },
        ))
        .unwrap();
        assert_eq!(out, items.iter().map(|x| x * x).collect::<Vec<_>>());
    }
}
// A cancelled caller stops between rounds with Cancelled.
// Proves: TC-057-002
#[test]
fn map_stops_when_cancelled() {
    let cancelled = std::sync::atomic::AtomicBool::new(false);
    let cancel = || cancelled.load(Ordering::Relaxed);
    let items: Vec<u64> = (0..10_000).collect();
    let mut budget = CpuBudget::new(&cancel);
    let result = complete(map(
        4,
        &items,
        &mut budget,
        || (),
        |_, _, _| {
            cancelled.store(true, Ordering::Relaxed);
            std::thread::sleep(Duration::from_millis(1));
        },
    ));
    assert_eq!(result.err(), Some(DecodeError::Cancelled));
}
