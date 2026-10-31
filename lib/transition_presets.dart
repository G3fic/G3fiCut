/// FFmpeg xfade presets used by the timeline transition library.
///
/// Every entry maps to a transition name supported by FFmpeg's xfade filter.
const Map<String, String> transitionFilterNames = <String, String>{
  'Затемнение': 'fadeblack',
  'Белая вспышка': 'fadewhite',
  'Растворение': 'dissolve',
  'Смахивание влево': 'wipeleft',
  'Смахивание вправо': 'wiperight',
  'Смахивание вверх': 'wipeup',
  'Смахивание вниз': 'wipedown',
  'Скольжение влево': 'slideleft',
  'Скольжение вправо': 'slideright',
  'Круговое открытие': 'circlecrop',
  'Пикселизация': 'pixelize',
  'Приближение': 'zoomin',
  'Покрытие слева': 'coverleft',
  'Открытие справа': 'revealright',
};

String transitionFilterName(String type) =>
    transitionFilterNames[type] ?? 'fade';
