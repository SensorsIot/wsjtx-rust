use super::*;

/// Direct upper-bound capacity state, never a signal-generated candidate claim.
pub(in super::super) struct PeakCapacityReserve {
    heap: BinaryHeap<Peak>,
    old_generation: Vec<Peak>,
}
impl PeakCapacityReserve {
    pub(in super::super) fn new() -> Self {
        let points = || {
            (0..435).step_by(2).flat_map(|row| {
                (0..1057).step_by(2).map(move |frequency_index| Peak {
                    score: 3.,
                    row,
                    frequency_index,
                })
            })
        };
        let mut heap = BinaryHeap::new();
        let mut growth = vec![];
        let mut largest_pair = (0usize, 0usize);
        for peak in points() {
            let old = heap.capacity();
            heap.push(peak);
            let new = heap.capacity();
            if old != new {
                growth.push(
                    serde_json::json!({"len":heap.len(),"old_capacity":old,"new_capacity":new}),
                );
                if old + new > largest_pair.0 + largest_pair.1 {
                    largest_pair = (old, new);
                }
            }
        }
        assert_eq!(heap.len(), 115322);
        assert!(heap.capacity() >= largest_pair.1);
        let mut old_generation = Vec::with_capacity(largest_pair.0);
        old_generation.extend(points().take(largest_pair.0));
        assert_eq!(old_generation.len(), largest_pair.0);
        assert!(old_generation.capacity() >= largest_pair.0);
        let data = serde_json::json!({"owner":"direct_peak_two_generation_reserve",
            "mode":"ft8","direct_capacity_not_signal":true,
            "logical_maximum_peaks":heap.len(),"peak_size_bytes":std::mem::size_of::<Peak>(),
            "growth":growth,"largest_observed_old_new":largest_pair,
            "retained_heap_capacity":heap.capacity(),"retained_old_generation_capacity":old_generation.capacity(),
            "retained_raw_bytes":(heap.capacity()+old_generation.capacity())*std::mem::size_of::<Peak>(),
            "is_signal_generated":false,"is_decoded_success":false,
            "same_artifact_growth_trace_only":true,"cross_version_growth_assumed":false});
        let encoded = serde_json::to_string(&data).unwrap();
        assert!(encoded.len() < 16000);
        eprintln!("RESOURCE_CAPACITY {encoded}");
        Self {
            heap,
            old_generation,
        }
    }
    pub(in super::super) fn retain(&self) {
        std::hint::black_box((&self.heap, &self.old_generation));
    }
}
