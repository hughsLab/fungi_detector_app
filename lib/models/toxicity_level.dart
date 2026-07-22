enum ToxicityLevel {
  deadly,
  poisonous,
  potentiallyPoisonous,
  causesGastrointestinalIllness,
  psychoactive,
  notKnown,
  unknown,
}

extension ToxicityLevelDisplay on ToxicityLevel {
  String get label => switch (this) {
    ToxicityLevel.deadly => 'Deadly',
    ToxicityLevel.poisonous => 'Poisonous',
    ToxicityLevel.potentiallyPoisonous => 'Potentially poisonous',
    ToxicityLevel.causesGastrointestinalIllness => 'May cause illness',
    ToxicityLevel.psychoactive => 'Psychoactive',
    ToxicityLevel.notKnown => 'No known toxicity data',
    ToxicityLevel.unknown => 'Toxicity unknown',
  };

  bool get isDangerous => switch (this) {
    ToxicityLevel.deadly ||
    ToxicityLevel.poisonous ||
    ToxicityLevel.potentiallyPoisonous ||
    ToxicityLevel.causesGastrointestinalIllness => true,
    _ => false,
  };
}

ToxicityLevel parseToxicityLevel(
  dynamic value, {
  bool? legacyIsPoisonous,
}) {
  final normalized = value
      ?.toString()
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ');
  switch (normalized) {
    case 'deadly':
    case 'fatal':
      return ToxicityLevel.deadly;
    case 'poisonous':
    case 'toxic':
      return ToxicityLevel.poisonous;
    case 'potentially poisonous':
    case 'possibly poisonous':
      return ToxicityLevel.potentiallyPoisonous;
    case 'causes gastrointestinal illness':
    case 'gastrointestinal':
    case 'may cause illness':
      return ToxicityLevel.causesGastrointestinalIllness;
    case 'psychoactive':
      return ToxicityLevel.psychoactive;
    case 'not known':
    case 'no known toxicity data':
      return ToxicityLevel.notKnown;
    case 'unknown':
    case null:
    case '':
      return legacyIsPoisonous == true
          ? ToxicityLevel.poisonous
          : legacyIsPoisonous == false
          ? ToxicityLevel.notKnown
          : ToxicityLevel.unknown;
    default:
      return ToxicityLevel.unknown;
  }
}

