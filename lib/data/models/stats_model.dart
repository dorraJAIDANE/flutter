class StatsModel {
  const StatsModel({
    this.total = 0,
    this.livres = 0,
    this.enCoursLivraison = 0,
    this.enRetour = 0,
    this.annules = 0,
    this.totalTrend = '',
    this.livresTrend = '',
    this.enCoursTrend = '',
    this.enRetourTrend = '',
    this.annulesTrend = '',
    this.livresPerc,
    this.enCoursPerc,
    this.enRetourPerc,
  });

  final int total;
  final int livres;
  final int enCoursLivraison;
  final int enRetour;
  final int annules;
  final String totalTrend;
  final String livresTrend;
  final String enCoursTrend;
  final String enRetourTrend;
  final String annulesTrend;
  final String? livresPerc;
  final String? enCoursPerc;
  final String? enRetourPerc;

  double get deliveryRate {
    if (total <= 0) return 0;
    return (livres / total) * 100;
  }

  factory StatsModel.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) => (v as num?)?.toInt() ?? int.tryParse('$v') ?? 0;

    return StatsModel(
      total: toInt(json['total']),
      livres: toInt(json['livres']),
      enCoursLivraison: toInt(json['enCoursLivraison']),
      enRetour: toInt(json['enRetour']),
      annules: toInt(json['annules']),
      totalTrend: (json['totalTrend'] ?? '').toString(),
      livresTrend: (json['livresTrend'] ?? '').toString(),
      enCoursTrend: (json['enCoursTrend'] ?? '').toString(),
      enRetourTrend: (json['enRetourTrend'] ?? '').toString(),
      annulesTrend: (json['annulesTrend'] ?? '').toString(),
      livresPerc: json['livresPerc']?.toString(),
      enCoursPerc: json['enCoursPerc']?.toString(),
      enRetourPerc: json['enRetourPerc']?.toString(),
    );
  }
}
