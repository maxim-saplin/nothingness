void main() {
  print("Simulating Scale Calculation...");
  print("Target Width: 600.0");

  final scenarios = [
    // format: name, physicalWidth, physicalHeight, dpr
    ("LowDPI Tablet (160dpi)", 1920.0, 1080.0, 1.0),
    ("Normal Tablet (320dpi)", 1920.0, 1080.0, 2.0),
    ("High Res Tablet (320dpi)", 2560.0, 1600.0, 2.0),
    ("Small Tablet (320dpi)", 1280.0, 800.0, 2.0),
    ("Zeekr Ultrawide", 1920.0, 720.0, 1.0), 
    ("Zeekr Ultrawide HiDPI", 1920.0, 720.0, 1.5),
    ("Phone (Portrait)", 1080.0, 2400.0, 2.75), 
    ("Phone (Landscape)", 2400.0, 1080.0, 2.75),
  ];

  print(
      "Name | Phys WxH | DPR | Log WxH | Calc Scale | Effective WxH | Phys Px/DP");

  for (var s in scenarios) {
    final name = s.$1;
    final physW = s.$2;
    final physH = s.$3;
    final dpr = s.$4;

    final logW = physW / dpr;
    final logH = physH / dpr;

    // Current Algorithm
    double scale = logW / 600.0;
    scale = scale.clamp(1.0, 3.0);

    final effectiveW = logW / scale;
    final effectiveH = logH / scale;
    final physPxPerDp = scale * dpr;

    print(
        "$name | ${physW.toInt()}x${physH.toInt()} | $dpr | ${logW.toInt()}x${logH.toInt()} | ${scale.toStringAsFixed(2)} | ${effectiveW.toInt()}x${effectiveH.toInt()} | ${physPxPerDp.toStringAsFixed(2)}");
  }
}

