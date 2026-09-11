import 'package:flutter/widgets.dart';

final class AccessibleChart extends StatelessWidget {
  const AccessibleChart({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    image: true,
    label: label,
    child: ExcludeSemantics(child: child),
  );
}
