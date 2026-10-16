import '../services/condition/evidence_database.dart';
import 'package:intl/intl.dart';
import '../services/condition/shift_time_category.dart';
import 'generated/app_localizations.dart';

String sleepShiftLabel(ShiftTimeCategory category, AppLocalizations copy) =>
    switch (category) {
      ShiftTimeCategory.day => copy.sleepText253,
      ShiftTimeCategory.evening => copy.sleepText254,
      ShiftTimeCategory.night => copy.sleepText255,
      ShiftTimeCategory.off => copy.sleepText256,
      ShiftTimeCategory.unspecified => copy.sleepText257,
    };
String sleepDateLabel(DateTime date, AppLocalizations copy) =>
    copy.localeName.startsWith('ko')
        ? '${date.month}/${date.day}(${[
            '월',
            '화',
            '수',
            '목',
            '금',
            '토',
            '일'
          ][date.weekday - 1]})'
        : DateFormat.MMMEd(copy.localeName).format(date);

String sleepEvidenceTopic(Evidence evidence, AppLocalizations copy) =>
    switch (evidence.id) {
      'EVIDENCE-001' => copy.sleepText186,
      'EVIDENCE-002' => copy.sleepText191,
      'EVIDENCE-003' => copy.sleepText196,
      'EVIDENCE-004' => copy.sleepText200,
      'EVIDENCE-005' => copy.sleepText204,
      'EVIDENCE-006' => copy.sleepText208,
      'EVIDENCE-007' => copy.sleepText212,
      'EVIDENCE-008' => copy.sleepText216,
      'EVIDENCE-009' => copy.sleepText220,
      'EVIDENCE-010' => copy.sleepText224,
      'EVIDENCE-011' => copy.sleepText228,
      'EVIDENCE-012' => copy.sleepText233,
      'EVIDENCE-013' => copy.sleepText237,
      'EVIDENCE-014' => copy.sleepText242,
      _ =>
        throw StateError('Untranslated sleep evidence topic: ${evidence.id}'),
    };

String sleepEvidenceSource(Evidence evidence, AppLocalizations copy) =>
    switch (evidence.id) {
      'EVIDENCE-002' => copy.sleepText190,
      'EVIDENCE-003' => copy.sleepText195,
      'EVIDENCE-011' => copy.sleepText227,
      'EVIDENCE-012' => copy.sleepText232,
      'EVIDENCE-013' => copy.sleepText236,
      'EVIDENCE-014' => copy.sleepText241,
      _ => evidence
          .source, // These sources are published English bibliographic titles.
    };
