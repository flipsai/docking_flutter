import 'dart:math' as math;

import 'package:docking/src/docking_buttons_builder.dart';
import 'package:docking/src/drag_over_position.dart';
import 'package:docking/src/internal/widgets/draggable_config_mixin.dart';
import 'package:docking/src/internal/widgets/drop/content_wrapper.dart';
import 'package:docking/src/internal/widgets/drop/drop_feedback_widget.dart';
import 'package:docking/src/layout/docking_layout.dart';
import 'package:docking/src/layout/drop_position.dart';
import 'package:docking/src/on_item_close.dart';
import 'package:docking/src/on_item_selection.dart';
import 'package:docking/src/theme/docking_theme.dart';
import 'package:docking/src/theme/docking_theme_data.dart';
import 'package:flutter/material.dart';
import 'package:tabbed_view/tabbed_view.dart';
import 'package:get_it/get_it.dart';

/// State management for DockingTabsWidget using ValueNotifiers
class DockingTabsState {
  final ValueNotifier<DropPosition?> activeDropPositionNotifier = ValueNotifier<DropPosition?>(null);
  
  DropPosition? get activeDropPosition => activeDropPositionNotifier.value;
  set activeDropPosition(DropPosition? value) => activeDropPositionNotifier.value = value;
  
  void dispose() {
    activeDropPositionNotifier.dispose();
  }
}

/// Represents a widget for [DockingTabs].
class DockingTabsWidget extends StatefulWidget {
  const DockingTabsWidget(
      {Key? key,
      required this.layout,
      required this.dragOverPosition,
      required this.dockingTabs,
      this.onItemSelection,
      this.onItemClose,
      this.itemCloseInterceptor,
      this.dockingButtonsBuilder,
      required this.maximizableTab,
      required this.maximizableTabsArea,
      required this.draggable})
      : super(key: key);

  final DockingLayout layout;
  final DockingTabs dockingTabs;
  final OnItemSelection? onItemSelection;
  final OnItemClose? onItemClose;
  final ItemCloseInterceptor? itemCloseInterceptor;
  final DockingButtonsBuilder? dockingButtonsBuilder;
  final bool maximizableTab;
  final bool maximizableTabsArea;
  final DragOverPosition dragOverPosition;
  final bool draggable;

  @override
  State<StatefulWidget> createState() => DockingTabsWidgetState();
}

