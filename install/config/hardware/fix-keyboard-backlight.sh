#!/bin/bash

# Set the keyboard backlight to maximum brightness on startup for MacBooks T2
if command -v brightnessctl >/dev/null 2>&1; then
  sudo brightnessctl --device ":white:kbd_backlight" set 100%
else
  cat "/sys/class/leds/:white:kbd_backlight/max_brightness" | sudo tee "/sys/class/leds/:white:kbd_backlight/brightness"
fi
