import 'package:flutter/widgets.dart';

/// Text remains Korean/English; regional English also drives Material date/time
/// pickers. Never infer a public-holiday jurisdiction from a language.
Locale resolveReleaseLocale(List<Locale>? locales, Iterable<Locale> supported) {
  final device = locales?.firstOrNull ?? const Locale('en', 'US');
  if (device.languageCode == 'ko') return const Locale('ko');
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
