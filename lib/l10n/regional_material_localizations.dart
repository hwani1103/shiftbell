import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Targeted regional gaps in the pinned Flutter/intl data. Put this before the
/// global delegate; all other locales continue to use Flutter's translations.
const releaseRegionalMaterialDelegate = _RegionalMaterialDelegate();

class _RegionalMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _RegionalMaterialDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'en' &&
      (locale.countryCode == 'AE' || locale.countryCode == 'ZA');

  @override
  Future<MaterialLocalizations> load(Locale locale) async {
    // Use the public loader to initialize Intl data before building formatters.
    await GlobalMaterialLocalizations.delegate.load(locale);
    final uae = locale.countryCode == 'AE';
    // intl 0.20.2 has no en_AE data. CLDR English UAE uses M/d/y and a 12h clock;
    // retain English defaults, overriding only the Monday-first calendar.
    final name = uae ? 'en_US' : 'en_ZA';
    final create = uae ? _EnglishUae.new : _EnglishSouthAfrica.new;
    return create(
      fullYearFormat: intl.DateFormat.y(name),
      compactDateFormat: intl.DateFormat.yMd(name),
      shortDateFormat: intl.DateFormat.yMMMd(name),
      mediumDateFormat: intl.DateFormat.MMMEd(name),
      longDateFormat: intl.DateFormat.yMMMMEEEEd(name),
      yearMonthFormat: intl.DateFormat.yMMMM(name),
      shortMonthDayFormat: intl.DateFormat.MMMd(name),
      decimalFormat: intl.NumberFormat.decimalPattern(name),
      twoDigitZeroPaddedFormat: intl.NumberFormat('00', name),
    );
  }

  @override
  bool shouldReload(_RegionalMaterialDelegate old) => false;
}

class _EnglishUae extends MaterialLocalizationEn {
  const _EnglishUae({
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  }) : super(localeName: 'en_AE');

  @override
  int get firstDayOfWeekIndex => 1;
}

class _EnglishSouthAfrica extends MaterialLocalizationEnZa {
  const _EnglishSouthAfrica({
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  // Flutter's generated hint says dd/mm/yyyy, but the en_ZA formatter/parser
  // supplied by intl uses y/MM/dd. Keep the hint consistent with actual input.
  @override
  String get dateHelpText => 'yyyy/mm/dd';
}
