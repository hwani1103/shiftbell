import 'package:flutter/material.dart';

enum GameTextRole {
  title,
  section,
  body,
  supporting,
  button,
  unit,
  deviceLabel,
}

/// Independent host tokens mirror the established role/size hierarchy. No
/// dependency on ShiftBell's theme or providers is introduced.
@immutable
final class GameSkin {
  final Color background,
      surface,
      primary,
      onPrimary,
      text,
      secondary,
      border,
      blocked,
      goal,
      selection,
      collision,
      disabledSurface,
      disabledText;
  final Color goalStar, goalStarOutline;
  final Color portal;
  List<Color> get gateColors => this == dark
      ? const [Color(0xFFFFD34E), Color(0xFF66B3FF)]
      : const [Color(0xFFB77900), Color(0xFF006BDD)];
  final List<Color> unitColors;
  const GameSkin({
    this.portal = const Color(0xFF007E88),
    this.goalStar = const Color(0xFFFFD34E),
    this.goalStarOutline = const Color(0xFF9A6A0A),
    required this.background,
    required this.surface,
    required this.primary,
    required this.onPrimary,
    required this.text,
    required this.secondary,
    required this.border,
    required this.blocked,
    required this.goal,
    required this.selection,
    required this.collision,
    required this.disabledSurface,
    required this.disabledText,
    required this.unitColors,
  });
  static const light = GameSkin(
    background: Color(0xFFEEF6FD),
    surface: Color(0xFFFFFFFF),
    primary: Color(0xFF3D63B8),
    onPrimary: Color(0xFFFFFFFF),
    text: Color(0xFF263B54),
    secondary: Color(0xFF52677F),
    border: Color(0xFFC5D9EF),
    blocked: Color(0xFF4B6078),
    goal: Color(0xFF267450),
    selection: Color(0xFF7450AA),
    collision: Color(0xFFA93C44),
    disabledSurface: Color(0xFFE4EBF3),
    disabledText: Color(0xFF718096),
    unitColors: [
      Color(0xFF365FB0),
      Color(0xFFB3453D),
      Color(0xFF7150A8),
      Color(0xFF27725B),
      Color(0xFF88601A),
    ],
  );
  static const dark = GameSkin(
    portal: Color(0xFF76E0DF),
    background: Color(0xFF131F32),
    surface: Color(0xFF223149),
    primary: Color(0xFFBDD3FF),
    onPrimary: Color(0xFF192A45),
    text: Color(0xFFF3F6FF),
    secondary: Color(0xFFB8C7DE),
    border: Color(0xFF637894),
    blocked: Color(0xFF7C8CA3),
    goal: Color(0xFF84D6AB),
    selection: Color(0xFFD6B8FF),
    collision: Color(0xFFFFABA6),
    disabledSurface: Color(0xFF34445B),
    disabledText: Color(0xFF8E9DB4),
    unitColors: [
      Color(0xFFBDD3FF),
      Color(0xFFFFB8AE),
      Color(0xFFDBC6FF),
      Color(0xFF9CE2C2),
      Color(0xFFF0D194),
    ],
  );
  TextStyle style(GameTextRole role, {Color? color}) {
    final (size, weight, height) = switch (role) {
      GameTextRole.title => (24.0, FontWeight.w700, 1.35),
      GameTextRole.section => (16.0, FontWeight.w600, 1.4),
      GameTextRole.body => (14.0, FontWeight.w400, 1.5),
      GameTextRole.supporting => (12.0, FontWeight.w400, 1.5),
      GameTextRole.button => (15.0, FontWeight.w600, 1.35),
      GameTextRole.unit => (14.0, FontWeight.w600, 1.3),
      GameTextRole.deviceLabel => (10.0, FontWeight.w700, 1.0),
    };
    return TextStyle(
      fontFamily: 'packages/sync_path_ui/GameSans',
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: 0,
      color: color ?? text,
    );
  }

