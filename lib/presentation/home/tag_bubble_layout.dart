import 'dart:math' as math;
import 'dart:ui';

final class TagBubblePlacement {
  const TagBubblePlacement({
    required this.center,
    required this.radius,
    required this.hitRadius,
  });

  final Offset center;
  final double radius;
  final double hitRadius;
}

/// Packs visual circles and their circular touch targets on the same scale.
/// Only touch targets have a minimum radius; visual area always represents value.
final class TagBubbleLayout {
  const TagBubbleLayout._(this.size, this.bubbles);

  final Size size;
  final List<TagBubblePlacement> bubbles;

  static TagBubbleLayout pack(List<int> amounts, {required double width}) {
    if (!width.isFinite ||
        width < 0 ||
        amounts.length > 6 ||
        amounts.any((amount) => amount <= 0)) {
      throw ArgumentError(
        'Expected up to six positive amounts and a finite width.',
      );
    }
    if (amounts.isEmpty || width == 0) {
      return TagBubbleLayout._(Size(width, 0), const []);
    }
    final maximum = amounts.reduce(math.max);
    // Leave room for two large targets beside each other on narrow panels.
    final scale = math.min(90.0, width * .24);
    final minimumHitRadius = math.min(24.0, width / 2);
    var alternatives = <List<TagBubblePlacement>>[[]];
    const gap = 4.0;
    const tolerance = .000001;

    for (final amount in amounts) {
      final radius = scale * math.sqrt(amount / maximum);
      final hitRadius = math.max(radius, minimumHitRadius);
      final next =
          <({List<TagBubblePlacement> bubbles, double score, int order})>[];
      final seen = <String>{};
      for (final placed in alternatives) {
        final centers = <String>{};
        for (final center in _centers(placed, hitRadius)) {
          if (!centers.add(
            '${center.dx.toStringAsFixed(5)},${center.dy.toStringAsFixed(5)}',
          )) {
            continue;
          }
          if (placed.any(
            (other) =>
                (other.center - center).distance + tolerance <
                other.hitRadius + hitRadius + gap,
          )) {
            continue;
          }
          final bubbles = [
            ...placed,
            TagBubblePlacement(
              center: center,
              radius: radius,
              hitRadius: hitRadius,
            ),
          ];
          final bounds = _bounds(bubbles);
          if (bounds.width > width + tolerance) continue;
          final signature = bubbles
              .map(
                (bubble) =>
                    '${(bubble.center.dx - bounds.left).toStringAsFixed(5)},'
                    '${(bubble.center.dy - bounds.top).toStringAsFixed(5)}',
              )
              .join(';');
          if (!seen.add(signature)) continue;
          next.add((
            bubbles: bubbles,
            score: _score(bounds),
            order: next.length,
          ));
        }
      }
      next.sort((a, b) {
        final comparison = a.score.compareTo(b.score);
        return comparison != 0 ? comparison : a.order.compareTo(b.order);
      });
      // Keep alternatives so the first triangle cannot dictate all six positions.
      alternatives = next
          .take(24)
          .map((candidate) => candidate.bubbles)
          .toList();
    }
    var placed = alternatives.first;
    var bestScore = _score(_bounds(placed));
    // Retain compact row candidates too: mirrored triangles can fill the beam
    // before a two-by-three arrangement becomes the better final choice.
    for (final columns in [2, 3]) {
      final rows = _rows(placed, columns, width);
      if (rows == null) continue;
      final score = _score(_bounds(rows));
      if (score < bestScore) {
        placed = rows;
        bestScore = score;
      }
    }
    final bounds = _bounds(placed);
    final shift = Offset((width - bounds.width) / 2 - bounds.left, -bounds.top);
    return TagBubbleLayout._(
      Size(width, bounds.height),
      List.unmodifiable([
        for (final bubble in placed)
          TagBubblePlacement(
            center: bubble.center + shift,
            radius: bubble.radius,
            hitRadius: bubble.hitRadius,
          ),
      ]),
    );
  }

  static double _score(Rect bounds) {
    final difference = bounds.height - bounds.width;
    return bounds.width * bounds.height + .2 * difference * difference;
  }

  static Iterable<Offset> _centers(
    List<TagBubblePlacement> placed,
    double radius,
  ) sync* {
    if (placed.isEmpty) {
      yield Offset.zero;
      return;
    }
    for (final previous in placed) {
      final distance = previous.hitRadius + radius + 4;
      for (var direction = 0; direction < 16; direction++) {
        final angle = direction * math.pi / 8;
        yield previous.center +
            Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      }
    }
    for (var a = 0; a < placed.length; a++) {
      for (var b = a + 1; b < placed.length; b++) {
        yield* _tangencies(
          placed[a].center,
          placed[a].hitRadius + radius + 4,
          placed[b].center,
          placed[b].hitRadius + radius + 4,
        );
      }
    }
    final bounds = _bounds(placed);
    yield Offset(bounds.center.dx, bounds.bottom + radius + 4);
  }

  static List<TagBubblePlacement>? _rows(
    List<TagBubblePlacement> bubbles,
    int columns,
    double width,
  ) {
    final result = <TagBubblePlacement>[];
    var y = 0.0;
    for (var start = 0; start < bubbles.length; start += columns) {
      final row = bubbles.skip(start).take(columns).toList();
      final rowWidth =
          row.fold(0.0, (sum, bubble) => sum + bubble.hitRadius * 2) +
          (row.length - 1) * 4;
      if (rowWidth > width) return null;
      final height = row.map((bubble) => bubble.hitRadius).reduce(math.max) * 2;
      var x = (width - rowWidth) / 2;
      for (final bubble in row) {
        result.add(
          TagBubblePlacement(
            center: Offset(x + bubble.hitRadius, y + height / 2),
            radius: bubble.radius,
            hitRadius: bubble.hitRadius,
          ),
        );
        x += bubble.hitRadius * 2 + 4;
      }
      y += height + 4;
    }
    return result;
  }

  static Rect _bounds(List<TagBubblePlacement> bubbles) {
    var bounds = Rect.fromCircle(
      center: bubbles.first.center,
      radius: bubbles.first.hitRadius,
    );
    for (final bubble in bubbles.skip(1)) {
      bounds = bounds.expandToInclude(
        Rect.fromCircle(center: bubble.center, radius: bubble.hitRadius),
      );
    }
    return bounds;
  }

  static Iterable<Offset> _tangencies(
    Offset a,
    double ar,
    Offset b,
    double br,
  ) sync* {
    final delta = b - a;
    final distance = delta.distance;
    if (distance == 0 || distance > ar + br || distance < (ar - br).abs()) {
      return;
    }
    final along = (ar * ar - br * br + distance * distance) / (2 * distance);
    final height = math.sqrt(math.max(0, ar * ar - along * along));
    final direction = delta / distance;
    final middle = a + direction * along;
    final perpendicular = Offset(-direction.dy, direction.dx) * height;
    yield middle + perpendicular;
    yield middle - perpendicular;
  }
}
