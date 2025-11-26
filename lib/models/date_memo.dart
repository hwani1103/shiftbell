// models/date_memo.dart

class DateMemo {
  final int? id;
  final String date;  // 'YYYY-MM-DD'
  final String memoText;
  final int orderIndex;  // 0, 1, 2
  final String createdAt;

  DateMemo({
    this.id,
    required this.date,
    required this.memoText,
    required this.orderIndex,
    required this.createdAt,
  });

  factory DateMemo.fromMap(Map<String, dynamic> map) {
    return DateMemo(
      id: map['id'],
      date: map['date'],
      memoText: map['memo_text'],
      orderIndex: map['order_index'],
      createdAt: map['created_at'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date,
      'memo_text': memoText,
      'order_index': orderIndex,
      'created_at': createdAt,
    };
  }
}
