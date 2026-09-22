import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

extension Cast on Object? {
  double? asDoubleOrNull() {
    double? value;
    if (this is int) {
      final intValue = this as int;
      value = intValue.toDouble();
    } else if (this is double) {
      value = this as double;
    } else if (this is String) {
      final stringValue = this as String;
      value = double.parse(stringValue);
    } else {
      value = null;
    }

    return value;
  }
}

extension CastString on String {
  String? toStringOrNull() {
    if (isEmpty) {
      return null;
    } else {
      return this;
    }
  }

  double? toDoubleOrNull() {
    if (isEmpty) {
      return null;
    } else {
      return double.parse(this);
    }
  }
}

extension Round on double {
  double roundToPrecision(int n) {
    int fac = pow(10, n).toInt();
    return (this * fac).round() / fac;
  }
}

extension DisplayDouble on double? {
  /// The value for a text field, or "" for null. Float noise from unit
  /// conversions is trimmed (2.000000000000004 shows as "2") while tiny
  /// micronutrient amounts keep their significant digits, which rounding to
  /// fixed decimals would zero.
  String toStringOrEmpty() {
    final value = this;
    if (value == null) return "";
    final text = double.parse(value.toStringAsPrecision(12)).toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}

extension FormatString on DateTime {
  String toParsedDay() => DateFormat('yyyy-MM-dd').format(this);
}

extension ColorExtension on Color {
  /// Converts the color to a hexadecimal string.
  String toHex() {
    final red = (r * 255).toInt().toRadixString(16).padLeft(2, '0');
    final green = (g * 255).toInt().toRadixString(16).padLeft(2, '0');
    final blue = (b * 255).toInt().toRadixString(16).padLeft(2, '0');

    return '#'
            '$red$green$blue'
        .toUpperCase();
  }
}
