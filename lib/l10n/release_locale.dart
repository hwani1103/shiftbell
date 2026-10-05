import 'package:flutter/widgets.dart';

/// Release languages and regional Material date/time picker defaults.
/// Portuguese copy is Brazilian. Public holidays remain Korean-only.
Locale resolveReleaseLocale(List<Locale>? locales, Iterable<Locale> supported) {
  final device = locales?.firstOrNull ?? const Locale('en', 'US');
  if (device.languageCode == 'ko') return const Locale('ko');
  if (device.languageCode == 'de') return const Locale('de', 'DE');
  if (device.languageCode == 'pt') return const Locale('pt', 'BR');
  if (device.languageCode == 'hi') return const Locale('hi', 'IN');
  const mondayRegions = {
    'GB',
    'IE',
    'AU',
    'NZ',
    'AT',
    'BE',
    'BG',
    'CH',
    'CY',
    'CZ',
    'DE',
    'DK',
    'EE',
    'ES',
    'FI',
    'FR',
    'GR',
    'HR',
    'HU',
    'IS',
    'IT',
    'LI',
    'LT',
    'LU',
    'LV',
    'MC',
    'NL',
    'NO',
    'PL',
    'RO',
    'RS',
    'SE',
    'SI',
    'SK',
  };
  return mondayRegions.contains(device.countryCode)
      ? const Locale('en', 'GB')
      : const Locale('en', 'US');
}
