E1: I cleared preferences and observed the disabled playing state with no overlay, but could not complete a genuine fresh-app restart because the candidate launch had no Flutter input FIFO.
E2: I reproduced enabled long metadata rendering live, but could not verify persistence through a restart for the same launch limitation.
E3: I reproduced the disabled live state with a playing track and no overlay, but could not verify the required post-restart round trip.
E4: I staged artist and title values over 60 characters and inspected a fresh 100% screenshot; both lines were legibly ellipsized within the hero above the dot.
E5: I inspected the corresponding 150% screenshot; the long overlay remained contained and separated from the dot.
E6: The candidate's normal screenshot sequence played the short supplied fixture, so its submitted screenshot was not the required long-metadata evidence; my own normal reproduction passed.
E7: The candidate's max screenshot sequence likewise used the short supplied fixture, so it was not the required long-metadata evidence; my own max reproduction passed.
E8: Tree captures at normal and maximum scale show non-empty hero artist/title Text widgets, including 30px artist text at maximum scale.
E9: I played the supplied short fixture and captured normal and maximum states; both were visually clean without collision or clipping.
E10: After repeated setting and track changes, the final runtime capture was live with playback active and zero overflow reports.
