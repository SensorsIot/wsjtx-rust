**Layer:** HOW. **Scope:** this project's development environment and procedures.

## Machine

The factory runs on one Windows PC, **HB9BLA** (`192.168.0.37`), with the checkout
`D:\Github\wsjtx-rust`. The transceiver (IC-7300, COM3), the station, the test inputs that
are not in the repository, the timing baseline, the gate and the merge queue are there.
`machines:` in `harness/project/config.yaml` names it, so a gate and the queue worker start
only there. Heavy builds and gates share it with the live station: do not operate the radio
during a heavy gate.

On HB9BLA:

- **Station:** `https://192.168.0.37:18081`, scheduled task `WSTX Rust Station HB9BLA`,
  receipt `%LOCALAPPDATA%\WstxRust\station\station-running.json`. The deployed source is the
  one the issue checkpoint and this receipt name.
- **Station log:** `%LOCALAPPDATA%\WstxRust\station\profiles\ic7300\contacts.adi`, imported
  from the operator's Log4OM export; a rerun of Update logbook with the same export adds
  nothing.
- **IC-7300:** COM3 and the USB Audio CODEC. The operator runs it on 20 m FT8
  (14.074 MHz USB-D) with AGC SLOW for FT8 and FT4 (it removes the AGC line between periods).
  Agents key it as [Keying the radio](deployment-authority.md#keying-the-radio) says. The camera microphone belongs
  to Dictate, not the radio.
- **Comparison:** the official WSJT-X 3.3.0-beta4 runs alongside as `WSTX-Comparison`,
  Rig=None, no CAT/PTT, Fast/AP-off. A connected Edge frontend runs here too.
- **Credentials:** `%LOCALAPPDATA%\WstxMigration\credential-tools\PRIVATE-CREDENTIAL-HANDOFF.md`;
  readiness is checked without reading a value. Scoped Infisical authentication and secret
  reading work with normal TLS validation; native CLI use needs standard Windows CA trust.
  TLS is never bypassed.
- **Model toolchain:** the JDK and the Pilot are in `%USERPROFILE%\.cache\wsjtx-rust\sysml-tools`.
- **Fortran** is never installed on HB9BLA.

The `windows-rust.yml` artifact (`wstx-rust-windows-x64`) is build evidence only. It shows
that the build and tests pass on a clean Windows runner and is never installed on the
station.
