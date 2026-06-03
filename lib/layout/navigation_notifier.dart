import 'package:flutter/material.dart';

class NavigationNotifier extends ChangeNotifier {
  final List<String> _routeHistory = ['/playlist'];
  String get currentRoute => _routeHistory.last;
  
  bool get canPop => _routeHistory.length > 1;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void navigateTo(String routeName) {
    if (currentRoute == routeName) return;
    _routeHistory.clear();
    _routeHistory.add(routeName);
    notifyListeners();
    navigatorKey.currentState?.pushNamedAndRemoveUntil(routeName, (route) => false);
  }

  void pushRoute(String routeName) {
    if (currentRoute == routeName) return;
    _routeHistory.add(routeName);
    notifyListeners();
    navigatorKey.currentState?.pushNamedAndRemoveUntil(routeName, (route) => false);
  }

  void popRoute() {
    if (canPop) {
      _routeHistory.removeLast();
      notifyListeners();
      navigatorKey.currentState?.pushNamedAndRemoveUntil(currentRoute, (route) => false);
    }
  }
}
