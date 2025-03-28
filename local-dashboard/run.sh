#!/usr/bin/with-contenv bashio

################################################################################
#Get config variables
START_URL=$(bashio::config 'start_url' || echo "http://localhost:8123")
LOGIN_DELAY=$(bashio::config 'login_delay' || echo "2")
HA_USERNAME=$(bashio::config 'ha_username' || echo "")
HA_PASSWORD=$(bashio::config 'ha_password' || echo "")
BROWSER_REFRESH=$(bashio::config 'browser_refresh' || echo "30") #Default to 30 seconds
export START_URL LOGIN_DELAY HA_USERNAME HA_PASSWORD BROWSER_REFRESH #Referenced in 'userconfig.lua'

HDMI_PORT=$(bashio::config 'hdmi_port' || echo "0")
#NOTE: For now, both HDMI ports are mirrored and there is only /dev/fb0
#      Not sure how to get them unmirrored so that console can be on /dev/fb0 and X on /dev/fb1
#      As a result, setting HDMI=0 vs. 1 has no effect
SCREEN_TIMEOUT=$(bashio::config 'screen_timeout' || echo "600") #Default to 600 seconds


#Validate environment variables set by config.yaml
if [ -z "$HA_USERNAME" ] || [ -z "$HA_PASSWORD" ]; then
    echo "Error: HA_USERNAME and HA_PASSWORD must be set" >&2
    exit 1
fi

################################################################################
#Note need to delete /dev/tty0 since X won't start if it is there
#because X doesn't have permissions to access it in the container
#First, remount /dev as read-write since X absolutely, must have /dev/tty access
#Note: need to use the version in util-linux, not busybox
if [ -e "/dev/tty0" ]; then
    echo "Attempting to (temporarily) delete /dev/tty0..." >&2
    mount -o remount,rw /dev
    if [ $? -ne 0 ]; then
        echo "Failed to remount /dev as read-write..." >&2
        exit 1
    fi
    rm /dev/tty0
    if [ $? -ne 0 ]; then
        mount -o remount,ro /dev
        echo "Failed to delete /dev/tty0..." >&2
        exit 1
    fi
    TTY0_DELETED=1
fi

#Start Xorg in the background
Xorg $DISPLAY -layout Layout${HDMI_PORT} & < /dev/null

XSTARTUP=30
for ((i=0; i<=$XSTARTUP; i++)); do
  if xset q >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

#Restore /dev/tty0 and 'ro' mode for /dev if deleted
if [ -n "TTY0_DELETED" ]; then
    if ! ( mknod -m 620 /dev/tty0 c 4 0 &&  mount -o remount,ro /dev ); then
        echo "Failed to restore /dev/tty0 and remount /dev/ read only..." >&2
    fi
fi

if ! xset q >/dev/null 2>&1; then
  echo "Error: X server failed to start within $XSTARTUP seconds." >&2
  exit 1
fi
echo "X started successfully..." >&2

#Stop console blinking cursor (this projects through the X-screen)
echo -e "\033[?25l" > /dev/console

#Start Openbox in the background
openbox &
O_PID=$!
sleep 0.5  #Ensure Openbox starts
if ! kill -0 "$O_PID" 2>/dev/null; then #Checks if process alive
    echo "Failed to start Openbox window manager" >&2
    exit 1
fi
echo "Openbox started successfully..." >&2

#Start D-Bus session (otherwise luakit hangs for 5 minutes befor starting)
dbus-daemon --session --address=unix:path=/tmp/dbus-session &
sleep 0.5  #Allow DBUS to initialize
export DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/dbus-session
echo "DBUS started..." >&2

#Configure screen timeout
if [ "$SCREEN_TIMEOUT" -eq 0 ]; then #Disable screen saver and DPMS for no timeout
    xset s 0
    xset dpms 0 0 0
    xset -dpms
    echo "Screen timeout disabled..." >&2
else
    xset s "$SCREEN_TIMEOUT"
    xset dpms "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT" "$SCREEN_TIMEOUT"  #DPMS standby, suspend, off
    xset +dpms
    echo "Screen timeout after $SCREEN_TIMEOUT seconds..." >&2
fi

#Run Luakit in the foreground
echo "Launching Luakit browser..." >&2
exec luakit "$START_URL"
