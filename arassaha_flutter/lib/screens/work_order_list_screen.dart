import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/work_order.dart';
import '../providers/work_order_list_provider.dart';
import '../widgets/work_order_card.dart';
import 'work_order_detail_screen.dart';

/// Görevler sekmesinin içeriği. MainShell'in ortak app bar'ı/alt navigasyonu
/// altında gösterilir; kendi Scaffold/AppBar'ı yoktur.
class WorkOrderListScreen extends StatefulWidget {
  /// Dashboard'daki özet kartlarından belirli bir statü ile açılmak istendiğinde
  /// verilir (örn. "Açık Arızalar" kartı -> WorkOrderStatus.acik). Null ise
  /// mevcut filtre neyse onunla (ya da tümüyle) açılır.
  final WorkOrderStatus? initialStatusFilter;

  const WorkOrderListScreen({super.key, this.initialStatusFilter});

  @override
  State<WorkOrderListScreen> createState() => _WorkOrderListScreenState();
}

class _WorkOrderListScreenState extends State<WorkOrderListScreen> {
  @override
  void initState() {
    super.initState();
    // Ekran ilk açıldığında listeyi backend'den çek.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<WorkOrderListProvider>();
      if (widget.initialStatusFilter != null) {
        provider.setFilter(widget.initialStatusFilter);
      } else {
        provider.loadWorkOrders();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SearchBar(),
        const _FilterBar(),
        Expanded(
          child: Consumer<WorkOrderListProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.errorMessage != null) {
                return _ErrorState(
                  message: provider.errorMessage!,
                  onRetry: provider.loadWorkOrders,
                );
              }

              if (provider.workOrders.isEmpty) {
                return const _EmptyState();
              }

              return RefreshIndicator(
                onRefresh: provider.loadWorkOrders,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: provider.workOrders.length,
                  itemBuilder: (context, index) {
                    final workOrder = provider.workOrders[index];
                    return WorkOrderCard(
                      workOrder: workOrder,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WorkOrderDetailScreen(workOrderId: workOrder.id),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    final provider = context.read<WorkOrderListProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        onChanged: provider.setSearchQuery,
        decoration: const InputDecoration(
          hintText: 'Görev ara (İş, başlık, adres)...',
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkOrderListProvider>();
    final scheme = Theme.of(context).colorScheme;

    final filters = <String, WorkOrderStatus?>{
      'Tümü': null,
      'Açık': WorkOrderStatus.acik,
      'Yolda': WorkOrderStatus.yolda,
      'Sahada': WorkOrderStatus.sahada,
      'Çözüldü': WorkOrderStatus.cozuldu,
    };

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = provider.filterStatus == entry.value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant),
              onSelected: (_) => provider.setFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined, size: 56, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('Kayıt bulunamadı', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
          ],
        ),
      ),
    );
  }
}
