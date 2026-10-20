import 'package:china_map/widgets/label_text_cache.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TextPainter get(LabelTextCache cache, String text, {double scale = 2}) =>
      cache.get(
        text: text,
        fontSize: 10,
        scale: scale,
        bold: false,
        color: const Color(0xff000000),
      );

  test('同样的文字与缩放命中缓存，排版与直接构造一致', () {
    final cache = LabelTextCache();
    final first = get(cache, '南昌');
    expect(identical(get(cache, '南昌'), first), isTrue);
    expect(cache.length, 1);
    final direct = TextPainter(
      text: const TextSpan(
        text: '南昌',
        style: TextStyle(fontSize: 5, color: Color(0xff000000)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(first.size, direct.size);
    direct.dispose();
    // 缩放不同即为不同排版，描边版本也单独缓存。
    expect(identical(get(cache, '南昌', scale: 3), first), isFalse);
    cache.get(
      text: '南昌',
      fontSize: 10,
      scale: 2,
      bold: false,
      color: const Color(0xff000000),
      outline: true,
    );
    expect(cache.length, 3);
    cache.clear();
    expect(cache.length, 0);
  });

  test('超出容量时淘汰最久未使用的条目', () {
    final cache = LabelTextCache(capacity: 2);
    final a = get(cache, 'A');
    get(cache, 'B');
    // 访问 A 使 B 成为最久未使用。
    expect(identical(get(cache, 'A'), a), isTrue);
    get(cache, 'C');
    expect(cache.length, 2);
    expect(identical(get(cache, 'A'), a), isTrue);
    final b = get(cache, 'B');
    expect(cache.length, 2);
    expect(identical(get(cache, 'B'), b), isTrue);
    cache.clear();
  });
}
