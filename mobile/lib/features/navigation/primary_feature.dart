import 'package:flutter/material.dart';

enum PrimaryFeature {
  capture(
    icon: Icons.mic_none_rounded,
    selectedIcon: Icons.mic_rounded,
    label: '录音',
    navigationLabel: '录音',
  ),
  soundscape(
    icon: Icons.radar_outlined,
    selectedIcon: Icons.radar_rounded,
    label: '共听杭州',
    navigationLabel: '共听',
  ),
  parkGuide(
    icon: Icons.map_outlined,
    selectedIcon: Icons.map_rounded,
    label: '游园指南',
    navigationLabel: '游园',
  ),
  natureBook(
    icon: Icons.collections_bookmark_outlined,
    selectedIcon: Icons.collections_bookmark_rounded,
    label: '自然册',
    navigationLabel: '自然册',
  );

  const PrimaryFeature({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.navigationLabel,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String navigationLabel;
}
