import 'package:flutter/material.dart';

enum PrimaryFeature {
  capture(Icons.mic_none_rounded, '录音'),
  soundscape(Icons.radar_rounded, '共听杭州'),
  parkGuide(Icons.map_outlined, '游园指南'),
  natureBook(Icons.collections_bookmark_outlined, '自然册');

  const PrimaryFeature(this.icon, this.label);

  final IconData icon;
  final String label;
}
