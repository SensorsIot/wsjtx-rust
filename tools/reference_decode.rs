#![forbid(unsafe_code)]
use std::{env, fs, time::Instant};
use wstx_rust::decoder::{Decoder, Mode};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        return Err("usage: reference_decode ft8|ft4 samples.f32".into());
    }
    let mode = match args[1].as_str() {
        "ft8" => Mode::Ft8,
        "ft4" => Mode::Ft4,
        _ => return Err("invalid mode".into()),
    };
    let bytes = fs::read(&args[2])?;
    if bytes.len() % 4 != 0 {
        return Err("incomplete float32 sample".into());
    }
    let samples: Vec<f32> = bytes.chunks_exact(4)
        .map(|b| f32::from_le_bytes(b.try_into().unwrap())).collect();
    if samples.iter().any(|x| !x.is_finite()) {
        return Err("non-finite sample".into());
    }
    let start = Instant::now();
    let result = Decoder::new().decode(&samples, mode, &|| false);
    match result {
        Ok(rows) => println!("{}", serde_json::json!({"wall_seconds":start.elapsed().as_secs_f64(),"decoded":rows})),
        Err(error) => return Err(format!("decode error: {error:?}").into()),
    }
    Ok(())
}
