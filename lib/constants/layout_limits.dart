// lib/constants/layout_limits.dart
//
// 앱 전체 레이아웃 한계값. main.dart가 모든 화면을 이 폭 이하로 제한하고(Fold 펼침 등 넓은 화면은 가운데 정렬),
// 광고 크기 요청(ad_service.dart)도 같은 값을 써야 슬롯 폭과 요청 폭이 어긋나지 않음(출시 적합성 재검토 AUD-07).

/// 6.5인치 기준 최대 콘텐츠 너비(dp)
const double kAppMaxContentWidth = 500.0;
