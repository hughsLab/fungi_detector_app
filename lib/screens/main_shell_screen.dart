import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'observations_screen.dart';

class MainShellScreen extends StatefulWidget {
  final int initialIndex;

  const MainShellScreen({super.key, this.initialIndex = 0});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _currentIndex;
  late final List<Widget> _shellTabs;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 3);
    _shellTabs = [
      HomeScreen(onSelectTab: _onTabSelected),
      const ObservationsScreen(),
    ];
  }

  void _onTabSelected(int index) {
    switch (index) {
      case 0:
        if (_currentIndex == 0) return;
        setState(() => _currentIndex = 0);
        return;
      case 1:
        Navigator.of(context).pushNamed('/detect');
        return;
      case 2:
        if (_currentIndex == 2) return;
        setState(() => _currentIndex = 2);
        return;
      case 3:
        Navigator.of(context).pushNamed('/species-library');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final shellIndex = _currentIndex == 2 ? 1 : 0;

    return Scaffold(
      body: IndexedStack(index: shellIndex, children: _shellTabs),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected
                  ? const Color(0xFF2D774E)
                  : const Color(0xD9FFFFFF),
              size: selected ? 25 : 24,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected
                  ? Colors.white
                  : const Color(0xCCFFFFFF),
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: _onTabSelected,
          height: 72,
          elevation: 8,
          backgroundColor: const Color(0xFF1F6F47),
          indicatorColor: const Color(0xFFE3F2E8),
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x66244A35),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.center_focus_strong_outlined),
              selectedIcon: Icon(Icons.center_focus_strong_rounded),
              label: 'Detect',
            ),
            NavigationDestination(
              icon: Icon(Icons.collections_bookmark_outlined),
              selectedIcon: Icon(Icons.collections_bookmark_rounded),
              label: 'Observations',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'Library',
            ),
          ],
        ),
      ),
    );
  }
}