class DockingTabsWidgetState extends State<DockingTabsWidget>
    with DraggableConfigMixin {
  late DockingTabsState _state;

  @override
  void initState() {
    super.initState();
    // Register state management in DI if not already registered
    final String stateKey = 'DockingTabsState_${widget.dockingTabs.hashCode}';
    if (!GetIt.instance.isRegistered<DockingTabsState>(instanceName: stateKey)) {
      GetIt.instance.registerSingleton<DockingTabsState>(
          DockingTabsState(), instanceName: stateKey);
    }
    _state = GetIt.instance<DockingTabsState>(instanceName: stateKey);
  }

  @override
  Widget build(BuildContext context) {
    List<TabData> tabs = [];
    widget.dockingTabs.forEach((child) {
      Widget content = child.widget;
      if (child.globalKey != null) {
        content = KeyedSubtree(key: child.globalKey, child: content);
      }
      List<TabButton>? buttons;
      if (child.buttons != null && child.buttons!.isNotEmpty) {
        buttons = [];
        buttons.addAll(child.buttons!);
      }
      final bool maximizable = child.maximizable != null
          ? child.maximizable!
          : widget.maximizableTab;
      if (maximizable) {
        buttons ??= [];
        DockingThemeData data = DockingTheme.of(context);
        if (widget.layout.maximizedArea != null &&
            widget.layout.maximizedArea == child) {
          buttons.add(TabButton(
              icon: data.restoreIcon,
              onPressed: () => widget.layout.restore()));
        } else {
          buttons.add(TabButton(
              icon: data.maximizeIcon,
              onPressed: () => widget.layout.maximizeDockingItem(child)));
        }
      }
      tabs.add(TabData(
          value: child,
          text: child.name != null ? child.name! : '',
          content: content,
          closable: child.closable,
          keepAlive: child.globalKey != null,
          leading: child.leading,
          buttons: buttons,
          draggable: widget.draggable));
    });
    TabbedViewController controller = TabbedViewController(tabs);
    controller.selectedIndex =
        math.min(widget.dockingTabs.selectedIndex, tabs.length - 1);

    Widget tabbedView = TabbedView(
        controller: controller,
        tabsAreaButtonsBuilder: _tabsAreaButtonsBuilder,
        onTabSelection: (int? index) {
          if (index != null) {
            widget.dockingTabs.selectedIndex = index;
            if (widget.onItemSelection != null) {
              widget.onItemSelection!(widget.dockingTabs.childAt(index));
            }
          }
        },
        tabCloseInterceptor: _tabCloseInterceptor,
        onDraggableBuild: widget.draggable
            ? (TabbedViewController controller, int tabIndex, TabData tabData) {
                return buildDraggableConfig(
                    dockingDrag: widget.dragOverPosition, tabData: tabData);
              }
            : null,
        onTabClose: _onTabClose,
        contentBuilder: (context, tabIndex) => TabsContentWrapper(
            listener: _updateActiveDropPosition,
            layout: widget.layout,
            dockingTabs: widget.dockingTabs,
            child: controller.tabs[tabIndex].content!),
        onBeforeDropAccept: widget.draggable ? _onBeforeDropAccept : null);
    
    if (widget.draggable && widget.dragOverPosition.enable) {
      // Use ValueListenableBuilder for reactive updates
      return ValueListenableBuilder<DropPosition?>(
        valueListenable: _state.activeDropPositionNotifier,
        builder: (context, activeDropPosition, child) {
          return DropFeedbackWidget(
              dropPosition: activeDropPosition, child: tabbedView);
        },
      );
    }
    return tabbedView;
  }

  void _updateActiveDropPosition(DropPosition? dropPosition) {
    if (_state.activeDropPosition != dropPosition) {
      // Use reactive state management instead of setState
      _state.activeDropPosition = dropPosition;
    }
  }

  bool _onBeforeDropAccept(
      DraggableData source, TabbedViewController target, int newIndex) {
    DockingItem dockingItem = source.tabData.value;
    widget.layout.moveItem(
        draggedItem: dockingItem,
        targetArea: widget.dockingTabs,
        dropIndex: newIndex);
    return true;
  }

  List<TabButton> _tabsAreaButtonsBuilder(BuildContext context, int tabsCount) {
    List<TabButton> buttons = [];
    if (widget.dockingButtonsBuilder != null) {
      buttons.addAll(
          widget.dockingButtonsBuilder!(context, widget.dockingTabs, null));
    }
    final bool maximizable = widget.dockingTabs.maximizable != null
        ? widget.dockingTabs.maximizable!
        : widget.maximizableTabsArea;
    if (maximizable) {
      DockingThemeData data = DockingTheme.of(context);
      if (widget.layout.maximizedArea != null &&
          widget.layout.maximizedArea == widget.dockingTabs) {
        buttons.add(TabButton(
            icon: data.restoreIcon, onPressed: () => widget.layout.restore()));
      } else {
        buttons.add(TabButton(
            icon: data.maximizeIcon,
            onPressed: () =>
                widget.layout.maximizeDockingTabs(widget.dockingTabs)));
      }
    }
    return buttons;
  }

  bool _tabCloseInterceptor(int tabIndex) {
    if (widget.itemCloseInterceptor != null) {
      return widget.itemCloseInterceptor!(widget.dockingTabs.childAt(tabIndex));
    }
    return true;
  }

  void _onTabClose(int tabIndex, TabData tabData) {
    DockingItem dockingItem = widget.dockingTabs.childAt(tabIndex);
    widget.layout.removeItem(item: dockingItem);
    if (widget.onItemClose != null) {
      widget.onItemClose!(dockingItem);
    }
  }

  @override
  void dispose() {
    // Clean up the state when widget is disposed
    final String stateKey = 'DockingTabsState_${widget.dockingTabs.hashCode}';
    if (GetIt.instance.isRegistered<DockingTabsState>(instanceName: stateKey)) {
      GetIt.instance.unregister<DockingTabsState>(instanceName: stateKey);
    }
    super.dispose();
  }
}
