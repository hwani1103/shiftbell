// lib/widgets/word_safe_spans.dart
//
// ⭐ 2026-08-24 추가 - 한글 텍스트가 단어(공백으로 구분된 단위) 중간에서
// 줄바꿈되는 걸 막는 공통 유틸.
//
// 문제: 유니코드 줄바꿈 규칙(UAX#14)상 한글 음절은 영어 단어와 달리 공백이
// 없어도 음절과 음절 사이에서 줄바꿈이 허용됨. 그래서 Flutter의 기본 Text
// 줄바꿈이 "있습니다"처럼 공백 없는 한 단어를 "있습니\n다"로 잘라버리는 경우가
// 생김 - 좁은 화면이나 큰 글꼴 배율에서 특히 잘 보임.
//
// 해결: 공백으로 구분된 각 "단어"를 WidgetSpan(child: Text(word))로 감싸서
// RichText/Text.rich에 넣음 - WidgetSpan은 그 자체로 하나의 원자적(atomic)
// 인라인 블록이라 내부에서 절대 줄바꿈되지 않고, 줄바꿈은 반드시 WidgetSpan들
// 사이(=원래 공백이 있던 자리)에서만 일어남. 공백/개행 문자는 원래 그대로
// TextSpan으로 보존하므로 간격이나 명시적 \n 줄바꿈도 그대로 유지됨.
//
// 사용법 (두 가지):
// 1) 이 자체가 텍스트 전부라면: Text.rich(TextSpan(children: wordSafeSpans(str, style)))
// 2) 다른 TextSpan(예: 탭 가능한 링크)과 섞어 쓰려면: TextSpan(children: [
//      ...wordSafeSpans(prefix, style), linkSpan, ...wordSafeSpans(suffix, style),
//    ])

import 'package:flutter/material.dart';

/// [text]를 "단어(WidgetSpan)"와 "공백/개행(TextSpan)"이 번갈아 나오는
/// InlineSpan 목록으로 변환함. 원래 문자열의 공백/개행 위치와 개수를 그대로
/// 보존하므로, 있던 간격이 사라지거나 늘어나지 않음.
List<InlineSpan> wordSafeSpans(String text, TextStyle? style) {
  final tokens = RegExp(r'\S+|\s+').allMatches(text).map((m) => m.group(0)!);
  return [
    for (final token in tokens)
      if (token.trim().isEmpty)
        TextSpan(text: token, style: style)
      else
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Text(token, style: style),
        ),
  ];
}
