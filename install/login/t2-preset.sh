#!/bin/bash

# Delete /etc/mkinitcpio.d/linux.preset if it exists
if [ -e "/etc/mkinitcpio.d/linux.preset" ]; then
  sudo rm "/etc/mkinitcpio.d/linux.preset"
fi