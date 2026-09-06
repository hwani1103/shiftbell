// lib/widgets/evidence_library_section.dart
//
// ⭐ 2026-09-01 후속13 - 원래 condition_tab.dart 안에 있던 "근거 자료" 섹션
// (Evidence Database 전체 12개, 접이식)을 사용자 요청으로 컨디션 탭에서
// 빼서 이 파일로 분리해뒀다. **지금은 어디에도 연결(import)돼 있지 않음** -
// "도움말 쪽을 나중에 싹 다 리팩토링할 때 거기다 넣을 것"이라는 사용자
// 계획대로, 그 작업을 시작할 때 설정/도움말 화면에서 이 파일을 그대로
// import해서 쓰면 된다. 기능/문구 자체는 컨디션 탭에 있던 마지막 버전
// 그대로(URL 링크 줄은 이미 이때 삭제된 상태 - "not found" 뜬다는 지적).
//
// 클래스명 앞의 언더스코어를 뗀 것 외에는 로직 변경 없음(다른 파일에서
// import해서 쓸 수 있어야 하므로 public으로 유지).

import 'package:flutter/material.dart';
import '../services/condition/evidence_database.dart';

/// "근거 자료" - Evidence Database 전체(12개)를 보여주는 접이식 섹션.
/// 안 펼쳤을 때는 제목 줄만, 탭하면 전체 목록이 펼쳐짐.
class EvidenceLibrarySection extends StatefulWidget {
  const EvidenceLibrarySection({super.key});

  @override
  State<EvidenceLibrarySection> createState() => _EvidenceLibrarySectionState();
}

class _EvidenceLibrarySectionState extends State<EvidenceLibrarySection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.menu_book_outlined, color: Colors.black45),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('근거 자료', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final e in kEvidenceDatabase) EvidenceTile(e)],
              ),
            ),
        ],
      ),
    );
  }
}

class EvidenceTile extends StatelessWidget {
  final Evidence evidence;
  const EvidenceTile(this.evidence, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${evidence.id} · ${evidence.topic}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(evidence.source, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(evidence.finding, style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 2),
          Text('근거 수준: ${evidence.evidenceLevel}', style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
          // ⭐ URL 링크 줄 삭제(일부가 "not found"로 뜬다는 지적) - 출처(source)/
          // 제목(topic)만으로 어떤 기관·연구인지는 충분히 드러남. url 필드 자체는
          // evidence_database.dart에 원문 조사 이력으로 그대로 남아있음(화면
          // 표시만 뺌).
        ],
      ),
    );
  }
}
