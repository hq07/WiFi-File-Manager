// android/lib/services/layout_prefs.dart
import 'package:shared_preferences/shared_preferences.dart';

enum LayoutMode { list, grid }
enum SortField { name, size, date }

class LayoutPrefs {
  static const _keyLayoutMode = 'layout_mode';
  static const _keyShowThumbnails = 'show_thumbnails';
  static const _keyGridColumns = 'grid_columns';
  static const _keyShowSize = 'show_size';
  static const _keyShowDate = 'show_date';
  static const _keyShowExtension = 'show_extension';
  static const _keyShowDuration = 'show_duration';
  static const _keyShowResolution = 'show_resolution';
  static const _keySortField = 'sort_field';
  static const _keySortAscending = 'sort_ascending';

  late final SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  LayoutMode get layoutMode =>
      _prefs.getString(_keyLayoutMode) == 'grid' ? LayoutMode.grid : LayoutMode.list;

  set layoutMode(LayoutMode v) =>
      _prefs.setString(_keyLayoutMode, v == LayoutMode.grid ? 'grid' : 'list');

  bool get showThumbnails => _prefs.getBool(_keyShowThumbnails) ?? true;
  set showThumbnails(bool v) => _prefs.setBool(_keyShowThumbnails, v);

  int get gridColumns => _prefs.getInt(_keyGridColumns) ?? 3;
  set gridColumns(int v) => _prefs.setInt(_keyGridColumns, v);

  bool get showSize => _prefs.getBool(_keyShowSize) ?? true;
  set showSize(bool v) => _prefs.setBool(_keyShowSize, v);

  bool get showDate => _prefs.getBool(_keyShowDate) ?? true;
  set showDate(bool v) => _prefs.setBool(_keyShowDate, v);

  bool get showExtension => _prefs.getBool(_keyShowExtension) ?? false;
  set showExtension(bool v) => _prefs.setBool(_keyShowExtension, v);

  bool get showDuration => _prefs.getBool(_keyShowDuration) ?? true;
  set showDuration(bool v) => _prefs.setBool(_keyShowDuration, v);

  bool get showResolution => _prefs.getBool(_keyShowResolution) ?? true;
  set showResolution(bool v) => _prefs.setBool(_keyShowResolution, v);

  SortField get sortField {
    final v = _prefs.getString(_keySortField);
    return SortField.values.asNameMap()[v] ?? SortField.name;
  }
  set sortField(SortField v) => _prefs.setString(_keySortField, v.name);

  bool get sortAscending => _prefs.getBool(_keySortAscending) ?? true;
  set sortAscending(bool v) => _prefs.setBool(_keySortAscending, v);
}
