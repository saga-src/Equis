import 'dart:math' as math;

import 'package:equis/presentation/home/tag_bubble_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TagBubbleLayout.pack', () {
    test('returns an empty layout for no bubbles', () {
      final layout = TagBubbleLayout.pack(const [], width: 320);

      expect(layout.bubbles, isEmpty);
      expect(layout.size.width, 320);
      expect(layout.size.height, greaterThanOrEqualTo(0));
    });

    test('handles a zero-width constraint without placing bubbles', () {
      final layout = TagBubbleLayout.pack(const [1], width: 0);

      expect(layout.size.width, 0);
      expect(layout.bubbles, isEmpty);
    });

    test('rejects invalid geometry inputs', () {
      expect(
        () => TagBubbleLayout.pack(const [1], width: double.nan),
        throwsArgumentError,
      );
      expect(
        () => TagBubbleLayout.pack(const [1], width: double.infinity),
        throwsArgumentError,
      );
      expect(
        () => TagBubbleLayout.pack(const [1], width: -1),
        throwsArgumentError,
      );
      expect(
        () => TagBubbleLayout.pack(const [0], width: 120),
        throwsArgumentError,
      );
      expect(
        () => TagBubbleLayout.pack(const [-1], width: 120),
        throwsArgumentError,
      );
      expect(
        () => TagBubbleLayout.pack(List.filled(7, 1), width: 120),
        throwsArgumentError,
      );
    });

    test('keeps equal-scale circle areas proportional to amounts', () {
      const amounts = [40000, 10000, 2500, 625, 100, 25];
      final layout = TagBubbleLayout.pack(amounts, width: 640);
      final largest = layout.bubbles.first;

      expect(layout.bubbles, hasLength(amounts.length));
      for (var index = 1; index < amounts.length; index++) {
        final bubble = layout.bubbles[index];
        expect(
          bubble.radius * bubble.radius,
          closeTo(
            largest.radius * largest.radius * amounts[index] / amounts.first,
            1e-6,
          ),
        );
      }
    });

    test('fits without overlap across narrow, mobile, and desktop widths', () {
      const amounts = [10000000, 1000000, 100000, 10000, 1000, 1];
      for (final width in [48.0, 72.0, 120.0, 240.0, 360.0, 640.0]) {
        final layout = TagBubbleLayout.pack(amounts, width: width);

        expect(layout.size.width, lessThanOrEqualTo(width));
        expect(layout.size.height, greaterThan(0));
        for (final bubble in layout.bubbles) {
          expect(bubble.radius, greaterThan(0));
          expect(bubble.hitRadius, greaterThanOrEqualTo(bubble.radius));
          expect(
            bubble.center.dx - bubble.hitRadius,
            greaterThanOrEqualTo(-1e-6),
          );
          expect(
            bubble.center.dy - bubble.hitRadius,
            greaterThanOrEqualTo(-1e-6),
          );
          expect(
            bubble.center.dx + bubble.hitRadius,
            lessThanOrEqualTo(layout.size.width + 1e-6),
          );
          expect(
            bubble.center.dy + bubble.hitRadius,
            lessThanOrEqualTo(layout.size.height + 1e-6),
          );
        }

        for (var first = 0; first < layout.bubbles.length; first++) {
          for (
            var second = first + 1;
            second < layout.bubbles.length;
            second++
          ) {
            final a = layout.bubbles[first];
            final b = layout.bubbles[second];
            final distance = (a.center - b.center).distance;
            expect(distance, greaterThanOrEqualTo(a.radius + b.radius - 1e-6));
            expect(
              distance,
              greaterThanOrEqualTo(a.hitRadius + b.hitRadius - 1e-6),
            );
          }
        }
      }
    });

    test('packs six equal values within a compact mobile cluster', () {
      final layout = TagBubbleLayout.pack(List.filled(6, 10000), width: 240);
      final diameter = layout.bubbles.first.radius * 2;

      expect(layout.bubbles, hasLength(6));
      expect(layout.size.height, lessThanOrEqualTo(diameter * 3.5));
    });

    test('does not scale the largest bubble past the visual cap', () {
      final layout = TagBubbleLayout.pack(const [100, 50], width: 1000);

      expect(layout.bubbles.first.radius * 2, lessThanOrEqualTo(180));
    });

    test('uses the same placement for the same input and width', () {
      const amounts = [9, 9, 4, 3, 2, 1];
      final first = TagBubbleLayout.pack(amounts, width: 320);
      final second = TagBubbleLayout.pack(amounts, width: 320);

      expect(second.size, first.size);
      expect(second.bubbles, hasLength(first.bubbles.length));
      for (var index = 0; index < first.bubbles.length; index++) {
        expect(second.bubbles[index].center, first.bubbles[index].center);
        expect(second.bubbles[index].radius, first.bubbles[index].radius);
        expect(second.bubbles[index].hitRadius, first.bubbles[index].hitRadius);
      }
    });

    test('preserves ratios for tiny and very large values', () {
      const amounts = [1, 1000000000000];
      final layout = TagBubbleLayout.pack(amounts, width: 640);
      final smallest = layout.bubbles.first;
      final largest = layout.bubbles.last;

      expect(smallest.radius, greaterThan(0));
      expect(
        smallest.radius / largest.radius,
        closeTo(math.sqrt(1 / 1000000000000), 1e-12),
      );
    });
  });
}
