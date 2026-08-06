// lib/widgets/tappable_number_picker.dart
//
// ⭐ 앱 전역에서 쓰는 탭 가능한 NumberPicker (스와이프 + 즉시 탭 지원).
// 원래 settings_tab.dart의 알람 시간 설정 UI에서만 쓰던 private 위젯이었는데,
// 근로시간 설정 화면에서도 동일한 조작감이 필요해서 공용 위젯으로 분리함.
// (기존 alarm 화면: 위/아래로 스와이프도 되고, 보이는 숫자를 직접 탭하면 그
// 숫자로 즉시 점프함 - `numberpicker` 패키지 기본 동작은 탭에 반응하지 않고
// 스크롤/드래그로만 값이 바뀌어서 이질감이 있었음.)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class TappableNumberPicker extends StatefulWidget {
  final int value;
  final int minValue;
  final int maxValue;
  final ValueChanged<int> onChanged;
  final bool infiniteLoop;
  final bool zeroPad;
  final int step;  // ⭐ 값 간격 (예: 30분 단위면 30)
  final Axis axis;  // ⭐ 가로/세로 방향 (가로는 내부적으로 회전 트릭 사용)
  final double itemHeight;
  final double itemWidth;
  final TextStyle? textStyle;
  final TextStyle? selectedTextStyle;
  final BoxDecoration? decoration;

  const TappableNumberPicker({
    super.key,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
    this.infiniteLoop = false,
    this.zeroPad = false,
    this.step = 1,
    this.axis = Axis.vertical,
    this.itemHeight = 50.0,
    this.itemWidth = 60.0,
    this.textStyle,
    this.selectedTextStyle,
    this.decoration,
  });

  @override
  State<TappableNumberPicker> createState() => _TappableNumberPickerState();
}

class _TappableNumberPickerState extends State<TappableNumberPicker> {
  late FixedExtentScrollController _controller;
  static const int _infiniteOffset = 5000;

  @override
  void initState() {
    super.initState();
    final initialIndex = (widget.value - widget.minValue) ~/ widget.step;
    _controller = FixedExtentScrollController(
      initialItem: widget.infiniteLoop ? initialIndex + _infiniteOffset * _itemCount : initialIndex,
    );
  }

  @override
  void didUpdateWidget(TappableNumberPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final currentIndex = _controller.selectedItem;
      final currentValue = _indexToValue(currentIndex);
      if (currentValue != widget.value) {
        final targetIndex = _valueToIndex(widget.value);
        _controller.jumpToItem(targetIndex);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _itemCount => (widget.maxValue - widget.minValue) ~/ widget.step + 1;

  int _indexToValue(int index) {
    if (widget.infiniteLoop) {
      final normalizedIndex = index % _itemCount;
      return widget.minValue + normalizedIndex * widget.step;
    }
    return widget.minValue + index * widget.step;
  }

  int _valueToIndex(int value) {
    final baseIndex = (value - widget.minValue) ~/ widget.step;
    if (widget.infiniteLoop) {
      final currentIndex = _controller.selectedItem;
      final currentCycle = currentIndex ~/ _itemCount;
      return baseIndex + currentCycle * _itemCount;
    }
    return baseIndex;
  }

  void _handleTap(int targetValue) {
    final targetIndex = _valueToIndex(targetValue);
    _controller.jumpToItem(targetIndex);  // ⭐ 즉시 점프 (애니메이션 없음)
    HapticFeedback.selectionClick();
    widget.onChanged(targetValue);
  }

  String _formatNumber(int value) {
    return widget.zeroPad ? value.toString().padLeft(2, '0') : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.axis == Axis.horizontal;

    // ⭐ 가로 방향은 ListWheelScrollView(세로 전용)를 90도 회전시켜 흉내냄 -
    // numberpicker 패키지가 쓰는 것과 동일한 트릭. 안의 아이템들은 반대로
    // 90도 되돌려 회전시켜 글씨가 눕지 않게 함.
    Widget wheel = ListWheelScrollView.useDelegate(
      controller: _controller,
      itemExtent: widget.itemHeight,
      physics: const FixedExtentScrollPhysics(),
      diameterRatio: 1.2,
      perspective: 0.003,
      squeeze: 1.0,
      onSelectedItemChanged: (index) {
        final value = _indexToValue(index);
        HapticFeedback.selectionClick();
        widget.onChanged(value);
      },
      childDelegate: ListWheelChildBuilderDelegate(
        builder: (context, index) {
          if (!widget.infiniteLoop && (index < 0 || index >= _itemCount)) {
            return null;
          }

          final value = _indexToValue(index);
          final isSelected = value == widget.value;

          final text = Text(
            _formatNumber(value),
            style: isSelected
                ? (widget.selectedTextStyle ?? TextStyle(fontSize: 24.sp, fontWeight: FontWeight.bold))
                : (widget.textStyle ?? TextStyle(fontSize: 16.sp, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          );

          return GestureDetector(
            onTap: () => _handleTap(value),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: isHorizontal ? RotatedBox(quarterTurns: 1, child: text) : text,
            ),
          );
        },
        childCount: widget.infiniteLoop ? null : _itemCount,
      ),
    );

    if (isHorizontal) {
      wheel = RotatedBox(quarterTurns: -1, child: wheel);
    }

    return Container(
      height: isHorizontal ? widget.itemWidth : widget.itemHeight * 3,
      width: isHorizontal ? widget.itemHeight * 3 : widget.itemWidth,
      decoration: widget.decoration,
      child: wheel,
    );
  }
}
