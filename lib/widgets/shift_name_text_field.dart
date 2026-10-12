import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/shift_name_limits.dart';

/// Evaluate the incoming text, allowing replacement of a Korean name with a
/// longer English name. Defer truncation until the IME finishes composition.
class ShiftNameLengthFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      LengthLimitingTextInputFormatter(shiftNameLengthLimit(newValue.text),
          maxLengthEnforcement: MaxLengthEnforcement.truncateAfterCompositionEnds)
          .formatEditUpdate(oldValue, newValue);
}

class ShiftNameTextField extends StatelessWidget {
  const ShiftNameTextField({super.key, required this.controller,
    required this.decoration, this.autofocus = false});
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => TextField(
      controller: controller,
      autofocus: autofocus,
      maxLength: shiftNameLengthLimit(value.text),
      // Only our incoming-value formatter enforces the limit. The dynamic
      // maxLength supplies the counter without applying the previous limit.
      maxLengthEnforcement: MaxLengthEnforcement.none,
      inputFormatters: [ShiftNameLengthFormatter()],
      decoration: decoration,
    ),
  );
}
