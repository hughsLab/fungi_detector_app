import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'map_screen.dart';
import 'observations_screen.dart';
import 'settings_screen.dart';
import 'species_library_screen.dart';
import '../models/navigation_args.dart';

class MainShellScreen extends StatefulWidget {
  final int initialIndex;

  const MainShellScreen({super.key, this.initialIndex = 0});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  late int _currentIndex;
  final GlobalKey<MapScreenState> _mapKey = GlobalKey<MapScreenState>();
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _tabs = [
      HomeScreen(onSelectTab: _onTabSelected),
      ObservationsScreen(onMapFocusRequest: _handleMapFocus),
      const SpeciesLibraryScreen(),
      MapScreen(key: _mapKey),
      const SettingsScreen(),
    ];
  }

  void _onTabSelected(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
  }

  void _handleMapFocus(MapFocusRequest request) {
    if (_currentIndex != 3) {
      setState(() {
        _currentIndex = 3;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapKey.currentState?.handleFocusRequest(request);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
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
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Library',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
