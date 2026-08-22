# Orb of Annulment audio process

This is the repeatable recipe for making a custom Path of Exile 2 alert that combines a voice
recording with the game's Divine-style ding.

## Inputs and outputs

- `OrbOfAnnulment.ogg` — the original WhatsApp recording, kept as the source backup.
- `AlertSound6.mp3` — the short reference for filter sound ID 6, downloaded from
  [FilterBlade](https://www.filterblade.xyz/assets/sounds/AlertSound6.mp3).
- `OrbOfAnnulment.mp3` — the final asset installed beside the `.filter` file.

## FFmpeg recipe

The first 0.5 seconds are trimmed from the voice recording. The trimmed voice and the ding both
start at time zero, then are mixed into one 48 kHz stereo MP3. The final mix receives a small
approximately +3 dB gain so the spoken alert is closer to the level of the other custom alerts:

```powershell
ffmpeg -y -i .\OrbOfAnnulment.ogg -i .\AlertSound6.mp3 `
  -filter_complex "[0:a]atrim=start=0.5,asetpts=PTS-STARTPTS,aresample=48000[voice];[1:a]aresample=48000[ding];[voice][ding]amix=inputs=2:duration=longest:dropout_transition=0:normalize=1[mix];[mix]volume=1.4[final]" `
  -map "[final]" -ar 48000 -ac 2 -c:a libmp3lame -b:a 320k .\OrbOfAnnulment.mp3
```

If `ffmpeg` is not on `PATH`, replace it with the full path to `ffmpeg.exe`. Listen to the result
before installing it. Because the ding is already inside the final MP3, the filter rule must not
use `Continue`; otherwise the parent currency rule would play a second ding.
