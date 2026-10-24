#!/bin/bash
# branch-only: normal vs iqama phase, same hosted widgets, same bounds. Usage: iqama_pair.sh <apk> <outdir>
APK=$1; OUT=$2; PKG=com.wathakker.app; mkdir -p "$OUT"; adb root >/dev/null 2>&1; adb shell settings put global auto_time 0; adb shell settings put global auto_time_zone 0
P=(NextPrayer PrayerBar Schedule DayPrayer Pill Clock Hijri Gregorian Hero OneUI)
P=(NextPrayer PrayerBar Schedule DayPrayer Pill Clock Hijri Gregorian Hero OneUI)
adb install -r -g "$APK" > "$OUT/install.txt" 2>&1
adb shell svc power stayon true
adb shell settings put global anr_show_background 0
adb shell settings put system accelerometer_rotation 0; adb shell settings put system user_rotation 0
dump(){ adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml "$1" >/dev/null 2>&1; }
tap_re(){ python3 - "$1" "$2" <<'PY'
import re,sys
x=open(sys.argv[2],encoding='utf8').read()
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0)
    t=re.search(r'text="([^"]*)"',n); d=re.search(r'content-desc="([^"]*)"',n); b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',n)
    s=(t.group(1) if t else '')+' '+(d.group(1) if d else '')
    if b and re.search(sys.argv[1],s):
        a=list(map(int,b.groups())); print((a[0]+a[2])//2,(a[1]+a[3])//2); break
PY
}
noanr(){ for i in 1 2 3; do dump "$OUT/_anr.xml"; if grep -q "isn't responding" "$OUT/_anr.xml"; then XY=$(tap_re "^ *Wait *$" "$OUT/_anr.xml"); [ -n "$XY" ] && adb shell input tap $XY; sleep 3; else break; fi; done; }
shot(){ noanr; local n=1 f="$OUT/$1.png"
  while :; do
    adb exec-out screencap -p > "$f"
    if [ "$(python3 "$(dirname "$0")/screen_dark.py" "$f")" = "1" ] && [ $n -le 4 ]; then
      dump "$OUT/_anr.xml"; XY=$(tap_re "Wait" "$OUT/_anr.xml")
      [ -z "$XY" ] && XY="$((W*28/100)) $((H*57/100))"
      adb shell input tap $XY; sleep 4; n=$((n+1))
    else break; fi
  done
}
top(){ adb shell dumpsys activity activities | grep -m1 -E "mResumedActivity|ResumedActivity" | grep -o 'com\.[A-Za-z.]*/[A-Za-z.]*' | head -1; }
RES="$OUT/widgets.txt"; : > "$RES"
host(){ # mask
  adb shell am force-stop $PKG; sleep 2
  if [ -n "$1" ]; then adb shell am start -S -W -n $PKG/com.example.WidgetHostCheck --es m "$1" >> "$OUT/hostlaunch.txt" 2>&1; else adb shell am start -S -W -n $PKG/com.example.WidgetHostCheck >> "$OUT/hostlaunch.txt" 2>&1; fi
  sleep 9; noanr
}
SZ=$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1); W=${SZ%x*}; H=${SZ#*x}
echo "screen $SZ" >> "$RES"
tapw(){ # label index expected(Main|Host) mask(for relaunch)
  local i=$2 col=$(( $2 % 5 )) row=$(( $2 / 5 ))
  local x=$(( (2*col+1) * W / 10 )) y=$(( (2*row+1) * (H-120) / 4 ))
  noanr; adb shell input tap $x $y; sleep 4; local T=$(top) GOT
  case "$T" in *MainActivity*) GOT=Main;; *WidgetHostCheck*) GOT=Host;; *) GOT="other:$T";; esac
  if [ "$GOT" = "$3" ]; then R=PASS; else R=FAIL; fi
  echo "$1 ${P[$i]} tap -> $GOT (expected $3) $R" >> "$RES"
  if [ "$GOT" != Host ]; then adb shell am force-stop $PKG; sleep 1; adb shell am start -S -W -n $PKG/com.example.WidgetHostCheck >> "$OUT/hostlaunch.txt" 2>&1; sleep 7; fi
}
phase(){ # name mask  (expected derived from mask: o->Main n->Host)
  local name=$1 mask=$2; host "$mask"; shot "host_$name"
  for i in 0 1 2 3 4 5 6 7 8 9; do c=${mask:$i:1}; [ "$c" = n ] && e=Host || e=Main; tapw "$name" $i $e; done
}
# first launch to create data dir, onboarding prefs
adb shell am start -W -n $PKG/com.example.MainActivity >/dev/null 2>&1; sleep 8
adb shell am force-stop $PKG
adb shell "printf '%s' '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?><map><boolean name=\"onboarding_done\" value=\"true\" /><boolean name=\"perm_flow_done\" value=\"true\" /><string name=\"language\">ar</string></map>' > /data/data/$PKG/shared_prefs/app_prefs.xml"
# bind all 10 through the system dialog
adb shell am start -S -W -n $PKG/com.example.WidgetHostCheck >> "$OUT/hostlaunch.txt" 2>&1; sleep 8
for n in $(seq 1 16); do noanr; dump "$OUT/bind.xml"; XY=$(tap_re "^ *Create *$" "$OUT/bind.xml"); if [ -z "$XY" ]; then [[ "$(top)" == *WidgetHostCheck* ]] && break; fi; echo "bind tap $n: $XY" >> "$RES"; [ -n "$XY" ] && adb shell input tap $XY; sleep 5; done
adb logcat -d | grep HOSTCHECK > "$OUT/hostcheck_log.txt"
echo "bound: $(grep -c 'ok=false' $OUT/hostcheck_log.txt) dialogs; ids: $(grep 'ids=' $OUT/hostcheck_log.txt | tail -1)" >> "$RES"
adb shell "date -u" > "$OUT/clock0.txt"
sized(){ tag=$1 stamp=$2 k=$3
  adb shell date -u "$stamp" >> "$OUT/clock_$tag.txt" 2>&1
  adb shell am start -S -W -n $PKG/com.example.IqamaSizedCheck --ef k $k >> "$OUT/hostlaunch.txt" 2>&1; sleep 9; noanr; sleep 2; shot "sized_${tag}_k$k"; adb logcat -d | grep IQDUMP | tail -80 > "$OUT/dump_${tag}_k$k.txt"
  adb logcat -d | grep -E "WathakkerHome|AndroidRuntime|com.example|RemoteViews|AppWidget|Wathkkir" | grep -v "Calling main|START com|boot image|lock profiling|Shutting down" | tail -40 > "$OUT/log_${tag}_k$k.txt"
}
sized normal 102408502026.00 1.0
sized iqama 102409502026.00 1.0
if [ "$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1 | cut -dx -f1)" -gt 1800 ]; then sized normal 102408502026.00 1.4; sized iqama 102409502026.00 1.4; fi
grid(){ tag=$1 stamp=$2; adb shell date -u "$stamp" >> "$OUT/clock_$tag.txt" 2>&1; adb shell am force-stop $PKG; sleep 2; adb shell am start -S -W -n $PKG/com.example.IqamaSizedCheck --ef k 1.0 >> "$OUT/hostlaunch.txt" 2>&1; sleep 8; host ""; shot "grid_$tag"; adb logcat -d | grep -E "ovFrac|size .*used=" | tail -30 > "$OUT/log_grid_$tag.txt"; }
grid normal 102408502026.00
grid iqama 102409502026.00
# scenario coverage: long remaining text, transitions into/out of the iqama window, live per-second ticking
sized longnormal 102406002026.00 1.0
sized preadhan 102409382026.00 1.0
sized iqamastart 102409412026.00 1.0
sized preend 102409582026.00 1.0
sized postend 102410012026.00 1.0
adb shell date -u "102409502026.00" >> "$OUT/clock_tick.txt" 2>&1
adb shell am start -S -W -n $PKG/com.example.IqamaSizedCheck --ef k 1.0 >> "$OUT/hostlaunch.txt" 2>&1; sleep 9; noanr; shot tick_a; sleep 3; shot tick_b
adb shell wm size > "$OUT/wm.txt"; adb shell wm density >> "$OUT/wm.txt"
