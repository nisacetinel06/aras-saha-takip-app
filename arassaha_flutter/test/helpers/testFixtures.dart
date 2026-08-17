import 'package:arassaha_flutter/models/work_order.dart';

/// Provider testlerinde tekrar tekrar kullanılan sahte veri nesneleri —
/// her test dosyasında ayrı ayrı tanımlamak yerine buradan içe aktar.

final testUser = AssignedUser(id: 1001, name: 'Test Teknisyen', role: 'teknisyen');

final testManager = AssignedUser(id: 2001, name: 'Test Yönetici', role: 'yonetici');

final testWorkOrder1 = WorkOrder(
  id: 1,
  title: 'Trafo arızası',
  description: 'Trafo aşırı ısınıyor',
  status: WorkOrderStatus.acik,
  priority: WorkOrderPriority.acil,
  locationName: 'Erzurum Merkez',
  lat: 39.9,
  lng: 41.27,
  assignedUser: testUser,
  equipmentRef: 'EQ-001',
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
);

final testWorkOrder2 = WorkOrder(
  id: 2,
  title: 'Sayaç anomalisi',
  description: 'Beklenmedik tüketim artışı',
  status: WorkOrderStatus.yolda,
  priority: WorkOrderPriority.normal,
  locationName: 'Erzurum Palandöken',
  lat: 39.88,
  lng: 41.23,
  assignedUser: testUser,
  equipmentRef: 'EQ-002',
  createdAt: DateTime(2026, 8, 2),
  updatedAt: DateTime(2026, 8, 2),
);
