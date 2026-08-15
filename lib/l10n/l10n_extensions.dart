// lib/l10n/l10n_extensions.dart
//
// ⭐ `AppLocalizations.of(context)!.someKey`가 매 호출부마다 반복되는 걸 줄이기
// 위한 짧은 확장(extension). 모든 화면/위젯에서 `context.l10n.someKey` 형태로
// 통일해서 씀. AppLocalizations 자체는 l10n.yaml 설정에 따라 lib/l10n/app_ko.arb
// (원본) + app_en.arb(번역)에서 `flutter gen-l10n`이 자동 생성함
// (lib/l10n/generated/app_localizations.dart - 직접 수정 금지, arb 파일을 고칠 것).
import 'package:flutter/widgets.dart';
import 'generated/app_localizations.dart';

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}
