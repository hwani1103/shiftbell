import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftbell/utils/holiday_util.dart';
import 'package:shiftbell/utils/national_holiday.dart';
import 'package:shiftbell/generated/national_holidays.dart';

void main() {
  String? holiday(String date, String country, {String language = 'en'}) =>
      getHolidayName(DateTime.parse(date), isKorean: false,
          countryCode: country, languageCode: language);

  test('country uses actual device region without borrowing an English fallback', () {
    expect(holidayCountryForLocale(const Locale('ar', 'AE')), 'AE');
    expect(holidayCountryForLocale(const Locale('fil', 'PH')), 'PH');
    expect(holidayCountryForLocale(const Locale('en', 'IN')), 'IN');
    expect(holidayCountryForLocale(const Locale('fr', 'FR')), isNull);
    expect(holidayCountryForLocale(const Locale('de', 'AT')), isNull);
    expect(holidayCountryForLocale(const Locale('en')), isNull);
    expect(holidayCountryForLocale(const Locale('de')), 'DE');
    expect(holidayCountryForLocale(const Locale('pt')), 'BR');
    expect(holidayCountryForLocale(const Locale('hi')), 'IN');
  });

  test('national scope excludes state, regional and working observances', () {
    expect(holiday('2026-10-09', 'US'), isNull); // Korean Hangeul Day
    expect(holiday('2026-11-26', 'US'), 'Thanksgiving Day');
    expect(holiday('2026-04-03', 'GB'), 'Good Friday');
    expect(holiday('2026-04-06', 'GB'), isNull); // Not common to Scotland
    expect(holiday('2026-08-31', 'GB'), isNull);
    expect(holiday('2026-11-04', 'ZA'), 'Local Government Elections');
    expect(holiday('2026-01-26', 'IN', language: 'hi'), 'गणतंत्र दिवस');
    expect(holiday('2026-03-04', 'IN'), isNull); // Not all-state Holi scope
    expect(holiday('2026-10-03', 'DE', language: 'de'), 'Tag der Deutschen Einheit');
    expect(holiday('2026-10-31', 'DE'), isNull); // State-only Reformation Day
    expect(holiday('2026-11-20', 'BR', language: 'pt'), contains('Consciência Negra'));
    expect(holiday('2026-02-17', 'BR'), isNull); // Optional Carnival
    expect(holiday('2026-04-03', 'BR'), isNull); // Municipal religious holiday
    expect(holiday('2026-05-25', 'AE'), isNull); // Federal-government extension
    expect(holiday('2026-03-22', 'AE'), 'Eid al-Fitr');
    expect(holiday('2026-06-15', 'AE'), 'Hijri New Year');
    expect(holiday('2026-06-16', 'AE'), isNull); // Forecast differs from official
    expect(holiday('2026-08-28', 'AE'), 'Prophet Muhammad’s Birthday');
    expect(holiday('2026-02-17', 'PH'), 'Chinese New Year');
    expect(holiday('2026-02-25', 'PH'), isNull); // Special working day
    expect(holiday('2026-11-16', 'PH'), isNull); // NCR-only
    expect(holiday('2027-02-06', 'PH'), 'Chinese New Year');
  });

  test('observed days cross years without spreading substitutes to other countries', () {
    expect(holiday('2027-12-31', 'US'), 'New Year’s Day (observed)');
    expect(holiday('2028-01-01', 'US'), 'New Year’s Day');
    expect(holiday('2028-01-03', 'GB'), 'New Year’s Day (substitute day)');
    expect(holiday('2026-08-10', 'ZA'), 'National Women’s Day (observed)');
    expect(holiday('2027-12-27', 'ZA'), 'Day of Goodwill (observed)');
    expect(holiday('2028-09-25', 'ZA'), 'Heritage Day (observed)');
    expect(holiday('2026-10-05', 'DE'), isNull);
    expect(holiday('2026-11-16', 'BR'), isNull);
  });

  test('only reviewed years/dates and no guessed future lunar announcements', () {
    expect(holiday('2025-12-25', 'US'), isNull);
    expect(holiday('2029-01-01', 'US'), isNull);
    expect(holiday('2028-12-08', 'PH'), isNotNull);
    expect(holiday('2028-02-17', 'PH'), isNull);
    expect(holiday('2027-03-10', 'AE'), isNull);
    for (final country in nationalHolidayNames.values) {
      for (final entry in country.entries) {
        expect(DateTime.parse(entry.key).year, inInclusiveRange(2026, 2028));
        expect(entry.value['en'], isNotEmpty);
      }
    }
  });

  test('Korean overrides cannot leak into foreign calendars and local day is retained', () {
    final previous = HolidayOverrides.current;
    addTearDown(() => HolidayOverrides.current = previous);
    HolidayOverrides.current = const HolidayOverrides(add: {'2026-07-04': '한국 임시 휴일'},
        remove: {'2026-12-25'});
    expect(holiday('2026-07-04', 'US'), 'Independence Day');
    expect(holiday('2026-12-25', 'US'), 'Christmas Day');
    expect(getHolidayName(DateTime(2026, 7, 4), isKorean: true), '한국 임시 휴일');
    expect(getHolidayName(DateTime(2026, 12, 25), isKorean: true), isNull);
    expect(nationalHolidayName(DateTime.utc(2026, 7, 4, 23, 59), 'US'), 'Independence Day');
  });
}
