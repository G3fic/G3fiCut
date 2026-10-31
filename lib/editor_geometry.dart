/// Aspect ratios used by the preview frame and the exported video.
const Map<String, double> previewAspectRatios = <String, double>{
  '16:9': 16 / 9,
  '9:16': 9 / 16,
  '1:1': 1,
  '4:3': 4 / 3,
  '4:5': 4 / 5,
  '3:2': 3 / 2,
};

double aspectRatioForPreset(String preset) =>
    previewAspectRatios[preset] ?? previewAspectRatios['16:9']!;
