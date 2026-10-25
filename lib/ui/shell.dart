import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';
import 'screens/approvals_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/home_screen.dart';
import 'screens/more_screen.dart';
import 'screens/trading_screen.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(selectedTabProvider);
    final approvals = ref.watch(pendingApprovalsProvider).valueOrNull ?? const [];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: tab,
          children: const [
            HomeScreen(),
            ChatScreen(),
            TradingScreen(),
            ApprovalsScreen(),
            MoreScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (index) =>
            ref.read(selectedTabProvider.notifier).state = index,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          const NavigationDestination(
            icon: Icon(Icons.candlestick_chart_outlined),
            selectedIcon: Icon(Icons.candlestick_chart),
            label: 'Trading',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: approvals.isNotEmpty,
              label: Text('${approvals.length}'),
              child: const Icon(Icons.verified_user_outlined),
            ),
            selectedIcon: const Icon(Icons.verified_user),
            label: 'Approve',
          ),
          const NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