  ThemeData theme() => ThemeData(
    fontFamily: 'packages/sync_path_ui/GameSans',
    useMaterial3: true,
    brightness: this == dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: this == dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: primary,
          onPrimary: onPrimary,
          surface: surface,
          onSurface: text,
          error: collision,
        ),
    textTheme: TextTheme(
      bodyMedium: style(GameTextRole.body),
      titleLarge: style(GameTextRole.section),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, GameMetrics.controlHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: GameMetrics.controlPadding,
        ),
        textStyle: style(GameTextRole.button),
        backgroundColor: primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: disabledSurface,
        disabledForegroundColor: disabledText,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameMetrics.radius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, GameMetrics.controlHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: GameMetrics.controlPadding,
        ),
        textStyle: style(GameTextRole.button),
        foregroundColor: text,
        disabledForegroundColor: disabledText,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameMetrics.radius),
        ),
      ),
    ),
  );
}

abstract final class GameMetrics {
  static double minCellForBoard(int columns) => columns > 7 ? 38 : minCell;
  static double boardPagePadding(double width, double height, int columns) {
    final boardMinimum = columns * minCellForBoard(columns);
    final containerWidth = (height - gameChromeHeight)
        .clamp(boardMinimum + 2 * minBoardPagePadding, maxWidth)
        .clamp(0, width);
    return ((containerWidth - boardMinimum) / 2)
        .clamp(minBoardPagePadding, pagePadding)
        .toDouble();
  }

  static const playControlsHeight = 112.0,
      levelBadgeWidth = 88.0,
      levelBadgeHeight = 36.0,
      gameChromeHeight = 240.0,
      lessonIconSize = 48.0,
      unitChipPadding = 4.0,
      unitChipPreview = 32.0,
      unitChipIcon = 14.0;
  static const pagePadding = 20.0,
      minBoardPagePadding = 6.0,
      gap = 12.0,
      smallGap = 8.0,
      radius = 16.0,
      controlPadding = 16.0,
      controlHeight = 48.0,
      maxWidth = 560.0;
  static const minCell = 44.0,
      cellInset = 3.0,
      cellRadius = 8.0,
      routeWidth = 3.0,
      markerRadius = 12.0,
      coreRadius = 2.5,
      boardInset = 1.0;
  static const gateDotColumnX = .37,
      gateDotColumnHeight = .66,
      gateDotRadius = .035;
  static const transition = Duration(milliseconds: 160);
  static const heartFillTransition = Duration(seconds: 1);
}

