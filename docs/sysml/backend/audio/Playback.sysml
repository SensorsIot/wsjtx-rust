package WstxAudioPlayback {
    private import ScalarValues::*;
    action def AudioPlayback {
        doc /* WASAPI shared event-driven render on exactly the profile's
             audio.output_device endpoint ID (no default fallback), 48 kHz mix format
             only (float32 or PCM16/24/32, any channel count, the mono program on every
             channel); otherwise audioUnavailable before PTT is keyed. The device opens
             streaming silence before keying, plays one program (waveform from its
             planned sample or the Tune tone), and stops and closes within 250 ms from
             any thread. Buffer: the shared-mode buffer is requested at renderBufferMs;
             without a program at most silencePrefillMs of silence is queued, so the
             first program sample is not delayed behind a full buffer; a program fills
             the whole buffer, so a render thread delayed by load does not underrun the
             device and stretch the transmission. Drain: after the program's last frame
             nothing more is written, so the device padding drains and the end is
             reported only when every program frame was consumed. Render watchdog: while playing, no device
             consumption for renderStallMs, or an ended render thread, is
             audioDeviceLost. A render error or invalidated device during audio is
             audioDeviceLost: PTT is released and the station disarms. Capture never
             opens it; it never touches CAT. */
    }
}
