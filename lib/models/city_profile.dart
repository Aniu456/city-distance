import 'city.dart';

class DataSource {
  const DataSource({required this.title, required this.url});
  final String title;
  final String url;

  factory DataSource.fromJson(Map<String, Object?> json) {
    final url = readText(json, 'url');
    if (Uri.tryParse(url)?.scheme != 'https') {
      throw const FormatException('资料来源链接无效');
    }
    return DataSource(title: readText(json, 'title'), url: url);
  }
}

class IndustryShare {
  const IndustryShare(this.name, this.percent);
  final String name;
  final double? percent;
}

/// 同年度统计公报快照，居民支出口径与来源一同保存。
class CityProfile {
  CityProfile({
    required this.code,
    required this.year,
    required this.gdp,
    required this.sectors,
    required this.industries,
    required this.annualConsumption,
    required this.consumptionScope,
    required this.sources,
  });

  final String code;
  final int year;

  /// 亿元，现价。
  final double gdp;
  final List<double> sectors;
  final List<IndustryShare> industries;

  /// 元/人/年，包含居住等消费；不是新迁入者预算。
  final double annualConsumption;
  final String consumptionScope;
  final List<DataSource> sources;

  factory CityProfile.fromJson(Map<String, Object?> json) {
    final sectors = readList(json['sectors'])
        .map((value) {
          if (value is! num || !value.isFinite || value < 0 || value > 100) {
            throw const FormatException('产业占比无效');
          }
          return value.toDouble();
        })
        .toList(growable: false);
    if (sectors.length != 3 ||
        (sectors.reduce((a, b) => a + b) - 100).abs() > 0.15) {
      throw const FormatException('三次产业占比合计不正确');
    }
    final industries = readList(json['industries'])
        .map((value) {
          final item = readObject(value);
          final percent = item['percent'] == null
              ? null
              : readNumber(item, 'percent');
          if (percent != null && percent > 100) {
            throw const FormatException('行业占比超出范围');
          }
          return IndustryShare(readText(item, 'name'), percent);
        })
        .toList(growable: false);
    final sources = readList(json['sources'])
        .map((value) => DataSource.fromJson(readObject(value)))
        .toList(growable: false);
    if (sources.isEmpty || json['year'] is! int) {
      throw const FormatException('资料缺少年度或来源');
    }
    return CityProfile(
      code: readText(json, 'code'),
      year: json['year'] as int,
      gdp: readNumber(json, 'gdp'),
      sectors: sectors,
      industries: industries,
      annualConsumption: readNumber(json, 'annualConsumption'),
      consumptionScope: readText(json, 'consumptionScope'),
      sources: sources,
    );
  }
}

class RentReference {
  const RentReference({
    required this.average,
    required this.median,
    required this.period,
    required this.source,
  });

  /// 样本住宅元/平方米/月，不代表某套房源的报价。
  final double average;
  final double median;
  final String period;
  final DataSource source;
}
