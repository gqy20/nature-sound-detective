import 'package:flutter/material.dart';

class CapturePage extends StatelessWidget {
  const CapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自然声探员')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '把耳朵借给大自然',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              Text(
                '录下杭州身边的声音，寻找鸟、青蛙和昆虫的线索。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('record-button'),
                onPressed: null,
                icon: const Icon(Icons.mic_rounded),
                label: const Text('录音能力即将接入'),
              ),
              const SizedBox(height: 12),
              const Text(
                '当前已完成跨平台工程骨架；下一步接入 Android 本地录音。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
