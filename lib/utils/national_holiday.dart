import 'package:flutter/widgets.dart';
import '../generated/national_holidays.dart';

/// Country comes from the device region, not the translated UI fallback.
/// With no region, only the release language's unambiguous default is used.
String? holidayCountryForLocale(Locale locale) {
  final region = locale.countryCode?.toUpperCase();
  if (region != null && region.isNotEmpty) {
    return nationalHolidayNames.containsKey(region) ? region : null;
  }
  return switch (locale.languageCode) {
    'de' => 'DE',
    'pt' => 'BR',
    'hi' => 'IN',
    _ => null,
  };
}

String? deviceHolidayCountry() =>
    holidayCountryForLocale(WidgetsBinding.instance.platformDispatcher.locale);

/// Date-only lookup: never shift a displayed calendar day through UTC/DST.
/// No Korean remote overrides or network dependency in this dataset.
String? nationalHolidayName(DateTime date, String? country,
    {String languageCode = 'en'}) {
  if (date.year < 2026 || date.year > 2028) return null;
  final key = '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  final names = nationalHolidayNames[country]?[key];
  return names?[languageCode] ?? names?['en'];
}
