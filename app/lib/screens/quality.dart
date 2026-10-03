import 'package:flutter/material.dart';
import 'package:go_core/go_core.dart';

Color qualityColor(MoveQuality q) => switch (q) {
      MoveQuality.tesuji => const Color(0xFF00BCD4),
      MoveQuality.great => const Color(0xFF5C6BC0),
      MoveQuality.good => const Color(0xFF66BB6A),
      MoveQuality.poor => const Color(0xFFFDD835),
      MoveQuality.mistake => const Color(0xFFFB8C00),
      MoveQuality.blunder => const Color(0xFFE53935),
    };

IconData qualityIcon(MoveQuality q) => switch (q) {
      MoveQuality.tesuji => Icons.auto_awesome,
      MoveQuality.great => Icons.star,
      MoveQuality.good => Icons.check_circle,
      MoveQuality.poor => Icons.help,
      MoveQuality.mistake => Icons.error,
      MoveQuality.blunder => Icons.cancel,
    };

/// Colour for a candidate move that loses [loss] points against the best.
Color lossColor(double loss) {
  if (loss <= 0.5) return const Color(0xFF4FC3F7);
  if (loss <= 1) return const Color(0xFF81C784);
  if (loss <= 3) return const Color(0xFFFFF176);
  if (loss <= 8) return const Color(0xFFFFB74D);
  return const Color(0xFFE57373);
}

String signed(double v) => '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}';

String leadText(double blackLead) {
  if (blackLead.abs() < 0.05) return 'Even';
  return '${blackLead > 0 ? 'B' : 'W'}+${blackLead.abs().toStringAsFixed(1)}';
}
