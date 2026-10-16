enum IssueCode {
  inputTooLarge,
  invalidFormat,
  invalidInteger,
  invalidId,
  invalidRevision,
  unsupportedSchema,
  unsupportedRuleSet,
  unsupportedMechanic,
  outOfBounds,
  invalidMap,
  duplicateLevelId,
  duplicateUnitId,
  duplicateStart,
  startOnGoal,
  blockedPlacement,
  disconnectedWalkable,
  individuallyUnreachable,
  missingRoute,
  extraRoute,
  duplicateRoute,
  emptyRoute,
  tooManyCommands,
  diagonalMove,
  zeroLengthMove,
  blockedMove,
  goalPassThrough,
  commandAfterGoal,
  incompleteRoute,
  staleLevelIdentity,
}

final class ValidationIssue {
  final IssueCode code;
  final String path;
  final String? unitId;
  final int? commandIndex;
  const ValidationIssue(this.code, this.path, {this.unitId, this.commandIndex});
  Map<String, Object> toJson() => {
    'code': code.name,
    'path': path,
    if (unitId != null) 'unitId': unitId!,
    if (commandIndex != null) 'commandIndex': commandIndex!,
  };
  @override
  String toString() => '${code.name}:$path';
}

final class ValidationResult {
  final List<ValidationIssue> issues;
  ValidationResult(Iterable<ValidationIssue> issues)
    : issues = List.unmodifiable(issues);
  bool get isValid => issues.isEmpty;
}

final class ParseResult<T> {
  final T? value;
  final List<ValidationIssue> issues;
  ParseResult.success(T data) : value = data, issues = const [];
  ParseResult.failure(Iterable<ValidationIssue> issues)
    : value = null,
      issues = List.unmodifiable(issues);
  bool get isValid => value != null && issues.isEmpty;
}
