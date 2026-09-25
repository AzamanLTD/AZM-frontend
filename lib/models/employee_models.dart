// =============================================================================
// AZAMAN — EMPLOYEE MODELS (2026-07-06 v3)
// Cross-checked against Prisma schema enums.
// =============================================================================

enum EmployeeRole {
  owner, manager, supervisor, staff, driver, housekeeper, waiter,
  chef, receptionist, concierge, security,
}

enum EmployeeStatus { active, suspended, terminated, onLeave }

enum ShiftStatus { scheduled, clockedIn, clockedOut, late, noShow }

enum ShiftSwapStatus { open, claimed, approved, rejected }

enum TimeOffType { sick, personal, vacation, emergency, unpaid }

enum TimeOffStatus { pending, approved, rejected }

enum PayrollStatus { pending, processed, failed, partial }

enum PayrollType { salary, hourly, pieceRate }

EmployeeRole employeeRoleFromString(String? val) {
  switch (val?.toUpperCase()) {
    case 'OWNER': return EmployeeRole.owner;
    case 'MANAGER': return EmployeeRole.manager;
    case 'SUPERVISOR': return EmployeeRole.supervisor;
    case 'STAFF': return EmployeeRole.staff;
    case 'DRIVER': return EmployeeRole.driver;
    case 'HOUSEKEEPER': return EmployeeRole.housekeeper;
    case 'WAITER': return EmployeeRole.waiter;
    case 'CHEF': return EmployeeRole.chef;
    case 'RECEPTIONIST': return EmployeeRole.receptionist;
    case 'CONCIERGE': return EmployeeRole.concierge;
    case 'SECURITY': return EmployeeRole.security;
    default: return EmployeeRole.staff;
  }
}

EmployeeStatus employeeStatusFromString(String? val) {
  switch (val?.toUpperCase()) {
    case 'ACTIVE': return EmployeeStatus.active;
    case 'SUSPENDED': return EmployeeStatus.suspended;
    case 'TERMINATED': return EmployeeStatus.terminated;
    case 'ON_LEAVE': return EmployeeStatus.onLeave;
    default: return EmployeeStatus.active;
  }
}

ShiftStatus shiftStatusFromString(String? val) {
  switch (val?.toUpperCase()) {
    case 'SCHEDULED': return ShiftStatus.scheduled;
    case 'CLOCKED_IN': return ShiftStatus.clockedIn;
    case 'CLOCKED_OUT': return ShiftStatus.clockedOut;
    case 'LATE': return ShiftStatus.late;
    case 'NO_SHOW': return ShiftStatus.noShow;
    default: return ShiftStatus.scheduled;
  }
}

PayrollStatus payrollStatusFromString(String? val) {
  switch (val?.toUpperCase()) {
    case 'PENDING': return PayrollStatus.pending;
    case 'PROCESSED': return PayrollStatus.processed;
    case 'FAILED': return PayrollStatus.failed;
    case 'PARTIAL': return PayrollStatus.partial;
    default: return PayrollStatus.pending;
  }
}

PayrollType payrollTypeFromString(String? val) {
  switch (val?.toUpperCase()) {
    case 'SALARY': return PayrollType.salary;
    case 'HOURLY': return PayrollType.hourly;
    case 'PIECE_RATE': return PayrollType.pieceRate;
    default: return PayrollType.salary;
  }
}

TimeOffType timeOffTypeFromString(String? val) {
  switch (val?.toUpperCase()) {
    case 'SICK': return TimeOffType.sick;
    case 'PERSONAL': return TimeOffType.personal;
    case 'VACATION': return TimeOffType.vacation;
    case 'EMERGENCY': return TimeOffType.emergency;
    case 'UNPAID': return TimeOffType.unpaid;
    default: return TimeOffType.personal;
  }
}

TimeOffStatus timeOffStatusFromString(String? val) {
  switch (val?.toUpperCase()) {
    case 'PENDING': return TimeOffStatus.pending;
    case 'APPROVED': return TimeOffStatus.approved;
    case 'REJECTED': return TimeOffStatus.rejected;
    default: return TimeOffStatus.pending;
  }
}

class BusinessEmployee {
  final String id;
  final String businessProfileId;
  final String userId;
  final EmployeeRole role;
  final EmployeeStatus status;
  final String? title;
  final String? department;
  final PayrollType payrollType;
  final double? salaryAmount;
  final double? hourlyRate;
  final String paymentPreference;
  final double accruedWages;
  final double withdrawnEarly;
  final bool ewaEligible;
  final DateTime? hireDate;
  final DateTime? terminationDate;
  final String? emergencyContact;
  final String? notes;
  final int lateCount;
  final int totalShifts;
  final double totalHours;
  final DateTime createdAt;
  final String? businessName;
  final String? businessCategory;
  final String? businessLogoUrl;
  final String? username;

