E1: The candidate changed the Void bottom line to render target/duration/percentage, but its own event trail only shows synthetic dragByKeyPause attempts and post-call screenshots; no genuine in-flight capture is traceable.

E2: Fresh held X11 swipes in both directions showed the bottom readout without a centered time readout or tall vertical marker.

E3: After releasing and waiting, the bottom line returned to the normal “~” folder-path display.

E4: The candidate did not produce two genuine in-flight captures with different legible target values; its event evidence is synthetic, including one mouse assertion failure.

E5: Starting playback at 3:00, a real leftward swipe displayed 2:03 and released to a position near that target while still advancing, confirming an actual seek.

E6: The candidate’s screenshot artifacts were captured after synthetic dragByKeyPause attempts, not during a traceable real held gesture.

E7: The fresh post-gesture screenshot showed the normal folder line with no lingering seek feedback or center indicator.

E8: The settled screenshot was independently corroborated by the verification tree and semantics, both showing the normal “~” bottom line.

E9: Real X11 taps exercised previous, pause/play, and next and the app stayed responsive, but the attempted vertical drag did not clearly demonstrate its prior browser transition, so this is partial.

E10: Several varied real X11 swipes left the app live and responsive; the final runtime verification reported zero overflow entries.

Operationally, the candidate was auto-finished by the deadline guard after 1628 seconds; I relaunched the candidate container to obtain valid live evidence before scoring.
