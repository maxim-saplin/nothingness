E1: Cleared preferences and restarted; the live Dot screenshot showed the pulsing dot alone, confirming the fresh default is off.
E2: The setting was on after restart, but with long metadata playing the hero still showed no overlay because the candidate's new LayoutBuilder produced an Infinity-height/NEEDS-LAYOUT subtree.
E3: Toggled the setting off and restarted; the Dot remained free of song-info text.
E4: At 100% with artist and title each over 60 characters, the genuine screenshot showed no rendered overlay; the tree exposed SizedBox(height: Infinity) and NEEDS-LAYOUT.
E5: At 150% with the same long track, the genuine screenshot again showed no overlay; the max tree contained 45px/22.5px text under the same invalid layout.
E6: Captured a fresh 100% long-metadata screenshot, but the candidate provided no submitted screenshot and the fresh state had no overlay to support the requested claim.
E7: Captured a fresh 150% long-metadata screenshot, but the candidate provided no submitted screenshot and the fresh state had no overlay to support the requested claim.
E8: Both normal and max trees contained non-empty hero text nodes, but they were NEEDS-LAYOUT, so non-zero rendered geometry was not established.
E9: Short fixture playback stayed responsive at normal and max scales, yet song-info text was absent in both captures, so ordinary metadata was not cleanly rendered.
E10: Final runtime inspection and overflow read showed the app live, playing, and reporting zero overflows after the exercise.
