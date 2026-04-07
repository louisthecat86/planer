class ProductionTask {
  final int? id;
  final int productId;
  final int departmentId;
  final String plannedDate;
  final int plannedQuantity;
  final int teamSize;
  final int estimatedDurationMinutes;
  final String dependencyDepartmentIds;

  ProductionTask({
    this.id,
    required this.productId,
    required this.departmentId,
    required this.plannedDate,
    required this.plannedQuantity,
    required this.teamSize,
    required this.estimatedDurationMinutes,
    required this.dependencyDepartmentIds,
  });

  factory ProductionTask.fromMap(Map<String, Object?> map) {
    return ProductionTask(
      id: map['id'] as int?,
      productId: map['productId'] as int,
      departmentId: map['departmentId'] as int,
      plannedDate: map['plannedDate'] as String,
      plannedQuantity: map['plannedQuantity'] as int,
      teamSize: map['teamSize'] as int,
      estimatedDurationMinutes: map['estimatedDurationMinutes'] as int,
      dependencyDepartmentIds: map['dependencyDepartmentIds'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'productId': productId,
      'departmentId': departmentId,
      'plannedDate': plannedDate,
      'plannedQuantity': plannedQuantity,
      'teamSize': teamSize,
      'estimatedDurationMinutes': estimatedDurationMinutes,
      'dependencyDepartmentIds': dependencyDepartmentIds,
    };
  }
}
