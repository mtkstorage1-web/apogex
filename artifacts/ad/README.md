# T-MINUS ad

Final: tminus_ad_20s.mp4 — silent, 20 seconds, 1920×1080, 30 fps, H.264/yuv420p.

Driver: scripts/ad_capture.gd, invoked by --ad in scripts/main.gd. Existing game rules are unchanged. Construction and cinematics are compressed; travel clocks are advanced as edit cuts. The driver scans and loads a real Science Flag before returning to Planet A. Titles are rendered in Godot because the installed ffmpeg has no drawtext filter.

Capture used a temporary override.cfg (removed afterward):

```ini
[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
```

```sh
~/Downloads/Godot.app/Contents/MacOS/Godot --path . --write-movie artifacts/ad/raw.avi --fixed-fps 30 --resolution 1920x1080 -- --ad
/opt/homebrew/bin/ffmpeg -y -i artifacts/ad/raw.avi -an -vf 'setpts=PTS*20/22.3,fps=30,scale=in_range=full:out_range=limited,format=yuv420p,fade=t=in:st=0:d=0.35,fade=t=out:st=19.5:d=0.5' -t 20 -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -color_range tv -movflags +faststart artifacts/ad/tminus_ad_20s.mp4
```

Checks: check_01.png through check_04.png at 3, 8, 13, 18 seconds. Visually inspected and nonblack. See ffprobe.txt and capture.log for validation.

Resolved issues: --resolution alone recorded 1600×900 (project viewport); temporary override fixed native capture. First encode reported yuvj420p; explicit limited-range conversion fixed yuv420p. No Godot capture or final encoding errors.
