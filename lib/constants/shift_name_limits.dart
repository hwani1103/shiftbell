// User-selected limit: 16 characters including spaces, accommodating
// Night Shift (11) and Afternoon Shift (15). Longer names need abbreviations.
// Research: docs/next_version/근무명_길이_조사_2026-10-02.txt.
// Limits follow the name's script, not the app locale. Mixed Hangul/Latin names
// use the Hangul limit. Include composing jamo as well as completed syllables.
// Input length is independent of the two fixed grid-chip geometry presets.
const int kMaxShiftNameLength = 16;
const int kMaxHangulShiftNameLength = 6;
final _hangul = RegExp(r'[\u1100-\u11FF\u3130-\u318F\uA960-\uA97F\uAC00-\uD7FF\uFFA0-\uFFDC]');
int shiftNameLengthLimit(String name) => _hangul.hasMatch(name)
    ? kMaxHangulShiftNameLength : kMaxShiftNameLength;

// Six initial names plus the seven custom names allowed during onboarding.
const int kMaxShiftTypes = 13;
const int kMaxCustomShiftTypes = 7;
