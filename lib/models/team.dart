class Team {
  String name;
  String colorHex;
  bool hasUsedJolly;

  Team({
    required this.name,
    required this.colorHex,
    this.hasUsedJolly = false,
  });

  // Trasforma in JSON per il salvataggio
  Map<String, dynamic> toJson() => {
    'name': name,
    'colorHex': colorHex,
    'hasUsedJolly': hasUsedJolly,
  };

  // Ricrea l'oggetto dal JSON
  factory Team.fromJson(Map<String, dynamic> json) => Team(
    name: json['name'],
    colorHex: json['colorHex'],
    hasUsedJolly: json['hasUsedJolly'] ?? false,
  );
}