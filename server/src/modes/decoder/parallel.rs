//! Order-preserving parallel map of independent decode work (CL-057-02).
//! Results keep the input order and each item is computed exactly as on one thread, so
//! the caller's in-order folds give the single-threaded decode set and order.
use super::{DecodeError, search::CpuBudget};
use std::{
    sync::atomic::{AtomicUsize, Ordering},
    time::{Duration, Instant},
};

/// The logical CPUs a decode leaves to capture, display and transmit threads.
const SPARED_PROCESSORS: usize = 1;
/// Logical CPUs minus SPARED_PROCESSORS, and at least one.
pub(super) fn default_threads() -> usize {
    std::thread::available_parallelism()
        .map_or(1, |n| n.get().saturating_sub(SPARED_PROCESSORS))
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
#[path = "parallel_test.rs"]
mod tests;
