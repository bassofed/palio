class Team {
  int id; // <-- ASSICURATI CHE CI SIA!
  String name;
  String colorHex;
  bool hasUsedJolly;

  Team({
    required this.id, // <-- ASSICURATI CHE CI SIA!
    required this.name,
    required this.colorHex,
    this.hasUsedJolly = false,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? 0, // Fallback a 0 se manca
      name: json['name'] ?? '',
      colorHex: json['colorHex'] ?? '#FFFFFF',
      hasUsedJolly: json['hasUsedJolly'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'colorHex': colorHex,
      'hasUsedJolly': hasUsedJolly,
    };
  }
}