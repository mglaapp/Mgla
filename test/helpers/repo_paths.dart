import 'dart:io';

import 'package:path/path.dart' as p;

/// Путь внутри репозитория — ВСЕГДА через прямой слэш.
///
/// ЗАЧЕМ ЭТО ОТДЕЛЬНЫМ ФАЙЛОМ. Сторожа сравнивают пути с записанными от руки списками
/// (`lib/common/launch.dart`, `/generated/`, `lib/l10n/intl/`), а Windows отдаёт
/// `lib\common\launch.dart`. Сравнение молча не совпадает, и дальше — по-разному: у одного
/// сторожа набор файлов пустеет и он зеленеет, не проверив ничего; у другого перестаёт
/// работать исключение и он краснеет на исправном коде.
///
/// Один такой сторож починили 13-09 — и ТОЛЬКО ЕГО, хотя в правилах записано, что грабля из
/// одного инструмента чинится во всех. Остальные пять с тех пор были красными на ноутбуке и
/// зелёными в конвейере, то есть красными ровно там, где их читают перед отправкой. Набор, в
/// котором «всегда пара красных», не отличается от молчащего: следующая настоящая поломка
/// приезжает шестой строкой в списке, который никто не дочитывает.
///
/// Поэтому нормализация живёт ЗДЕСЬ, а не копией в каждом стороже: следующий сторож получит
/// её, не зная о проблеме.
String repoPath(String path) => path.replaceAll(r'\', '/');

/// Путь от корня репозитория, через прямой слэш. Замена `p.relative`, которая на Windows
/// возвращает обратные слэши и рвёт сравнение со списками.
String relativeRepoPath(String path) => repoPath(p.relative(path));

/// Сгенерированный ли это файл. Один ответ на всех: списки расходились по стороже.
bool isGeneratedPath(String path) {
  final normalized = repoPath(path);
  return normalized.endsWith('.g.dart') ||
      normalized.endsWith('.freezed.dart') ||
      normalized.contains('/generated/');
}

/// Все `.dart` под [root], путями через прямой слэш.
///
/// `File(repoPath(...))` вместо исходного объекта намеренно: иначе `file.path` у вызывающего
/// снова окажется с обратными слэшами, и нормализация кончится на пороге.
Iterable<File> dartFilesIn(String root, {bool includeGenerated = true}) sync* {
  final directory = Directory(root);
  if (!directory.existsSync()) {
    throw StateError('$root no longer exists; update the test that lists it.');
  }
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File) continue;
    final path = repoPath(entity.path);
    if (!path.endsWith('.dart')) continue;
    if (!includeGenerated && isGeneratedPath(path)) continue;
    yield File(path);
  }
}
