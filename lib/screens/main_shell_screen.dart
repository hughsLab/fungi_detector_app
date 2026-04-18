import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'observations_screen.dart';

class MainShellScreen extends StatefulWidget {
  final int initialIndex;

  const MainShellScreen({super.key, this.initialIndex = 2});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _currentIndex;
  late final List<Widget> _shellTabs;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(1, 2);
    _shellTabs = [
      const ObservationsScreen(),
      HomeScreen(onSelectTab: _onTabSelected),
    ];
  }

  void _onTabSelected(int index) {
    if (index == 0) {
      Navigator.of(context).pushNamed('/detect');
      return;
    }
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex - 1, children: _shellTabs),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0F3D2E),
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        onTap: _onTabSelected,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.center_focus_strong),
            label: 'Detect',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.collections_bookmark),
            label: 'Observations',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        ],
      ),
    );
  }
}
