//! Order-preserving parallel map of independent decode work (#57 CL-057-02).
//! Results keep the input order and each item is computed exactly as on one thread, so
//! the caller's in-order folds give the single-threaded decode set and order.
use super::{DecodeError, search::CpuBudget};
use std::{
    sync::atomic::{AtomicUsize, Ordering},
    time::{Duration, Instant},
};

/// Logical CPUs minus one, leaving headroom for capture, display and transmit threads.
pub(super) fn default_threads() -> usize {
    std::thread::available_parallelism()
        .map_or(1, |n| n.get().saturating_sub(1))
        .max(1)
}

/// Applies `work` to every item on up to `threads` threads, this one included. Work runs
/// in rounds of about one cooperative quantum (each started item finishes), and the
/// caller's future yields between rounds, so the station worker keeps draining capture.
/// Each thread builds its own `state` (for example a forked pass transform) per round.
pub(super) async fn map<T: Sync, S, R: Send>(
    threads: usize,
    items: &[T],
    budget: &mut CpuBudget<'_>,
    state: impl Fn() -> S + Sync,
    work: impl Fn(&T, &mut S, &mut CpuBudget<'_>) -> R + Sync,
) -> Result<Vec<R>, DecodeError> {
    const QUANTUM: Duration = Duration::from_millis(10);
    let mut results: Vec<Option<R>> = items.iter().map(|_| None).collect();
    let next = AtomicUsize::new(0);
    let cancel = budget.cancel;
    let threads = threads.clamp(1, items.len().max(1));
    while next.load(Ordering::Relaxed) < items.len() {
        budget.checkpoint().await?;
        let deadline = Instant::now() + QUANTUM;
        let run = || {
            let mut state = state();
            let mut local = CpuBudget::new(cancel);
            let mut done = vec![];
            while Instant::now() < deadline {
                let index = next.fetch_add(1, Ordering::Relaxed);
                let Some(item) = items.get(index) else {
                    break;
                };
                done.push((index, work(item, &mut state, &mut local)));
            }
            done
        };
        let round = std::thread::scope(|scope| {
            let others: Vec<_> = (1..threads).map(|_| scope.spawn(run)).collect();
            let mut round = run();
            for other in others {
                round.extend(
                    other
                        .join()
                        .unwrap_or_else(|panic| std::panic::resume_unwind(panic)),
                );
            }
            round
        });
        for (index, result) in round {
            results[index] = Some(result);
        }
    }
    budget.checkpoint().await?;
    Ok(results.into_iter().map(|r| r.unwrap()).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::decoder::search::complete;
    // Proves: CL-057-02; TC-057-002. Every item once, in input order, for 1..8 threads and a slow item.
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
    // Proves: CL-057-02; TC-057-002. A cancelled caller stops between rounds with Cancelled.
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
}