final class GameStrings {
  final bool korean;
  const GameStrings({this.korean = true});
  String pick(String ko, String en) => korean ? ko : en;
  String get appTitle => 'Sync Paths';
  String get tagline => pick(
    '같은 칸당 속도로 함께 출발해요. 긴 길은 더 오래 걸려요.',
    'Start together at equal speed. Longer paths take longer.',
  );
  String get gateHelp => pick(
    '열쇠와 같은 색 문이 한 쌍이에요. 오른쪽 점 하나가 한 칸 이동 시간이에요.',
    'A key opens the door of the same color. Each dot on the right equals one cell of travel.',
  );
  String gateFailure(String unit, String gate) =>
      pick('닫힌 문에 닿았어요.', 'A ball reached a closed door.');
  String get chooseBall =>
      pick('아래 공 버튼을 골라 주세요', 'Choose a ball button below');
  String get testMode =>
      pick('테스트: 전체 해금 · 무한 하트', 'Testing: all levels · unlimited hearts');
  String get normalMode =>
      pick('순차 해금 · 레벨마다 하트 세 개', 'Progression · three hearts per level');
  String get heartsHelp => pick(
    '레벨마다 하트 세 개예요. 함께 출발할 때 하나를 써요. 모두 소진하면 충전이 시작돼요. 앱을 보고 있으면 1분, 다른 앱을 보거나 종료하면 1시간에 하나씩 세 개까지 채워져요.',
    'Each level has three hearts. Starting a run uses one. Recovery begins when all are spent, then continues to three: one per minute while viewing this app, or one per hour away or closed.',
  );
  String get menu => pick('게임 메뉴', 'Game menu');
  String get help => pick('도움말', 'Help');
  String get previous => pick('이전', 'Back');
  String get helpNext => pick('다음', 'Next');
  String get helpDone => pick('확인', 'Done');
  String get play => pick('플레이', 'Play');
  String get exhausted => pick(
    '횟수를 모두 썼어요. 되돌려서 수정하세요.',
    'No moves left. Undo to adjust your path.',
  );
  String collisionUnits(String ids) =>
      pick('공이 서로 부딪혔어요.', 'The balls collided.');
  String unitRemaining(String id, int n, bool done) => pick(
    '${unit(id)}, ${done ? '경로 완성' : '남은 선택 $n회'}',
    '${unit(id)}, ${done ? 'ready' : '$n moves left'}',
  );
  String gateDuration(String id, int n) =>
      pick('$id번 문: $n칸 이동 시간', 'Gate $id: $n cell-times');
  List<String> get lessonTitles => [
    pick('기본 규칙', 'Basic rules'),
    pick('돌아서 가는 방법', 'Taking a detour'),
    pick('문과 스위치', 'Doors and switches'),
    pick('포탈', 'Portals'),
  ];
  List<String> get lessons => [
    pick(
      '각 공은 벽이 없는 가로·세로 직선 위의 어느 칸이든 한 번에 갈 수 있어요. 대각선으로는 갈 수 없어요.\n\n칸을 탭하면 선택 1회를 써요. 공 옆에 표시된 남은 횟수 안에 모든 공의 길을 별까지 이으세요.\n\n아래에서 공을 고르고 밝은 칸을 탭해요. 모두 준비되면 함께 출발해요. 중간에 서로 부딪히거나 닫힌 문에 닿으면 탈락이에요. 별에서 만나는 건 괜찮아요.',
      'Each ball can move any distance along a clear horizontal or vertical line. No diagonal moves.\n\nEach endpoint tap uses one move. The number beside a ball shows moves left. Get every ball to the star within that limit.\n\nChoose a ball below and tap lit cells. All balls start together. Colliding on the way or hitting a closed door ends the run. Meeting at the star is safe.',
    ),
    pick(
      '모든 공은 함께 출발하고 같은 속도로 움직여요. 짧은 길은 빨리, 돌아가는 긴 길은 늦게 도착해요.\n\n서로 길이 겹쳐도 지나가는 시간이 다르면 괜찮아요. 남은 선택 횟수 안에서 돌아가는 길로 이동 시간을 조절해 보세요. 칸과 칸 사이에서 마주쳐도 충돌하니 주의하세요.',
      'All balls start together and move at the same speed. Short paths arrive sooner; longer detours arrive later.\n\nPaths may cross safely at different times. Use a detour within the move limit to adjust travel time. Balls can also collide between cells.',
    ),
    pick(
      '열쇠 모양 스위치를 지나면 같은 색 문이 잠깐 열려요. 오른쪽 점 하나는 공이 한 칸 가는 시간이에요. 점이 모두 흐려지면 문이 닫혀요.\n\n문이 열려 있을 때 통과해야 해요. 스위치를 다시 밟으면 시간이 갱신돼요. 스위치와 문에 같은 순간 도착해도 통과할 수 있어요.',
      'Cross a key-shaped switch to open the door of the same color briefly. Each dot on the right equals one cell of travel time. The door closes when all dots fade.\n\nCross while the door is open. Crossing the switch again refreshes the timer. Arriving at the switch and door at the same instant is allowed.',
    ),
    pick(
      'IN은 입구, OUT은 출구예요. 입구를 끝점으로 탭하면 같은 색 출구로 즉시 이동해요. 다음 길은 출구에서 이어요. 추가 횟수나 시간은 들지 않아요. 그냥 지나치면 타지 않아요. 포탈은 계속 사용할 수 있어요. 입구나 출구에서 같은 순간 만나면 충돌해요.',
      'IN marks the entrance; OUT marks the exit. End a move on IN to transfer to the same-color OUT, without extra time or moves. Continue from the exit. Passing over an entrance does not activate it. Portals are reusable. Meeting at either end at the same instant is a collision.',
    ),
  ];
  String get start => pick('시작하기', 'Start');
  String get continueGame => pick('이어하기', 'Continue');
  String get levels => pick('레벨 선택', 'Choose a level');
  String get exit => pick('나가기', 'Exit');
  String get undo => pick('되돌리기', 'Undo');
  String get clear => pick('이 길 지우기', 'Clear path');
  String get restart => pick('다시 시작', 'Restart');
  String get execute => pick('출발', 'Go');
  String get pause => pick('일시정지', 'Pause');
  String get resume => pick('이어 보기', 'Resume');
  String get nextScene => pick('다음 장면', 'Next scene');
  String get edit => pick('경로 고치기', 'Edit paths');
  String get replay => pick('다시 보기', 'Replay');
  String get next => pick('다음 판', 'Next puzzle');
  String get success => pick('모두 무사히 도착했어요', 'Everyone arrived safely');
  String get finaleSuccess => pick('마지막 레벨을 클리어했어요!', 'Final level cleared!');
  String get failure => pick('같은 순간에 만났어요', 'They met at the same moment');
  String get planning =>
      pick('선택한 길을 도착점까지 이어 주세요', 'Connect each path to the goal');
  String planningUnit(String id) =>
      pick('$id의 경로를 고르는 중', 'Planning $id\'s path');
  String legalCells(int count) => pick(
    '밝게 표시된 $count칸 중 다음 칸을 탭하세요',
    'Tap one of the $count highlighted cells',
  );
  String get chooseAnother =>
      pick('이 경로는 완성됐어요. 다른 공을 골라 주세요', 'Path ready. Choose another ball');
  String get paused => pick('재생을 멈췄어요', 'Replay paused');
  String get running => pick('함께 움직이는 중이에요', 'Moving together');
  String get invalid => pick(
    '같은 가로나 세로의 열린 칸을 골라 주세요',
    'Choose a clear cell in the same row or column',
  );
  String get budget => pick('되돌려서 길을 바꿔 주세요', 'Undo a move to change the path');
  String get saveError => pick(
    '저장하지 못했어요. 경로는 화면에 남아 있어요.',
    'Could not save. Your paths remain on screen.',
  );
  String get corruptSave => pick(
    '저장한 초안을 읽지 못했어요. 새로 시작할 수 있어요.',
    'The saved draft could not be read. You can start again.',
  );
  String get retry => pick('저장 다시 시도', 'Retry save');
  String get complete => pick('완성', 'Ready');
  String get unfinished => pick('길 고르는 중', 'Planning');
  String get locked =>
      pick('앞의 판을 먼저 완료해 주세요', 'Complete the previous puzzle first');
  String get campaignComplete => pick(
    '모든 판을 완료했어요. 다시 풀어 볼 수 있어요.',
    'All puzzles complete. You can play them again.',
  );
  String get goal => pick('도착점', 'Goal');
  String get wall => pick('막힌 칸', 'Blocked cell');
  String unit(String id) => switch (id) {
    'A' => pick('파란 원무늬 공', 'Blue dotted ball'),
    'B' => pick('빨간 줄무늬 공', 'Red striped ball'),
    'C' => pick('보라 십자무늬 공', 'Purple cross ball'),
    'D' => pick('초록 마름모무늬 공', 'Green diamond ball'),
    _ => pick('별무늬 공', 'Star ball'),
  };
  String puzzle(int number, String title) => 'LV $number';
}
