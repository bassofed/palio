class Game {
  int id;
  String name;
  Map<String, dynamic> scores;
  Map<String, dynamic> partials;
  Map<int, bool> activeJollies;
  Map<String, bool> participations; // <-- NUOVO: Registra chi partecipa

  Game({
    required this.id,
    required this.name,
    Map<String, dynamic>? scores,
    Map<String, dynamic>? partials,
    Map<int, bool>? activeJollies,
    Map<String, bool>? participations,
  })  : scores = scores ?? {},
        partials = partials ?? {},
        activeJollies = activeJollies ?? {},
        participations = participations ?? {}; // Di default tutti partecipano

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'],
      name: json['name'],
      scores: json['scores'] != null ? Map<String, dynamic>.from(json['scores']) : null,
      partials: json['partials'] != null ? Map<String, dynamic>.from(json['partials']) : null,
      activeJollies: json['activeJollies'] != null
          ? (json['activeJollies'] as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), v as bool))
          : null,
      participations: json['participations'] != null
          ? Map<String, bool>.from(json['participations'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'scores': scores,
      'partials': partials,
      'activeJollies': activeJollies.map((k, v) => MapEntry(k.toString(), v)),
      'participations': participations,
    };
  }
}