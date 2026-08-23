# Orb of Annulment audio process

This is the repeatable recipe for making a custom Path of Exile 2 alert that combines a voice
recording with the game's Divine-style ding.

## Inputs and outputs

- `OrbOfAnnulment.ogg` — the original WhatsApp recording, kept as the source backup.
- `AlertSound6.mp3` — the short reference for filter sound ID 6, downloaded from
  [FilterBlade](https://www.filterblade.xyz/assets/sounds/AlertSound6.mp3).
- `OrbOfAnnulment.mp3` — the final asset installed beside the `.filter` file.

## FFmpeg mix recipe

The first 0.5 seconds are trimmed from the voice recording. The trimmed voice and the ding both
start at time zero, then are mixed into one 48 kHz stereo MP3. Only the voice layer receives a
small approximately +3 dB gain; the Divine-style ding keeps its original level:

```powershell
ffmpeg -y -i .\OrbOfAnnulment.ogg -i .\AlertSound6.mp3 `
  -filter_complex "[0:a]atrim=start=0.5,asetpts=PTS-STARTPTS,aresample=48000,volume=1.4[voice];[1:a]aresample=48000[ding];[voice][ding]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1[mix]" `
  -map "[mix]" -ar 48000 -ac 2 -c:a libmp3lame -b:a 320k .\OrbOfAnnulment-premaster.mp3
```

## Loudness acceptance pass

The published Orb of Annulment alert is intentionally **0.20 LU louder** than
`HibOmenLight.mp3`. Do not reuse an old gain value after changing either source or the mix;
measure the reference and premaster every time:

```powershell
ffmpeg -hide_banner -nostats -i .\HibOmenLight.mp3 `
  -af "loudnorm=I=-24:LRA=7:TP=-1:print_format=json" -f null NUL

ffmpeg -hide_banner -nostats -i .\OrbOfAnnulment-premaster.mp3 `
  -af "loudnorm=I=-24:LRA=7:TP=-1:print_format=json" -f null NUL
```

Read `input_i` from both reports. Calculate:

```text
target LUFS = Omen of Light input_i + 0.20
gain dB     = target LUFS - premaster input_i
```

Render to a candidate, then run the loudness analysis again before replacing the installed file:

```powershell
$gainDb = -17.05 - (-19.43) # example only; use the measurements from this run
ffmpeg -y -i .\OrbOfAnnulment-premaster.mp3 -af "volume=${gainDb}dB" `
  -ar 48000 -ac 2 -c:a libmp3lame -b:a 320k .\OrbOfAnnulment-candidate.mp3
```

Acceptance criteria:

- integrated loudness is within 0.1 LU of the calculated target;
- true peak (`input_tp`) remains below 0 dBTP with sensible headroom;
- duration, 48 kHz sample rate, stereo channels, and decoding are intact;
- only then replace `OrbOfAnnulment.mp3` and record its SHA-256.

The asset published on 2026-08-23 measured -17.04 LUFS and -2.39 dBTP against Omen of Light at
-17.25 LUFS. These values are a verification record, not constants for a future remaster.

If `ffmpeg` is not on `PATH`, replace it with the full path to `ffmpeg.exe`. Listen to the result
before installing it. Because the ding is already inside the final MP3, the filter rule must not
use `Continue`; otherwise the parent currency rule would play a second ding.
