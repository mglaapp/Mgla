import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// The navigation rail on wide screens and TVs (see [SidebarFocus]).
///
/// Its own scope, because a page lives in a nested Navigator: "leave the page to the parent
/// scope" stopped at that navigator, so a TV remote never reached the rail — and with it the
/// profiles, tools and settings (Android TV emulator, 20-10).
final sidebarFocusScope = FocusScopeNode(debugLabel: 'sidebar');

final _pageScopes = <FocusScopeNode>{};

/// Moves the focus into the rail. False when there is no rail (phone layout).
bool focusSidebar() {
  if (sidebarFocusScope.context == null || !sidebarFocusScope.canRequestFocus) {
    return false;
  }
  final remembered = sidebarFocusScope.focusedChild;
  final target = remembered != null && remembered != sidebarFocusScope
      ? remembered
      : sidebarFocusScope.traversalDescendants
            .where((node) => node is! FocusScopeNode)
            .firstOrNull;
  if (target == null) return false;
  target.requestFocus();
  return true;
}

/// Moves the focus from the rail back into the page on screen, where it was last.
///
/// Pages kept alive but not shown sit under ExcludeFocus, so the one that can take the focus
/// is the active one.
bool focusActivePage() {
  for (final scope in _pageScopes) {
    if (scope.context == null || !scope.canRequestFocus) continue;
    final remembered = scope.focusedChild;
    final target = remembered != null && remembered != scope
        ? remembered
        : scope.traversalDescendants
              .where((node) => node is! FocusScopeNode && node.canRequestFocus)
              .firstOrNull;
    if (target == null) continue;
    target.requestFocus();
    return true;
  }
  return false;
}

/// Wraps the navigation rail: gives it [sidebarFocusScope] and sends "right" back to the page.
class SidebarFocus extends StatelessWidget {
  final Widget child;

  const SidebarFocus({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      node: sidebarFocusScope,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is! KeyUpEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowRight &&
              focusActivePage()) {
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }
}

class PageFocusScope extends StatefulWidget {
  final Widget child;

  const PageFocusScope({super.key, required this.child});

  @override
  State<PageFocusScope> createState() => _PageFocusScopeState();
}

class _PageFocusScopeState extends State<PageFocusScope> {
  final FocusScopeNode _node = FocusScopeNode(debugLabel: 'page')
    ..traversalEdgeBehavior = TraversalEdgeBehavior.parentScope
    ..directionalTraversalEdgeBehavior = TraversalEdgeBehavior.parentScope;

  @override
  void initState() {
    super.initState();
    _pageScopes.add(_node);
  }

  @override
  void dispose() {
    _pageScopes.remove(_node);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope.withExternalFocusNode(
      focusScopeNode: _node,
      child: widget.child,
    );
  }
}

class PageTraversalPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    if (super.inDirection(currentNode, direction)) {
      return true;
    }
    // Nothing further left on the page: the rail is there, not the previous control in
    // reading order (that jump landed on whatever came before and looked like lost focus).
    if (direction == TraversalDirection.left && focusSidebar()) {
      return true;
    }

    final parent = scope?.enclosingScope;
    if (parent == null || parent == FocusManager.instance.rootScope) {
      return false;
    }
    return switch (direction) {
      TraversalDirection.down || TraversalDirection.right => parent.nextFocus(),
      TraversalDirection.up ||
      TraversalDirection.left => parent.previousFocus(),
    };
  }
}
