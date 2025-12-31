import 'observation.dart';

class SpeciesDetailArgs {
  final String speciesId;
  final Observation? observation;

  const SpeciesDetailArgs({
    required this.speciesId,
    this.observation,
  });
}

class SaveObservationArgs {
  final String? preselectedSpeciesId;

  const SaveObservationArgs({this.preselectedSpeciesId});
}

class DisclaimerArgs {
  final String? nextRoute;
  final bool allowBack;

  const DisclaimerArgs({
    this.nextRoute,
    this.allowBack = true,
  });
}
