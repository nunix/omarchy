#!/bin/bash

# Set the keyboard backlight to maximum brightness on startup for MacBooks T2
if [ -e "/sys/class/leds/:white:kbd_backlight/max_brightness" ]; then
  cat "/sys/class/leds/:white:kbd_backlight/max_brightness" | sudo tee "/sys/class/leds/:white:kbd_backlight/brightness"
fi