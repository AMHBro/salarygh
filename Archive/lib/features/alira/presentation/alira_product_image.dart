import 'dart:convert';

import 'package:flutter/material.dart';

Widget aliraProductImage(
  String? imageUrl, {
  required Widget fallback,
}) {
  final value = imageUrl?.trim() ?? '';
  if (value.isEmpty) return fallback;
  if (value.startsWith('data:')) {
    final comma = value.indexOf(',');
    if (comma < 0) return fallback;
    try {
      final bytes = base64Decode(
        value.substring(comma + 1).replaceAll(RegExp(r'\s'), ''),
      );
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } catch (_) {
      return fallback;
    }
  }
  return Image.network(
    value,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => fallback,
  );
}