  BusinessEmployee({
    required this.id,
    required this.businessProfileId,
    required this.userId,
    required this.role,
    required this.status,
    this.title,
    this.department,
    required this.payrollType,
    this.salaryAmount,
    this.hourlyRate,
    this.paymentPreference = 'AZAMAN_BALANCE',
    this.accruedWages = 0,
    this.withdrawnEarly = 0,
    this.ewaEligible = false,
    this.hireDate,
    this.terminationDate,
    this.emergencyContact,
    this.notes,
    this.lateCount = 0,
    this.totalShifts = 0,
    this.totalHours = 0,
    required this.createdAt,
    this.businessName,
    this.businessCategory,
    this.businessLogoUrl,
    this.username,
  });

  factory BusinessEmployee.fromJson(Map<String, dynamic> j) {
    final biz = j['businessProfile'] as Map<String, dynamic>?;
    final user = j['user'] as Map<String, dynamic>?;
    return BusinessEmployee(
      id: j['id'] ?? '',
      businessProfileId: j['businessProfileId'] ?? '',
      userId: j['userId'] ?? '',
      role: employeeRoleFromString(j['role']),
      status: employeeStatusFromString(j['status']),
      title: j['title'],
      department: j['department'],
      payrollType: payrollTypeFromString(j['payrollType']),
      salaryAmount: (j['salaryAmount'] as num?)?.toDouble(),
      hourlyRate: (j['hourlyRate'] as num?)?.toDouble(),
      paymentPreference: j['paymentPreference'] ?? 'AZAMAN_BALANCE',
      accruedWages: (j['accruedWages'] as num?)?.toDouble() ?? 0,
      withdrawnEarly: (j['withdrawnEarly'] as num?)?.toDouble() ?? 0,
      ewaEligible: j['ewaEligible'] == true,
      hireDate: j['hireDate'] != null ? DateTime.tryParse(j['hireDate']) : null,
      terminationDate: j['terminationDate'] != null ? DateTime.tryParse(j['terminationDate']) : null,
      emergencyContact: j['emergencyContact'],
      notes: j['notes'],
      lateCount: (j['lateCount'] as num?)?.toInt() ?? 0,
      totalShifts: (j['totalShifts'] as num?)?.toInt() ?? 0,
      totalHours: (j['totalHours'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      businessName: biz?['businessName'],
      businessCategory: biz?['category'],
      businessLogoUrl: biz?['logoUrl'],
      username: user?['username'],
    );
  }
}

class Shift {
  final String id;
  final String businessProfileId;
  final String employeeId;
  final DateTime shiftDate;
  final DateTime startTime;
  final DateTime endTime;
  final ShiftStatus status;
  final String? shiftLabel;
  final int? breakMinutes;
  final int? lateMinutes;
  final bool isLate;
  final String? notes;

  Shift({
    required this.id,
    required this.businessProfileId,
    required this.employeeId,
    required this.shiftDate,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.shiftLabel,
    this.breakMinutes,
    this.lateMinutes,
    this.isLate = false,
    this.notes,
  });

  factory Shift.fromJson(Map<String, dynamic> j) {
    return Shift(
      id: j['id'] ?? '',
      businessProfileId: j['businessProfileId'] ?? '',
      employeeId: j['employeeId'] ?? '',
      shiftDate: DateTime.tryParse(j['shiftDate'] ?? '') ?? DateTime.now(),
      startTime: DateTime.tryParse(j['startTime'] ?? '') ?? DateTime.now(),
      endTime: DateTime.tryParse(j['endTime'] ?? '') ?? DateTime.now(),
      status: shiftStatusFromString(j['status']),
      shiftLabel: j['shiftLabel'],
      breakMinutes: (j['breakMinutes'] as num?)?.toInt(),
      lateMinutes: (j['lateMinutes'] as num?)?.toInt(),
      isLate: j['isLate'] == true,
      notes: j['notes'],
    );
  }

  double get durationHours => endTime.difference(startTime).inMinutes / 60.0;
}

class PayrollRecord {
  final String id;
  final String employeeId;
  final String period;
  final double grossAmount;
  final double netAmount;
  final double? ewaDeducted;
  final double? feeDeducted;
  final PayrollStatus status;
  final DateTime? processedAt;
  final DateTime createdAt;

  PayrollRecord({
    required this.id,
    required this.employeeId,
    required this.period,
    required this.grossAmount,
    required this.netAmount,
    this.ewaDeducted,
    this.feeDeducted,
    required this.status,
    this.processedAt,
    required this.createdAt,
  });

  factory PayrollRecord.fromJson(Map<String, dynamic> j) {
    return PayrollRecord(
      id: j['id'] ?? '',
      employeeId: j['employeeId'] ?? '',
      period: j['period'] ?? '',
      grossAmount: (j['grossAmount'] as num?)?.toDouble() ?? 0,
      netAmount: (j['netAmount'] as num?)?.toDouble() ?? 0,
      ewaDeducted: (j['ewaDeducted'] as num?)?.toDouble(),
      feeDeducted: (j['feeDeducted'] as num?)?.toDouble(),
      status: payrollStatusFromString(j['status']),
      processedAt: j['processedAt'] != null ? DateTime.tryParse(j['processedAt']) : null,
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class TimeOffRequest {
  final String id;
  final String employeeId;
  final TimeOffType type;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final TimeOffStatus status;
  final String? managerNote;
  final DateTime createdAt;

  TimeOffRequest({
    required this.id,
    required this.employeeId,
    required this.type,
    required this.startDate,
    required this.endDate,
    this.reason,
    required this.status,
    this.managerNote,
    required this.createdAt,
  });

  factory TimeOffRequest.fromJson(Map<String, dynamic> j) {
    return TimeOffRequest(
      id: j['id'] ?? '',
      employeeId: j['employeeId'] ?? '',
      type: timeOffTypeFromString(j['type']),
      startDate: DateTime.tryParse(j['startDate'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(j['endDate'] ?? '') ?? DateTime.now(),
      reason: j['reason'],
      status: timeOffStatusFromString(j['status']),
      managerNote: j['managerNote'],
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class EmployeeFeedback {
  final String id;
  final int rating;
  final List<String> tags;
  final String? comment;
  final bool isAnonymous;
  final String? giverName;
  final DateTime createdAt;

  EmployeeFeedback({
    required this.id,
    required this.rating,
    this.tags = const [],
    this.comment,
    this.isAnonymous = false,
    this.giverName,
    required this.createdAt,
  });

  factory EmployeeFeedback.fromJson(Map<String, dynamic> j) {
    final giver = j['giverEmployee'] as Map<String, dynamic>?;
    final giverUser = giver?['user'] as Map<String, dynamic>?;
    return EmployeeFeedback(
      id: j['id'] ?? '',
      rating: (j['rating'] as num?)?.toInt() ?? 5,
      tags: (j['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      comment: j['comment'],
      isAnonymous: j['isAnonymous'] == true,
      giverName: j['isAnonymous'] == true ? 'Anonymous' : giverUser?['username'],
      createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}

class TeamMember {
  final String name;
  final EmployeeRole role;
  final String? shiftLabel;

  TeamMember({required this.name, required this.role, this.shiftLabel});

  factory TeamMember.fromJson(Map<String, dynamic> j) {
    return TeamMember(
      name: j['name'] ?? '',
      role: employeeRoleFromString(j['role']),
      shiftLabel: j['shiftLabel'],
    );
  }
}

class SalaryInfo {
  final PayrollType type;
  final double? monthlySalary;
  final double? hourlyRate;
  final double expectedAccrued;
  final double netAccrued;
  final int daysUntilPayday;
  final DateTime? payday;

  SalaryInfo({
    required this.type,
    this.monthlySalary,
    this.hourlyRate,
    required this.expectedAccrued,
    required this.netAccrued,
    required this.daysUntilPayday,
    this.payday,
  });

  factory SalaryInfo.fromJson(Map<String, dynamic> j) {
    return SalaryInfo(
      type: payrollTypeFromString(j['type']),
      monthlySalary: (j['monthlySalary'] as num?)?.toDouble(),
      hourlyRate: (j['hourlyRate'] as num?)?.toDouble(),
      expectedAccrued: (j['expectedAccrued'] as num?)?.toDouble() ?? 0,
      netAccrued: (j['netAccrued'] as num?)?.toDouble() ?? 0,
      daysUntilPayday: (j['daysUntilPayday'] as num?)?.toInt() ?? 0,
      payday: j['payday'] != null ? DateTime.tryParse(j['payday']) : null,
    );
  }
}

class WorkerDashboard {
  final BusinessEmployee? employee;
  final Shift? nextShift;
  final Shift? currentShift;
  final List<TeamMember> teamOnDuty;
  final TeamMember? upcomingTeam;
  final SalaryInfo? salaryInfo;
  final double ewaAvailable;
  final List<EmployeeFeedback> recentFeedback;

  WorkerDashboard({
    this.employee,
    this.nextShift,
    this.currentShift,
    this.teamOnDuty = const [],
    this.upcomingTeam,
    this.salaryInfo,
    this.ewaAvailable = 0,
    this.recentFeedback = const [],
  });

  factory WorkerDashboard.fromJson(Map<String, dynamic> j) {
    final emp = j['employee'] as Map<String, dynamic>?;
    return WorkerDashboard(
      employee: emp != null ? BusinessEmployee.fromJson(emp) : null,
      nextShift: j['nextShift'] != null ? Shift.fromJson(j['nextShift']) : null,
      currentShift: j['currentShift'] != null ? Shift.fromJson(j['currentShift']) : null,
      teamOnDuty: (j['teamOnDuty'] as List<dynamic>?)
          ?.map((t) => TeamMember.fromJson(t as Map<String, dynamic>))
          .toList() ?? [],
      upcomingTeam: j['upcomingTeam'] != null
          ? TeamMember.fromJson(j['upcomingTeam'])
          : null,
      salaryInfo: j['salaryInfo'] != null
          ? SalaryInfo.fromJson(j['salaryInfo'])
          : null,
      ewaAvailable: (j['ewaAvailable'] as num?)?.toDouble() ?? 0,
      recentFeedback: (j['recentFeedback'] as List<dynamic>?)
          ?.map((f) => EmployeeFeedback.fromJson(f as Map<String, dynamic>))
          .toList() ?? [],
    );
  }
}
