import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/time/company_clock.dart';
import '../../../core/design/formatters.dart';

class ElapsedText extends StatefulWidget {
  const ElapsedText({super.key, required this.since, this.style});
  final DateTime since;
  final TextStyle? style;

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = context.read<CompanyClock>().nowUtc().difference(widget.since);
    return Text(
      formatClockDuration(elapsed.isNegative ? Duration.zero : elapsed),
      style: (widget.style ?? Theme.of(context).textTheme.titleLarge)?.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
