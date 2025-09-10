#!/bin/bash

# Ensure that F-keys on Apple-like keyboards (such as Lofree Flow84) are always F-keys
if [[ command brightnessctl ]]; then
  sudo brightnessctl --device ":white:kbd_backlight" set 100%
else
  cat "/sys/class/leds/:white:kbd_backlight/max_brightness" | sudo tee "/sys/class/leds/:white:kbd_backlight/brightness"
fi
